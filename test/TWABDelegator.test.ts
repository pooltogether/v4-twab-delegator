import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { Contract, ContractFactory, Signer, Wallet } from 'ethers';
import { ethers } from 'hardhat';
import { Interface } from 'ethers/lib/utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { beforeEach } from 'mocha';

const { constants, utils } = ethers;
const { MaxUint256 } = constants;
const { parseEther: toWei } = utils;

describe('Test Set Name', () => {
  let exampleContract: Contract;

  let owner: SignerWithAddress;
  let rep: SignerWithAddress;
  let controller: SignerWithAddress;
  let firstDelegatee: SignerWithAddress;
  let secondDelegatee: SignerWithAddress;

  let ticket: any;
  let twabDelegator: any;

  beforeEach(async () => {
    [owner, rep, controller, firstDelegatee, secondDelegatee] = await ethers.getSigners();

    const ticketContractFactory: ContractFactory = await ethers.getContractFactory(
      'TicketHarness',
    );

    ticket = await ticketContractFactory.deploy("Ticket", "ticket", 18, controller.address);

    const twabDelegatorContractFactory: ContractFactory = await ethers.getContractFactory('TWABDelegator');
    twabDelegator = await twabDelegatorContractFactory.deploy(ticket.address);
  });

  describe('stake()', () => {
    it('should allow a ticket holder to stake tickets', async () => {
      const amount = toWei('1000');

      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);

      await expect(twabDelegator.stake(owner.address, amount)).to.emit(twabDelegator, 'TicketsStaked').withArgs(owner.address, amount);
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

    it('should allow a rep to delegate so that the delegatee has a chance to win', async () => {
      expect(await twabDelegator.delegate(firstDelegatee.address, amount)).to.emit(twabDelegator, 'StakeDelegated').withArgs(firstDelegatee.address, amount);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);

      expect(accountDetails.balance).to.eq(amount);
    });

    it('should allow a rep to delegate to several delegatee so they have a chance to win', async () => {
      const halfAmount = amount.div(2);

      expect(await twabDelegator.delegate(firstDelegatee.address, halfAmount)).to.emit(twabDelegator, 'StakeDelegated').withArgs(firstDelegatee.address, halfAmount);
      expect(await twabDelegator.delegate(secondDelegatee.address, halfAmount)).to.emit(twabDelegator, 'StakeDelegated').withArgs(secondDelegatee.address, halfAmount);

      const firstDelegateeAccountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      const secondDelegateeAccountDetails = await ticket.getAccountDetails(secondDelegatee.address);

      expect(firstDelegateeAccountDetails.balance).to.eq(halfAmount);
      expect(secondDelegateeAccountDetails.balance).to.eq(halfAmount);
      expect(await twabDelegator.balanceOf(owner.address)).to.eq(toWei('0'));
    });
  });
});
