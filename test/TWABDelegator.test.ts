import { expect } from 'chai';
import { BigNumber, Contract, ContractFactory, Transaction } from 'ethers';
import { ethers } from 'hardhat';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { beforeEach } from 'mocha';

const { constants, provider, utils } = ethers;
const { AddressZero, MaxUint256, Zero } = constants;
const { parseEther: toWei } = utils;

import { getEvents as getEventsUtil } from './utils/getEvents';
import { increaseTime as increaseTimeUtil } from './utils/increaseTime';

const getEvents = (tx: Transaction, contract: Contract) => getEventsUtil(provider, tx, contract);
const increaseTime = (time: number) => increaseTimeUtil(provider, time);

const MAX_EXPIRY = 5184000; // 60 days
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
    const ticketEvents = await getEvents(transaction, ticket);
    const transferEvent = ticketEvents.find((event) => event && event.name === 'Transfer');
    return transferEvent?.args['to'];
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
    it('should return staker balance', async () => {
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

    it('should allow a staker to unstake tickets', async () => {
      await twabDelegator.stake(owner.address, amount);

      await expect(twabDelegator.unstake(owner.address, amount))
        .to.emit(twabDelegator, 'TicketsUnstaked')
        .withArgs(owner.address, owner.address, amount);

      expect(await twabDelegator.callStatic.balanceOf(owner.address)).to.eq(Zero);
      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);
      expect(await ticket.balanceOf(owner.address)).to.eq(amount);
    });

    it('should allow a staker to unstake tickets and send them to another user', async () => {
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
      ).to.be.revertedWith('TWABDelegator/only-staker');
    });

    it('should fail to unstake if caller has no stake', async () => {
      await expect(twabDelegator.unstake(owner.address, amount)).to.be.revertedWith(
        'TWABDelegator/only-staker',
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
      await twabDelegator.stake(owner.address, amount);
    });

    it('should allow a staker to delegate to a delegate', async () => {
      const transaction = await twabDelegator.createDelegation(
        owner.address,
        0,
        firstDelegatee.address,
        amount,
        MAX_EXPIRY,
      );

      const delegatedPositionAddress = await getDelegatedPositionAddress(transaction);
      const expiryTimestamp = await getMaxExpiryTimestamp();

      expect(await transaction)
        .to.emit(twabDelegator, 'DelegationCreated')
        .withArgs(
          delegatedPositionAddress,
          owner.address,
          0,
          expiryTimestamp,
          firstDelegatee.address,
          amount,
        );

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);
      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(accountDetails.balance).to.eq(amount);

      const delegatedPosition = await ethers.getContractAt(
        'DelegatePosition',
        delegatedPositionAddress,
      );

      expect(await delegatedPosition.lockUntil()).to.eq(expiryTimestamp);

      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(amount);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(firstDelegatee.address);
    });

    it('should allow a staker to delegate to several delegatees', async () => {
      const halfAmount = amount.div(2);

      const firstTransaction = await twabDelegator.createDelegation(
        owner.address,
        0,
        firstDelegatee.address,
        halfAmount,
        MAX_EXPIRY,
      );

      const firstTransactionExpiryTimestamp = await getMaxExpiryTimestamp();
      const firstDelegatedPositionAddress = await getDelegatedPositionAddress(firstTransaction);

      expect(await firstTransaction)
        .to.emit(twabDelegator, 'DelegationCreated')
        .withArgs(
          firstDelegatedPositionAddress,
          owner.address,
          0,
          firstTransactionExpiryTimestamp,
          firstDelegatee.address,
          halfAmount,
        );

      const secondTransaction = await twabDelegator.createDelegation(
        owner.address,
        1,
        secondDelegatee.address,
        halfAmount,
        MAX_EXPIRY,
      );

      const secondTransactionExpiryTimestamp = await getMaxExpiryTimestamp();
      const secondDelegatedPositionAddress = await getDelegatedPositionAddress(secondTransaction);

      expect(await secondTransaction)
        .to.emit(twabDelegator, 'DelegationCreated')
        .withArgs(
          secondDelegatedPositionAddress,
          owner.address,
          1,
          secondTransactionExpiryTimestamp,
          secondDelegatee.address,
          halfAmount,
        );

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);
      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);

      const firstDelegateeAccountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(firstDelegateeAccountDetails.balance).to.eq(halfAmount);

      const firstDelegatedPosition = await ethers.getContractAt(
        'DelegatePosition',
        firstDelegatedPositionAddress,
      );

      expect(await firstDelegatedPosition.lockUntil()).to.eq(firstTransactionExpiryTimestamp);

      expect(await ticket.balanceOf(firstDelegatedPositionAddress)).to.eq(halfAmount);
      expect(await ticket.delegateOf(firstDelegatedPositionAddress)).to.eq(firstDelegatee.address);

      const secondDelegateeAccountDetails = await ticket.getAccountDetails(secondDelegatee.address);
      expect(secondDelegateeAccountDetails.balance).to.eq(halfAmount);

      const secondDelegatedPosition = await ethers.getContractAt(
        'DelegatePosition',
        secondDelegatedPositionAddress,
      );

      expect(await secondDelegatedPosition.lockUntil()).to.eq(secondTransactionExpiryTimestamp);

      expect(await ticket.balanceOf(secondDelegatedPositionAddress)).to.eq(halfAmount);
      expect(await ticket.delegateOf(secondDelegatedPositionAddress)).to.eq(
        secondDelegatee.address,
      );
    });

    it('should allow a representative to delegate', async () => {
      await twabDelegator.setRepresentative(representative.address);

      const transaction = await twabDelegator
        .connect(representative)
        .createDelegation(owner.address, 0, firstDelegatee.address, amount, MAX_EXPIRY);

      const delegatedPositionAddress = await getDelegatedPositionAddress(transaction);
      const expiryTimestamp = await getMaxExpiryTimestamp();

      expect(await transaction)
        .to.emit(twabDelegator, 'DelegationCreated')
        .withArgs(
          delegatedPositionAddress,
          owner.address,
          0,
          expiryTimestamp,
          firstDelegatee.address,
          amount,
        );

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);
      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(accountDetails.balance).to.eq(amount);

      const delegatedPosition = await ethers.getContractAt(
        'DelegatePosition',
        delegatedPositionAddress,
      );

      expect(await delegatedPosition.lockUntil()).to.eq(expiryTimestamp);

      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(amount);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(firstDelegatee.address);
    });

    it('should fail to delegate if slot passed is already used', async () => {
      const halfAmount = amount.div(2);

      await twabDelegator.createDelegation(
        owner.address,
        0,
        firstDelegatee.address,
        halfAmount,
        MAX_EXPIRY,
      );

      await expect(
        twabDelegator.createDelegation(
          owner.address,
          0,
          secondDelegatee.address,
          halfAmount,
          MAX_EXPIRY,
        ),
      ).to.be.revertedWith('ERC1167: create2 failed');
    });

    it('should fail to delegate if not a staker or representative', async () => {
      await expect(
        twabDelegator
          .connect(stranger)
          .createDelegation(owner.address, 0, firstDelegatee.address, amount, MAX_EXPIRY),
      ).to.be.revertedWith('TWABDelegator/not-staker-or-rep');
    });

    it('should fail to delegate if staker is address zero', async () => {
      await expect(
        twabDelegator
          .connect(stranger)
          .createDelegation(AddressZero, 0, firstDelegatee.address, amount, MAX_EXPIRY),
      ).to.be.revertedWith('TWABDelegator/not-staker-or-rep');
    });

    it('should fail to delegate if delegatee is address zero', async () => {
      await expect(
        twabDelegator.createDelegation(owner.address, 0, AddressZero, amount, MAX_EXPIRY),
      ).to.be.revertedWith('TWABDelegator/del-not-zero-addr');
    });

    it('should fail to delegate if amount is not greater than zero', async () => {
      await expect(
        twabDelegator.createDelegation(owner.address, 0, firstDelegatee.address, Zero, MAX_EXPIRY),
      ).to.be.revertedWith('TWABDelegator/amount-gt-zero');
    });

    it('should fail to delegate if delegated amount is greater than staked amount', async () => {
      await expect(
        twabDelegator.createDelegation(
          owner.address,
          0,
          firstDelegatee.address,
          amount.mul(2),
          MAX_EXPIRY,
        ),
      ).to.be.revertedWith('TWABDelegator/stake-lt-amount');
    });

    it('should fail to delegate if expiry is greater than 60 days', async () => {
      await expect(
        twabDelegator.createDelegation(
          owner.address,
          0,
          firstDelegatee.address,
          amount,
          MAX_EXPIRY + 1,
        ),
      ).to.be.revertedWith('TWABDelegator/lock-too-long');
    });
  });

  describe('transfer()', () => {
    const amount = toWei('1000');

    beforeEach(async () => {
      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);
      await twabDelegator.stake(owner.address, amount);
    });

    it('should allow a delegated position owner to transfer his NFT and his delegated amount to another user', async () => {
      const transaction = await twabDelegator.mint(
        owner.address,
        firstDelegatee.address,
        amount,
        MAX_EXPIRY,
      );

      const expiryTimestamp = await getMaxExpiryTimestamp();
      const delegatedPositionAddress = await getDelegatedPositionAddress(transaction);

      expect(await twabDelegator.ownerOf(1)).to.eq(firstDelegatee.address);

      await twabDelegator
        .connect(firstDelegatee)
        .transferFrom(firstDelegatee.address, secondDelegatee.address, 1);

      const firstDelegateeAccountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(firstDelegateeAccountDetails.balance).to.eq(Zero);

      const secondDelegateeAccountDetails = await ticket.getAccountDetails(secondDelegatee.address);
      expect(secondDelegateeAccountDetails.balance).to.eq(amount);

      const delegation = await twabDelegator.delegation(1);
      expect(delegation.staker).to.eq(owner.address);
      expect(delegation.expiry).to.eq(expiryTimestamp);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);
      expect(await twabDelegator.ownerOf(1)).to.eq(secondDelegatee.address);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);
      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(amount);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(secondDelegatee.address);
    });

    it('should allow a staker to destroyDelegation a delegated position that was transferred to another user', async () => {
      const transaction = await twabDelegator.mint(
        owner.address,
        firstDelegatee.address,
        amount,
        MAX_EXPIRY,
      );

      const delegatedPositionAddress = await getDelegatedPositionAddress(transaction);

      await twabDelegator
        .connect(firstDelegatee)
        .transferFrom(firstDelegatee.address, secondDelegatee.address, 1);

      await increaseTime(MAX_EXPIRY);

      expect(await twabDelegator.destroyDelegation(1))
        .to.emit(twabDelegator, 'DelegationDestroyed')
        .withArgs(1, owner.address, amount);

      await expect(twabDelegator.ownerOf(1)).to.be.revertedWith(
        'ERC721: owner query for nonexistent token',
      );

      const firstDelegateeAccountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(firstDelegateeAccountDetails.balance).to.eq(Zero);

      const secondDelegateeAccountDetails = await ticket.getAccountDetails(secondDelegatee.address);
      expect(secondDelegateeAccountDetails.balance).to.eq(Zero);

      const delegation = await twabDelegator.delegation(1);
      expect(delegation.staker).to.eq(AddressZero);
      expect(delegation.expiry).to.eq(Zero);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(amount);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(amount);
      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(Zero);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(AddressZero);
    });
  });

  describe('destroyDelegation()', () => {
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
        amount,
        MAX_EXPIRY,
      );
      delegatedPositionAddress = await getDelegatedPositionAddress(transaction);
    });

    it('should allow a staker to destroy a delegated position to revoke delegated amount', async () => {
      await increaseTime(MAX_EXPIRY + 1);

      expect(await twabDelegator.destroyDelegation(owner.address, 0))
        .to.emit(twabDelegator, 'DelegationDestroyed')
        .withArgs(owner.address, 0, amount);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(amount);
      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(amount);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(accountDetails.balance).to.eq(Zero);

      const delegatedPosition = await ethers.getContractAt(
        'DelegatePosition',
        delegatedPositionAddress,
      );

      await expect(delegatedPosition.lockUntil()).to.be.revertedWith('');

      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(Zero);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(AddressZero);
    });

    it('should allow a representative to destroy a delegated position to revoke delegated amount', async () => {
      await increaseTime(MAX_EXPIRY + 1);
      await twabDelegator.setRepresentative(representative.address);

      expect(await twabDelegator.connect(representative).destroyDelegation(owner.address, 0))
        .to.emit(twabDelegator, 'DelegationDestroyed')
        .withArgs(owner.address, 0, amount);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(amount);
      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(amount);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(accountDetails.balance).to.eq(Zero);

      const delegatedPosition = await ethers.getContractAt(
        'DelegatePosition',
        delegatedPositionAddress,
      );

      await expect(delegatedPosition.lockUntil()).to.be.revertedWith('');

      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(Zero);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(AddressZero);
    });

    it('should fail to destroy a delegated position if caller is not the staker or representative of the delegated position', async () => {
      await increaseTime(MAX_EXPIRY + 1);
      await expect(twabDelegator.connect(stranger).destroyDelegation(owner.address, 0)).to.be.revertedWith(
        'TWABDelegator/not-staker-or-rep',
      );
    });

    it('should fail to destroy an inexistent delegated position', async () => {
      await expect(twabDelegator.destroyDelegation(owner.address, 1)).to.be.revertedWith(
        'Transaction reverted: function call to a non-contract account',
      );
    });

    it('should fail to destroy a delegated position if expiry timestamp has not been reached and delegation is still locked', async () => {
      await expect(twabDelegator.destroyDelegation(owner.address, 0)).to.be.revertedWith(
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
});
