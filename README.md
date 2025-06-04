# Hardhat Kurtosis Module 🚀

🛠️ Automate Hardhat contract deployment & testing in Kurtosis

## 📋 Overview

>This package allows you to integrate smart contract deployment into your Kurtosis workflows without hardcoding or bundling any full Hardhat directories into your package. It dynamically pulls your Hardhat projects on demand and provides a ready-to-use Hardhat environment with a broad set of utilities for flexible deployment. Use it to:
> - Deploy contracts across multiple chains with minimal setup.
> - Plug contracts deployment and config steps into broader Kurtosis flows — before, between, or after infrastructure components.
> - Spin up an always-running contract operations environment that plugs directly into your networks and can power tools like custom UIs for deploying, testing, or interacting with contracts.

## ⚡ Quick Start

This Starlark module spins up a Node.js container, loads a Hardhat project (local or GitHub), and gives you programmatic control to compile, test, and run hardhat scripts in a reproducible Kurtosis environment.

<details>
<summary> Prerequisites</summary>

- [Kurtosis](https://docs.kurtosis.com/) installed
- A Hardhat project (local folder or GitHub repo)
- (Optional) GitHub token for private repos
</details>

```python
# Import the module in your Kurtosis plan
hardhat_pkg = import_module("./hardhat-package/main.star")
```

---

## 🏗️ Usage

> **Note:** If your `project_url` is remote, it must start with `github.com` (not `https://`). If local, just use a local relative path.

### 2️⃣ Run the Package Standalone

You can run this Kurtosis package directly from the command line:

```bash
# 1. Authenticate Kurtosis with GitHub (for private repos or higher rate limits)
kurtosis github login .

# 2. Run the package, passing the project URL as a parameter
kurtosis run --enclave hardhat . -- '{"project_url": "github.com/LZeroAnalytics/hardhat-vrf-contracts"}'
```
- The first command logs you into GitHub for Kurtosis to access private repos.
- The second command runs the package in a new enclave, passing the Hardhat project URL as a parameter.



## 🧩 Function Reference

| Function   | Purpose                                      |
|------------|----------------------------------------------|
| `run`      | Start the Hardhat container with project     |
| `compile`  | Compile contracts                            |
| `script`   | Run a Hardhat script                         |
| `task`     | Run a Hardhat task                           |
| `test`     | Run Hardhat tests                            |
| `verify`   | Verify contract on Blockscout                |
| `configure_networks` | Configure multiple networks        |
| `interact` | Interact with deployed contracts             |
| `optimize_gas` | Analyze gas usage                        |
| `cleanup`  | Remove the Hardhat container                 |

---

### 🚀 Core Functions

#### `run(plan, project_url, env_vars={}, more_files={})`
Initializes a Hardhat environment with your project.

```python
# Basic usage
hardhat_service = hardhat_pkg.run(plan, "github.com/your-org/your-project")

# With environment variables
hardhat_service = hardhat_pkg.run(
    plan, 
    "github.com/your-org/your-project",
    env_vars = {
        "RPC_URL": "http://ethereum:8545",
        "PRIVATE_KEY": "0x123...",
        "CHAIN_ID": "1337"
    }
)

# With additional files and local contracts repo
hardhat_service = hardhat_pkg.run(
    plan,
    "./contracts",
    more_files = {
        "/tmp/hardhat/config.json": config_artifact
    }
)
```

#### `script(plan, script, network="bloctopus", return_keys=None, params=None, extraCmds=None)`
Runs a Hardhat script and optionally extracts JSON output.

```python
# Basic script execution
result = hardhat_pkg.script(plan, "scripts/deploy.js")

# With return value extraction
result = hardhat_pkg.script(
    plan,
    script = "scripts/deploy.js", 
    network = "bloctopus",
    return_keys = {"registry": "automationRegistry"}
)
registry_address = result["extract.registry"]

# With parameters
result = hardhat_pkg.script(
    plan,
    script = "scripts/configure.js",
    params = {
        "REGISTRY_ADDRESS": "0x123...",
        "NETWORK_TYPE": "ethereum"
    }
)
```

---

### 🧑‍💻 Extracting Return Keys (JSON Output Tips)

To extract return keys from your Hardhat script into Starlark, you have two options:

**Option 1: Output ONLY JSON**
- Your script must print only a single JSON object to `console.log` (no other logs, prints, or errors).
- Example:
  ```js
  console.log(JSON.stringify({ automationRegistry, automationRegistrar }));
  ```
- In Starlark:
  ```python
  result = hardhat_pkg.script(
      plan,
      script = "scripts/deploy-automation-v23.js",
      network = "bloctopus", 
      return_keys = {"registry": "automationRegistry", "registrar": "automationRegistrar"}
  )

  registry_addr = result["extract.registry"]
  registrar_addr = result["extract.registrar"]
  ```

**Option 2: Use Separators and extraCmds**
- If you want to include other logs, you MUST wrap your JSON output with clear separators and filter it in Kurtosis using `extraCmds`:
  ```python
  result = hardhat_pkg.script(
      plan,
      script = "scripts/deploy.js",
      extraCmds = " | grep -A 100 DEPLOYMENT_JSON_BEGIN | grep -B 100 DEPLOYMENT_JSON_END | sed '/DEPLOYMENT_JSON_BEGIN/d' | sed '/DEPLOYMENT_JSON_END/d'"
  )
  ```
- In your hardhat script:
  ```js
  console.log('🤖  DEPLOYING AUTOMATION v2.3...');
  console.log('DEPLOYMENT_JSON_BEGIN');
  console.log(JSON.stringify({ automationRegistry, automationRegistrar }));
  console.log('DEPLOYMENT_JSON_END');
  ```

**Summary:**
- If you want to extract return keys, you must EITHER output only JSON, OR use separators + extraCmds. Mixing logs and JSON without separators will break extraction.

---

## 🔍 Contract Verification

The package supports automatic contract verification with Blockscout explorer. This implementation detects and extends existing hardhat.config.js files instead of overwriting them.

```python
# Deploy a contract first
deployment_result = hardhat_pkg.script(
    plan,
    script = "scripts/deploy.js",
    network = "bloctopus",
    return_keys = {"contractAddress": "contractAddress"}
)

contract_address = deployment_result["extract.contractAddress"]

# Verify the deployed contract
verification_result = hardhat_pkg.verify(
    plan,
    contract_address = contract_address,
    network = "bloctopus",
    verification_url = "http://blockscout:8050",
    constructor_args = ["0x123", "argument2", "100"],  # Optional constructor arguments
    contract_path = "contracts/MyContract.sol:MyContract"  # Optional contract path
)

explorer_url = verification_result["explorer_contract_url"]
```

---

## 🌐 Multi-Network Deployment

Configure multiple networks for deployment with a single function call:

```python
# Configure multiple networks
networks = {
    "ethereum": {
        "rpc_url": "http://ethereum-node:8545",
        "chain_id": 1337,
        "private_key": "0xprivatekey",
        "verification_url": "http://blockscout:8050"
    },
    "polygon": {
        "rpc_url": "http://polygon-node:8545", 
        "chain_id": 80001,
        "private_key": "0xprivatekey",
        "verification_url": "http://blockscout-polygon:8050"
    }
}

network_result = hardhat_pkg.configure_networks(plan, networks)

# Deploy to Ethereum
ethereum_result = hardhat_pkg.script(
    plan,
    script = "scripts/deploy.js",
    network = "ethereum",
    return_keys = {"contractAddress": "contractAddress"}
)

# Deploy to Polygon
polygon_result = hardhat_pkg.script(
    plan,
    script = "scripts/deploy.js", 
    network = "polygon",
    return_keys = {"contractAddress": "contractAddress"}
)
```

---

## 🤝 Contract Interaction

Interact with deployed contracts directly:

```python
# Call a view function (e.g., balanceOf) - default extraction
interaction_result = hardhat_pkg.interact(
    plan,
    contract_address = "0x123...",
    function_name = "balanceOf", 
    network = "bloctopus",
    params = ["0x456..."]  # Function parameters as array
)

balance = interaction_result["return_value"]
tx_hash = interaction_result["transaction_hash"]  # null for view functions
gas_used = interaction_result["gas_used"]         # "0" for view functions

# Call a transaction function (e.g., transfer)
tx_result = hardhat_pkg.interact(
    plan,
    contract_address = "0x123...",
    function_name = "transfer",
    network = "bloctopus", 
    params = ["0x456...", "1000000000000000000"]  # to, amount
)

tx_hash = tx_result["transaction_hash"]
gas_used = tx_result["gas_used"]
result = tx_result["return_value"]

# Custom return value extraction (advanced)
custom_result = hardhat_pkg.interact(
    plan,
    contract_address = "0x123...",
    function_name = "getInfo",
    network = "bloctopus",
    params = [],
    return_keys = {"info": "result", "hash": "txHash", "gas": "gasUsed"}  # Custom keys
)

info = custom_result["return_value"]      # Uses extract.info
tx_hash = custom_result["transaction_hash"]  # Uses extract.hash  
gas_used = custom_result["gas_used"]      # Uses extract.gas
```

**Advanced Options:**
- **CONTRACT_NAME**: Set `params = {"CONTRACT_NAME": "MyContract"}` if your contract has a specific name different from "Contract"

---

## ⛽ Gas Optimization

Analyze and optimize gas usage in your contracts:

```python
# Run gas optimization on all contracts
gas_report = hardhat_pkg.optimize_gas(plan)
print(gas_report["gas_report"])

# Run gas optimization on a specific contract
gas_report = hardhat_pkg.optimize_gas(plan, "contracts/MyContract.sol")
print(gas_report["gas_report"])
```

---

## 🧪 Testing

Run your Hardhat tests in the Kurtosis environment:

```python
# Run all tests
test_result = hardhat_pkg.test(plan)

# Run specific test file
test_result = hardhat_pkg.test(plan, "test/AutomationRegistry.test.js")

# Run with specific network
test_result = hardhat_pkg.test(plan, "test/AutomationRegistry.test.js", "bloctopus")
```

---

## 🗂️ Tasks

Execute custom Hardhat tasks:

```python
# Run a custom task
task_result = hardhat_pkg.task(plan, "accounts", "bloctopus")

# Run task with parameters
task_result = hardhat_pkg.task(
    plan, 
    "verify-deployment",
    "bloctopus",
    params = {"REGISTRY_ADDRESS": "0x123..."}
)
```

---

## 🧹 Cleanup

Remove the Hardhat container when done:

```python
# Clean up resources
hardhat_pkg.cleanup(plan)
```

> **Note:** Cleanup is optional - Kurtosis will automatically clean up when the enclave is destroyed.
