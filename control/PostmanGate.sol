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

import {IEntrypoint} from 'interfaces/IEntrypoint.sol';

import {IPostmanGate} from '../interfaces/IPostmanGate.sol';

/**
 * @title PostmanGate
 * @author ZipBNB (https://zipbnb.cash)
 * @notice Holds the Entrypoint's ASP_POSTMAN role. The association-set service's operator key posts roots through it;
 *         the Safe can pause that key, replace it, or post a root itself, all without the 48-hour timelock that guards
 *         the Entrypoint's owner functions.
 * @dev Without this gate, a stolen postman key could post any root for 48 hours (the time a role revoke takes through
 *      the timelock). The Safe is immutable; to move to a new Safe, grant ASP_POSTMAN to a new gate through the
 *      timelock and revoke this one. Holds no funds.
 */
contract PostmanGate is IPostmanGate {
  /// @inheritdoc IPostmanGate
  address public immutable ENTRYPOINT;
  /// @inheritdoc IPostmanGate
  address public immutable SAFE;
  /// @inheritdoc IPostmanGate
  address public operator;
  /// @inheritdoc IPostmanGate
  bool public paused;

  constructor(address _entrypoint, address _safe, address _operator) {
    if (_entrypoint == address(0) || _safe == address(0) || _operator == address(0)) revert ZeroAddress();
    ENTRYPOINT = _entrypoint;
    SAFE = _safe;
    operator = _operator;
    emit OperatorSet(address(0), _operator);
  }

  modifier onlySafe() {
    if (msg.sender != SAFE) revert OnlySafe();
    _;
  }

  /// @inheritdoc IPostmanGate
  function updateRoot(uint256 _root, string calldata _ipfsCID) external returns (uint256 _index) {
    if (msg.sender != operator) revert OnlyOperator();
    if (paused) revert IsPaused();
    _index = IEntrypoint(ENTRYPOINT).updateRoot(_root, _ipfsCID);
    emit RootPosted(msg.sender, _root, _ipfsCID);
  }

  /// @inheritdoc IPostmanGate
  function safeUpdateRoot(uint256 _root, string calldata _ipfsCID) external onlySafe returns (uint256 _index) {
    _index = IEntrypoint(ENTRYPOINT).updateRoot(_root, _ipfsCID);
    emit RootPosted(msg.sender, _root, _ipfsCID);
  }

  /// @inheritdoc IPostmanGate
  function setOperator(address _operator) external onlySafe {
    if (_operator == address(0)) revert ZeroAddress();
    emit OperatorSet(operator, _operator);
    operator = _operator;
  }

  /// @inheritdoc IPostmanGate
  function setPaused(bool _paused) external onlySafe {
    paused = _paused;
    emit PausedSet(_paused);
  }
}
