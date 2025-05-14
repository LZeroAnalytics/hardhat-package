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
hardhat_pkg = import_module("./hardhat-package/hardhat.star")
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

---

### 1️⃣ Deploy Contracts Example

```python
def deploy_mpc_vrf_contracts(plan, private_key, rpc_url, link_token_address, link_native_token_feed_address, key_id, network_type="ethereum"):
    """Deploy contracts using Hardhat"""
    hardhat = hardhat_pkg.init(
        plan, 
        "github.com/LZeroAnalytics/hardhat-vrf-contracts.git",
        env_vars = {
            "RPC_URL": rpc_url,
            "PRIVATE_KEY": private_key,
            "NETWORK_TYPE": network_type
            "CHAIN_ID": chain_id
        }
    )

    hardhat_pkg.compile(plan)
    
    # Deploy coordinator and get addresses
    result = hardhat_pkg.run(
        plan = plan,
        script = "scripts/deploy-contracts.ts",
        network = "bloctopus",
        return_keys = ["contractAddress", "beaconContractAddress"]
    )
```

---

## 🧩 Function Reference

| Function   | Purpose                                      |
|------------|----------------------------------------------|
| `init`     | Start the Hardhat container                  |
| `compile`  | Compile contracts                            |
| `scripts`      | Run a Hardhat script                         |
| `task`     | Run a Hardhat task                           |
| `test`     | Run Hardhat tests                            |
| `cleanup`  | Remove the Hardhat container                 |

---

### 🧑‍💻 Extracting Return Keys (JSON Output Tips)

To extract return keys from your Hardhat script into Starlark, you have two options:

**Option 1: Output ONLY JSON**
- Your script must print only a single JSON object to `console.log` (no other logs, prints, or errors).
- Example:
  ```js
  console.log(JSON.stringify({ contractAddress, beaconContractAddress }));
  ```
- in starlark
  ```js
  result = hardhat_pkg.script(
    plan = plan,
    script = "scripts/deploy-contracts.ts",
    network = "bloctopus",
    return_keys = ["contractAddress", "beaconContractAddress"]
  )

  contract_addr = result["extract.vrfCoordinatorMPC"],
  beacon_addr = result["extract.dkg"]
  ```

**Option 2: Use Separators and extraCmds**
- If you want to include other logs, you MUST wrap your JSON output with clear separators and filter it in Kurtosis using `extraCmds`:
  ```python
  result = hardhat_pkg.script(
    ...
    extraCmds = " | grep -A 100 OUTPUT_JSON_BEGIN | grep -B 100 OUTPUT_JSON_END"
  )
  ```
- In your hardhat script:
  ```js
  console.log('some log...');
  console.log('OUTPUT_JSON_BEGIN');
  console.log(JSON.stringify({ contractAddress, beaconContractAddress }));
  console.log('OUTPUT_JSON_END');
  ```

**Summary:**
- If you want to extract return keys, you must EITHER output only JSON, OR use separators + extraCmds. Mixing logs and JSON without separators will break extraction.