Web3 = require 'web3'
solc = require 'solc'
SolidityCoder = require("web3/lib/solidity/coder.js")

module.exports = (config, publisher) ->
    # Start web3
    web3 = new Web3()
    eth_ip = config.eth_ip || '127.0.0.1'
    web3.setProvider(new web3.providers.HttpProvider("http://#{eth_ip}:8545"))

    # Helpers

    optionsOrDefaults = (options) ->
        {value, gas, account} = options
        return {
            value: value || 1000000
            gas: gas || 1000000
            account: account || null#config.eth_addresses[0]
        }

    getBalance = (account, cb) ->
        web3.eth.getBalance account, (err, balance) ->
            cb err, balance

    # TODO: how to manage addresses. API should probably be more transparent to allow
    # agents to use all these functions with their own addresses.

    ethAddress = ->
        return config.eth_addresses[0]

    contractAtAddress = (source, name, address, cb) =>
        compiled = solc.compile(source).contracts[name]
        abi = JSON.parse compiled.interface
        # console.log err if err?
        web3.eth.contract(abi).at address, cb

    pollAndReturnReceipt = (txid, cb) ->

        i = 0

        publishReceipt = (tx_receipt) ->
            if publisher?
                publisher.publish "tx:#{txid}:done"

        address_checker = setInterval ->
            web3.eth.getTransactionReceipt txid, (err, resp) ->
                console.log 'Polling for a receipt...', resp

                # It created a contract
                if resp?.contractAddress
                    cb err, resp.contractAddress
                    clearInterval(address_checker)
                    publishReceipt resp

                # It got hashed into a block
                else if resp?.blockNumber
                    cb err, resp
                    clearInterval(address_checker)
                    publishReceipt resp

                # It...
                else if i++ > 1000
                    cb "Took forever and no receipt" #TODO: log and manage these
        , 2000

    callFromABI = (abi, address, fn, args..., cb) ->
        console.log '[callFromABI]', abi, address, fn, args...
        web3.eth.contract(abi).at address, (err, Contract) ->
            Contract[fn].call args..., (err, resp) ->
                console.log err, resp
                return cb err if err?
                cb null, resp


    buildGenericMethods = (contract_schema) ->
        Contracts = {}
        abis = []
        contracts = []
        EventDecoders = {}

        Object.keys(contract_schema).map (name) ->

            source = contract_schema[name]

            Contracts[name] = 
                atAddress: (address, cb) ->
                    contractAtAddress source, name, address, cb
                compile: (cb) ->
                    compiled = solc.compile(source)
                    cb null, compiled.contracts[name]

            console.log 'Compiling event decoders...', name
            EventDecoders[name] ||= {}

            Contracts[name].compile (err, compiled) ->
                abi = JSON.parse(compiled.interface)
                abis.push abi
                contracts.push {name, abi}

                abi.map (abi_fn) ->

                    if abi_fn.type == 'event'
                        input_types = abi_fn.inputs.map (i) -> i.type
                        input_names = abi_fn.inputs.map (i) -> i.name
                        signature = "#{abi_fn.name}("
                        abi_fn.inputs.map (i) ->
                            signature += (i.type + ',')

                        signature = signature.slice(0, -1) + ')'
                        hashed_signature = web3.sha3(signature)

                        EventDecoders[name][hashed_signature] = (e) ->
                            data = SolidityCoder.decodeParams(input_types, e.data.replace("0x",""))
                            result = {}
                            input_names.map (i_n, i) ->
                                result[i_n] = data[i]
                            return result

        {getParameter: (name, address, parameter, args..., cb) ->
            Contracts[name].atAddress address, (err, resp) ->
                resp[parameter]?.call args..., (err, resp) ->
                    console.log err if err?
                    cb err, resp

        callFunction: (name, address, fn, args..., options, cb) ->
            Contracts[name].atAddress address, (err, resp) ->
                console.log "Calling #{fn} with args", args...
                return cb err if err?
                return cb 'This is not a function' if !resp[fn]?

                {account, value, gas} = options
                tx_options = {from: (account || ethAddress()), to: address, value, gas}

                web3.eth.estimateGas tx_options, (err, resp) ->
                    console.log 'Estimated gas', resp
                resp[fn] args..., tx_options, (err, resp) ->
                    cb err, resp

        sendTransaction: (name, address, amount, cb) ->
            Contracts[name].atAddress address, (err, resp) ->
                console.log err if err?
                console.log "Sending #{amount} to #{address}"
                web3.eth.estimateGas {from: ethAddress(), to: address, value: amount}, (err, est_gas) ->
                    cb err if err?
                    console.log "Estimate #{est_gas} gas is needed"
                    if est_gas == 50000000
                        console.log "This will take way too much gas for the gas limit..."

                    if est_gas > 1000
                        gas = est_gas + 10000
                    else
                        gas = 1000

                    web3.eth.sendTransaction {from: ethAddress(), to: address, value: amount, gas}, (err, resp) ->
                        console.log err if err
                        return cb err if err?
                        pollAndReturnReceipt resp, (err, receipt) ->
                            if receipt.gasUsed == gas
                                console.log '[WARNING] It used all the gas'
                            cb err, receipt

        deploy: (name, args..., options, cb) ->
            console.log name, args..., options
            console.log "DEPLOYING"

            Contracts[name].compile (err, compiled) ->
                return cb err if err

                console.log 'Compilation error', err if err?
                console.log 'Successfully compiled', compiled

                abi = JSON.stringify(compiled.interface)
                code = compiled.bytecode

                _contract = web3.eth.contract(abi, args...)

                {account, value} = options
                tx_options = {from: (account || ethAddress()), data: compiled.code, value}

                # web3.eth.estimateGas data: compiled.code, (err, resp) ->
                web3.eth.estimateGas tx_options, (err, resp) ->
                    console.log 'estimated gas', resp
                    return cb err if err?
                    if resp > 1000
                        gas = resp + 10000
                    else
                        gas = 1000

                    tx_options.gas = options.gas #TODO decide btw this and the estimate...
                    _contract.new(args..., tx_options, (err, contract) ->
                        console.log 'Completed deploy ^^^^^'
                        cb err, contract)

        compileContractData: (name, address, cb) ->
            Contracts[name].atAddress address, (err, resp) ->
                cb err, resp.abi

        decodeEvent: (name, event) ->
            if EventDecoders[name]?
                if EventDecoders[name][event.topics?[0]]?
                    return EventDecoders[name][event.topics[0]](event)
                else
                    return null
            else
                return null
        abis: abis
        contracts: contracts
        }

    {
        web3
        SolidityCoder
        callFromABI
        buildGenericMethods
    }
