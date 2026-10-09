// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.28;

/*
 *  ZipBNB · Move with privacy. Speak with purpose.
 *
 *  Website   https://zipbnb.cash
 *  App       https://app.zipbnb.cash
 *  X         https://x.com/zipbnb
 *  Token     ZBNB 0x4628076022bdecc04a4e52d10ffb3aba10745555 (BNB Chain)
 */

import {IERC20, SafeERC20} from '@oz/token/ERC20/utils/SafeERC20.sol';

import {ProofLib} from 'contracts/lib/ProofLib.sol';
import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

/**
 * @title Doorstep
 * @author ZipBNB (https://zipbnb.cash)
 * @notice Burn tokens to publish a message, optionally at someone's door and with a gift left there.
 * @dev Adapted from an open-source burn-to-speak contract (credited in contracts/NOTICE, as its licence requires).
 *      With no door and no gift it is plain burn-to-speak.
 *
 *      `speakAnon` spends a Privacy Pool note. This contract is the withdrawal `processooor`; the message, door,
 *      gift and relay fee live in `withdrawal.data`, which the pool binds to the proof through the `context`
 *      signal. Nobody, the relayer included, can change any of them. `speak` is the public version, straight from
 *      a wallet.
 *
 *      Every gift must come with a burn of at least a tenth of it, so a door is never a free private transfer.
 *      The protocol's own contracts (the Entrypoint, the pools, the Changer and the others named at deployment) can
 *      never be a door: none of them could pass a gift on, so it would be stuck or swept as fees.
 *      No owner, no admin, holds no funds between calls.
 */
contract Doorstep {
  using SafeERC20 for IERC20;
  using ProofLib for ProofLib.WithdrawProof;

  /**
   * @notice Payload carried in `Withdrawal.data` for anonymous speech
   * @param message The text
   * @param target Who the message is for, free text
   * @param to The door: receives the gift and collects the burn on its page (address(0) for no door)
   * @param gift Tokens left at the door, paid out of the withdrawn value
   * @param feeRecipient The relayer paid for submitting the transaction
   * @param relayFeeBPS The relayer fee, in basis points of the withdrawn value
   */
  struct Speech {
    string message;
    string target;
    address to;
    uint256 gift;
    address feeRecipient;
    uint256 relayFeeBPS;
  }

  address public constant BURN = 0x000000000000000000000000000000000000dEaD;
  uint256 public constant MAX_MESSAGE_BYTES = 280;
  uint256 public constant MAX_TARGET_BYTES = 120;
  /// @notice Burn at least this fraction of any gift (basis points)
  uint256 public constant MIN_BURN_OF_GIFT_BPS = 1000;

  IPrivacyPool public immutable POOL;
  IERC20 public immutable TOKEN;
  /// @notice Smallest burn that may carry a message. With gas near zero on BNB Chain this is the only spam floor.
  uint256 public immutable MIN_BURN;
  /// @notice Largest relay fee a speech may pay, in basis points of the withdrawn value
  uint256 public immutable MAX_RELAY_FEE_BPS;
  /// @notice Contracts that can never be a door: the pool's Entrypoint, and those named at deployment
  mapping(address => bool) public notADoor;

  /**
   * @notice Emitted for every speech
   * @param speaker The wallet that burned, or address(0) when anonymous
   * @param to The door (address(0) when there is none)
   * @param nullifierHash The spent note nullifier for anonymous speech, 0 for public speech
   * @param burned The amount sent to the burn address
   * @param gift The amount left at the door
   * @param fee The relayer fee paid out of the withdrawn value
   * @param message The text
   * @param target Who the message is for, free text
   */
  event Spoken(
    address indexed speaker,
    address indexed to,
    uint256 indexed nullifierHash,
    uint256 burned,
    uint256 gift,
    uint256 fee,
    string message,
    string target
  );

  error EmptyMessage();
  error MessageTooLong();
  error TargetTooLong();
  error BurnTooSmall();
  error GiftNeedsDoor();
  error InvalidDoor();
  error RelayFeeTooHigh();
  error InvalidProcessooor();
  error ValueTooSmall();
  error ZeroMinBurn();
  error InvalidMaxRelayFee();
  error InvalidFeeRecipient();

  /// @param _notDoors The protocol's other contracts (pools, Changer, Venue, ...); the Entrypoint is added here
  constructor(IPrivacyPool _pool, uint256 _minBurn, uint256 _maxRelayFeeBPS, address[] memory _notDoors) {
    if (_minBurn == 0) revert ZeroMinBurn();
    if (_maxRelayFeeBPS >= 10_000) revert InvalidMaxRelayFee();
    POOL = _pool;
    TOKEN = IERC20(_pool.ASSET());
    MIN_BURN = _minBurn;
    MAX_RELAY_FEE_BPS = _maxRelayFeeBPS;
    notADoor[address(_pool.ENTRYPOINT())] = true;
    for (uint256 _i; _i < _notDoors.length; ++_i) {
      notADoor[_notDoors[_i]] = true;
    }
  }

  /**
   * @notice Burn (and gift) from a note in the pool without revealing who you are
   * @param _withdrawal Withdrawal with `processooor == address(this)` and `data == abi.encode(Speech)`
   * @param _proof Withdrawal proof generated against that exact `_withdrawal`
   */
  function speakAnon(IPrivacyPool.Withdrawal calldata _withdrawal, ProofLib.WithdrawProof calldata _proof) external {
    if (_withdrawal.processooor != address(this)) revert InvalidProcessooor();

    Speech memory _s = abi.decode(_withdrawal.data, (Speech));
    _validate(_s.message, _s.target, _s.to, _s.gift);
    if (_s.relayFeeBPS > MAX_RELAY_FEE_BPS) revert RelayFeeTooHigh();

    uint256 _value = _proof.withdrawnValue();
    uint256 _fee = (_value * _s.relayFeeBPS) / 10_000;
    // A fee with nowhere to go would be burned (or revert inside the token): refuse it up front
    if (_fee != 0 && _s.feeRecipient == address(0)) revert InvalidFeeRecipient();
    if (_value < _fee + _s.gift) revert ValueTooSmall();
    uint256 _burned = _value - _fee - _s.gift;
    _checkBurn(_burned, _s.gift);

    POOL.withdraw(_withdrawal, _proof);

    if (_fee != 0) TOKEN.safeTransfer(_s.feeRecipient, _fee);
    if (_s.gift != 0) TOKEN.safeTransfer(_s.to, _s.gift);
    TOKEN.safeTransfer(BURN, _burned);

    emit Spoken(address(0), _s.to, _proof.existingNullifierHash(), _burned, _s.gift, _fee, _s.message, _s.target);
  }

  /**
   * @notice Burn (and gift) from your wallet, publicly
   * @param _to The door (address(0) for a message with no door)
   * @param _burn Amount to burn (requires approval of `_burn + _gift`)
   * @param _gift Amount left at the door
   * @param _message The text
   * @param _target Who the message is for, free text
   */
  function speak(
    address _to,
    uint256 _burn,
    uint256 _gift,
    string calldata _message,
    string calldata _target
  ) external {
    _validate(_message, _target, _to, _gift);
    _checkBurn(_burn, _gift);

    TOKEN.safeTransferFrom(msg.sender, BURN, _burn);
    if (_gift != 0) TOKEN.safeTransferFrom(msg.sender, _to, _gift);

    emit Spoken(msg.sender, _to, 0, _burn, _gift, 0, _message, _target);
  }

  function _checkBurn(uint256 _burn, uint256 _gift) internal view {
    if (_burn < MIN_BURN) revert BurnTooSmall();
    if (_burn * 10_000 < _gift * MIN_BURN_OF_GIFT_BPS) revert BurnTooSmall();
  }

  function _validate(string memory _message, string memory _target, address _to, uint256 _gift) internal view {
    uint256 _len = bytes(_message).length;
    if (_len == 0) revert EmptyMessage();
    if (_len > MAX_MESSAGE_BYTES) revert MessageTooLong();
    if (bytes(_target).length > MAX_TARGET_BYTES) revert TargetTooLong();
    if (_gift != 0 && _to == address(0)) revert GiftNeedsDoor();
    if (_to == address(this) || _to == address(POOL) || _to == BURN || notADoor[_to]) revert InvalidDoor();
  }
}
