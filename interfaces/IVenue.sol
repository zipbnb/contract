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

/**
 * @title IVenue
 * @author ZipBNB (https://zipbnb.cash)
 * @notice A swap venue adapter for spend contracts (the Changer). Stateless: it holds nothing between calls.
 * @dev FROZEN for audit (2026-10-05). Implemented by PancakeV3Venue over PancakeSwap's V3 SwapRouter.
 */
interface IVenue {
  /**
   * @notice Swaps exactly `_amountIn` of `_tokenIn` along `_route`, pulling the input from msg.sender (which must have
   *         approved this venue) and sending the output to msg.sender.
   * @param _tokenIn The input token (WBNB stands in for native BNB; the caller wraps first)
   * @param _amountIn The exact input amount
   * @param _route An encoded path for the underlying venue (for PancakeSwap V3: tokenIn, fee, tokenMid, fee, tokenOut)
   * @param _tokenOut The output token (WBNB for native BNB; the caller unwraps)
   * @param _minOut Minimum output; reverts below it
   * @return _amountOut The output sent to msg.sender
   */
  function swapExactIn(
    address _tokenIn,
    uint256 _amountIn,
    bytes calldata _route,
    address _tokenOut,
    uint256 _minOut
  ) external returns (uint256 _amountOut);
}
