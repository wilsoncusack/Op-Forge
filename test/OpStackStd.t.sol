// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Test, console2} from "forge-std/Test.sol";
import {Vm, VmSafe} from "lib/forge-std/src/Vm.sol";

import {OpStackStd} from "../src/testing/OpStackStd.sol";
import {AddressAliasHelper} from "./AddressAliasHelper.sol";

interface IPortal {
    event TransactionDeposited(address indexed from, address indexed to, uint256 indexed version, bytes opaqueData);

    function depositTransaction(address _to, uint256 _value, uint64 _gasLimit, bool _isCreation, bytes memory _data)
        external
        payable;
}

contract Simple {
    uint256 public x = 1;
}

contract OpStackStdTest is Test {
    uint256 l1Fork;
    uint256 opStackFork;
    IPortal portal;

    function setUp() public {
        l1Fork = vm.createFork("https://ethereum.publicnode.com");
        opStackFork = vm.createFork("https://mainnet.base.org");
        portal = IPortal(0x49048044D57e1C92A77f79988d21Fa8fAF74E97e);

        vm.selectFork(l1Fork);
    }

    // TODO(Wilson)
    // function getDepositTransactionFromLogs
    // fails if no log
    // correctly if log
    // handles create address correctly
    //
    // function relayDepositTransaction
    // reverts with revert message
    // reverts without revert message

    function testRelaysContractCallOnL2() public {
        uint256 value = 0.02002 ether;
        address to = 0xb129419F9B035E9d80B4a320ffcf5BE93Cb7994B;
        uint64 gasLimit = 300_000;
        bool isCreation = false;
        bytes memory data =
            hex"173a562d00000000000000000000000000000000000000000000000000000000000000010000000000000000000000003a6372b2013f9876a84761187d933dee0653e3770000000000000000000000000000000000000000000000000000000000000007";
        vm.deal(address(this), value);
        vm.recordLogs();
        portal.depositTransaction{value: value}(to, value, gasLimit, isCreation, data);
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        vm.expectCall(to, value, gasLimit, data);
        OpStackStd.relayDepositTransaction(logs, opStackFork);
    }

    function testSendEthOnL2() public {
        address bob = address(0xb0b);
        // pre check
        vm.selectFork(opStackFork);
        assertEq(bob.balance, 0);

        vm.selectFork(l1Fork);
        uint256 value = 1e18;
        vm.deal(address(this), value);
        vm.recordLogs();
        portal.depositTransaction{value: value}({
            _to: bob,
            _value: value,
            _gasLimit: 21_000,
            _isCreation: false,
            _data: ""
        });
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        OpStackStd.relayDepositTransaction(logs, opStackFork);

        // post check
        vm.selectFork(opStackFork);
        assertEq(bob.balance, value);
    }

    function testCreatesContractOnL2() public {
        address expectedAddress = computeCreateAddress(AddressAliasHelper.applyL1ToL2Alias(address(this)), 0);
        bytes memory expectedBytes = hex"";
        assertEq(expectedAddress.code, expectedBytes);
        vm.recordLogs();
        portal.depositTransaction(address(0), 0, 300_000, true, type(Simple).creationCode);
        VmSafe.Log[] memory logs = vm.getRecordedLogs();
        OpStackStd.relayDepositTransaction(logs, opStackFork);

        vm.selectFork(opStackFork);
        Simple simple = new Simple();
        assertEq(expectedAddress.code, address(simple).code);
    }

    function testParseOpaqueData(uint256 mint, uint256 value, uint64 gasLimit, bool isCreation, bytes memory data)
        public
    {
        bytes memory opaque = abi.encodePacked(mint, value, gasLimit, isCreation, data);
        (uint256 mint_, uint256 value_, uint64 gas_, bool isCreation_, bytes memory data_) =
            OpStackStd.parseOpaqueData(opaque);
        assertEq(mint_, mint);
        assertEq(value_, value);
        assertEq(gas_, gasLimit);
        assertEq(isCreation_, isCreation);
        assertEq(data_, data);
    }
}
