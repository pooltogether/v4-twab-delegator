// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@pooltogether/v4-core/contracts/interfaces/ITicket.sol";

import "./DelegatePosition.sol";

/// @title Contract to delegate chances of winning to multiple delegatees
/// @notice
contract TWABDelegator is ERC721 {
  using Clones for address;

  ITicket public immutable ticket;

  /// @notice The instance to which all proxies will point
  DelegatePosition public delegatePositionInstance;

  event TicketsStaked(address indexed recipient, uint256 amount);
  event StakeDelegated(address indexed delegatee, uint256 amount);

  mapping(address => uint256) public stakedAmount;

  uint256 public tokenIdCounter;

  constructor(address _ticket) ERC721("ERC721", "NFT") {
    require(_ticket != address(0), "TWABDelegator/ticket-not-zero-addr");
    ticket = ITicket(_ticket);

    delegatePositionInstance = new DelegatePosition();
    delegatePositionInstance.initialize();
  }

  function balanceOf(address _delegator) public view override returns (uint256) {
    return stakedAmount[_delegator];
  }

  function stake(address _to, uint256 _amount) external {
    require(_to != address(0), "TWABDelegator/to-not-zero-addr");

    ticket.transferFrom(msg.sender, address(this), _amount);
    stakedAmount[_to] += _amount;

    emit TicketsStaked(_to, _amount);
  }

  // As a Rep I want to Delegate so that the Delegatee has a chance to win
  function delegate(address _to, uint256 _amount) external {
    stakedAmount[msg.sender] -= _amount;

    tokenIdCounter++;
    uint256 _tokenIdCounter = tokenIdCounter;

    _mint(msg.sender, _tokenIdCounter);
    address _nftAddress = _computeAddress(_tokenIdCounter);

    ticket.transfer(_nftAddress, _amount);

    bytes4 selector = ticket.delegate.selector;
    bytes memory data = abi.encodeWithSelector(selector, _to);

    DelegatePosition.Call[] memory calls = new DelegatePosition.Call[](1);
    calls[0] = DelegatePosition.Call({
      to: address(ticket),
      value: 0,
      data: data
    });

    DelegatePosition delegatePosition = _createDelegatePosition(_tokenIdCounter);
    delegatePosition.executeCalls(calls);

    emit StakeDelegated(_to, _amount);
  }

  function _computeAddress(uint256 _tokenId) internal view returns (address) {
    return address(delegatePositionInstance).predictDeterministicAddress(keccak256(abi.encodePacked(_tokenId)), address(this));
  }

  /// @notice Creates a Loot Box for the given ERC721 token.
  /// @param _tokenId The ERC721 token id
  /// @return The address of the newly created DelegatePosition.
  function _createDelegatePosition(uint256 _tokenId) internal returns (DelegatePosition) {
    DelegatePosition delegatePosition = DelegatePosition(address(delegatePositionInstance).cloneDeterministic(keccak256(abi.encodePacked(_tokenId))));
    delegatePosition.initialize();
    return delegatePosition;
  }
}
