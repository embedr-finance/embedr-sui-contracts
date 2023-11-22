# Embedr Protocol

## Overview

Embedr Protocol is a decentralized lending/borrowing protocol built on the [Sui Network](https://sui.io/). Smart contracts are written with the [Move language](https://move-book.com/).

Embedr Protocol has different packages that are responsible for different parts of the protocol. These packages are:

- **`Library`** - Contains utility functions and shared code that is used by other packages in the protocol.
- **`Tokens`** - Handles the creation and management of tokens within Embedr Protocol.
- **`Stable Coin Factory`** - Responsible for creating and managing stable coins. Stable coins are created by depositing collateral into the protocol.
- **`Participation Bank Factory`** - Handles the creation and management of revenue farming pools. SMEs can borrow stable coins from liquidity providers and pay them back with interest.

## Getting Started

To use the Embedr Protocol, you need to install the `sui-cli`. Follow the instructions in the [Sui documentation](https://docs.sui.io/build/install) to install the `sui-cli`. Once you have the `sui-cli` installed, you can use the `sui` command to interact with the Embedr Protocol.

### Running Tests

Run tests for each module using the `make test` command. If you want to run tests for a specific module, you can use the `make test MODULE=<module_name>` command.

### Deploying Contracts

Deploy Embedr Protocol contracts on Sui testnet using the `make deploy` command.

This command executes several scripts in the process:

1. Checks if active address for `sui-cli` is funded with enough balance to deploy contracts. If not, it will request tokens from the faucet.
2. Publishes all contracts to Sui testnet. This will also update the `Move.toml` files in each contract with the correct addresses and dependencies. An `objects.json` file will also be generated for each contract with the generated object IDs.
3. Adds manager role to some of the modules on `rUSD Stable Coin` and `EMBD Incentive Token` contracts.

## License
The Embedr Protocol is licensed under the [Apache 2.0 License](http://www.apache.org/licenses/LICENSE-2.0)
