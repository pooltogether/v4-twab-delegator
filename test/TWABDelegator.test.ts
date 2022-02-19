import { expect } from 'chai';
import { BigNumber, Contract, ContractFactory, Transaction } from 'ethers';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { beforeEach } from 'mocha';

const { constants, provider, utils } = ethers;
const { AddressZero, MaxUint256, Zero } = constants;
const { parseEther: toWei } = utils;

import { permitSignature } from './utils/permitSignature';
import { getEvents as getEventsUtil } from './utils/getEvents';
import { increaseTime as increaseTimeUtil } from './utils/increaseTime';

const getEvents = (tx: Transaction, contract: Contract) => getEventsUtil(provider, tx, contract);
const increaseTime = (time: number) => increaseTimeUtil(provider, time);

const MAX_EXPIRY = 5184000; // 60 days

const getTimestamp = async () => (await provider.getBlock('latest')).timestamp;

const getMaxExpiryTimestamp = async () =>
  (await provider.getBlock('latest')).timestamp + MAX_EXPIRY;

describe('Test Set Name', () => {
  let owner: SignerWithAddress;
  let representative: SignerWithAddress;
  let controller: SignerWithAddress;
  let firstDelegatee: SignerWithAddress;
  let secondDelegatee: SignerWithAddress;
  let stranger: SignerWithAddress;

  let ticket: Contract;
  let twabDelegator: Contract;

  let constructorTest = false;

  const getDelegatedPositionAddress = async (transaction: any) => {
    const ticketEvents = await getEvents(transaction, twabDelegator);
    const delegationCreatedEvent = ticketEvents.find(
      (event) => event && event.name === 'DelegationCreated',
    );
    return delegationCreatedEvent?.args['delegatedPosition'];
  };

  const deployTwabDelegator = async (ticketAddress = ticket.address) => {
    const twabDelegatorContractFactory: ContractFactory = await ethers.getContractFactory(
      'TWABDelegatorHarness',
    );

    return await twabDelegatorContractFactory.deploy(ticketAddress);
  };

  beforeEach(async () => {
    [owner, representative, controller, firstDelegatee, secondDelegatee, stranger] =
      await ethers.getSigners();

    const ticketContractFactory: ContractFactory = await ethers.getContractFactory('TicketHarness');
    ticket = await ticketContractFactory.deploy(
      'PoolTogether aUSDC Ticket',
      'PTaUSDC',
      18,
      controller.address,
    );

    if (!constructorTest) {
      twabDelegator = await deployTwabDelegator();
    }
  });

  describe('constructor()', () => {
    beforeEach(() => {
      constructorTest = true;
    });

    afterEach(() => {
      constructorTest = false;
    });

    it('should deploy and set ticket', async () => {
      const twabDelegator = await deployTwabDelegator();

      await expect(twabDelegator.deployTransaction)
        .to.emit(twabDelegator, 'TicketSet')
        .withArgs(ticket.address);
    });

    it('should fail to deploy if ticket address is address zero', async () => {
      await expect(deployTwabDelegator(AddressZero)).to.be.revertedWith(
        'TWABDelegator/tick-not-zero-addr',
      );
    });
  });

  describe('stake()', () => {
    let amount: BigNumber;

    beforeEach(async () => {
      amount = toWei('1000');

      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);
    });

    it('should allow a ticket holder to stake tickets', async () => {
      await expect(twabDelegator.stake(owner.address, amount))
        .to.emit(twabDelegator, 'TicketsStaked')
        .withArgs(owner.address, amount);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(amount);
      expect(await ticket.balanceOf(owner.address)).to.eq(Zero);
      expect(await twabDelegator.balanceOf(owner.address)).to.eq(amount);
    });

    it('should allow a ticket holder to stake tickets on behalf of another user', async () => {
      await expect(twabDelegator.stake(stranger.address, amount))
        .to.emit(twabDelegator, 'TicketsStaked')
        .withArgs(stranger.address, amount);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(amount);
      expect(await ticket.balanceOf(owner.address)).to.eq(Zero);
      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);
      expect(await twabDelegator.balanceOf(stranger.address)).to.eq(amount);
    });

    it('should fail to stake tickets if recipient is address zero', async () => {
      await expect(twabDelegator.stake(AddressZero, amount)).to.be.revertedWith(
        'TWABDelegator/to-not-zero-addr',
      );
    });

    it('should fail to stake tickets if amount is not greater than zero', async () => {
      await expect(twabDelegator.stake(owner.address, Zero)).to.be.revertedWith(
        'TWABDelegator/amount-gt-zero',
      );
    });
  });

  describe('balanceOf()', () => {
    it('should return delegator balance', async () => {
      const amount = toWei('1000');

      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);
      await twabDelegator.stake(owner.address, amount);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(amount);
      expect(await ticket.balanceOf(owner.address)).to.eq(Zero);
      expect(await twabDelegator.balanceOf(owner.address)).to.eq(amount);
    });

    it('should return 0 if address has no stake', async () => {
      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);
    });
  });

  describe('unstake()', () => {
    let amount: BigNumber;

    beforeEach(async () => {
      amount = toWei('1000');

      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);
    });

    it('should allow a delegator to unstake tickets', async () => {
      await twabDelegator.stake(owner.address, amount);

      await expect(twabDelegator.unstake(owner.address, amount))
        .to.emit(twabDelegator, 'TicketsUnstaked')
        .withArgs(owner.address, owner.address, amount);

      expect(await twabDelegator.callStatic.balanceOf(owner.address)).to.eq(Zero);
      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);
      expect(await ticket.balanceOf(owner.address)).to.eq(amount);
    });

    it('should allow a delegator to unstake tickets and send them to another user', async () => {
      await twabDelegator.stake(owner.address, amount);

      await expect(twabDelegator.unstake(stranger.address, amount))
        .to.emit(twabDelegator, 'TicketsUnstaked')
        .withArgs(owner.address, stranger.address, amount);

      expect(await twabDelegator.callStatic.balanceOf(owner.address)).to.eq(Zero);
      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);
      expect(await ticket.balanceOf(owner.address)).to.eq(Zero);
      expect(await ticket.balanceOf(stranger.address)).to.eq(amount);
    });

    it('should fail to unstake if caller is a representative', async () => {
      await twabDelegator.stake(owner.address, amount);
      await twabDelegator.setRepresentative(representative.address);

      await expect(
        twabDelegator.connect(representative).unstake(owner.address, amount),
      ).to.be.revertedWith('TWABDelegator/only-delegator');
    });

    it('should fail to unstake if caller has no stake', async () => {
      await expect(twabDelegator.unstake(owner.address, amount)).to.be.revertedWith(
        'TWABDelegator/only-delegator',
      );
    });

    it('should fail to unstake if recipient is address zero', async () => {
      await twabDelegator.stake(owner.address, amount);

      await expect(twabDelegator.unstake(AddressZero, amount)).to.be.revertedWith(
        'TWABDelegator/to-not-zero-addr',
      );
    });

    it('should fail to unstake if amount is zero', async () => {
      await twabDelegator.stake(owner.address, amount);

      await expect(twabDelegator.unstake(owner.address, Zero)).to.be.revertedWith(
        'TWABDelegator/amount-gt-zero',
      );
    });

    it('should fail to unstake if amount is greater than staked amount', async () => {
      await twabDelegator.stake(owner.address, amount);

      await expect(twabDelegator.unstake(owner.address, toWei('1500'))).to.be.revertedWith(
        'TWABDelegator/stake-lt-amount',
      );
    });
  });

  describe('createDelegation()', () => {
    const amount = toWei('1000');

    beforeEach(async () => {
      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);
    });

    it('should allow anyone to create a delegation', async () => {
      const transaction = await twabDelegator.createDelegation(
        owner.address,
        0,
        firstDelegatee.address,
        MAX_EXPIRY,
      );

      const delegationAddress = await getDelegatedPositionAddress(transaction);
      const expiryTimestamp = await getMaxExpiryTimestamp();

      await expect(await transaction)
        .to.emit(twabDelegator, 'DelegationCreated')
        .withArgs(
          owner.address,
          0,
          expiryTimestamp,
          firstDelegatee.address,
          delegationAddress,
          owner.address,
        );

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);
      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);
      expect(await ticket.balanceOf(owner.address)).to.eq(amount);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(accountDetails.balance).to.eq(Zero);

      const delegatedPosition = await ethers.getContractAt('DelegatePosition', delegationAddress);

      expect(await delegatedPosition.lockUntil()).to.eq(expiryTimestamp);

      expect(await ticket.balanceOf(delegationAddress)).to.eq(Zero);
      expect(await ticket.delegateOf(delegationAddress)).to.eq(firstDelegatee.address);
    });

    it('should fail to create a delegation if slot passed is already used', async () => {
      await twabDelegator.createDelegation(owner.address, 0, firstDelegatee.address, MAX_EXPIRY);

      await expect(
        twabDelegator.createDelegation(owner.address, 0, secondDelegatee.address, MAX_EXPIRY),
      ).to.be.revertedWith('ERC1167: create2 failed');
    });

    it('should fail to create delegation if delegator is address zero', async () => {
      await expect(
        twabDelegator.createDelegation(AddressZero, 0, firstDelegatee.address, MAX_EXPIRY),
      ).to.be.revertedWith('TWABDelegator/not-delegator-or-rep');
    });

    it('should fail to create delegation if delegatee is address zero', async () => {
      await expect(
        twabDelegator.createDelegation(owner.address, 0, AddressZero, MAX_EXPIRY),
      ).to.be.revertedWith('TWABDelegator/dlgt-not-zero-adr');
    });

    it('should fail to create delegation if expiry is greater than 60 days', async () => {
      await expect(
        twabDelegator.createDelegation(owner.address, 0, firstDelegatee.address, MAX_EXPIRY + 1),
      ).to.be.revertedWith('TWABDelegator/lock-too-long');
    });
  });

  describe('updateDelegatee()', () => {
    const amount = toWei('1000');
    let delegatedPositionAddress = '';

    beforeEach(async () => {
      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);
      await twabDelegator.stake(owner.address, amount);

      const transaction = await twabDelegator.createDelegation(
        owner.address,
        0,
        firstDelegatee.address,
        MAX_EXPIRY,
      );

      delegatedPositionAddress = await getDelegatedPositionAddress(transaction);

      await twabDelegator.fundDelegationFromStake(owner.address, 0, amount);
    });

    it('should allow a delegator to transfer a delegation to another delegatee', async () => {
      await increaseTime(MAX_EXPIRY + 1);

      expect(await twabDelegator.updateDelegatee(owner.address, 0, secondDelegatee.address, 0))
        .to.emit(twabDelegator, 'DelegateeUpdated')
        .withArgs(owner.address, 0, secondDelegatee.address, await getTimestamp(), owner.address);

      const firstDelegateeAccountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(firstDelegateeAccountDetails.balance).to.eq(Zero);

      const secondDelegateeAccountDetails = await ticket.getAccountDetails(secondDelegatee.address);
      expect(secondDelegateeAccountDetails.balance).to.eq(amount);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);
      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(amount);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(secondDelegatee.address);
    });

    it('should allow a delegator update the lock duration', async () => {
      await increaseTime(MAX_EXPIRY + 1);

      expect(await twabDelegator.updateDelegatee(owner.address, 0, secondDelegatee.address, MAX_EXPIRY))
        .to.emit(twabDelegator, 'DelegateeUpdated')
        .withArgs(owner.address, 0, secondDelegatee.address, await getMaxExpiryTimestamp(), owner.address);

      const delegatedPosition = await twabDelegator.getDelegationPosition(owner.address, 0);
      expect(delegatedPosition.lockUntil).to.equal(await getTimestamp() + MAX_EXPIRY);
    });

    it('should allow a delegator to destroy a delegated position that was transferred to another user', async () => {
      await increaseTime(MAX_EXPIRY + 1);

      await twabDelegator.updateDelegatee(owner.address, 0, secondDelegatee.address, 0);

      expect(await twabDelegator.withdrawDelegationToStake(owner.address, 0, amount))
        .to.emit(twabDelegator, 'WithdrewDelegationToStake')
        .withArgs(owner.address, 0, amount, owner.address);

      const firstDelegateeAccountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(firstDelegateeAccountDetails.balance).to.eq(Zero);

      const secondDelegateeAccountDetails = await ticket.getAccountDetails(secondDelegatee.address);
      expect(secondDelegateeAccountDetails.balance).to.eq(Zero);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(amount);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(amount);
      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(Zero);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(secondDelegatee.address);
    });

    it('should fail to update a delegatee if caller is not the delegator or representative of the delegated position', async () => {
      await expect(
        twabDelegator.connect(stranger).updateDelegatee(owner.address, 0, secondDelegatee.address, 0),
      ).to.be.revertedWith('TWABDelegator/not-delegator-or-rep');
    });

    it('should fail to update a delegatee if delegatee address passed is address zero', async () => {
      await expect(twabDelegator.updateDelegatee(owner.address, 0, AddressZero, 0)).to.be.revertedWith(
        'TWABDelegator/dlgt-not-zero-adr',
      );
    });

    it('should fail to update an inexistent delegated position', async () => {
      await expect(
        twabDelegator.updateDelegatee(owner.address, 1, secondDelegatee.address, 0),
      ).to.be.revertedWith('Transaction reverted: function call to a non-contract account');
    });

    it('should fail to update a delegatee if delegation is still locked', async () => {
      await expect(
        twabDelegator.updateDelegatee(owner.address, 0, secondDelegatee.address, 0),
      ).to.be.revertedWith('TWABDelegator/delegation-locked');
    });
  });

  describe('fundDelegation()', () => {
    const amount = toWei('1000');
    let delegatedPositionAddress = '';

    beforeEach(async () => {
      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);

      await ticket.mint(stranger.address, amount);
      await ticket.connect(stranger).approve(twabDelegator.address, MaxUint256);

      const transaction = await twabDelegator.createDelegation(
        owner.address,
        0,
        firstDelegatee.address,
        MAX_EXPIRY,
      );
      delegatedPositionAddress = await getDelegatedPositionAddress(transaction);
    });

    it('should allow any user to transfer tickets to a delegated position', async () => {
      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(Zero);

      expect(await twabDelegator.connect(stranger).fundDelegation(owner.address, 0, amount))
        .to.emit(twabDelegator, 'DelegationFunded')
        .withArgs(owner.address, 0, amount, stranger.address);

      const firstDelegateeAccountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(firstDelegateeAccountDetails.balance).to.eq(amount);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);
      expect(await twabDelegator.balanceOf(stranger.address)).to.eq(Zero);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);
      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(amount);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(firstDelegatee.address);
    });

    it('should fail to transfer tickets to a delegated position if delegator passed is address zero', async () => {
      await expect(
        twabDelegator.connect(stranger).fundDelegation(AddressZero, 0, amount),
      ).to.be.revertedWith('TWABDelegator/dlgtr-not-zero-adr');
    });

    it('should fail to transfer tickets to a delegated position if amount passed is not greater than zero', async () => {
      await expect(
        twabDelegator.connect(stranger).fundDelegation(owner.address, 0, Zero),
      ).to.be.revertedWith('TWABDelegator/amount-gt-zero');
    });

    it('should fail to fund an inexistent delegated position', async () => {
      await expect(
        twabDelegator.connect(stranger).fundDelegation(owner.address, 1, amount),
      ).to.be.revertedWith('TWABDelegator/not-a-contract');
    });
  });

  describe('fundDelegationFromStake()', () => {
    const amount = toWei('1000');
    let delegatedPositionAddress = '';

    beforeEach(async () => {
      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);

      await ticket.mint(stranger.address, amount);
      await ticket.connect(stranger).approve(twabDelegator.address, MaxUint256);

      await twabDelegator.stake(owner.address, amount);

      const transaction = await twabDelegator.createDelegation(
        owner.address,
        0,
        firstDelegatee.address,
        MAX_EXPIRY,
      );
      delegatedPositionAddress = await getDelegatedPositionAddress(transaction);
    });

    it('should allow a delegator to transfer tickets from his stake to a delegation', async () => {
      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(Zero);

      expect(await twabDelegator.fundDelegationFromStake(owner.address, 0, amount))
        .to.emit(twabDelegator, 'DelegationFundedFromStake')
        .withArgs(owner.address, 0, amount, owner.address);

      const firstDelegateeAccountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(firstDelegateeAccountDetails.balance).to.eq(amount);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);
      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(amount);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(firstDelegatee.address);
    });

    it('should fail to transfer tickets to a delegation if delegator passed is not a delegator', async () => {
      await expect(
        twabDelegator.fundDelegationFromStake(stranger.address, 0, amount),
      ).to.be.revertedWith('TWABDelegator/not-delegator-or-rep');
    });

    it('should fail to transfer tickets to a delegation if amount passed is not greater than zero', async () => {
      await expect(
        twabDelegator.fundDelegationFromStake(owner.address, 0, Zero),
      ).to.be.revertedWith('TWABDelegator/amount-gt-zero');
    });

    it('should fail to transfer tickets to a delegation if amount passed is greater than amount staked', async () => {
      await expect(
        twabDelegator.fundDelegationFromStake(owner.address, 0, amount.mul(2)),
      ).to.be.revertedWith('TWABDelegator/stake-lt-amount');
    });

    it('should fail to fund an inexistent delegation', async () => {
      await expect(
        twabDelegator.fundDelegationFromStake(owner.address, 1, amount),
      ).to.be.revertedWith('TWABDelegator/not-a-contract');
    });
  });

  describe('withdrawDelegationToStake()', () => {
    const amount = toWei('1000');
    let delegatedPositionAddress = '';

    beforeEach(async () => {
      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);
      await twabDelegator.stake(owner.address, amount);

      const transaction = await twabDelegator.createDelegation(
        owner.address,
        0,
        firstDelegatee.address,
        MAX_EXPIRY,
      );

      delegatedPositionAddress = await getDelegatedPositionAddress(transaction);

      await twabDelegator.fundDelegationFromStake(owner.address, 0, amount);
    });

    it('should allow a delegator to withdraw from a delegation to the stake', async () => {
      await increaseTime(MAX_EXPIRY + 1);

      expect(await twabDelegator.withdrawDelegationToStake(owner.address, 0, amount))
        .to.emit(twabDelegator, 'WithdrewDelegationToStake')
        .withArgs(owner.address, 0, amount, owner.address);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(amount);
      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(amount);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(accountDetails.balance).to.eq(Zero);

      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(Zero);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(firstDelegatee.address);
    });

    it('should allow a representative to withdraw from a delegation to the stake', async () => {
      await increaseTime(MAX_EXPIRY + 1);
      await twabDelegator.setRepresentative(representative.address);

      expect(await twabDelegator.connect(representative).withdrawDelegationToStake(owner.address, 0, amount))
        .to.emit(twabDelegator, 'WithdrewDelegationToStake')
        .withArgs(owner.address, 0, amount, representative.address);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(amount);
      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(amount);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(accountDetails.balance).to.eq(Zero);

      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(Zero);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(firstDelegatee.address);
    });

    it('should fail to withdraw from a delegation to the stake if amount is not greater than zero', async () => {
      await expect(
        twabDelegator.withdrawDelegationToStake(owner.address, 0, Zero),
      ).to.be.revertedWith('TWABDelegator/amount-gt-zero');
    });

    it('should fail to withdraw from a delegation to the stake if caller is not the delegator or representative of the delegated position', async () => {
      await expect(
        twabDelegator.connect(stranger).withdrawDelegationToStake(owner.address, 0, amount),
      ).to.be.revertedWith('TWABDelegator/not-delegator-or-rep');
    });

    it('should fail to withdraw from a delegation to the stake an inexistent delegated position', async () => {
      await expect(twabDelegator.withdrawDelegationToStake(owner.address, 1, amount)).to.be.revertedWith(
        'Transaction reverted: function call to a non-contract account',
      );
    });

    it('should fail to withdraw from a delegation to the stake a delegated position if delegation is still locked', async () => {
      await expect(twabDelegator.withdrawDelegationToStake(owner.address, 0, amount)).to.be.revertedWith(
        'TWABDelegator/delegation-locked',
      );
    });
  });

  describe('withdrawDelegation()', () => {
    const amount = toWei('1000');
    let delegatedPositionAddress = '';

    beforeEach(async () => {
      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);
      await twabDelegator.stake(owner.address, amount);

      const transaction = await twabDelegator.createDelegation(
        owner.address,
        0,
        firstDelegatee.address,
        MAX_EXPIRY,
      );

      delegatedPositionAddress = await getDelegatedPositionAddress(transaction);

      await twabDelegator.fundDelegationFromStake(owner.address, 0, amount);
    });

    it('should allow a delegator to withdraw from a delegation', async () => {
      await increaseTime(MAX_EXPIRY + 1);

      expect(await twabDelegator.withdrawDelegation(0, amount))
        .to.emit(twabDelegator, 'WithdrewDelegation')
        .withArgs(owner.address, 0, amount);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);
      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);
      expect(await ticket.balanceOf(owner.address)).to.eq(amount);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(accountDetails.balance).to.eq(Zero);

      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(Zero);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(firstDelegatee.address);
    });

    it('should not allow a representative to withdraw from a delegation', async () => {
      await increaseTime(MAX_EXPIRY + 1);
      await twabDelegator.setRepresentative(representative.address);

      await expect(twabDelegator.connect(representative).withdrawDelegation(0, amount))
        .to.be.revertedWith('Transaction reverted: function call to a non-contract account');
    });

    it('should fail to withdraw from a delegation if amount is not greater than zero', async () => {
      await expect(
        twabDelegator.withdrawDelegation(0, Zero),
      ).to.be.revertedWith('TWABDelegator/amount-gt-zero');
    });

    it('should fail to withdraw from a delegation if caller is not the delegator', async () => {
      await expect(
        twabDelegator.connect(stranger).withdrawDelegation(0, amount),
      ).to.be.revertedWith('Transaction reverted: function call to a non-contract account');
    });

    it('should fail to withdraw from an inexistent delegation', async () => {
      await expect(twabDelegator.withdrawDelegation(1, amount)).to.be.revertedWith(
        'Transaction reverted: function call to a non-contract account',
      );
    });

    it('should fail to withdraw from a delegation if still locked', async () => {
      await expect(twabDelegator.withdrawDelegation(0, amount)).to.be.revertedWith(
        'TWABDelegator/delegation-locked',
      );
    });
  });

  describe('setRepresentative()', () => {
    it('should set a representative', async () => {
      expect(await twabDelegator.setRepresentative(representative.address))
        .to.emit(twabDelegator, 'RepresentativeSet')
        .withArgs(owner.address, representative.address);

      expect(await twabDelegator.representative(owner.address, representative.address)).to.eq(true);
    });

    it('should set several representatives', async () => {
      expect(await twabDelegator.setRepresentative(representative.address))
        .to.emit(twabDelegator, 'RepresentativeSet')
        .withArgs(owner.address, representative.address);

      expect(await twabDelegator.representative(owner.address, representative.address)).to.eq(true);

      expect(await twabDelegator.setRepresentative(stranger.address))
        .to.emit(twabDelegator, 'RepresentativeSet')
        .withArgs(owner.address, stranger.address);

      expect(await twabDelegator.representative(owner.address, stranger.address)).to.eq(true);
    });

    it('should fail to set a representative if passed address is address zero', async () => {
      await expect(twabDelegator.setRepresentative(AddressZero)).to.be.revertedWith(
        'TWABDelegator/rep-not-zero-addr',
      );
    });
  });

  describe('removeRepresentative()', () => {
    it('should remove a representative', async () => {
      await twabDelegator.setRepresentative(representative.address);

      expect(await twabDelegator.removeRepresentative(representative.address))
        .to.emit(twabDelegator, 'RepresentativeRemoved')
        .withArgs(owner.address, representative.address);

      expect(await twabDelegator.representative(owner.address, representative.address)).to.eq(
        false,
      );
    });

    it('should fail to remove a representative if passed address is address zero', async () => {
      await expect(twabDelegator.removeRepresentative(AddressZero)).to.be.revertedWith(
        'TWABDelegator/rep-not-zero-addr',
      );
    });

    it('should fail to remove a representative if passed address is not a representative', async () => {
      await expect(twabDelegator.removeRepresentative(stranger.address)).to.be.revertedWith(
        'TWABDelegator/rep-not-set',
      );
    });
  });

  describe('multicall()', () => {
    it('should allow a user to run multiple transactions in one go', async () => {
      const amount = toWei('1000');
      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, amount);

      const stakeTx = await twabDelegator.populateTransaction.stake(owner.address, amount);

      const createDelegationTx = await twabDelegator.populateTransaction.createDelegation(
        owner.address,
        0,
        firstDelegatee.address,
        0,
      );

      await twabDelegator.multicall([stakeTx.data, createDelegationTx.data]);
    });
  });

  describe('permitAndMulticall()', () => {
    it('should allow a user to stake in one transaction', async () => {
      const amount = toWei('1000');
      await ticket.mint(owner.address, amount);

      const signature = await permitSignature({
        permitToken: ticket.address,
        fromWallet: owner,
        spender: twabDelegator.address,
        amount,
        provider,
      });

      const stakeTx = await twabDelegator.populateTransaction.stake(owner.address, amount);

      const createDelegationTx = await twabDelegator.populateTransaction.createDelegation(
        owner.address,
        0,
        firstDelegatee.address,
        0,
      );

      await twabDelegator.permitAndMulticall(
        owner.address,
        amount,
        { v: signature.v, r: signature.r, s: signature.s, deadline: signature.deadline },
        [stakeTx.data, createDelegationTx.data],
      );
    });
  });

  describe('getDelegationPosition()', () => {
    it('should allow a user to get the delegate position info', async () => {
      const amount = toWei('1000');
      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);
      await twabDelegator.stake(owner.address, amount);
      const transaction = await twabDelegator.createDelegation(
        owner.address,
        0,
        firstDelegatee.address,
        MAX_EXPIRY,
      );

      await twabDelegator.fundDelegationFromStake(owner.address, 0, amount);

      const block = await ethers.provider.getBlock(transaction.blockNumber);
      const position = await twabDelegator.computeDelegationPositionAddress(owner.address, 0);
      const { delegationPosition, delegatee, balance, lockUntil } =
        await twabDelegator.getDelegationPosition(owner.address, 0);

      expect(delegationPosition).to.equal(position);
      expect(delegatee).to.equal(firstDelegatee.address);
      expect(balance).to.equal(amount);
      expect(lockUntil).to.equal(block.timestamp + MAX_EXPIRY);
    });
  });
});
