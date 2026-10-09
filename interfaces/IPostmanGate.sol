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
 * @title IPostmanGate
 * @author ZipBNB (https://zipbnb.cash)
 * @notice Holds the Entrypoint's ASP_POSTMAN role so the association root can be controlled without waiting on the
 *         48-hour timelock. The server's operator key posts roots through it; the Safe can pause the operator, replace
 *         it, or post a root itself (for example a frozen root that stops private withdrawals), immediately.
 * @dev FROZEN for audit (2026-10-05). The Safe is immutable: moving control to a new Safe means granting ASP_POSTMAN to
 *      a new gate through the timelock and revoking this one.
 */
interface IPostmanGate {
  event OperatorSet(address indexed previous, address indexed operator);
  event PausedSet(bool paused);
  event RootPosted(address indexed by, uint256 root, string ipfsCID);

  error OnlyOperator();
  error OnlySafe();
  error IsPaused();
  error ZeroAddress();

  /// @notice Posts a root for the operator (the association-set service). Reverts while paused.
  function updateRoot(uint256 _root, string calldata _ipfsCID) external returns (uint256 _index);

  /// @notice Safe only: posts a root directly, even while paused (e.g. the frozen root)
  function safeUpdateRoot(uint256 _root, string calldata _ipfsCID) external returns (uint256 _index);

  /// @notice Safe only: replaces the operator key
  function setOperator(address _operator) external;

  /// @notice Safe only: stops (or resumes) operator posts
  function setPaused(bool _paused) external;

  function ENTRYPOINT() external view returns (address);
  function SAFE() external view returns (address);
  function operator() external view returns (address);
  function paused() external view returns (bool);
}
