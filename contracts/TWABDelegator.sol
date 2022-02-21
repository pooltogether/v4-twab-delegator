// SPDX-License-Identifier: GPL-3.0

pragma solidity 0.8.6;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@pooltogether/v4-core/contracts/interfaces/ITicket.sol";

import "./Delegation.sol";
import "./LowLevelDelegator.sol";
import "./PermitAndMulticall.sol";

/**
  * @title Contract to delegate chances of winning to multiple delegatees.
  * @dev Delegations are instantiated via CREATE2 through the LowLevelDelegator contract by calling `_createDelegation`.
  * @dev Delegators and their representatives can then handle their delegations through this contract.
 */
contract TWABDelegator is ERC20, LowLevelDelegator, PermitAndMulticall {
  using Address for address;
  using Clones for address;
  using SafeERC20 for IERC20;

  /* ============ Events ============ */

  /**
   * @notice Emmited when ticket associated with this contract has been set.
   * @param ticket Address of the ticket
   */
  event TicketSet(address indexed ticket);

  /**
   * @notice Emmited when tickets have been staked.
   * @param delegator Address of the delegator
   * @param amount Amount of tokens staked
   */
  event TicketsStaked(address indexed delegator, uint256 amount);

  /**
   * @notice Emmited when tickets have been unstaked.
   * @param delegator Address of the delegator
   * @param recipient Address of the recipient that will receive the tickets
   * @param amount Amount of tokens staked
   */
  event TicketsUnstaked(address indexed delegator, address indexed recipient, uint256 amount);

  /**
   * @notice Emmited when a new delegation is created.
   * @param delegator Delegator of the delegation
   * @param slot Slot of the delegation
   * @param lockUntil Timestamp until which the delegation is locked
   * @param delegatee Address of the delegatee
   * @param delegation Address of the delegation that was created
   * @param user Address of the user who created the delegation
   */
  event DelegationCreated(
    address indexed delegator,
    uint256 indexed slot,
    uint256 lockUntil,
    address indexed delegatee,
    Delegation delegation,
    address user
  );

  /**
   * @notice Emmited when a delegatee is updated.
   * @param delegator Address of the delegator
   * @param slot Slot of the delegation
   * @param delegatee Address of the delegatee
   * @param lockUntil Timestamp until which the delegation is locked
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
   * @notice Emmited when a delegation is funded.
   * @param delegator Address of the delegator
   * @param slot Slot of the delegation
   * @param amount Amount of tokens that were sent to the delegation
   * @param user Address of the user who funded the delegation
   */
  event DelegationFunded(
    address indexed delegator,
    uint256 indexed slot,
    uint256 amount,
    address user
  );

  /**
   * @notice Emmited when a delegation is funded from the staked amount.
   * @param delegator Address of the delegator
   * @param slot Slot of the delegation
   * @param amount Amount of tokens that were sent to the delegation
   * @param user Address of the user who funded the delegation
   */
  event DelegationFundedFromStake(
    address indexed delegator,
    uint256 indexed slot,
    uint256 amount,
    address user
  );

  /**
   * @notice Emmited when an amount of tickets has been withdrawn from a delegation to this contract.
   * @param delegator Address of the delegator
   * @param slot  Slot of the delegation
   * @param amount Amount of tickets withdrawn
   * @param user Address of the user who withdrew the tickets
   */
  event WithdrewDelegationToStake(
    address indexed delegator,
    uint256 indexed slot,
    uint256 amount,
    address user
  );

  /**
   * @notice Emmited when a delegator withdrawn an amount of tickets from a delegation to his wallet.
   * @param delegator Address of the delegator
   * @param slot  Slot of the delegation
   * @param amount Amount of tickets withdrawn
   */
  event WithdrewDelegation(address indexed delegator, uint256 indexed slot, uint256 amount);

  /**
   * @notice Emmited when a representative is set.
   * @param delegator Address of the delegator
   * @param representative Address of the representative
   * @param set Boolean indicating if the representative was set or unset
   */
  event RepresentativeSet(address indexed delegator, address indexed representative, bool set);

  /* ============ Variables ============ */

  /// @notice Prize pool ticket to which this contract is tied to.
  ITicket public immutable ticket;

  /// @notice Max lock time during which a delegation cannot be updated.
  uint256 public constant MAX_LOCK = 60 days;

  /**
   * @notice Representative elected by the delegator to handle delegation.
   * @dev Representative can only handle delegation and cannot withdraw tickets to their wallet.
   * @dev delegator => representative => bool allowing representative to represent the delegator
   */
  mapping(address => mapping(address => bool)) public representative;

  /* ============ Constructor ============ */

  /**
   * @notice Contract constructor.
   * @param _ticket Address of the prize pool ticket
   */
  constructor(string memory name_, string memory symbol_, address _ticket) LowLevelDelegator() ERC20(name_, symbol_) {
    require(_ticket != address(0), "TWABDelegator/tick-not-zero-addr");
    ticket = ITicket(_ticket);

    emit TicketSet(_ticket);
  }

  /* ============ External Functions ============ */

  /**
   * @notice Stake `_amount` of tickets in this contract.
   * @dev Tickets can be staked on behalf of a `_to` user.
   * @param _to Address to which the stake will be attributed
   * @param _amount Amount of tickets to stake
   */
  function stake(address _to, uint256 _amount) external {
    _requireRecipientNotZeroAddress(_to);
    _requireAmountGtZero(_amount);

    uint256 _balanceBefore = ticket.balanceOf(address(this));
    IERC20(ticket).safeTransferFrom(msg.sender, address(this), _amount);
    uint256 _balanceAfter = ticket.balanceOf(address(this));
    uint256 _transferredAmount = _balanceAfter - _balanceBefore;

    _mint(_to, _transferredAmount);

    emit TicketsStaked(_to, _amount);
  }

  /**
   * @notice Unstake `_amount` of tickets from this contract.
   * @dev Only callable by a delegator.
   * @dev If delegator has delegated his whole stake, he will first have to withdraw from a delegation to be able to unstake.
   * @param _to Address of the recipient that will receive the tickets
   * @param _amount Amount of tickets to unstake
   */
  function unstake(address _to, uint256 _amount) external {
    _requireRecipientNotZeroAddress(_to);
    _requireAmountGtZero(_amount);

    _burn(msg.sender, _amount);

    IERC20(ticket).safeTransfer(_to, _amount);

    emit TicketsUnstaked(msg.sender, _to, _amount);
  }

  /**
   * @notice Creates a new delegation.
   * @dev Callable by anyone.
   * @dev The `_delegator` and `_slot` params are used to compute the salt of the delegation.
   * @param _delegator Address of the delegator that will be able to handle the delegation
   * @param _slot Slot of the delegation
   * @param _delegatee Address of the delegatee
   * @param _lockDuration Time during which the delegation cannot be updated
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
    Delegation _delegation = _createDelegation(_delegator, _slot, _lockUntil);
    _delegateCall(_delegation, _delegatee);

    emit DelegationCreated(_delegator, _slot, _lockUntil, _delegatee, _delegation, msg.sender);
  }

  /**
   * @notice Update a delegation `delegatee` and `amount` delegated.
   * @dev Only callable by the `_delegator` or his representative.
   * @dev Will revert if staked amount is less than `_amount`.
   * @dev Will revert if delegation is still locked.
   * @param _delegator Address of the delegator
   * @param _slot Slot of the delegation
   * @param _delegatee Address of the delegatee
   * @param _lockDuration Time during which the delegation cannot be updated
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

    Delegation _delegation = Delegation(_computeAddress(_delegator, _slot));
    _requireDelegatedPositionUnlocked(_delegation);

    uint96 _lockUntil = uint96(block.timestamp) + _lockDuration;

    if (_lockDuration > 0) {
      _delegation.setLockUntil(_lockUntil);
    }

    _delegateCall(_delegation, _delegatee);

    emit DelegateeUpdated(_delegator, _slot, _delegatee, _lockUntil, msg.sender);
  }

  /**
   * @notice Fund a delegation.
   * @dev Callable by anyone.
   * @dev Will revert if delegation does not exist.
   * @param _delegator Address of the delegator
   * @param _slot Slot of the delegation
   * @param _amount Amount of tickets to delegate and send to the delegation
   */
  function fundDelegation(
    address _delegator,
    uint256 _slot,
    uint256 _amount
  ) external {
    _requireDelegatorNotZeroAddress(_delegator);
    _requireAmountGtZero(_amount);

    address _delegation = address(Delegation(_computeAddress(_delegator, _slot)));
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
   * @param _amount Amount of tickets from the staked amount to send to the delegation
   */
  function fundDelegationFromStake(
    address _delegator,
    uint256 _slot,
    uint256 _amount
  ) external {
    _requireDelegatorOrRepresentative(_delegator);
    _requireAmountGtZero(_amount);

    address _delegation = address(Delegation(_computeAddress(_delegator, _slot)));
    _requireContract(_delegation);

    _burn(_delegator, _amount);

    IERC20(ticket).safeTransfer(_delegation, _amount);

    emit DelegationFundedFromStake(_delegator, _slot, _amount, msg.sender);
  }

  /**
   * @notice Withdraw an amount of tickets from a delegation to this contract.
   * @dev Only callable by the `_delegator` or his representative.
   * @dev Will send the tickets to this contract and increase the `_delegator` staked amount.
   * @dev Will revert if delegation is still locked.
   * @param _delegator Address of the delegator
   * @param _slot Slot of the delegation
   * @param _amount Amount of tickets to withdraw
   */
  function withdrawDelegationToStake(
    address _delegator,
    uint256 _slot,
    uint256 _amount
  ) external {
    _requireDelegatorOrRepresentative(_delegator);

    Delegation _delegation = Delegation(_computeAddress(_delegator, _slot));

    uint256 _balanceBefore = ticket.balanceOf(address(this));

    _withdraw(_delegation, address(this), _amount);

    uint256 _balanceAfter = ticket.balanceOf(address(this));
    uint256 _withdrawnAmount = _balanceAfter - _balanceBefore;

    _mint(_delegator, _withdrawnAmount);

    emit WithdrewDelegationToStake(_delegator, _slot, _withdrawnAmount, msg.sender);
  }

  /**
   * @notice Withdraw an `_amount` of tickets from a delegation to the delegator wallet.
   * @dev Only callable by the delegator of the delegation.
   * @dev Will directly send the tickets to the delegator wallet.
   * @dev Will revert if delegation is still locked.
   * @param _slot Slot of the delegation
   * @param _amount Amount to withdraw
   */
  function withdrawDelegation(uint256 _slot, uint256 _amount) external {
    Delegation _delegation = Delegation(_computeAddress(msg.sender, _slot));
    _withdraw(_delegation, msg.sender, _amount);

    emit WithdrewDelegation(msg.sender, _slot, _amount);
  }

  /**
   * @notice Allow a `msg.sender` to set or unset a `_representative` to handle delegation.
   * @dev If `_set` is `true`, `_representative` will be set as representative of `msg.sender`.
   * @dev If `_set` is `false`, `_representative` will be unset as representative of `msg.sender`.
   * @param _representative Address of the representative
   * @param _set Set or unset the representative
   */
  function setRepresentative(address _representative, bool _set) external {
    require(_representative != address(0), "TWABDelegator/rep-not-zero-addr");

    representative[msg.sender][_representative] = _set;

    emit RepresentativeSet(msg.sender, _representative, _set);
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
   * @notice Allows the caller to easily get the details for a delegation.
   * @param _staker The address whose stake it is
   * @param _slot The delegation slot they are using
   * @return delegation The address of the delegation that holds tickets
   * @return delegatee The address that the position is delegating to
   * @return balance The balance of tickets held by the position
   * @return lockUntil The timestamp at which the position unlocks
   * @return wasCreated Whether or not the position has already been created
   */
  function getDelegation(address _staker, uint256 _slot)
    external
    view
    returns (
      address delegation,
      address delegatee,
      uint256 balance,
      uint256 lockUntil,
      bool wasCreated
    )
  {
    Delegation _delegation = Delegation(_computeAddress(_staker, _slot));

    delegation = address(_delegation);
    wasCreated = delegation.isContract();
    delegatee = ticket.delegateOf(address(_delegation));
    balance = ticket.balanceOf(address(_delegation));

    if (wasCreated) {
      lockUntil = _delegation.lockUntil();
    }
  }

  /**
   * @notice Computes the address of the delegation for the staker + slot combination.
   * @param _staker The user who is staking tickets
   * @param _slot The slot for which they are staking
   * @return The address of the delegation.  This is the address that holds the balance of tickets.
   */
  function computeDelegationAddress(address _staker, uint256 _slot)
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
   * @param _slot Slot of the delegation
   * @return Address at which the clone will be deployed
   */
  function _computeAddress(address _delegator, uint256 _slot) internal view returns (address) {
    return _computeAddress(_computeSalt(_delegator, bytes32(_slot)));
  }

  /**
   * @notice Creates a delegation.
   * @dev This function will deploy a clone, also known as minimal proxy contract.
   * @param _delegator Address of the delegator
   * @param _slot Slot of the delegation
   * @param _lockUntil Timestamp until which the delegation is locked
   * @return Address of the newly created delegation
   */
  function _createDelegation(
    address _delegator,
    uint256 _slot,
    uint96 _lockUntil
  ) internal returns (Delegation) {
    return _createDelegation(_computeSalt(_delegator, bytes32(_slot)), _lockUntil);
  }

  /**
   * @notice Call the ticket `delegate` function on the delegation.
   * @param _delegation Address of the delegation contract
   * @param _delegatee Address of the delegatee
   */
  function _delegateCall(Delegation _delegation, address _delegatee) internal {
    bytes4 _selector = ticket.delegate.selector;
    bytes memory _data = abi.encodeWithSelector(_selector, _delegatee);

    _executeCall(_delegation, _data);
  }

  /**
   * @notice Call the ticket `transfer` function on the delegation.
   * @dev Will withdraw `_amount` of tickets from the `_delegation` to the `_to` address.
   * @param _delegation Address of the delegation contract
   * @param _to Address of the recipient
   * @param _amount Amount of tickets to withdraw
   */
  function _withdrawCall(
    Delegation _delegation,
    address _to,
    uint256 _amount
  ) internal {
    bytes4 _selector = ticket.transfer.selector;
    bytes memory _data = abi.encodeWithSelector(_selector, _to, _amount);

    _executeCall(_delegation, _data);
  }

  /**
   * @notice Execute a function call to the ticket on the delegation.
   * @param _delegation Address of the delegation contract
   * @param _data The call data that will be executed
   */
  function _executeCall(Delegation _delegation, bytes memory _data)
    internal
    returns (bytes[] memory)
  {
    Delegation.Call[] memory _calls = new Delegation.Call[](1);
    _calls[0] = Delegation.Call({ to: address(ticket), value: 0, data: _data });

    return _delegation.executeCalls(_calls);
  }

  /**
   * @notice Withdraw tickets from a delegation.
   * @param _delegation Address of the delegation contract
   * @param _to Address of the recipient
   * @param _amount Amount of tickets to withdraw
   */
  function _withdraw(
    Delegation _delegation,
    address _to,
    uint256 _amount
  ) internal {
    _requireAmountGtZero(_amount);
    _requireDelegatedPositionUnlocked(_delegation);

    _withdrawCall(_delegation, _to, _amount);
  }

  /* ============ Modifier/Require Functions ============ */

  /**
   * @notice Require to only allow the delegator or representative to call a function.
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
   * @notice Require to verify that `_amount` is greater than 0.
   * @param _amount Amount to check
   */
  function _requireAmountGtZero(uint256 _amount) internal pure {
    require(_amount > 0, "TWABDelegator/amount-gt-zero");
  }

  /**
   * @notice Require to verify that `_delegator` is not address zero.
   * @param _delegator Address to check
   */
  function _requireDelegatorNotZeroAddress(address _delegator) internal pure {
    require(_delegator != address(0), "TWABDelegator/dlgtr-not-zero-adr");
  }

  /**
   * @notice Require to verify that `_to` is not address zero.
   * @param _to Address to check
   */
  function _requireRecipientNotZeroAddress(address _to) internal pure {
    require(_to != address(0), "TWABDelegator/to-not-zero-addr");
  }

  /**
   * @notice Require to verify if a `_delegation` is locked.
   * @param _delegation Delegation to check
   */
  function _requireDelegatedPositionUnlocked(Delegation _delegation) internal view {
    require(block.timestamp > _delegation.lockUntil(), "TWABDelegator/delegation-locked");
  }

  /**
   * @notice Require to verify that `_address` is a contract.
   * @param _address Address to check
   */
  function _requireContract(address _address) internal view {
    require(_address.isContract(), "TWABDelegator/not-a-contract");
  }

  /**
   * @notice Require to verify that a `_lockDuration` does not exceed the maximum lock duration.
   * @param _lockDuration Lock duration to check
   */
  function _requireLockDuration(uint256 _lockDuration) internal pure {
    require(_lockDuration <= MAX_LOCK, "TWABDelegator/lock-too-long");
  }
}
