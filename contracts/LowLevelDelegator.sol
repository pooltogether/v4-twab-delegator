// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/proxy/Clones.sol";

import "./DelegatePosition.sol";

/// @title The LowLevelDelegator allows users to create delegated positions very cheaply.
contract LowLevelDelegator {
  using Clones for address;

  /// @notice The instance to which all proxies will point
  DelegatePosition public delegatePositionInstance;

  /// @notice Contract constructor
  constructor() {
    delegatePositionInstance = new DelegatePosition();
    delegatePositionInstance.initialize(uint96(0));
  }

  /**
   * @notice Creates a clone of the delegated position.
   * @param _salt Random number used to deterministically deploy the clone
   * @param _lockUntil Timestamp until which the delegated position is locked
   * @return The newly created delegated position
   */
  function _createDelegation(bytes32 _salt, uint96 _lockUntil)
    internal
    returns (DelegatePosition)
  {
    DelegatePosition _delegatedPosition = DelegatePosition(
      address(delegatePositionInstance).cloneDeterministic(_salt)
    );
    _delegatedPosition.initialize(_lockUntil);
    return _delegatedPosition;
  }

  /**
   * @notice Computes the address of a clone, also known as minimal proxy contract.
   * @param _salt Random number used to compute the address
   * @return Address at which the clone will be deployed
   */
  function _computeAddress(bytes32 _salt) internal view returns (address) {
    return address(delegatePositionInstance).predictDeterministicAddress(_salt, address(this));
  }

  /**
   * @notice Compute salt used to deterministically deploy a clone.
   * @param _delegator Address of the delegator
   * @param _slot Slot of the delegated position
   * @return Salt used to deterministically deploy a clone.
   */
  function _computeSalt(address _delegator, bytes32 _slot) internal pure returns (bytes32) {
    return keccak256(abi.encodePacked(_delegator, _slot));
  }
}
