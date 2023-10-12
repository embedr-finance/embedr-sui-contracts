# Embedr Protocol

## Overview

Embedr Protocol is a decentralized lending/borrowing protocol built on the [Sui Network](https://sui.io/). Smart contracts are written with the [Move language](https://move-book.com/).

Embedr Protocol has different modules that are responsible for different parts of the protocol. The modules are:

- **`Library`** - Contains utility functions and shared code that is used by other modules in the protocol.
- **`Tokens`** - Handles the creation and management of tokens within the Embedr Protocol.
- **`Stable Coin Factory`** - Responsible for creating and managing stable coins within the Embedr Protocol.

## Getting Started

To use the Embedr Protocol, you need to install the `sui-cli`. Follow the instructions in the [Sui documentation](https://docs.sui.io/build/install) to install the `sui-cli`. Once you have the `sui-cli` installed, you can use the `sui` command to interact with the Embedr Protocol.

### Running Tests

To run tests for each module using the `make test` command. If you want to run tests for a specific module, you can use the `make test MODULE=<module_name>` command.

### Publishing Modules

To publish the Embedr Protocol modules, run the `publish.sh` command. This will be integrated into the `Makefile` in the future.

`publish.sh` command will loop through each module and publish them to the Sui Network. 

After publishing the modules, it will update the `Move.toml` files in each module with the correct addresses and dependencies. 

It will also save the generated object IDs in the `objects.json` file related to each module.

## License
The Embedr Protocol is licensed under the [Apache 2.0 License](http://www.apache.org/licenses/LICENSE-2.0)
