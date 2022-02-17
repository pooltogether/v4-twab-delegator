// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@pooltogether/v4-core/contracts/interfaces/ITicket.sol";

import "./DelegatePosition.sol";
import "./LowLevelDelegator.sol";

/// @title Contract to delegate chances of winning to multiple delegatees
contract TWABDelegator is ERC721, LowLevelDelegator {
  using Clones for address;
  using SafeERC20 for IERC20;

  /* ============ Events ============ */

  /**
   * @notice Emmited when ticket associated with this contract has been set
   * @param ticket Address of the ticket
   */
  event TicketSet(address indexed ticket);

  /**
   * @notice Emmited when tickets have been staked
   * @param staker Address of the staker
   * @param amount Amount of tokens staked
   */
  event TicketsStaked(address indexed staker, uint256 amount);

  /**
   * @notice Emmited when tickets have been unstaked
   * @param staker Address of the staker
   * @param recipient Address of the recipient that will receive the tickets
   * @param amount Amount of tokens staked
   */
  event TicketsUnstaked(address indexed staker, address indexed recipient, uint256 amount);

  /**
   * @notice Emmited when a new delegated position is minted
   * @param delegatedPosition Address of the NFT that was minted
   * @param tokenId Id of the NFT that has been minted to the delegatee
   * @param delegatee Address of the delegatee
   * @param amount Amount of tokens delegated
   */
  event Minted(
    address indexed delegatedPosition,
    uint256 indexed tokenId,
    address indexed delegatee,
    uint256 amount
  );

  /**
   * @notice Emmited when a delegated position is burned
   * @param tokenId Id of the NFT that has been burned
   * @param delegatee Address of the delegatee
   * @param amount Amount of tokens undelegated
   */
  event Burned(uint256 tokenId, address indexed delegatee, uint256 amount);

  /**
   * @notice Emmited when a representative is set
   * @param user Address of the user
   * @param representative Amount of the representative
   */
  event RepresentativeSet(address indexed user, address indexed representative);

  /**
   * @notice Emmited when a representative is removed
   * @param user Address of the user
   * @param representative Amount of the representative
   */
  event RepresentativeRemoved(address indexed user, address indexed representative);

  /* ============ Structs ============ */

  /**
   * @notice Struct to store metadata about a delegated position
   * @param staker Address of the staker
   * @param expiry Timestamp after which the delegated position can be transferred or burned
   */
  struct Delegation {
    address staker;
    uint96 expiry;
  }

  /* ============ Variables ============ */

  /// @notice Prize pool ticket to which this contract is tied to
  ITicket public immutable ticket;

  /// @notice Max expiry time during which a delegated position cannot be burned
  uint256 public constant MAX_EXPIRY = 60 days;

  /**
   * @notice Staked amount per staker address
   * @dev staker => amount
   */
  mapping(address => uint256) internal stakedAmount;

  /**
    @notice Delegation struct per tokenId.
    @dev tokenId => Delegation
  */
  mapping(uint256 => Delegation) public delegation;

  /**
   * @notice Representative elected by the staker to handle delegation.
   * @dev Representative can only handle delegation and cannot unstake tickets.
   * @dev staker => representative => bool allowing representative to represent the staker
   */
  mapping(address => mapping(address => bool)) public representative;

  /// @notice Counter increasing when minting unique delegated position NFTs
  uint256 public tokenIdCounter;

  /* ============ Constructor ============ */

  /**
   * @notice Contract constructor
   * @param _ticket Address of the prize pool ticket
   * @param _name Name of the NFT
   * @param _symbol Symbol of the NFT
   */
  constructor(
    address _ticket,
    string memory _name,
    string memory _symbol
  ) ERC721(_name, _symbol) {
    require(_ticket != address(0), "TWABDelegator/tick-not-zero-addr");
    ticket = ITicket(_ticket);

    delegatePositionInstance = new DelegatePosition();
    delegatePositionInstance.initialize();

    emit TicketSet(_ticket);
  }

  /* ============ External Functions ============ */

  /**
   * @notice Returns the amount of tickets staked by a `_staker`.
   * @param _staker Address of the staker
   * @return Amount of tickets staked by the `_staker`
   */
  function balanceOf(address _staker) public view override returns (uint256) {
    return stakedAmount[_staker];
  }

  /**
   * @notice Stake `_amount` of tickets in this contract.
   * @dev Tickets can be staked on behalf of a `_to` user.
   * @param _to Address to which the stake will be attributed
   * @param _amount Amount of tickets to stake
   */
  function stake(address _to, uint256 _amount) external {
    _requireRecipientNotZeroAddress(_to);
    _requireAmountGtZero(_amount);

    IERC20(ticket).safeTransferFrom(msg.sender, address(this), _amount);
    stakedAmount[_to] += _amount;

    emit TicketsStaked(_to, _amount);
  }

  /**
   * @notice Unstake `_amount` of tickets from this contract.
   * @dev Only callable by a staker.
   * @dev If staker has delegated his whole stake, he will first have to burn a delegated position to be able to unstake.
   * @param _to Address of the recipient that will receive the tickets
   * @param _amount Amount of tickets to unstake
   */
  function unstake(address _to, uint256 _amount) external onlyStaker {
    _requireRecipientNotZeroAddress(_to);
    _requireAmountGtZero(_amount);
    _requireAmountLtStakedAmount(stakedAmount[msg.sender], _amount);

    stakedAmount[msg.sender] -= _amount;
    IERC20(ticket).safeTransfer(_to, _amount);

    emit TicketsUnstaked(msg.sender, _to, _amount);
  }

  /**
   * @notice Mint an NFT representing the delegated `_amount` of tickets to `_delegatee`.
   * @dev Only callable by the `_staker` or his representative.
   * @dev Will revert if staked amount is less than `_amount`.
   * @dev Ticket delegation is handled in the `_beforeTokenTransfer` hook.
   * @param _staker Address of the staker
   * @param _delegatee Address of the delegatee
   * @param _amount Amount of tickets to delegate
   * @param _expiry Time during which the delegated position cannot be burned
   */
  function mint(
    address _staker,
    address _delegatee,
    uint256 _amount,
    uint96 _expiry
  ) external {
    _requireStakerOrRepresentative(_staker);
    require(_delegatee != address(0), "TWABDelegator/del-not-zero-addr");
    _requireAmountGtZero(_amount);
    _requireAmountLtStakedAmount(stakedAmount[_staker], _amount);
    require(_expiry <= MAX_EXPIRY, "TWABDelegator/expiry-too-long");

    stakedAmount[_staker] -= _amount;

    tokenIdCounter++;
    uint256 _tokenId = tokenIdCounter;

    address _delegatedPosition = address(_createDelegatePosition(_tokenId));

    IERC20(ticket).safeTransfer(_delegatedPosition, _amount);
    _safeMint(_delegatee, _tokenId);

    delegation[_tokenId] = Delegation({
      staker: _staker,
      expiry: uint96(block.timestamp) + _expiry
    });

    emit Minted(_delegatedPosition, _tokenId, _delegatee, _amount);
  }

  /**
   * @notice Burn the NFT representing the amount of tickets delegated to `_delegatee`.
   * @dev Only callable by the `_staker` or his representative.
   * @dev Will revert if expiry timestamp has not been reached.
   * @dev Tickets are withdrawn from the NFT in the `_beforeTokenTransfer` hook.
   * @param _tokenId Id of the NFT to burn
   */
  function burn(uint256 _tokenId) external {
    require(_tokenId > 0, "TWABDelegator/token-id-gt-zero");

    Delegation memory _delegation = delegation[_tokenId];
    require(block.timestamp > _delegation.expiry, "TWABDelegator/delegation-locked");

    address _staker = _delegation.staker;
    _requireStakerOrRepresentative(_staker);

    uint256 _balanceBefore = ticket.balanceOf(address(this));

    _burn(_tokenId);

    uint256 _balanceAfter = ticket.balanceOf(address(this));
    uint256 _burntAmount = _balanceAfter - _balanceBefore;

    stakedAmount[_staker] += _burntAmount;

    emit Burned(_tokenId, _staker, _burntAmount);
  }

  /**
   * @notice Allow a `msg.sender` to set a `_representative` to handle delegation.
   * @param _representative Address of the representative
   */
  function setRepresentative(address _representative) external {
    require(_representative != address(0), "TWABDelegator/rep-not-zero-addr");

    representative[msg.sender][_representative] = true;

    emit RepresentativeSet(msg.sender, _representative);
  }

  /**
   * @notice Allow `msg.sender` to remove a `_representative` associated to his address.
   * @dev Will revert if `_representative` is not associated to `msg.sender`.
   * @param _representative Address of the representative
   */
  function removeRepresentative(address _representative) external {
    require(_representative != address(0), "TWABDelegator/rep-not-zero-addr");
    require(representative[msg.sender][_representative], "TWABDelegator/rep-not-set");

    representative[msg.sender][_representative] = false;

    emit RepresentativeRemoved(msg.sender, _representative);
  }

  /* ============ Internal Functions ============ */

  /**
   * @notice Hook from OpenZeppelin ERC721 implementation.
   * @dev Called when an NFT is minted, burned or transferred.
   * @dev When burned, tickets will be withdrawn from the NFT and undelegated.
   * @dev When minted or transferred, tickets will be delegated to the new recipient `_to`.
   * @param _from Address of the sender
   * @param _to Address of the recipient
   * @param _tokenId Id of the NFT
   */
  function _beforeTokenTransfer(
    address _from,
    address _to,
    uint256 _tokenId
  ) internal override {
    DelegatePosition _delegatedPosition = DelegatePosition(_computeAddress(_tokenId));

    if (_to == address(0)) {
      _withdrawCall(_delegatedPosition);
      _delegateCall(_delegatedPosition, address(0));
      _delegatedPosition.destroy(payable(_from));
      delete delegation[_tokenId];
    } else {
      _delegateCall(_delegatedPosition, _to);
    }

    super._beforeTokenTransfer(_from, _to, _tokenId);
  }

  /**
   * @notice Computes the address of a clone, also known as minimal proxy contract.
   * @param _tokenId Token id of the NFT
   * @return Address at which the clone will be deployed
   */
  function _computeAddress(uint256 _tokenId) internal view returns (address) {
    return _computeAddress(_computeSalt(address(this), bytes32(_tokenId)));
  }

  /**
   * @notice Creates a delegated position
   * @dev This function will deploy a clone, also known as minimal proxy contract.
   * @param _tokenId ERC721 token id
   * @return Address of the newly created delegated position
   */
  function _createDelegatePosition(uint256 _tokenId) internal returns (DelegatePosition) {
    return _createDelegation(_computeSalt(address(this), bytes32(_tokenId)));
  }

  /**
   * @notice Call the `delegate` function on the delegated position.
   * @param _delegatedPosition Address of the delegated position contract
   * @param _delegatee Address of the delegatee
   */
  function _delegateCall(DelegatePosition _delegatedPosition, address _delegatee) internal {
    bytes4 _selector = ticket.delegate.selector;
    bytes memory _data = abi.encodeWithSelector(_selector, _delegatee);

    _executeCall(_delegatedPosition, _data);
  }

  /**
   * @notice Call the `transfer` function on the delegated position.
   * @dev Will withdraw all the tickets from the `_delegatedPosition` to this contract.
   * @param _delegatedPosition Address of the delegated position contract
   */
  function _withdrawCall(DelegatePosition _delegatedPosition) internal {
    bytes4 _selector = ticket.transfer.selector;
    uint256 _balance = ticket.balanceOf(address(_delegatedPosition));
    bytes memory _data = abi.encodeWithSelector(_selector, address(this), _balance);

    _executeCall(_delegatedPosition, _data);
  }

  /**
   * @notice Call the `delegate` function on the delegated position
   * @param _delegatedPosition Address of the delegated position contract
   * @param _data The call data that will be executed
   */
  function _executeCall(DelegatePosition _delegatedPosition, bytes memory _data) internal returns (bytes[] memory){
    DelegatePosition.Call[] memory _calls = new DelegatePosition.Call[](1);
    _calls[0] = DelegatePosition.Call({ to: address(ticket), value: 0, data: _data });

    return _delegatedPosition.executeCalls(_calls);
  }

  /* ============ Modifier/Require Functions ============ */

  /**
   * @notice Modifier to only allow the staker to call a function
   */
  modifier onlyStaker() {
    require(stakedAmount[msg.sender] > 0, "TWABDelegator/only-staker");
    _;
  }

  /**
   * @notice Require to only allow the staker or representative to call a function
   * @param _staker Address of the staker
   */
  function _requireStakerOrRepresentative(address _staker) internal view {
    require(
      _staker == msg.sender || representative[_staker][msg.sender] == true,
      "TWABDelegator/not-staker-or-rep"
    );
  }

  /**
   * @notice Require to verify that amount is greater than 0
   * @param _amount Amount to check
   */
  function _requireAmountGtZero(uint256 _amount) internal pure {
    require(_amount > 0, "TWABDelegator/amount-gt-zero");
  }

  /**
   * @notice Require to verify that amount is greater than 0
   * @param _to Address to check
   */
  function _requireRecipientNotZeroAddress(address _to) internal pure {
    require(_to != address(0), "TWABDelegator/to-not-zero-addr");
  }

  /**
   * @notice Require to verify that amount is greater than 0
   * @param _stakedAmount Amount of tickets staked by the staker
   * @param _amount Amount to check
   */
  function _requireAmountLtStakedAmount(uint256 _stakedAmount, uint256 _amount) internal pure {
    require(_stakedAmount >= _amount, "TWABDelegator/stake-lt-amount");
  }
}
