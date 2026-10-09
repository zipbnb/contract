// SPDX-License-Identifier: MIT
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
import {ReentrancyGuard} from '@oz/utils/ReentrancyGuard.sol';

import {Constants} from 'contracts/lib/Constants.sol';
import {ProofLib} from 'contracts/lib/ProofLib.sol';
import {IEntrypoint} from 'interfaces/IEntrypoint.sol';
import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

import {IChanger} from '../interfaces/IChanger.sol';
import {IVenue} from '../interfaces/IVenue.sol';

interface IWBNB {
  function deposit() external payable;
  function withdraw(uint256 _amount) external;
}

/**
 * @title Changer
 * @author ZipBNB (https://zipbnb.cash)
 * @notice "Unzip as BNB / USDT": spends a Privacy Pool note and swaps the withdrawn value before it reaches the
 *         recipient, in one transaction. See IChanger for the flow.
 * @dev The Changer is the withdrawal's processooor and calls the pool directly, so the Entrypoint's per-asset relay
 *      fee cap does not apply here; MAX_RELAY_FEE_BPS is this contract's own, immutable cap. No owner, no admin, and
 *      it holds nothing between calls.
 */
contract Changer is IChanger, ReentrancyGuard {
  using SafeERC20 for IERC20;
  using ProofLib for ProofLib.WithdrawProof;

  uint256 internal constant HOP = 23;
  uint256 internal constant ADDRESS = 20;
  uint256 internal constant MAX_HOPS = 3;

  IEntrypoint public immutable ENTRYPOINT;
  IVenue public immutable VENUE;
  address public immutable WBNB;
  /// @inheritdoc IChanger
  uint256 public immutable MAX_RELAY_FEE_BPS;

  constructor(IEntrypoint _entrypoint, IVenue _venue, address _wbnb, uint256 _maxRelayFeeBps) {
    if (address(_entrypoint) == address(0) || address(_venue) == address(0) || _wbnb == address(0)) {
      revert ZeroAddress();
    }
    if (_maxRelayFeeBps >= 10_000) revert RelayFeeTooHigh();
    ENTRYPOINT = _entrypoint;
    VENUE = _venue;
    WBNB = _wbnb;
    MAX_RELAY_FEE_BPS = _maxRelayFeeBps;
  }

  /// @notice Native BNB arrives only from the native pool (a withdrawal) or WBNB (an unwrap)
  receive() external payable {
    if (msg.sender != WBNB && msg.sender != address(_nativePool())) revert UnexpectedSender();
  }

  /// @dev The two ends of a change, resolved once (kept in memory to stay clear of stack limits)
  struct Leg {
    IPrivacyPool pool;
    address assetIn;
    address swapIn;
    address swapOut;
    bool nativeIn;
    bool nativeOut;
  }

  /// @inheritdoc IChanger
  function change(
    IPrivacyPool.Withdrawal calldata _withdrawal,
    ProofLib.WithdrawProof calldata _proof,
    uint256 _scope
  ) external nonReentrant {
    if (_withdrawal.processooor != address(this)) revert InvalidProcessooor();
    Change memory _c = abi.decode(_withdrawal.data, (Change));
    if (block.timestamp > _c.deadline) revert Expired();
    if (_c.relayFeeBPS > MAX_RELAY_FEE_BPS) revert RelayFeeTooHigh();
    if (_c.recipient == address(0) || _c.feeRecipient == address(0)) revert ZeroAddress();

    Leg memory _leg = _resolve(_scope, _c);
    _checkRoute(_c.route, _leg.swapIn, _leg.swapOut);

    uint256 _amountIn = _withdraw(_leg, _withdrawal, _proof);
    uint256 _out = _swap(_leg, _amountIn, _c.route);

    // Relay fee from the output; the recipient's minimum is net of it
    uint256 _fee = (_out * _c.relayFeeBPS) / 10_000;
    uint256 _net = _out - _fee;
    if (_net < _c.minOut) revert InsufficientOutput();
    _deliver(_leg, _c, _out, _net, _fee);

    emit Changed(_proof.existingNullifierHash(), _c.recipient, _leg.assetIn, _c.tokenOut, _amountIn, _net, _fee);
  }

  function _resolve(uint256 _scope, Change memory _c) internal view returns (Leg memory _leg) {
    _leg.pool = ENTRYPOINT.scopeToPool(_scope);
    if (address(_leg.pool) == address(0)) revert UnknownScope();
    _leg.assetIn = _leg.pool.ASSET();
    _leg.nativeIn = _leg.assetIn == Constants.NATIVE_ASSET;
    _leg.nativeOut = _c.tokenOut == Constants.NATIVE_ASSET;
    _leg.swapIn = _leg.nativeIn ? WBNB : _leg.assetIn;
    _leg.swapOut = _leg.nativeOut ? WBNB : _c.tokenOut;
  }

  /// @dev Spends the note; the pool sends the withdrawn value here. Native input is wrapped for the swap.
  function _withdraw(
    Leg memory _leg,
    IPrivacyPool.Withdrawal calldata _withdrawal,
    ProofLib.WithdrawProof calldata _proof
  ) internal returns (uint256 _amountIn) {
    uint256 _before = _leg.nativeIn ? address(this).balance : IERC20(_leg.assetIn).balanceOf(address(this));
    _leg.pool.withdraw(_withdrawal, _proof);
    _amountIn = (_leg.nativeIn ? address(this).balance : IERC20(_leg.assetIn).balanceOf(address(this))) - _before;
    if (_leg.nativeIn) IWBNB(WBNB).deposit{value: _amountIn}();
  }

  /// @dev The output is measured from this contract's balance, not trusted from the venue's return value
  function _swap(Leg memory _leg, uint256 _amountIn, bytes memory _route) internal returns (uint256 _out) {
    uint256 _before = IERC20(_leg.swapOut).balanceOf(address(this));
    IERC20(_leg.swapIn).forceApprove(address(VENUE), _amountIn);
    VENUE.swapExactIn(_leg.swapIn, _amountIn, _route, _leg.swapOut, 0);
    IERC20(_leg.swapIn).forceApprove(address(VENUE), 0);
    _out = IERC20(_leg.swapOut).balanceOf(address(this)) - _before;
  }

  /// @dev Pays the recipient and the relayer; native sends go last
  function _deliver(Leg memory _leg, Change memory _c, uint256 _out, uint256 _net, uint256 _fee) internal {
    if (_leg.nativeOut) {
      IWBNB(WBNB).withdraw(_out);
      _sendNative(_c.recipient, _net);
      if (_fee != 0) _sendNative(_c.feeRecipient, _fee);
    } else {
      IERC20(_leg.swapOut).safeTransfer(_c.recipient, _net);
      if (_fee != 0) IERC20(_leg.swapOut).safeTransfer(_c.feeRecipient, _fee);
    }
  }

  /// @dev Route ends must match the note's asset and the requested output; 1 to MAX_HOPS hops
  function _checkRoute(bytes memory _route, address _in, address _out) internal pure {
    uint256 _len = _route.length;
    if (_len < ADDRESS + HOP || (_len - ADDRESS) % HOP != 0 || (_len - ADDRESS) / HOP > MAX_HOPS) {
      revert InvalidRoute();
    }
    address _first;
    address _last;
    // solhint-disable-next-line no-inline-assembly
    assembly {
      _first := shr(96, mload(add(_route, 32)))
      _last := shr(96, mload(add(add(_route, 32), sub(_len, 20))))
    }
    if (_first != _in || _last != _out || _in == _out) revert InvalidRoute();
  }

  function _nativePool() internal view returns (IPrivacyPool _pool) {
    (_pool,,,) = ENTRYPOINT.assetConfig(IERC20(Constants.NATIVE_ASSET));
  }

  function _sendNative(address _to, uint256 _amount) internal {
    (bool _ok,) = _to.call{value: _amount}('');
    if (!_ok) revert NativeTransferFailed();
  }
}
