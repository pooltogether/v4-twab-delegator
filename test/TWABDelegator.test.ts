import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { Contract, ContractFactory, Signer, Wallet } from 'ethers';
import { ethers } from 'hardhat';
import { Interface } from 'ethers/lib/utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { beforeEach } from 'mocha';

const { constants, utils } = ethers;
const { AddressZero, MaxUint256 } = constants;
const { parseEther: toWei } = utils;

describe('Test Set Name', () => {
  let owner: SignerWithAddress;
  let representative: SignerWithAddress;
  let controller: SignerWithAddress;
  let firstDelegatee: SignerWithAddress;
  let secondDelegatee: SignerWithAddress;
  let stranger: SignerWithAddress;

  let ticket: Contract;
  let twabDelegator: Contract;

  beforeEach(async () => {
    [owner, representative, controller, firstDelegatee, secondDelegatee, stranger] =
      await ethers.getSigners();

    const ticketContractFactory: ContractFactory = await ethers.getContractFactory('TicketHarness');
    ticket = await ticketContractFactory.deploy('Ticket', 'ticket', 18, controller.address);

    const twabDelegatorContractFactory: ContractFactory = await ethers.getContractFactory(
      'TWABDelegator',
    );

    twabDelegator = await twabDelegatorContractFactory.deploy(ticket.address);
  });

  describe('stake()', () => {
    it('should allow a ticket holder to stake tickets', async () => {
      const amount = toWei('1000');

      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);

      await expect(twabDelegator.stake(owner.address, amount))
        .to.emit(twabDelegator, 'TicketsStaked')
        .withArgs(owner.address, amount);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(amount);
      expect(await ticket.balanceOf(owner.address)).to.eq(toWei('0'));
      expect(await twabDelegator.balanceOf(owner.address)).to.eq(amount);
    });
  });

  describe('delegate()', () => {
    const amount = toWei('1000');

    beforeEach(async () => {
      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);
      await twabDelegator.stake(owner.address, amount);
    });

    it('should allow a staker to delegate so that the delegatee has chances to win', async () => {
      expect(await twabDelegator.delegate(firstDelegatee.address, amount))
        .to.emit(twabDelegator, 'StakeDelegated')
        .withArgs(firstDelegatee.address, amount);

      expect(
        await twabDelegator.callStatic.delegatedAmount(owner.address, firstDelegatee.address),
      ).to.eq(amount);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);

      expect(accountDetails.balance).to.eq(amount);
    });

    it('should allow a staker to delegate to several delegatee so they have chances to win', async () => {
      const halfAmount = amount.div(2);

      expect(await twabDelegator.delegate(firstDelegatee.address, halfAmount))
        .to.emit(twabDelegator, 'StakeDelegated')
        .withArgs(firstDelegatee.address, halfAmount);

      expect(await twabDelegator.delegate(secondDelegatee.address, halfAmount))
        .to.emit(twabDelegator, 'StakeDelegated')
        .withArgs(secondDelegatee.address, halfAmount);

      expect(
        await twabDelegator.callStatic.delegatedAmount(owner.address, firstDelegatee.address),
      ).to.eq(halfAmount);

      expect(
        await twabDelegator.callStatic.delegatedAmount(owner.address, secondDelegatee.address),
      ).to.eq(halfAmount);

      const firstDelegateeAccountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      const secondDelegateeAccountDetails = await ticket.getAccountDetails(secondDelegatee.address);

      expect(firstDelegateeAccountDetails.balance).to.eq(halfAmount);
      expect(secondDelegateeAccountDetails.balance).to.eq(halfAmount);
      expect(await twabDelegator.balanceOf(owner.address)).to.eq(toWei('0'));
    });

    it('should fail to delegate if not a staker', async () => {
      await expect(twabDelegator.connect(stranger).delegate(firstDelegatee.address, amount))
        .to.be.revertedWith('TWABDelegator/only-staker');
    });

    it('should fail to delegate if delegatee is address zero', async () => {
      await expect(twabDelegator.delegate(AddressZero, amount))
        .to.be.revertedWith('TWABDelegator/del-not-zero-addr');
    });

    it('should fail to delegate if amount is not greater than zero', async () => {
      await expect(twabDelegator.delegate(firstDelegatee.address, toWei('0')))
        .to.be.revertedWith('TWABDelegator/amount-gt-zero');
    });

    it('should fail to delegate if delegated amount is greater than staked amount', async () => {
      await expect(twabDelegator.delegate(firstDelegatee.address, amount.mul(2)))
        .to.be.revertedWith('TWABDelegator/stake-lt-amount');
    });
  });

  describe('revoke()', () => {
    const amount = toWei('1000');

    beforeEach(async () => {
      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);
      await twabDelegator.stake(owner.address, amount);
      await twabDelegator.delegate(firstDelegatee.address, amount);
    });

    it('should allow a staker to revoke a delegation', async () => {
      expect(await twabDelegator.revoke(firstDelegatee.address))
        .to.emit(twabDelegator, 'DelegationRevoked')
        .withArgs(firstDelegatee.address, amount);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);

      expect(accountDetails.balance).to.eq(toWei('0'));
    });

    it('should fail to revoke if not delegator', async () => {
      await expect(twabDelegator.connect(stranger).revoke(firstDelegatee.address))
        .to.be.revertedWith('TWABDelegator/only-delegator');
    });
  });
});
