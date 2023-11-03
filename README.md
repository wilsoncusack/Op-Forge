### Op-Forge 

Tools for using forge with OpStack chains. 

#### OPStackStd - Testing Tools 

##### relayDepositTransaction 
A helper method for creating an L2 transactions from the L1 event logs, just as the Op-Node does. 

```solidity
import {OpStackStd} from "Op-Forge/testing/OpStackStd.sol";

function testSendEthOnL2() public {
    address bob = address(0xb0b);
    // pre check
    vm.selectFork(opStackFork);
    assertEq(bob.balance, 0);
    
    vm.selectFork(l1Fork);
    uint256 value = 1e18;
    vm.deal(address(this), value);
    vm.recordLogs();
    portal.depositTransaction{value: value}({_to: bob, _value: value, _gasLimit: 21_000, _isCreation: false, _data: ""});
    VmSafe.Log[] memory logs = vm.getRecordedLogs();
    OpStackStd.relayDepositTransaction(logs, opStackFork);

    // post check
    vm.selectFork(opStackFork);
    assertEq(bob.balance, value);
}
```