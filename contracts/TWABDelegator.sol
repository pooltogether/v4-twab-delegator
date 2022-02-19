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
  using Address for address;
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
   * @param delegator Address of the delegator
   * @param amount Amount of tokens staked
   */
  event TicketsStaked(address indexed delegator, uint256 amount);

  /**
   * @notice Emmited when tickets have been unstaked
   * @param delegator Address of the delegator
   * @param recipient Address of the recipient that will receive the tickets
   * @param amount Amount of tokens staked
   */
  event TicketsUnstaked(address indexed delegator, address indexed recipient, uint256 amount);

  /**
   * @notice Emmited when a new delegated position is created
   * @param delegator delegator of the delegated position
   * @param slot Slot of the delegated position
   * @param lockUntil Timestamp until which the delegated position is locked
   * @param delegatee Address of the delegatee
   * @param delegatedPosition Address of the delegated position that was created
   * @param user Address of the user who created the delegated position
   */
  event DelegationCreated(
    address indexed delegator,
    uint256 indexed slot,
    uint256 lockUntil,
    address indexed delegatee,
    DelegatePosition delegatedPosition,
    address user
  );

  /**
   * @notice Emmited when a delegatee is updated
   * @param delegator Address of the delegator
   * @param slot Slot of the delegated position
   * @param delegatee Address of the delegatee
   * @param lockUntil Timestamp until which the delegated position is locked
   * @param user Address of the user who updated the delegatee
   */
  event DelegateeUpdated(
    address indexed delegator,
    uint256 indexed slot,
    address indexed delegatee,
    uint96 lockUntil,
    address user
  );

  /**
   * @notice Emmited when a delegated position is funded
   * @param delegator Address of the delegator
   * @param slot Slot of the delegated position
   * @param amount Amount of tokens that were sent to the delegated position
   * @param user Address of the user who funded the delegated position
   */
  event DelegationFunded(
    address indexed delegator,
    uint256 indexed slot,
    uint256 amount,
    address user
  );

  /**
   * @notice Emmited when a delegated position is funded
   * @param delegator Address of the delegator
   * @param slot Slot of the delegated position
   * @param amount Amount of tokens that were sent to the delegated position
   * @param user Address of the user who funded the delegated position
   */
  event DelegationFundedFromStake(
    address indexed delegator,
    uint256 indexed slot,
    uint256 amount,
    address user
  );

  /**
   * @notice Emmited when a delegated position is destroyed
   * @param delegator Address of the delegator
   * @param slot  Slot of the delegated position
   * @param amount Amount of tokens undelegated
   * @param user Address of the user who destroyed the delegated position
   */
  event WithdrewDelegationToStake(
    address indexed delegator,
    uint256 indexed slot,
    uint256 amount,
    address user
  );

  /**
   * @notice Emmited when a delegated position is destroyed
   * @param delegator Address of the delegator
   * @param slot  Slot of the delegated position
   * @param amount Amount of tokens undelegated
   */
  event WithdrewDelegation(
    address indexed delegator,
    uint256 indexed slot,
    uint256 amount
  );

  /**
   * @notice Emmited when a representative is set
   * @param delegator Address of the delegator
   * @param representative Amount of the representative
   */
  event RepresentativeSet(address indexed delegator, address indexed representative);

  /**
   * @notice Emmited when a representative is removed
   * @param delegator Address of the delegator
   * @param representative Amount of the representative
   */
  event RepresentativeRemoved(address indexed delegator, address indexed representative);

  /* ============ Variables ============ */

  /// @notice Prize pool ticket to which this contract is tied to
  ITicket public immutable ticket;

  /// @notice Max lock time during which a delegated position cannot be destroyed
  uint256 public constant MAX_LOCK = 60 days;

  /**
   * @notice Staked amount per delegator address
   * @dev delegator => amount
   */
  mapping(address => uint256) internal stakedAmount;

  /**
   * @notice Representative elected by the delegator to handle delegation.
   * @dev Representative can only handle delegation and cannot unstake tickets.
   * @dev delegator => representative => bool allowing representative to represent the delegator
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
   * @notice Returns the amount of tickets staked by a `_delegator`.
   * @param _delegator Address of the delegator
   * @return Amount of tickets staked by the `_delegator`
   */
  function balanceOf(address _delegator) public view returns (uint256) {
    return stakedAmount[_delegator];
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
   * @dev Only callable by a delegator.
   * @dev If delegator has delegated his whole stake, he will first have to burn a delegated position to be able to unstake.
   * @param _to Address of the recipient that will receive the tickets
   * @param _amount Amount of tickets to unstake
   */
  function unstake(address _to, uint256 _amount) external onlyDelegator {
    _requireRecipientNotZeroAddress(_to);
    _requireAmountGtZero(_amount);
    _requireAmountLtEqStakedAmount(stakedAmount[msg.sender], _amount);

    stakedAmount[msg.sender] -= _amount;
    IERC20(ticket).safeTransfer(_to, _amount);

    emit TicketsUnstaked(msg.sender, _to, _amount);
  }

  /**
   * @notice Creates a new delegated position.
   * @dev Callable by anyone.
   * @dev The `_delegator` and `_slot` params are used to compute the salt of the delegated position.
   * @param _delegator Address of the delegator that will be able to handle the delegated position
   * @param _slot Slot of the delegated position
   * @param _delegatee Address of the delegatee
   * @param _lockDuration Time during which the delegated position cannot be destroyed or updated
   */
  function createDelegation(
    address _delegator,
    uint256 _slot,
    address _delegatee,
    uint96 _lockDuration
  ) external {
    _requireDelegatorOrRepresentative(_delegator);
    _requireDelegateeNotZeroAddress(_delegatee);
    _requireLockDuration(_lockDuration);

    uint96 _lockUntil = uint96(block.timestamp) + _lockDuration;
    DelegatePosition _delegatedPosition = _createDelegatedPosition(_delegator, _slot, _lockUntil);
    _delegateCall(_delegatedPosition, _delegatee);

    emit DelegationCreated(
      _delegator,
      _slot,
      _lockUntil,
      _delegatee,
      _delegatedPosition,
      msg.sender
    );
  }

  /**
   * @notice Update a delegated position `delegatee` and `amount` delegated.
   * @dev Only callable by the `_delegator` or his representative.
   * @dev Will revert if staked amount is less than `_amount`.
   * @dev Will revert if delegated position is still locked.
   * @param _delegator Address of the delegator
   * @param _slot Slot of the delegated position
   * @param _delegatee Address of the delegatee
   * @param _lockDuration Time during which the delegated position cannot be destroyed or updated
   */
  function updateDelegatee(
    address _delegator,
    uint256 _slot,
    address _delegatee,
    uint96 _lockDuration
  ) external {
    _requireDelegatorOrRepresentative(_delegator);
    _requireDelegateeNotZeroAddress(_delegatee);
    _requireLockDuration(_lockDuration);

    DelegatePosition _delegatedPosition = DelegatePosition(_computeAddress(_delegator, _slot));
    _requireDelegatedPositionUnlocked(_delegatedPosition);

    uint96 _lockUntil = uint96(block.timestamp) + _lockDuration;

    if (_lockDuration > 0) {
      _delegatedPosition.setLockUntil(_lockUntil);
    }

    _delegateCall(_delegatedPosition, _delegatee);

    emit DelegateeUpdated(_delegator, _slot, _delegatee, _lockUntil, msg.sender);
  }

  /**
   * @notice Fund a delegation.
   * @dev Callable by anyone.
   * @dev Will revert if delegation does not exist.
   * @param _delegator Address of the delegator
   * @param _slot Slot of the delegation
   * @param _amount Amount of tickets to send to the delegation
   */
  function fundDelegation(
    address _delegator,
    uint256 _slot,
    uint256 _amount
  ) external {
    _requireDelegatorNotZeroAddress(_delegator);
    _requireAmountGtZero(_amount);

    address _delegation = address(DelegatePosition(_computeAddress(_delegator, _slot)));
    _requireContract(_delegation);

    IERC20(ticket).safeTransferFrom(msg.sender, _delegation, _amount);

    emit DelegationFunded(_delegator, _slot, _amount, msg.sender);
  }

  /**
   * @notice Fund a delegation using `_amount` of tokens that has been staked by the `_delegator`.
   * @dev Callable only by the `_delegator` or his representative.
   * @dev Will revert if delegation does not exist.
   * @dev Will revert if `_amount` is greater than the staked amount.
   * @param _delegator Address of the delegator
   * @param _slot Slot of the delegation
   * @param _amount Amount of tickets to send to the delegation
   */
  function fundDelegationFromStake(
    address _delegator,
    uint256 _slot,
    uint256 _amount
  ) external {
    _requireDelegatorOrRepresentative(_delegator);
    _requireAmountGtZero(_amount);
    _requireAmountLtEqStakedAmount(stakedAmount[_delegator], _amount);

    address _delegation = address(DelegatePosition(_computeAddress(_delegator, _slot)));
    _requireContract(_delegation);

    stakedAmount[_delegator] -= _amount;

    IERC20(ticket).safeTransfer(_delegation, _amount);

    emit DelegationFundedFromStake(_delegator, _slot, _amount, msg.sender);
  }

  /**
   * @notice Burn the NFT representing the amount of tickets delegated to `_delegatee`.
   * @dev Only callable by the `_delegator` or his representative.
   * @dev Will revert if delegated position is still locked.
   * @param _delegator Address of the delegator
   * @param _slot Slot of the delegation
   * @param _amount Amount to withdraw
   */
  function withdrawDelegationToStake(address _delegator, uint256 _slot, uint256 _amount) external {
    _requireDelegatorOrRepresentative(_delegator);

    DelegatePosition _delegatedPosition = DelegatePosition(_computeAddress(_delegator, _slot));

    uint256 _balanceBefore = ticket.balanceOf(address(this));

    _withdraw(_delegatedPosition, address(this), _amount);

    uint256 _balanceAfter = ticket.balanceOf(address(this));
    uint256 _withdrawnAmount = _balanceAfter - _balanceBefore;

    stakedAmount[_delegator] += _withdrawnAmount;

    emit WithdrewDelegationToStake(_delegator, _slot, _withdrawnAmount, msg.sender);
  }

  /**
   * @notice Burn the NFT representing the amount of tickets delegated to `_delegatee`.
   * @dev Only callable by the `_delegator` or his representative.
   * @dev Will revert if delegated position is still locked.
   * @param _slot Slot of the delegation
   * @param _amount Amount to withdraw
   */
  function withdrawDelegation(uint256 _slot, uint256 _amount) external {
    DelegatePosition _delegatedPosition = DelegatePosition(_computeAddress(msg.sender, _slot));
    _withdraw(_delegatedPosition, msg.sender, _amount);

    emit WithdrewDelegation(msg.sender, _slot, _amount);
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
   * @notice Allows a user to call multiple functions on the same contract.  Useful for EOA who want to batch transactions.
   * @param _data An array of encoded function calls.  The calls must be abi-encoded calls to this contract.
   * @return results The results from each function call
   */
  function multicall(bytes[] calldata _data) external returns (bytes[] memory results) {
    return _multicall(_data);
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

  /**
   * @notice Allows the caller to easily get the details for a delegation position.
   * @param _staker The address whose stake it is
   * @param _slot The delegation slot they are using
   * @return delegationPosition The address of the delegation position that holds ticket
   * @return delegatee The address that the position is delegating to
   * @return balance The balance of tickets held by the position
   * @return lockUntil The timestamp at which the position unlocks
   */
  function getDelegationPosition(address _staker, uint256 _slot)
    external
    view
    returns (
      address delegationPosition,
      address delegatee,
      uint256 balance,
      uint256 lockUntil
    )
  {
    DelegatePosition _delegatedPosition = DelegatePosition(_computeAddress(_staker, _slot));
    delegationPosition = address(_delegatedPosition);
    delegatee = ticket.delegateOf(address(_delegatedPosition));
    balance = ticket.balanceOf(address(_delegatedPosition));
    lockUntil = _delegatedPosition.lockUntil();
  }

  /**
   * @notice Computes the address of the delegated position for the staker + slot combination
   * @param _staker The user who is staking tickets
   * @param _slot The slot for which they are staking
   * @return The address of the delegation position.  This is the address that holds the balance of tickets.
   */
  function computeDelegationPositionAddress(address _staker, uint256 _slot)
    external
    view
    returns (address)
  {
    return _computeAddress(_staker, _slot);
  }

  /* ============ Internal Functions ============ */

  /**
   * @notice Computes the address of a clone, also known as minimal proxy contract.
   * @param _delegator Address of the delegator
   * @param _slot Slot of the delegated position
   * @return Address at which the clone will be deployed
   */
  function _computeAddress(address _delegator, uint256 _slot) internal view returns (address) {
    return _computeAddress(_computeSalt(_delegator, bytes32(_slot)));
  }

  /**
   * @notice Creates a delegated position
   * @dev This function will deploy a clone, also known as minimal proxy contract.
   * @param _delegator Address of the delegator
   * @param _slot Slot of the delegated position
   * @param _lockUntil Timestamp until which the delegated position is locked
   * @return Address of the newly created delegated position
   */
  function _createDelegatedPosition(
    address _delegator,
    uint256 _slot,
    uint96 _lockUntil
  ) internal returns (DelegatePosition) {
    return _createDelegation(_computeSalt(_delegator, bytes32(_slot)), _lockUntil);
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
   * @param _to Address of the recipient
   * @param _amount Amount to withdraw
   */
  function _withdrawCall(DelegatePosition _delegatedPosition, address _to, uint256 _amount) internal {
    bytes4 _selector = ticket.transfer.selector;
    bytes memory _data = abi.encodeWithSelector(_selector, _to, _amount);

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

  /**
    * @notice Withdraw from a delegation
    * @param _delegatedPosition Address of the delegated position contract
    * @param _to Address of the recipient
    * @param _amount Amount to withdraw
  */
  function _withdraw(DelegatePosition _delegatedPosition, address _to, uint256 _amount) internal {
    _requireAmountGtZero(_amount);
    _requireDelegatedPositionUnlocked(_delegatedPosition);

    _withdrawCall(_delegatedPosition, _to, _amount);
  }

  /* ============ Modifier/Require Functions ============ */

  /**
   * @notice Modifier to only allow the delegator to call a function
   */
  modifier onlyDelegator() {
    require(stakedAmount[msg.sender] > 0, "TWABDelegator/only-delegator");
    _;
  }

  /**
   * @notice Require to only allow the delegator or representative to call a function
   * @param _delegator Address of the delegator
   */
  function _requireDelegatorOrRepresentative(address _delegator) internal view {
    require(
      _delegator == msg.sender || representative[_delegator][msg.sender] == true,
      "TWABDelegator/not-delegator-or-rep"
    );
  }

  /**
   * @notice Require to verify that `_delegatee` is not address zero.
   * @param _delegatee Address of the delegatee
   */
  function _requireDelegateeNotZeroAddress(address _delegatee) internal pure {
    require(_delegatee != address(0), "TWABDelegator/dlgt-not-zero-adr");
  }

  /**
   * @notice Require to verify that amount is greater than 0.
   * @param _amount Amount to check
   */
  function _requireAmountGtZero(uint256 _amount) internal pure {
    require(_amount > 0, "TWABDelegator/amount-gt-zero");
  }

  /**
   * @notice Require to verify that the delegator is not address zero.
   * @param _delegator Address to check
   */
  function _requireDelegatorNotZeroAddress(address _delegator) internal pure {
    require(_delegator != address(0), "TWABDelegator/dlgtr-not-zero-adr");
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
   * @param _stakedAmount Amount of tickets staked by the delegator
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

  /**
   * @notice Require to verify that the address passed is a contract.
   * @param _address Address to check
   */
  function _requireContract(address _address) internal view {
    require(_address.isContract(), "TWABDelegator/not-a-contract");
  }

  /**
   * @notice Require to verify that a lock duration does not exceed the maximum lock duration.
   * @param _lockDuration Lock duration to check
   */
  function _requireLockDuration(uint256 _lockDuration) internal pure {
    require(_lockDuration <= MAX_LOCK, "TWABDelegator/lock-too-long");
  }
}
