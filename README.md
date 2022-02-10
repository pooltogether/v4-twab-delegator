<p align="center">
  <a href="https://github.com/pooltogether/pooltogether--brand-assets">
    <img src="https://github.com/pooltogether/pooltogether--brand-assets/blob/977e03604c49c63314450b5d432fe57d34747c66/logo/pooltogether-logo--purple-gradient.png?raw=true" alt="PoolTogether Brand" style="max-width:100%;" width="200">
  </a>
</p>

<br />

# PoolTogether Contracts Template

[![Coverage Status](https://coveralls.io/repos/github/pooltogether/pooltogether-contracts-template/badge.svg?branch=master)](https://coveralls.io/github/pooltogether/pooltogether-contracts-template?branch=master)

![Tests](https://github.com/pooltogether/pooltogether-contracts-template/actions/workflows/main.yml/badge.svg)

# Usage

1. Clone this repo: `git clone git@github.com:pooltogether/pooltogether-contracts-template.git <DESTINATION REPO>`
1. Create repo using Github GUI
1. Set remote repo (`git remote add origin git@github.com:pooltogether/<NAME_OF_NEW_REPO>.git`),
1. Checkout a new branch (`git checkout -b name_of_new_branch`)
1. Begin implementing as appropriate.
1. Update this README

## Usage

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
