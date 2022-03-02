// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/proxy/Clones.sol";

import "./Delegation.sol";

/// @title The LowLevelDelegator allows users to create delegations very cheaply.
contract LowLevelDelegator {
  using Clones for address;

  /// @notice The instance to which all proxies will point.
  Delegation public delegationInstance;

  /// @notice Contract constructor.
  constructor() {
    delegationInstance = new Delegation();
  }

  /**
   * @notice Creates a clone of the delegation.
   * @param _salt Random number used to deterministically deploy the clone
   * @param _lockUntil Timestamp until which the delegation is locked
   * @return The newly created delegation
   */
  function _createDelegation(bytes32 _salt, uint96 _lockUntil) internal returns (Delegation) {
    Delegation _delegation = Delegation(address(delegationInstance).cloneDeterministic(_salt));
    _delegation.setLockUntil(_lockUntil);
    return _delegation;
  }

  /**
   * @notice Computes the address of a clone, also known as minimal proxy contract.
   * @param _salt Random number used to compute the address
   * @return Address at which the clone will be deployed
   */
  function _computeAddress(bytes32 _salt) internal view returns (address) {
    return address(delegationInstance).predictDeterministicAddress(_salt, address(this));
  }

  /**
   * @notice Computes salt used to deterministically deploy a clone.
   * @param _delegator Address of the delegator
   * @param _slot Slot of the delegation
   * @return Salt used to deterministically deploy a clone.
   */
  function _computeSalt(address _delegator, bytes32 _slot) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(_delegator, _slot));
  }
}
