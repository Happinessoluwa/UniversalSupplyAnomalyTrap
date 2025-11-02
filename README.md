# UniversalSupplyAnomalyTrap

## **README — UniversalSupplyAnomalyTrap**

### **Overview**

**UniversalSupplyAnomalyTrap** is a Drosera-compatible proof-of-concept trap designed to monitor **any ERC20 token’s total supply** and flag anomalies when a rapid increase or decrease exceeds a configurable threshold.
It provides a generic, universal version of the supply anomaly detector — no hardcoded addresses — making it deployable across different tokens and networks without modification.

This repository contains:

* The main trap contract `UniversalSupplyAnomalyTrap.sol`
* The response handler `UniversalSupplyResponse.sol`
* A working `drosera.toml` configuration for the Hoodi testnet.

---

### **Files in this repo**

| File                                 | Description                                          |
| ------------------------------------ | ---------------------------------------------------- |
| `src/UniversalSupplyAnomalyTrap.sol` | Main Drosera trap (implements `ITrap`)               |
| `src/UniversalSupplyResponse.sol`    | Response contract that logs and emits anomaly alerts |
| `drosera.toml`                       | Configuration for Hoodi Drosera relay setup          |
| `README.md`                          | This documentation and test instructions             |

---

### **Behaviour & Data Flow**

1. The operator calls `setTargetToken(address)` to define the ERC20 token to monitor.
2. The operator configures `setMaxSupplyChange(uint256)` to define the maximum allowed supply deviation.
3. Drosera (or any external observer) periodically calls `collect()` on the trap.

   * `collect()` reads the token’s `totalSupply()` and returns encoded data:

     ```solidity
     abi.encode(address token, uint256 totalSupply, uint256 threshold)
     ```
4. The relay accumulates samples over its configured window, then calls:

   ```solidity
   shouldRespond(bytes[] calldata data)
   ```

   where:

   * `data[0]` = latest sample
   * `data[data.length-1]` = oldest sample
5. If the difference between the latest and oldest total supply exceeds the threshold,
   the trap deterministically returns `(true, abi.encode(token, oldSupply, newSupply))`.
6. The Drosera relay (or any response handler) calls:

   ```solidity
   respondWithSupplyAlert(address,uint256,uint256)
   ```

   on the deployed `UniversalSupplyResponse.sol` contract to log the event.

---

### **Deploying (Quick)**

1. **Compile:**

   ```bash
   forge build
   ```
2. **Deploy Response Contract:**
   Deploy `UniversalSupplyResponse.sol` to Hoodi testnet using Remix or Foundry.
   Copy the deployed contract address.
3. **Deploy Trap:**
   Deploy `UniversalSupplyAnomalyTrap.sol` (no constructor arguments).
4. **Configure Trap:**

   ```bash
   cast send <TRAP_ADDRESS> "setTargetToken(address)" <TOKEN_ADDRESS> --private-key <KEY>
   cast send <TRAP_ADDRESS> "setMaxSupplyChange(uint256)" <THRESHOLD> --private-key <KEY>
   ```
5. **Edit drosera.toml:**
   Update it to include your deployed response contract and operator address.

---

### **Quick Cast Examples**

Replace `<RPC>`, `<TRAP_ADDRESS>`, `<TOKEN>`, and `<KEY>` with your values.

#### **1) Collect supply data**

```bash
COLLECT_RAW=$(cast call --rpc-url <RPC> <TRAP_ADDRESS> "collect()")
cast abi-decode "(address,uint256,uint256)" "$COLLECT_RAW"
```

**Example Output:**

```
(address) 0xBaa...
(uint256) 1000000000000000000000
(uint256) 50000000000000000000
```

*Interpretation:* Token supply is 1000 units, threshold is 50 units.

---

#### **2) Check for anomaly (manual)**

Collect multiple samples:

```bash
cast call --rpc-url <RPC> <TRAP_ADDRESS> "collect()" > oldData
# wait or simulate time / mint / burn
cast call --rpc-url <RPC> <TRAP_ADDRESS> "collect()" > newData
```

Then call:

```bash
cast call <TRAP_ADDRESS> "shouldRespond(bytes[]) returns (bool,bytes)" '[<encodedNew>,<encodedOld>]' --rpc-url <RPC>
```

If it returns `true`, decode payload:

```bash
cast abi-decode "(address,uint256,uint256)" <PAYLOAD>
```

---

#### **3) Emit response manually**

```bash
cast send <RESPONSE_CONTRACT> "respondWithSupplyAlert(address,uint256,uint256)" <TOKEN> <OLD_SUPPLY> <NEW_SUPPLY> --private-key <KEY>
```

---

### **Foundry Test — test/UniversalSupplyAnomalyTrap.t.sol**

```solidity
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/UniversalSupplyAnomalyTrap.sol";
import "../src/UniversalSupplyResponse.sol";

contract UniversalSupplyAnomalyTrapTest is Test {
    UniversalSupplyAnomalyTrap trap;
    UniversalSupplyResponse response;

    contract MockERC20 {
        uint256 public totalSupply;
        function mint(uint256 a) external { totalSupply += a; }
        function burn(uint256 a) external { totalSupply -= a; }
    }

    MockERC20 token;

    function setUp() public {
        trap = new UniversalSupplyAnomalyTrap();
        response = new UniversalSupplyResponse();
        token = new MockERC20();

        trap.setTargetToken(address(token));
        trap.setMaxSupplyChange(1000 ether);
    }

    function testCollectEncodesData() public {
        bytes memory data = trap.collect();
        UniversalSupplyAnomalyTrap.SupplyData memory decoded = abi.decode(data, (UniversalSupplyAnomalyTrap.SupplyData));
        assertEq(decoded.tokenAddress, address(token));
    }

    function testShouldRespondTriggersOnAnomaly() public {
        token.mint(10000 ether);
        bytes memory oldData = trap.collect();
        token.mint(12000 ether);
        bytes memory newData = trap.collect();

        bytes ;
        samples[0] = newData;
        samples[1] = oldData;

        (bool trigger, bytes memory payload) = trap.shouldRespond(samples);
        assertTrue(trigger);

        (address tkn, uint256 oldSupply, uint256 newSupply) = abi.decode(payload, (address, uint256, uint256));
        response.respondWithSupplyAlert(tkn, oldSupply, newSupply);
    }
}
```

---

### **drosera.toml (example)**

```toml
ethereum_rpc = "https://ethereum-hoodi-rpc.publicnode.com"
drosera_rpc = "https://relay.hoodi.drosera.io"
eth_chain_id = 560048
drosera_address = "0x91cB447BaFc6e0EA0F4Fe056F5a9b1F14bb06e5D"

[traps]

[traps.supplyanomaly]
path = "out/UniversalSupplyAnomalyTrap.sol/UniversalSupplyAnomalyTrap.json"
response_contract = "Response contract address" #Replace with your deployed response contract address
response_function = "respond(string,bytes)"
cooldown_period_blocks = 30
min_number_of_operators = 1
max_number_of_operators = 2
block_sample_size = 10
private_trap = true
whitelist = ["YOUR_OPERATOR_ADDRESS"]
```

---

### **Attribution**

This design is inspired by **BridgeSupplyTrap** by *Kingflirckz22* and adapted into a universal, token-agnostic trap.
Repository: [Happinessoluwa/UniversalSupplyAnomalyTrap](https://github.com/Happinessoluwa/UniversalSupplyAnomalyTrap)

