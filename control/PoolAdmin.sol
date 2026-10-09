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

import {IERC20} from '@oz/token/ERC20/IERC20.sol';
import {IERC20Metadata} from '@oz/token/ERC20/extensions/IERC20Metadata.sol';

import {PrivacyPoolComplex} from 'contracts/implementations/PrivacyPoolComplex.sol';
import {PrivacyPoolSimple} from 'contracts/implementations/PrivacyPoolSimple.sol';
import {Constants} from 'contracts/lib/Constants.sol';
import {IEntrypoint} from 'interfaces/IEntrypoint.sol';
import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

import {IPoolAdmin} from '../interfaces/IPoolAdmin.sol';

/// @title PoolAdmin
/// @author ZipBNB (https://zipbnb.cash)
/// @notice See IPoolAdmin. No owner besides the immutable Safe; holds nothing.
contract PoolAdmin is IPoolAdmin {
  address public immutable ENTRYPOINT;
  address public immutable SAFE;
  address public immutable WITHDRAWAL_VERIFIER;
  address public immutable RAGEQUIT_VERIFIER;
  uint256 public immutable VETTING_FEE_BPS;
  uint256 public immutable MAX_RELAY_FEE_BPS;
  uint256 public immutable MAX_VETTING_FEE_BPS;

  constructor(
    address _entrypoint,
    address _safe,
    address _withdrawalVerifier,
    address _ragequitVerifier,
    uint256 _vettingFeeBps,
    uint256 _maxRelayFeeBps,
    uint256 _maxVettingFeeBps
  ) {
    if (
      _entrypoint == address(0) || _safe == address(0) || _withdrawalVerifier == address(0)
        || _ragequitVerifier == address(0)
    ) revert ZeroAddress();
    ENTRYPOINT = _entrypoint;
    SAFE = _safe;
    WITHDRAWAL_VERIFIER = _withdrawalVerifier;
    RAGEQUIT_VERIFIER = _ragequitVerifier;
    VETTING_FEE_BPS = _vettingFeeBps;
    MAX_RELAY_FEE_BPS = _maxRelayFeeBps;
    if (_vettingFeeBps > _maxVettingFeeBps || _maxVettingFeeBps >= 10_000) revert FeeAboveCap();
    MAX_VETTING_FEE_BPS = _maxVettingFeeBps;
  }

  modifier onlySafe() {
    if (msg.sender != SAFE) revert OnlySafe();
    _;
  }

  /// @inheritdoc IPoolAdmin
  function addPool(address _asset, uint256 _minDeposit) external onlySafe returns (IPrivacyPool _pool) {
    // The Entrypoint accepts a zero minimum; a pool open to dust deposits could be spammed, so refuse it here
    if (_minDeposit == 0) revert ZeroMinimum();
    if (_asset == Constants.NATIVE_ASSET) {
      _pool = IPrivacyPool(address(new PrivacyPoolSimple(ENTRYPOINT, WITHDRAWAL_VERIFIER, RAGEQUIT_VERIFIER)));
    } else {
      if (_asset.code.length == 0) revert NotAToken();
      // The app, the relayer's pricing and the Changer's routes all assume 18 decimals, as every major BNB Chain token
      if (IERC20Metadata(_asset).decimals() != 18) revert UnsupportedDecimals();
      _pool = IPrivacyPool(address(new PrivacyPoolComplex(ENTRYPOINT, WITHDRAWAL_VERIFIER, RAGEQUIT_VERIFIER, _asset)));
    }
    // Reverts if the asset already has a pool
    IEntrypoint(ENTRYPOINT).registerPool(IERC20(_asset), _pool, _minDeposit, VETTING_FEE_BPS, MAX_RELAY_FEE_BPS);
    emit PoolAdded(_asset, address(_pool), _minDeposit);
  }

  /// @inheritdoc IPoolAdmin
  function windDownPool(address _asset) external onlySafe {
    IPrivacyPool _pool = _poolOf(_asset);
    IEntrypoint(ENTRYPOINT).windDownPool(_pool);
    emit PoolWoundDown(address(_pool));
  }

  /// @inheritdoc IPoolAdmin
  function removePool(address _asset) external onlySafe {
    IPrivacyPool _pool = _poolOf(_asset);
    if (!_pool.dead()) revert PoolStillLive();
    IEntrypoint(ENTRYPOINT).removePool(IERC20(_asset));
    emit PoolRemoved(_asset, address(_pool));
  }

  /// @inheritdoc IPoolAdmin
  function configurePool(address _asset, uint256 _minDeposit, uint256 _vettingFeeBps) external onlySafe {
    if (_vettingFeeBps > MAX_VETTING_FEE_BPS) revert FeeAboveCap();
    if (_minDeposit == 0) revert ZeroMinimum();
    _poolOf(_asset);
    IEntrypoint(ENTRYPOINT).updatePoolConfiguration(IERC20(_asset), _minDeposit, _vettingFeeBps, MAX_RELAY_FEE_BPS);
    emit PoolConfigured(_asset, _minDeposit, _vettingFeeBps);
  }

  /// @inheritdoc IPoolAdmin
  function collectFees(address _asset) external onlySafe returns (uint256 _amount) {
    _amount = _asset == Constants.NATIVE_ASSET ? ENTRYPOINT.balance : IERC20(_asset).balanceOf(ENTRYPOINT);
    // The recipient is fixed: fees can only ever go to the Safe
    IEntrypoint(ENTRYPOINT).withdrawFees(IERC20(_asset), SAFE);
    emit FeesCollected(_asset, _amount);
  }

  function _poolOf(address _asset) internal view returns (IPrivacyPool _pool) {
    (_pool,,,) = IEntrypoint(ENTRYPOINT).assetConfig(IERC20(_asset));
    if (address(_pool) == address(0)) revert PoolNotFound();
  }
}
