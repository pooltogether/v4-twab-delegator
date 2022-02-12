// SPDX-License-Identifier: MIT

pragma solidity 0.8.6;


/// @title Allows anyone to "loot" an address
/// @author Brendan Asselstine
/// @notice A DelegatePosition allows anyone to withdraw all tokens or execute calls on behalf of the contract.
/// @dev This contract is intended to be counterfactually instantiated via CREATE2.
contract DelegatePosition {

  /// @notice A structure to define arbitrary contract calls
  struct Call {
    address to;
    uint256 value;
    bytes data;
  }

  /// @notice Emitted when the contract transfer ether
  event TransferredEther(address indexed to, uint256 amount);

  address private _owner;

  function initialize () public {
    require(_owner == address(0), "DelegatePosition/already-init");
    _owner = msg.sender;
  }

  /// @notice Executes calls on behalf of this contract.
  /// @param calls The array of calls to be executed.
  /// @return An array of the return values for each of the calls
  function executeCalls(Call[] calldata calls) external onlyOwner returns (bytes[] memory) {
    bytes[] memory response = new bytes[](calls.length);
    for (uint256 i = 0; i < calls.length; i++) {
      response[i] = _executeCall(calls[i].to, calls[i].value, calls[i].data);
    }
    return response;
  }

  /// @notice Destroys this contract using `selfdestruct`
  /// @param to The address to send remaining Ether to
  function destroy(address payable to) external onlyOwner {
    delete _owner;
    selfdestruct(to);
  }

  /// @notice Executes a call to another contract
  /// @param to The address to call
  /// @param value The Ether to pass along with the call
  /// @param data The call data
  /// @return The return data from the call
  function _executeCall(address to, uint256 value, bytes memory data) internal returns (bytes memory) {
    (bool succeeded, bytes memory returnValue) = to.call{value: value}(data);
    require(succeeded, string(returnValue));
    return returnValue;
  }

  modifier onlyOwner {
    require(msg.sender == _owner, "DelegatePosition/only-owner");
    _;
  }
}
