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

import {IVenue} from '../../interfaces/IVenue.sol';

/// @dev PancakeSwap V3 SwapRouter (v3-periphery shape, with a deadline in the params)
interface IPancakeV3SwapRouter {
  struct ExactInputParams {
    bytes path;
    address recipient;
    uint256 deadline;
    uint256 amountIn;
    uint256 amountOutMinimum;
  }

  function exactInput(ExactInputParams calldata _params) external payable returns (uint256 _amountOut);
}

/**
 * @title PancakeV3Venue
 * @author ZipBNB (https://zipbnb.cash)
 * @notice IVenue over PancakeSwap V3: exact-input swaps along an encoded V3 path. Stateless and ownerless; it holds no
 *         funds between calls (the input is pulled and spent in the same call, the output goes straight to msg.sender).
 */
contract PancakeV3Venue is IVenue {
  using SafeERC20 for IERC20;

  /// @dev One V3 hop in a path: a 20-byte token followed by a 3-byte fee
  uint256 internal constant HOP = 23;
  uint256 internal constant ADDRESS = 20;

  IPancakeV3SwapRouter public immutable ROUTER;

  error InvalidPath();
  error ZeroAddress();

  constructor(IPancakeV3SwapRouter _router) {
    if (address(_router) == address(0)) revert ZeroAddress();
    ROUTER = _router;
  }

  /// @inheritdoc IVenue
  function swapExactIn(
    address _tokenIn,
    uint256 _amountIn,
    bytes calldata _route,
    address _tokenOut,
    uint256 _minOut
  ) external returns (uint256 _amountOut) {
    if (_route.length < ADDRESS + HOP || (_route.length - ADDRESS) % HOP != 0) revert InvalidPath();
    if (address(bytes20(_route[:ADDRESS])) != _tokenIn) revert InvalidPath();
    if (address(bytes20(_route[_route.length - ADDRESS:])) != _tokenOut) revert InvalidPath();

    IERC20(_tokenIn).safeTransferFrom(msg.sender, address(this), _amountIn);
    IERC20(_tokenIn).forceApprove(address(ROUTER), _amountIn);
    _amountOut = ROUTER.exactInput(
      IPancakeV3SwapRouter.ExactInputParams({
        path: _route, recipient: msg.sender, deadline: block.timestamp, amountIn: _amountIn, amountOutMinimum: _minOut
      })
    );
    IERC20(_tokenIn).forceApprove(address(ROUTER), 0);
  }
}
