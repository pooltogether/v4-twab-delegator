import { expect } from 'chai';
import { deployMockContract, MockContract } from 'ethereum-waffle';
import { BigNumber, Contract, ContractFactory, Signer, Transaction, Wallet } from 'ethers';
import { ethers } from 'hardhat';
import { Interface } from 'ethers/lib/utils';
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers';
import { beforeEach } from 'mocha';

const { constants, provider, utils } = ethers;
const { AddressZero, MaxUint256, Zero } = constants;
const { defaultAbiCoder, parseEther: toWei } = utils;

import { getEvents as getEventsHelper } from './helpers/getEvents';

const getEvents = (tx: Transaction, contract: Contract) => getEventsHelper(provider, tx, contract);

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

  const deployTwabDelegator = async (
    ticketAddress = ticket.address,
    nftName = 'PoolTogether aUSDC Ticket Delegation',
    nftSymbol = 'PTaUSDCD',
  ) => {
    const twabDelegatorContractFactory: ContractFactory = await ethers.getContractFactory(
      'TWABDelegatorHarness',
    );

    return await twabDelegatorContractFactory.deploy(ticketAddress, nftName, nftSymbol);
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

  describe('mint()', () => {
    const amount = toWei('1000');

    beforeEach(async () => {
      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);
      await twabDelegator.stake(owner.address, amount);
    });

    it('should allow a staker to delegate by minting an NFT', async () => {
      const transaction = await twabDelegator.mint(owner.address, firstDelegatee.address, amount);
      const delegatedPositionAddress = await getDelegatedPositionAddress(transaction);

      expect(await transaction)
        .to.emit(twabDelegator, 'Minted')
        .withArgs(delegatedPositionAddress, 1, firstDelegatee.address, amount);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(accountDetails.balance).to.eq(amount);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);
      expect(await twabDelegator.staker(1)).to.eq(owner.address);
      expect(await twabDelegator.ownerOf(1)).to.eq(firstDelegatee.address);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);
      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(amount);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(firstDelegatee.address);
    });

    it('should allow a staker to delegate to several delegatee so they have chances to win', async () => {
      const halfAmount = amount.div(2);

      const firstTransaction = await twabDelegator.mint(
        owner.address,
        firstDelegatee.address,
        halfAmount,
      );

      const firstDelegatedPositionAddress = await getDelegatedPositionAddress(firstTransaction);

      expect(await firstTransaction)
        .to.emit(twabDelegator, 'Minted')
        .withArgs(firstDelegatedPositionAddress, 1, firstDelegatee.address, halfAmount);

      const secondTransaction = await twabDelegator.mint(
        owner.address,
        secondDelegatee.address,
        halfAmount,
      );

      const secondDelegatedPositionAddress = await getDelegatedPositionAddress(secondTransaction);

      expect(await secondTransaction)
        .to.emit(twabDelegator, 'Minted')
        .withArgs(secondDelegatedPositionAddress, 2, secondDelegatee.address, halfAmount);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);
      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);

      const firstDelegateeAccountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(firstDelegateeAccountDetails.balance).to.eq(halfAmount);

      expect(await twabDelegator.staker(1)).to.eq(owner.address);
      expect(await twabDelegator.ownerOf(1)).to.eq(firstDelegatee.address);

      expect(await ticket.balanceOf(firstDelegatedPositionAddress)).to.eq(halfAmount);
      expect(await ticket.delegateOf(firstDelegatedPositionAddress)).to.eq(firstDelegatee.address);

      const secondDelegateeAccountDetails = await ticket.getAccountDetails(secondDelegatee.address);
      expect(secondDelegateeAccountDetails.balance).to.eq(halfAmount);

      expect(await twabDelegator.staker(2)).to.eq(owner.address);
      expect(await twabDelegator.ownerOf(2)).to.eq(secondDelegatee.address);

      expect(await ticket.balanceOf(secondDelegatedPositionAddress)).to.eq(halfAmount);
      expect(await ticket.delegateOf(secondDelegatedPositionAddress)).to.eq(
        secondDelegatee.address,
      );
    });

    it('should allow a representative to delegate by minting an NFT', async () => {
      await twabDelegator.setRepresentative(representative.address);

      const transaction = await twabDelegator
        .connect(representative)
        .mint(owner.address, firstDelegatee.address, amount);

      const delegatedPositionAddress = await getDelegatedPositionAddress(transaction);

      expect(await transaction)
        .to.emit(twabDelegator, 'Minted')
        .withArgs(delegatedPositionAddress, 1, firstDelegatee.address, amount);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(accountDetails.balance).to.eq(amount);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);
      expect(await twabDelegator.staker(1)).to.eq(owner.address);
      expect(await twabDelegator.ownerOf(1)).to.eq(firstDelegatee.address);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);
      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(amount);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(firstDelegatee.address);
    });

    it('should fail to delegate if not a staker or representative', async () => {
      await expect(
        twabDelegator.connect(stranger).mint(owner.address, firstDelegatee.address, amount),
      ).to.be.revertedWith('TWABDelegator/not-staker-or-rep');
    });

    it('should fail to delegate if staker is address zero', async () => {
      await expect(
        twabDelegator.connect(stranger).mint(AddressZero, firstDelegatee.address, amount),
      ).to.be.revertedWith('TWABDelegator/not-staker-or-rep');
    });

    it('should fail to delegate if delegatee is address zero', async () => {
      await expect(twabDelegator.mint(owner.address, AddressZero, amount)).to.be.revertedWith(
        'TWABDelegator/del-not-zero-addr',
      );
    });

    it('should fail to delegate if amount is not greater than zero', async () => {
      await expect(
        twabDelegator.mint(owner.address, firstDelegatee.address, Zero),
      ).to.be.revertedWith('TWABDelegator/amount-gt-zero');
    });

    it('should fail to delegate if delegated amount is greater than staked amount', async () => {
      await expect(
        twabDelegator.mint(owner.address, firstDelegatee.address, amount.mul(2)),
      ).to.be.revertedWith('TWABDelegator/stake-lt-amount');
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
      const transaction = await twabDelegator.mint(owner.address, firstDelegatee.address, amount);
      const delegatedPositionAddress = await getDelegatedPositionAddress(transaction);

      await twabDelegator
        .connect(firstDelegatee)
        .transferFrom(firstDelegatee.address, secondDelegatee.address, 1);

      expect(await twabDelegator.ownerOf(1)).to.eq(secondDelegatee.address);

      const firstDelegateeAccountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(firstDelegateeAccountDetails.balance).to.eq(Zero);

      const secondDelegateeAccountDetails = await ticket.getAccountDetails(secondDelegatee.address);
      expect(secondDelegateeAccountDetails.balance).to.eq(amount);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(Zero);
      expect(await twabDelegator.staker(1)).to.eq(owner.address);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(Zero);
      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(amount);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(secondDelegatee.address);
    });

    it('should allow a staker to burn a delegated position that was transferred to another user', async () => {
      const transaction = await twabDelegator.mint(owner.address, firstDelegatee.address, amount);
      const delegatedPositionAddress = await getDelegatedPositionAddress(transaction);

      await twabDelegator
        .connect(firstDelegatee)
        .transferFrom(firstDelegatee.address, secondDelegatee.address, 1);

      expect(await twabDelegator.burn(1))
        .to.emit(twabDelegator, 'Burned')
        .withArgs(1, owner.address, amount);

      await expect(twabDelegator.ownerOf(1)).to.be.revertedWith(
        'ERC721: owner query for nonexistent token',
      );

      const firstDelegateeAccountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(firstDelegateeAccountDetails.balance).to.eq(Zero);

      const secondDelegateeAccountDetails = await ticket.getAccountDetails(secondDelegatee.address);
      expect(secondDelegateeAccountDetails.balance).to.eq(Zero);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(amount);
      expect(await twabDelegator.staker(1)).to.eq(AddressZero);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(amount);
      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(Zero);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(AddressZero);
    });
  });

  describe('burn()', () => {
    const amount = toWei('1000');
    let delegatedPositionAddress = '';

    beforeEach(async () => {
      await ticket.mint(owner.address, amount);
      await ticket.approve(twabDelegator.address, MaxUint256);
      await twabDelegator.stake(owner.address, amount);

      const transaction = await twabDelegator.mint(owner.address, firstDelegatee.address, amount);
      delegatedPositionAddress = await getDelegatedPositionAddress(transaction);
    });

    it('should allow a staker to burn a delegated position to revoke delegated amount', async () => {
      expect(await twabDelegator.burn(1))
        .to.emit(twabDelegator, 'Burned')
        .withArgs(1, owner.address, amount);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(accountDetails.balance).to.eq(Zero);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(amount);
      expect(await twabDelegator.staker(1)).to.eq(AddressZero);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(amount);
      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(Zero);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(AddressZero);

      await expect(twabDelegator.ownerOf(1)).to.be.revertedWith(
        'ERC721: owner query for nonexistent token',
      );
    });

    it('should allow a representative to burn a delegated position to revoke delegated amount', async () => {
      await twabDelegator.setRepresentative(representative.address);

      expect(await twabDelegator.connect(representative).burn(1))
        .to.emit(twabDelegator, 'Burned')
        .withArgs(1, owner.address, amount);

      const accountDetails = await ticket.getAccountDetails(firstDelegatee.address);
      expect(accountDetails.balance).to.eq(Zero);

      expect(await twabDelegator.balanceOf(owner.address)).to.eq(amount);
      expect(await twabDelegator.staker(1)).to.eq(AddressZero);

      expect(await ticket.balanceOf(twabDelegator.address)).to.eq(amount);
      expect(await ticket.balanceOf(delegatedPositionAddress)).to.eq(Zero);
      expect(await ticket.delegateOf(delegatedPositionAddress)).to.eq(AddressZero);

      await expect(twabDelegator.ownerOf(1)).to.be.revertedWith(
        'ERC721: owner query for nonexistent token',
      );
    });

    it('should fail to burn if token id is not greater than zero', async () => {
      await expect(twabDelegator.burn(Zero)).to.be.revertedWith('TWABDelegator/token-id-gt-zero');
    });

    it('should fail to burn if caller is not the staker or representative of the delegated position', async () => {
      await expect(twabDelegator.connect(stranger).burn(1)).to.be.revertedWith(
        'TWABDelegator/not-staker-or-rep',
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
