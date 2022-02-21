<p align="center">
  <a href="https://github.com/pooltogether/pooltogether--brand-assets">
    <img src="https://github.com/pooltogether/pooltogether--brand-assets/blob/977e03604c49c63314450b5d432fe57d34747c66/logo/pooltogether-logo--purple-gradient.png?raw=true" alt="PoolTogether Brand" style="max-width:100%;" width="200">
  </a>
</p>

<br />

# PoolTogether TWAB Delegator

[![Coverage Status](https://coveralls.io/repos/github/pooltogether/v4-twab-delegator/badge.svg?branch=master)](https://coveralls.io/github/pooltogether/v4-twab-delegator?branch=master)

![Tests](https://github.com/pooltogether/v4-twab-delegator/actions/workflows/main.yml/badge.svg)

The PoolTogether V4 TWAB Delegator contract allows accounts to easily delegate their chance of winning to other accounts. See the [PoolTogether V4 Docs](https://dev.pooltogether.com) for more details on chance and the TWAB.

There are three roles that relate to this contract:

- Delegators
- Delegatees
- Representatives

**Delegators**

Delegators are accounts that want to delegate their chance to win to another account. They do so using delegation "slots". Each delegation slot corresponds to a smart contract deployed as a minimal proxy. This contract holds the tickets and delegates the chance of the held tickets to the delegatee.

**Delegatees**

Delegatees are those who have tickets delegated to them.  The delegatee gets a higher chance to win thanks to the delegation, but they don't have access to the underlying funds.

**Representatives**

Representatives are accounts that can manage delegations for a delegator.  They can create and update the delegations, but cannot withdraw any funds. This enables smart contracts to manage delegations, or even a human representative.

# User Flow

The main user flow is that a delegator delegates tickets to a delegatee. The flow proceeds like so:

1. Delegator creates a delegation for the given slot:
```solidity
createDelegation(address delegatorAddress, uint256 slotIndex, address delegatee, uint256 lockDuration)
```
2. Delegator funds the delegation (transfers tickets into the delegation)
```solidity
fundDelegation(address delegator, uint256 slotIndex, uint256 amount)
```

If a delegator wishes a representative to manage their delegations for them, then the delegator can stake on the contract instead. The representative can use the stake to create delegations, but cannot withdraw the stake.

The staking and rep flow looks like so:

1. Delegator stakes tickets into the contract:
```solidity
stake(address to, uint256 amount)
```
2. Delegator adds a rep:
```solidity
setRepresentative(address rep, bool isRep)
```

The representative would follow a similar flow to create a delegation, but would instead fund from the stake:

1. Delegator creates a delegation for the given slot:
```solidity
createDelegation(address delegatorAddress, uint256 slotIndex, address delegatee, uint256 lockDuration)
```
2. Delegator funds the delegation (transfers tickets into the delegation)
```solidity
fundDelegationFromStake(address delegator, uint256 slotIndex, uint256 amount)
```

# Permit & Multicall

This contract implements the Multicall interface which allows EOAs to batch transactions together. It also implements a special `permitAndMulticall` function so that users can also approve the ticket contract before running transactions, allowing them to create a delegation in a single tx.

# Development

1. Clone this repo: `git clone git@github.com:pooltogether/pooltogether-contracts-template.git <DESTINATION REPO>`
1. Create repo using Github GUI
1. Set remote repo (`git remote add origin git@github.com:pooltogether/<NAME_OF_NEW_REPO>.git`),
1. Checkout a new branch (`git checkout -b name_of_new_branch`)
1. Begin implementing as appropriate.
1. Update this README

This repo is setup to compile (`nvm use && yarn compile`) and successfully pass tests (`yarn test`)

# Preset Packages

## Generic Proxy Factory

The minimal proxy factory is a powerful pattern used throughout PoolTogethers smart contracts. A [typescript package](https://www.npmjs.com/package/@pooltogether/pooltogether-proxy-factory-package) is available to use a generic deployed instance. This is typically used in the deployment script.

## Generic Registry

The [generic registry](https://www.npmjs.com/package/@pooltogether/pooltogether-generic-registry) is a iterable singly linked list data structure that is commonly used throughout PoolTogethers contracts. Consider using this where appropriate or deploying in a seperate repo such as the (Prize Pool Registry)[https://github.com/pooltogether/pooltogether-prizepool-registry.

# Installation

Install the repo and dependencies by running:
`yarn`

## Deployment

These contracts can be deployed to a network by running:
`yarn deploy <networkName>`

## Verification

These contracts can be verified on Etherscan, or an Etherscan clone, for example (Polygonscan) by running:
`yarn etherscan-verify <ethereum network name>` or `yarn etherscan-verify-polygon matic`

# Testing

Run the unit tests locally with:
`yarn test`

## Coverage

Generate the test coverage report with:
`yarn coverage`
