// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@pooltogether/v4-core/contracts/interfaces/ITicket.sol";

import "./DelegatePosition.sol";
import "./LowLevelDelegator.sol";
import "./PermitAndMulticall.sol";

/// @title Contract to delegate chances of winning to multiple delegatees
contract TWABDelegator is LowLevelDelegator, PermitAndMulticall {
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
   * @notice Emmited when a new delegated position is created
   * @param delegatedPosition Address of the delegated position that was created
   * @param staker Address of the staker
   * @param slot Slot of the delegated position
   * @param lockUntil Timestamp until which the delegated position is locked
   * @param delegatee Address of the delegatee
   * @param amount Amount of tokens delegated
   */
  event DelegationCreated(
    DelegatePosition indexed delegatedPosition,
    address indexed staker,
    uint256 slot,
    uint256 lockUntil,
    address indexed delegatee,
    uint256 amount
  );

  /**
   * @notice Emmited when a delegatee is updated
   * @param delegatedPosition Address of the delegated position that was created
   * @param staker Address of the staker
   * @param slot Slot of the delegated position
   * @param delegatee Address of the delegatee
   */
  event DelegateeUpdated(
    DelegatePosition indexed delegatedPosition,
    address indexed staker,
    uint256 slot,
    address indexed delegatee
  );

  /**
   * @notice Emmited when a delegated position is destroyed
   * @param staker Address of the staker
   * @param slot  Slot of the delegated position
   * @param amount Amount of tokens undelegated
   */
  event DelegationDestroyed(address indexed staker, uint256 indexed slot, uint256 amount);

  /**
   * @notice Emmited when a representative is set
   * @param staker Address of the staker
   * @param representative Amount of the representative
   */
  event RepresentativeSet(address indexed staker, address indexed representative);

  /**
   * @notice Emmited when a representative is removed
   * @param staker Address of the staker
   * @param representative Amount of the representative
   */
  event RepresentativeRemoved(address indexed staker, address indexed representative);

  /* ============ Variables ============ */

  /// @notice Prize pool ticket to which this contract is tied to
  ITicket public immutable ticket;

  /// @notice Max lock time during which a delegated position cannot be destroyed
  uint256 public constant MAX_LOCK = 60 days;

  /**
   * @notice Staked amount per staker address
   * @dev staker => amount
   */
  mapping(address => uint256) internal stakedAmount;

  /**
   * @notice Representative elected by the staker to handle delegation.
   * @dev Representative can only handle delegation and cannot unstake tickets.
   * @dev staker => representative => bool allowing representative to represent the staker
   */
  mapping(address => mapping(address => bool)) public representative;

  /* ============ Constructor ============ */

  /**
   * @notice Contract constructor
   * @param _ticket Address of the prize pool ticket
   */
  constructor(address _ticket) LowLevelDelegator() {
    require(_ticket != address(0), "TWABDelegator/tick-not-zero-addr");
    ticket = ITicket(_ticket);

    emit TicketSet(_ticket);
  }

  /* ============ External Functions ============ */

  /**
   * @notice Returns the amount of tickets staked by a `_staker`.
   * @param _staker Address of the staker
   * @return Amount of tickets staked by the `_staker`
   */
  function balanceOf(address _staker) public view returns (uint256) {
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
    _requireAmountLtEqStakedAmount(stakedAmount[msg.sender], _amount);

    stakedAmount[msg.sender] -= _amount;
    IERC20(ticket).safeTransfer(_to, _amount);

    emit TicketsUnstaked(msg.sender, _to, _amount);
  }

  /**
   * @notice Mint an NFT representing the delegated `_amount` of tickets to `_delegatee`.
   * @dev Only callable by the `_staker` or his representative.
   * @dev Will revert if staked amount is less than `_amount`.
   * @param _staker Address of the staker
   * @param _slot Slot of the delegated position
   * @param _delegatee Address of the delegatee
   * @param _amount Amount of tickets to delegate
   * @param _lockDuration Time during which the delegated position cannot be destroyed
   */
  function createDelegation(
    address _staker,
    uint256 _slot,
    address _delegatee,
    uint256 _amount,
    uint256 _lockDuration
  ) external {
    _requireStakerOrRepresentative(_staker);
    _requireDelegateeNotZeroAddress(_delegatee);
    _requireAmountGtZero(_amount);
    _requireAmountLtEqStakedAmount(stakedAmount[_staker], _amount);
    require(_lockDuration <= MAX_LOCK, "TWABDelegator/lock-too-long");

    stakedAmount[_staker] -= _amount;

    uint256 _lockUntil = block.timestamp + _lockDuration;
    DelegatePosition _delegatedPosition = _createDelegatedPosition(_staker, _slot, _lockUntil);

    IERC20(ticket).safeTransfer(address(_delegatedPosition), _amount);
    _delegateCall(_delegatedPosition, _delegatee);

    emit DelegationCreated(_delegatedPosition, _staker, _slot, _lockUntil, _delegatee, _amount);
  }

  /**
   * @notice Update a delegated position `delegatee` and `amount` delegated.
   * @dev Only callable by the `_staker` or his representative.
   * @dev Will revert if staked amount is less than `_amount`.
   * @dev Will revert if delegated position is still locked.
   * @param _staker Address of the staker
   * @param _slot Slot of the delegated position
   * @param _delegatee Address of the delegatee
   */
  function updateDelegatee(
    address _staker,
    uint256 _slot,
    address _delegatee
  ) external {
    _requireStakerOrRepresentative(_staker);
    _requireDelegateeNotZeroAddress(_delegatee);

    DelegatePosition _delegatedPosition = DelegatePosition(_computeAddress(_staker, _slot));
    _requireDelegatedPositionUnlocked(_delegatedPosition);

    _delegateCall(_delegatedPosition, _delegatee);

    emit DelegateeUpdated(_delegatedPosition, _staker, _slot, _delegatee);
  }

  /**
   * @notice Burn the NFT representing the amount of tickets delegated to `_delegatee`.
   * @dev Only callable by the `_staker` or his representative.
   * @dev Will revert if delegated position is still locked.
   */
  function destroyDelegation(address _staker, uint256 _slot) external {
    _requireStakerOrRepresentative(_staker);

    DelegatePosition _delegatedPosition = DelegatePosition(_computeAddress(_staker, _slot));
    _requireDelegatedPositionUnlocked(_delegatedPosition);

    uint256 _balanceBefore = ticket.balanceOf(address(this));

    _withdrawCall(_delegatedPosition);
    _delegateCall(_delegatedPosition, address(0));
    _delegatedPosition.destroy(payable(_staker));

    uint256 _balanceAfter = ticket.balanceOf(address(this));
    uint256 _burntAmount = _balanceAfter - _balanceBefore;

    stakedAmount[_staker] += _burntAmount;

    emit DelegationDestroyed(_staker, _slot, _burntAmount);
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

  /**
    * @notice Alow a user to approve ticket and run various calls in one transaction.
    * @param _from Address of the sender
    * @param _amount Amount of tickets to approve
    * @param _permitSignature Permit signature
    * @param _data Datas to call with `functionDelegateCall`
   */
  function permitAndMulticall(
    address _from,
    uint256 _amount,
    Signature calldata _permitSignature,
    bytes[] calldata _data
  ) external {
    _permitAndMulticall(IERC20Permit(address(ticket)), _from, _amount, _permitSignature, _data);
  }

  /* ============ Internal Functions ============ */

  /**
   * @notice Computes the address of a clone, also known as minimal proxy contract.
   * @param _staker Address of the staker
   * @param _slot Slot of the delegated position
   * @return Address at which the clone will be deployed
   */
  function _computeAddress(address _staker, uint256 _slot) internal view returns (address) {
    return _computeAddress(_computeSalt(_staker, bytes32(_slot)));
  }

  /**
   * @notice Creates a delegated position
   * @dev This function will deploy a clone, also known as minimal proxy contract.
   * @param _staker Address of the staker
   * @param _slot Slot of the delegated position
   * @param _lockUntil Timestamp until which the delegated position is locked
   * @return Address of the newly created delegated position
   */
  function _createDelegatedPosition(
    address _staker,
    uint256 _slot,
    uint256 _lockUntil
  ) internal returns (DelegatePosition) {
    return _createDelegation(_computeSalt(_staker, bytes32(_slot)), _lockUntil);
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
  function _executeCall(DelegatePosition _delegatedPosition, bytes memory _data)
    internal
    returns (bytes[] memory)
  {
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
   * @notice Require to verify that `_delegatee` is not address zero.
   * @param _delegatee Address of the delegatee
   */
  function _requireDelegateeNotZeroAddress(address _delegatee) internal pure {
    require(_delegatee != address(0), "TWABDelegator/del-not-zero-addr");
  }

  /**
   * @notice Require to verify that amount is greater than 0.
   * @param _amount Amount to check
   */
  function _requireAmountGtZero(uint256 _amount) internal pure {
    require(_amount > 0, "TWABDelegator/amount-gt-zero");
  }

  /**
   * @notice Require to verify that amount is greater than 0.
   * @param _to Address to check
   */
  function _requireRecipientNotZeroAddress(address _to) internal pure {
    require(_to != address(0), "TWABDelegator/to-not-zero-addr");
  }

  /**
   * @notice Require to verify that amount is greater than 0.
   * @param _stakedAmount Amount of tickets staked by the staker
   * @param _amount Amount to check
   */
  function _requireAmountLtEqStakedAmount(uint256 _stakedAmount, uint256 _amount) internal pure {
    require(_stakedAmount >= _amount, "TWABDelegator/stake-lt-amount");
  }

  /**
   * @notice Require to verify if a delegated position is locked.
   * @param _delegatedPosition Delegated position to check
   */
  function _requireDelegatedPositionUnlocked(DelegatePosition _delegatedPosition) internal view {
    require(block.timestamp > _delegatedPosition.lockUntil(), "TWABDelegator/delegation-locked");
  }
}
