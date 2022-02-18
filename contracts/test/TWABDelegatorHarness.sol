// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../TWABDelegator.sol";

contract TWABDelegatorHarness is TWABDelegator {
  constructor(address _ticket) TWABDelegator(_ticket) {}

  function executeCall(DelegatePosition _delegatedPosition, bytes memory _data)
    external
    returns (bytes[] memory)
  {
    DelegatePosition.Call[] memory _calls = new DelegatePosition.Call[](1);
    _calls[0] = DelegatePosition.Call({ to: address(ticket), value: 0, data: _data });

    return _delegatedPosition.executeCalls(_calls);
  }
}
