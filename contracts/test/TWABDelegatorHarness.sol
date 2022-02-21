// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "../TWABDelegator.sol";

contract TWABDelegatorHarness is TWABDelegator {
  constructor(address _ticket) TWABDelegator(_ticket) {}

  function executeCall(Delegation _delegation, bytes memory _data)
    external
    returns (bytes[] memory)
  {
    Delegation.Call[] memory _calls = new Delegation.Call[](1);
    _calls[0] = Delegation.Call({ to: address(ticket), value: 0, data: _data });

    return _delegation.executeCalls(_calls);
  }
}
