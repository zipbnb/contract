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

import {IPrivacyPool} from 'interfaces/IPrivacyPool.sol';

/**
 * @title IPoolAdmin
 * @author ZipBNB (https://zipbnb.cash)
 * @notice Holds the Entrypoint's OWNER_ROLE so the Safe can add and retire pools and collect fees at once, without the
 *         48-hour timelock, while everything that could touch money already in the pools (upgrades, roles, fees above
 *         the cap) stays behind it. Its code is its limit: it can do nothing but the five calls below.
 * @dev FROZEN for audit (2026-10-05); `collectFees` added 2026-10-08 (owner).
 *      - `addPool` deploys the pool itself, from the audited pool code, on the live verifiers, with fixed fees. The Safe
 *        picks only the asset and the minimum deposit, so even a compromised Safe cannot register a pool that steals.
 *      - `windDownPool` stops deposits for good; unzips, relays, the Changer and ragequit keep working.
 *      - `removePool` unregisters a pool that is already wound down (freeing its asset for a new pool). After it, relayed
 *        unzips and the Changer no longer reach that pool; holders can still withdraw directly or ragequit.
 *      - `configurePool` changes a pool's minimum deposit and vetting fee at once, with the fee held under an immutable
 *        cap (MAX_VETTING_FEE_BPS). The fee is taken at deposit, so a cap bounds what a change made just before a
 *        pending deposit lands can cost it. The relay fee cap stays as deployed. (The timelock can still change all
 *        three after its 48-hour delay.)
 *      - `collectFees` sends the vetting fees the Entrypoint holds for an asset to the Safe, and only to the Safe. The
 *        Entrypoint holds nothing but fees (deposits go straight on to the pools in the same call).
 *      The timelock can revoke this contract's role at any time (48 h).
 */
interface IPoolAdmin {
  event PoolAdded(address indexed asset, address indexed pool, uint256 minDeposit);
  event PoolWoundDown(address indexed pool);
  event PoolRemoved(address indexed asset, address indexed pool);
  event PoolConfigured(address indexed asset, uint256 minDeposit, uint256 vettingFeeBps);
  event FeesCollected(address indexed asset, uint256 amount);

  error OnlySafe();
  error ZeroAddress();
  error NotAToken();
  error UnsupportedDecimals();
  error PoolStillLive();
  error PoolNotFound();
  error FeeAboveCap();
  error ZeroMinimum();

  /// @notice Safe only: deploys and registers a pool for `_asset` (NATIVE_ASSET for BNB)
  function addPool(address _asset, uint256 _minDeposit) external returns (IPrivacyPool _pool);

  /// @notice Safe only: stops new deposits into the asset's pool, permanently
  function windDownPool(address _asset) external;

  /// @notice Safe only: unregisters the asset's pool; it must be wound down first
  function removePool(address _asset) external;

  /// @notice Safe only: sets the asset's pool minimum deposit and vetting fee (at most MAX_VETTING_FEE_BPS), at once
  function configurePool(address _asset, uint256 _minDeposit, uint256 _vettingFeeBps) external;

  /// @notice Safe only: sends the Entrypoint's fee balance in `_asset` (NATIVE_ASSET for BNB) to the Safe, at once
  function collectFees(address _asset) external returns (uint256 _amount);

  function ENTRYPOINT() external view returns (address);
  function SAFE() external view returns (address);
  function WITHDRAWAL_VERIFIER() external view returns (address);
  function RAGEQUIT_VERIFIER() external view returns (address);
  function VETTING_FEE_BPS() external view returns (uint256);
  function MAX_RELAY_FEE_BPS() external view returns (uint256);
  function MAX_VETTING_FEE_BPS() external view returns (uint256);
}
