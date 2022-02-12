// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@pooltogether/v4-core/contracts/interfaces/ITicket.sol";

import "./DelegatePosition.sol";

/// @title Contract to delegate chances of winning to multiple delegatees
contract TWABDelegator is ERC721 {
  using Clones for address;
  using SafeERC20 for IERC20;

  /// @notice Prize pool ticket to which this contract is tied to
  ITicket public immutable ticket;

  /// @notice The instance to which all proxies will point
  DelegatePosition public delegatePositionInstance;

  /**
   * @notice Emmited when a stake has been staked
   * @param staker Address of the staker
   * @param amount Amount of tokens staked
   */
  event TicketsStaked(address indexed staker, uint256 amount);

  /**
   * @notice Emmited when a stake has been delegated
   * @param delegatee Address of the delegatee
   * @param amount Amount of tokens delegated
   */
  event StakeDelegated(address indexed delegatee, uint256 amount);

  /**
   * @notice Emmited when a delegation is revoked
   * @param delegatee Address of the delegatee
   * @param amount Amount of tokens that were delegated
   */
  event DelegationRevoked(address indexed delegatee, uint256 amount);

  /// @notice Staked amount per staker address
  mapping(address => uint256) public stakedAmount;

  /**
    @notice Delegated amount by delegator per delegatee address
    @dev delegator => delegatee => amount
  */
  mapping(address => mapping(address => uint256)) public delegatedAmount;

  /**
    @notice Delegated position by delegator per delegatee address
    @dev delegator => delegatee => DelegatePosition
  */
  mapping(address => mapping(address => DelegatePosition)) public delegatedPosition;

  /**
    @notice Representative elected by the staker to handle delegation
    @dev staker => representative
  */
  mapping(address => address) public representative;

  /// @notice Counter to mint unique delegated position NFTs and deploy clones
  uint256 public tokenIdCounter;

  /* ============ Constructor ============ */

  /**
   * TODO: pass NFT name and symbol
   * @notice Contract constructor
   * @param _ticket Address of the prize pool ticket
   */
  constructor(address _ticket) ERC721("ERC721", "NFT") {
    require(_ticket != address(0), "TWABDelegator/ticket-not-zero-addr");
    ticket = ITicket(_ticket);

    delegatePositionInstance = new DelegatePosition();
    delegatePositionInstance.initialize();
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
   * @dev Tickets can be staked on behalf of a `_staker`.
   * @param _staker Address of the staker
   * @param _amount Amount of tickets to stake
   */
  function stake(address _staker, uint256 _amount) external {
    require(_staker != address(0), "TWABDelegator/to-not-zero-addr");

    IERC20(ticket).safeTransferFrom(msg.sender, address(this), _amount);
    stakedAmount[_staker] += _amount;

    emit TicketsStaked(_staker, _amount);
  }

  /**
    @notice Delegate `_amount` of tickets to `_delegatee`.
    @param _delegatee Address of the delegatee
    @param _amount Amount of tickets to delegate
  */
  function delegate(address _delegatee, uint256 _amount) external onlyStaker(msg.sender) {
    require(_delegatee != address(0), "TWABDelegator/del-not-zero-addr");
    require(_amount > 0, "TWABDelegator/amount-gt-zero");
    require(stakedAmount[msg.sender] >= _amount, "TWABDelegator/stake-lt-amount");

    stakedAmount[msg.sender] -= _amount;
    delegatedAmount[msg.sender][_delegatee] += _amount;

    tokenIdCounter++;
    uint256 _tokenIdCounter = tokenIdCounter;

    _mint(msg.sender, _tokenIdCounter);
    address _nftAddress = _computeAddress(_tokenIdCounter);

    IERC20(ticket).safeTransfer(_nftAddress, _amount);

    DelegatePosition _delegatedPosition = _createDelegatePosition(_delegatee, _tokenIdCounter);

    _delegateCall(_delegatedPosition, _delegatee);
    delegatedPosition[msg.sender][_delegatee] = _delegatedPosition;

    emit StakeDelegated(_delegatee, _amount);
  }

  /**
    @notice Revoke the total amount of tickets delegated to `_delegatee`.
    @param _delegatee Address of the delegatee
  */
  function revoke(address _delegatee) external onlyDelegator(_delegatee) {
    require(_delegatee != address(0), "TWABDelegator/delegatee-not-zero-addr");

    uint256 _amountDelegated = delegatedAmount[msg.sender][_delegatee];
    delegatedAmount[msg.sender][_delegatee] = 0;

    DelegatePosition _delegatedPosition = delegatedPosition[msg.sender][_delegatee];

    _delegateCall(_delegatedPosition, address(0));
    stakedAmount[msg.sender] += _amountDelegated;

    emit DelegationRevoked(_delegatee, _amountDelegated);
  }

  /**
    @notice Allow a staker to set a `_representative` to handle delegation.
    @param _representative Address of the representative
  */
  function setRepresentative(address _representative) external {
    require(_representative != address(0), "TWABDelegator/rep-not-zero-addr");
    representative[msg.sender] = _representative;
  }

  /* ============ Internal Functions ============ */

  /**
   * @notice Computes the address of a clone, also known as minimal proxy contract.
   * @param _tokenId Token id of the NFT
   * @return Address at which the clone will be deployed
   */
  function _computeAddress(uint256 _tokenId) internal view returns (address) {
    return
      address(delegatePositionInstance).predictDeterministicAddress(
        keccak256(abi.encodePacked(_tokenId)),
        address(this)
      );
  }

  /**
   * @notice Creates a delegated position
   * @dev This function will deploy a clone, also known as minimal proxy contract.
   * @param _delegatee Address of the delegatee
   * @param _tokenId ERC721 token id
   * @return Address of the newly delegated position
   */
  function _createDelegatePosition(address _delegatee, uint256 _tokenId)
    internal
    returns (DelegatePosition)
  {
    DelegatePosition _delegatedPosition = DelegatePosition(
      address(delegatePositionInstance).cloneDeterministic(keccak256(abi.encodePacked(_tokenId)))
    );

    delegatedPosition[msg.sender][_delegatee] = _delegatedPosition;

    _delegatedPosition.initialize();
    return _delegatedPosition;
  }

  /**
    @notice Call the `delegate` function on the delegated position
    @param _delegatedPosition Address of the delegated position contract
    @param _delegatee Address of the delegatee
  */
  function _delegateCall(DelegatePosition _delegatedPosition, address _delegatee) internal {
    bytes4 _selector = ticket.delegate.selector;
    bytes memory _data = abi.encodeWithSelector(_selector, _delegatee);

    DelegatePosition.Call[] memory _calls = new DelegatePosition.Call[](1);
    _calls[0] = DelegatePosition.Call({ to: address(ticket), value: 0, data: _data });

    _delegatedPosition.executeCalls(_calls);
  }

  /* ============ Modifier Functions ============ */

  /**
   * @notice Modifier to only allow the staker to call a function
   * @param _delegatee Address of the delegatee
   */
  modifier onlyStaker(address _delegatee) {
    require(stakedAmount[msg.sender] > 0, "TWABDelegator/only-staker");
    _;
  }

  /**
   * @notice Modifier to only allow the delegator to call a function
   * @param _delegatee Address of the delegatee
   */
  modifier onlyDelegator(address _delegatee) {
    require(address(delegatedPosition[msg.sender][_delegatee]) != address(0), "TWABDelegator/only-delegator");
    _;
  }
}
