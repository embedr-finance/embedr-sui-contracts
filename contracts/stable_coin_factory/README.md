# Stable Coin Factory Package

## Overview

The Stable Coin Factory Package is a comprehensive suite of smart contracts designed to facilitate the creation and management of stable coins.

It provides a robust and secure framework for users to interact with the protocol, enabling them to deposit collateral, mint stable coins, adjust their positions, and engage in various other protocol operations. The package also includes mechanisms for liquidating under-collateralized positions and earning protocol fees, thereby ensuring the overall stability and integrity of the system.

## Available Contracts

The following contracts are included in the package:

- [Kasa Manager](https://github.com/embedr-finance/embedr-sui-contracts/blob/prototype/contracts/stable_coin_factory/sources/kasa_manager.move)
- [Kasa Operations](https://github.com/embedr-finance/embedr-sui-contracts/blob/prototype/contracts/stable_coin_factory/sources/kasa_operations.move)
- [Kasa Storage](https://github.com/embedr-finance/embedr-sui-contracts/blob/prototype/contracts/stable_coin_factory/sources/kasa_storage.move)
- [Liquidation Assets Distributor](https://github.com/embedr-finance/embedr-sui-contracts/blob/prototype/contracts/stable_coin_factory/sources/liquidation_assets_distributor.move)
- [Sorted Kasas](https://github.com/embedr-finance/embedr-sui-contracts/blob/prototype/contracts/stable_coin_factory/sources/sorted_kasas.move)
- [Stability Pool](https://github.com/embedr-finance/embedr-sui-contracts/blob/prototype/contracts/stable_coin_factory/sources/stability_pool.move)

Each contract has its own documentation written as comments in the source code.

## Published Resources

After the contracts are published, the objects and their information will be available under `object.json` file under the root directory of the package.
