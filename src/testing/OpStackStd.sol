// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Vm, VmSafe} from "forge-std/Vm.sol";

library OpStackStd {
    struct DepositTransaction {
        // not sure we can do source hash because
        // we need to know the relative position of the given logs
        // in the whole block. Could just assume 0? But probably not important
        // for most testing
        //
        // bytes32 sourceHash,
        //
        address from;
        address to;
        uint256 value;
        uint256 mint;
        uint64 gasLimit;
        bool isCreation;
        bytes data;
    }

    Vm private constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 constant transactionDepositedTopic = keccak256("TransactionDeposited(address,address,uint256,bytes)");

    error DepositTransactionNotFound();
    error OpaqueDataTooShort();

    function relayDepositTransaction(VmSafe.Log[] memory logs, uint256 forkId) public {
        uint256 currentFork = vm.activeFork();
        DepositTransaction memory depositTx = getDepositTransactionFromLogs(logs);
        vm.selectFork(forkId);
        vm.deal(depositTx.from, depositTx.mint);
        vm.startPrank(depositTx.from);
        if (depositTx.to == address(0)) {
            address newContract;
            uint256 value = depositTx.value;
            bytes memory bytecode = depositTx.data;
            // TODO(Wilson): How can we limit the gas here?
            assembly {
                newContract := create(value, add(bytecode, 0x20), mload(bytecode))
            }

            if (newContract == address(0)) {
                revert("L2 contract creation failed");
            }
        } else {
            (bool success, bytes memory returnedData) =
                depositTx.to.call{value: depositTx.value, gas: depositTx.gasLimit}(depositTx.data);

            if (!success) {
                if (returnedData.length > 0) {
                    (string memory reason) = abi.decode(returnedData, (string));
                    revert(string.concat("L2 call reverted with reason: ", reason));
                } else {
                    revert("L2 call reverted with no reason");
                }
            }
        }
        vm.selectFork(currentFork);
    }

    function getDepositTransactionFromLogs(VmSafe.Log[] memory logs) public pure returns (DepositTransaction memory) {
        for (uint256 i; i < logs.length; i++) {
            if (logs[i].topics[0] == transactionDepositedTopic) {
                address from = address(bytes20(logs[i].topics[1] << 96));
                address to = address(bytes20(logs[i].topics[2] << 96));
                (bytes memory opaqueData) = abi.decode(logs[i].data, (bytes));
                (uint256 mint, uint256 value, uint64 gas, bool isCreation, bytes memory data) =
                    parseOpaqueData(opaqueData);
                return DepositTransaction({
                    from: from,
                    to: isCreation ? address(0) : to,
                    value: value,
                    mint: mint,
                    gasLimit: gas,
                    isCreation: isCreation,
                    data: data
                });
            }
        }

        revert DepositTransactionNotFound();
    }

    function parseOpaqueData(bytes memory opaqueData)
        public
        pure
        returns (uint256 mint, uint256 value, uint64 _gas, bool isCreation, bytes memory data)
    {
        if (opaqueData.length < 73) revert OpaqueDataTooShort();

        // Extract the mint value (first 32 bytes)
        assembly {
            mint := mload(add(opaqueData, 32))
        }

        // Extract the value (second 32 bytes)
        assembly {
            value := mload(add(opaqueData, 64))
        }

        assembly {
            _gas := mload(add(opaqueData, 72)) // Load next 32 bytes
        }

        // Extract isCreation (next 1 byte)
        uint256 isCreationRaw = uint8(opaqueData[72]);
        isCreation = isCreationRaw == 0x01;

        // The rest of the data is the dynamic `data` part
        if (opaqueData.length > 73) {
            data = new bytes(opaqueData.length - 73);
            for (uint256 i = 73; i < opaqueData.length; i++) {
                data[i - 73] = opaqueData[i];
            }
        }
    }
}
