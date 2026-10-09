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

import {ProofLib} from 'contracts/lib/ProofLib.sol';
import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

/**
 * @title IChanger
 * @author ZipBNB (https://zipbnb.cash)
 * @notice "Unzip as BNB / USDT": spends a Privacy Pool note and swaps the withdrawn value before it reaches the
 *         recipient, in one transaction. The Changer is the withdrawal's processooor; everything in `Change` is
 *         encoded into `Withdrawal.data`, which the pool binds to the proof through the context signal, so nobody (the
 *         relayer included) can alter recipient, route, minimum, deadline or fee.
 * @dev FROZEN for audit (2026-10-05). No owner, no admin, holds nothing between calls.
 *
 *      Flow of `change`:
 *        1. checks: processooor == this, deadline not passed, fee <= MAX_RELAY_FEE_BPS, non-zero recipients;
 *        2. pool = ENTRYPOINT.scopeToPool(scope) (must exist); assetIn = pool.ASSET();
 *        3. route ends must equal assetIn and tokenOut (WBNB standing in for native), at most 3 hops;
 *        4. pool.withdraw(withdrawal, proof); the withdrawn value arrives here;
 *        5. wrap native input; approve VENUE exactly; VENUE.swapExactIn(..., minOut = 0); reset approval;
 *        6. out = measured balance increase; fee = out * relayFeeBPS / 10_000; net = out - fee; require net >= minOut;
 *        7. unwrap native output; pay `net` to recipient and `fee` to feeRecipient (native sends last);
 *        8. emit Changed; balances of assetIn and tokenOut back to their starting values.
 *      The relay fee is taken from the OUTPUT, so a relayer handling "unzip as BNB" is paid in BNB.
 */
interface IChanger {
  /**
   * @notice Payload carried in `Withdrawal.data`
   * @param recipient Receives the swap output, less the relay fee
   * @param tokenOut The output asset; 0xEeee…EEeE for native BNB
   * @param route Encoded venue path from the note's asset to tokenOut (WBNB stands in for native at either end)
   * @param minOut Minimum the recipient receives, after the relay fee
   * @param deadline Unix time after which the change reverts
   * @param feeRecipient The relayer paid for submitting the transaction
   * @param relayFeeBPS The relay fee, in basis points of the swap output
   */
  struct Change {
    address recipient;
    address tokenOut;
    bytes route;
    uint256 minOut;
    uint256 deadline;
    address feeRecipient;
    uint256 relayFeeBPS;
  }

  /**
   * @notice Emitted for every change
   * @param nullifierHash The spent note's nullifier hash
   * @param recipient Who received the output
   * @param tokenIn The note's asset
   * @param tokenOut The delivered asset
   * @param amountIn The withdrawn value swapped
   * @param amountOut The output delivered to the recipient (after the fee)
   * @param fee The relay fee, in tokenOut
   */
  event Changed(
    uint256 indexed nullifierHash,
    address indexed recipient,
    address tokenIn,
    address tokenOut,
    uint256 amountIn,
    uint256 amountOut,
    uint256 fee
  );

  error InvalidProcessooor();
  error Expired();
  error RelayFeeTooHigh();
  error ZeroAddress();
  error UnknownScope();
  error InvalidRoute();
  error InsufficientOutput();
  error UnexpectedSender();
  error NativeTransferFailed();

  /**
   * @notice Spends a note and delivers the swapped output
   * @param _withdrawal Withdrawal with `processooor == address(this)` and `data == abi.encode(Change)`
   * @param _proof Withdrawal proof generated against that exact `_withdrawal`
   * @param _scope The pool's scope (selects the pool through the Entrypoint)
   */
  function change(
    IPrivacyPool.Withdrawal calldata _withdrawal,
    ProofLib.WithdrawProof calldata _proof,
    uint256 _scope
  ) external;

  /// @notice Largest relay fee a change may pay, in basis points of the output
  function MAX_RELAY_FEE_BPS() external view returns (uint256);
}
