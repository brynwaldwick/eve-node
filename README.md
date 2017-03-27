# eve-node

A readable interface for using ethereum in reactive webapps.

## Usage

Construct core generic methods off of a dictionary of contracts. The keys of the dictionary should be the name in the Contract's constructor. This name will be used to key future calls to a Contract of each type.

Each method for a Contract has the `name` of that Contract's type as its first argument. For methods operating on deployed Contracts, the deployed Contract's `address` is the second argument.

You can pass in an array of accounts with `config.eth_addresses` to restrict a local portion of the system to use a subset of your available accounts.

    eve = require('eve-node')(config)

    contract_schema =
        'MyContract' = 'pragma solidity ^0.4.0;
            contract MyContract {
                ...'
        'MyOtherContract' = 'pragma solidity ^0.4.0;
            contract MyOtherContract {
                ...'

    Eve = eve.buildGenericMethods(contract_schema)


## Generic Methods

#### `getParameter(name, address, parameter, args..., cb)`

Query the value of a public state variable or constant function that returns a value on a Contract of type `name` at `address`.

##### Arguments

    parameter: The name of the variable or constant function to call
    args: (optional) arguments


#### `callFunction(name, address, fn, args..., options, cb)`

Execute a function on a Contract of type `name` at `address`.

##### Arguments

    fn: The name of the function to call
    args: (optional) arguments for the function
    options: set {value, gas, from} for the transaction


#### `deploy(name, args..., options, cb)`

Deploy a Contract of type `name`.

##### Arguments

    args: Arguments for the constrcutor
    options: Set {value, from} for the transaction. Value should be 0.


#### `decodeEvent(name, event)`

Decode an [event](https://github.com/ethereum/wiki/wiki/Ethereum-Contract-ABI#events) from the ethereum blockchain into a usable json blob based off of events specified in your Contract's source code. Will only successfully decode events if the Contract throwing the event has an identical Event function signature to that specified in your Contract's source code.

##### Arguments

    event: The raw event from ethereum

##### Returns

    event: The raw event from ethereum
    [keys]: Populated keys from the value


## ABI Methods

#### `callFromABI(abi, address, fn, args..., cb)`

Call a function from an abi for a contract at `address`.

##### Arguments

    abi: A partial or full representation of a Contract's interface
    fn: A function specified by name in the abi
    args: Arguments for the function
