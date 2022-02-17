// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/proxy/Clones.sol";

import "./DelegatePosition.sol";

/**
 * The LowLevelDelegator allows users to create delegation positions very cheaply.
 */
contract LowLevelDelegator {
  using Clones for address;

  /// @notice The instance to which all proxies will point
  DelegatePosition public delegatePositionInstance;

  constructor() {
    delegatePositionInstance = new DelegatePosition();
    delegatePositionInstance.initialize();
  }
/*
  function createDelegation(bytes32 _salt) external returns (DelegatePosition) {
    return _createDelegation(_computeSalt(msg.sender, _salt));
  }

  function callDelegation(bytes32 _salt, DelegatePosition.Call[] memory _calls)
    external
    returns (bytes[] memory)
  {
    DelegatePosition _delegatedPosition = DelegatePosition(_computeAddress(_computeSalt(msg.sender, _salt)));
    return _delegatedPosition.executeCalls(_calls);
  }

  function destroyDelegation(bytes32 _salt, address _to) external {
    _destroyDelegation(_computeSalt(msg.sender, _salt), _to);
  }

  function computeAddress(address _from, bytes32 _salt) external view returns (address) {
      return _computeAddress(_computeSalt(_from, _salt));
  }
*/

  function _createDelegation(bytes32 _salt) internal returns (DelegatePosition) {
    DelegatePosition _delegatedPosition = DelegatePosition(
      address(delegatePositionInstance).cloneDeterministic(_salt)
    );
    _delegatedPosition.initialize();
    return _delegatedPosition;
  }

  function _destroyDelegation(bytes32 _salt, address _to) internal {
    DelegatePosition _delegatedPosition = DelegatePosition(_computeAddress(_salt));

    _delegatedPosition.destroy(payable(_to));
  }

  /**
   * @notice Computes the address of a clone, also known as minimal proxy contract.
   * @return Address at which the clone will be deployed
   */
  function _computeAddress(bytes32 _salt) internal view returns (address) {
    return
      address(delegatePositionInstance).predictDeterministicAddress(
        _salt,
        address(this)
      );
  }

  function _computeSalt(address _from, bytes32 _salt) internal view returns (bytes32) {
    return keccak256(abi.encodePacked(_from, _salt));
  }
}
