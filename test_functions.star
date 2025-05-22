import json

def run(plan):
    """
    Test all hardhat-package functions with the Bloctopus network.
    
    This function tests each function in the hardhat-package with the Bloctopus network:
    - verify() - Verifies a deployed contract on Blockscout
    - configure_networks() - Configures multiple networks for deployment
    - interact() - Interacts with a deployed contract
    - optimize_gas() - Runs gas optimization tools on contracts
    - track_deployment() - Tracks a deployed contract for future reference
    
    Args:
        plan: The Kurtosis plan
        
    Returns:
        The result of the tests
    """
    # Import the hardhat-package
    hardhat = import_module("github.com/LZeroAnalytics/hardhat-package/main.star")
    
    # Bloctopus network configuration
    bloctopus_network = {
        "bloctopus": {
            "rpc_url": "https://eb9ad9faac334860ba32433d00ea3a19-rpc.network.bloctopus.io",
            "chain_id": 6129906,
            "private_key": "0xd29644a2fbc8649ef6831514c241af9ca09c16156ac159dc7cb9cd64466b2569",
            "verification_url": "https://eb9ad9faac334860ba32433d00ea3a19-blockscout.network.bloctopus.io"
        }
    }
    
    # Create a temporary directory for the test project
    test_dir = plan.render_templates(
        name = "test-project",
        templates = {
            "hardhat.config.js": """
                require("@nomicfoundation/hardhat-toolbox");
                
                module.exports = {
                  solidity: "0.8.18",
                  networks: {
                    bloctopus: {
                      url: "https://eb9ad9faac334860ba32433d00ea3a19-rpc.network.bloctopus.io",
                      chainId: 6129906,
                      accounts: ["0xd29644a2fbc8649ef6831514c241af9ca09c16156ac159dc7cb9cd64466b2569"]
                    }
                  }
                };
            """,
            "contracts/SimpleStorage.sol": """
                // SPDX-License-Identifier: MIT
                pragma solidity ^0.8.0;
                
                contract SimpleStorage {
                    uint256 private value;
                    
                    constructor(uint256 initialValue) {
                        value = initialValue;
                    }
                    
                    function setValue(uint256 newValue) public {
                        value = newValue;
                    }
                    
                    function getValue() public view returns (uint256) {
                        return value;
                    }
                }
            """,
            "scripts/deploy.js": """
                async function main() {
                    const [deployer] = await ethers.getSigners();
                    console.log("Deploying contracts with the account:", deployer.address);
                
                    const SimpleStorage = await ethers.getContractFactory("SimpleStorage");
                    const initialValue = 42;
                    const simpleStorage = await SimpleStorage.deploy(initialValue);
                
                    await simpleStorage.waitForDeployment();
                
                    const contractAddress = await simpleStorage.getAddress();
                    console.log("SimpleStorage deployed to:", contractAddress);
                    console.log(JSON.stringify({
                        contractAddress: contractAddress,
                        constructorArgs: [initialValue]
                    }));
                
                    return {
                        contractAddress: contractAddress,
                        constructorArgs: [initialValue]
                    };
                }
                
                main()
                    .then((result) => process.exit(0))
                    .catch((error) => {
                        console.error(error);
                        process.exit(1);
                    });
            """,
            "package.json": """
                {
                  "name": "test-project",
                  "version": "1.0.0",
                  "description": "Test project for hardhat-package verification",
                  "main": "index.js",
                  "scripts": {
                    "test": "echo \\"Error: no test specified\\" && exit 1"
                  },
                  "keywords": [],
                  "author": "",
                  "license": "ISC",
                  "devDependencies": {
                    "@nomicfoundation/hardhat-toolbox": "^2.0.0",
                    "@nomicfoundation/hardhat-verify": "^1.0.0",
                    "hardhat": "^2.14.0",
                    "hardhat-gas-reporter": "^1.0.9"
                  }
                }
            """
        }
    )
    
    # Test results
    results = {}
    
    # Test 1: Initialize the hardhat project
    print("Test 1: Initialize the hardhat project")
    hardhat_service = hardhat.run(
        plan=plan,
        project_url=test_dir,
        env_vars={
            "RPC_URL": "https://eb9ad9faac334860ba32433d00ea3a19-rpc.network.bloctopus.io",
            "CHAIN_ID": "6129906",
            "PRIVATE_KEY": "0xd29644a2fbc8649ef6831514c241af9ca09c16156ac159dc7cb9cd64466b2569"
        }
    )
    results["initialize"] = "Success"
    
    # Test 2: Configure networks
    print("Test 2: Configure networks")
    network_result = hardhat.configure_networks(
        plan=plan,
        networks=bloctopus_network
    )
    results["configure_networks"] = network_result
    
    # Test 3: Compile the contract
    print("Test 3: Compile the contract")
    compile_result = hardhat.compile(plan)
    results["compile"] = compile_result
    
    # Test 4: Deploy the contract
    print("Test 4: Deploy the contract")
    deployment_result = hardhat.script(
        plan=plan,
        script="deploy.js",
        network="bloctopus",
        return_keys={
            "contractAddress": "fromjson | .contractAddress",
            "constructorArgs": "fromjson | .constructorArgs"
        }
    )
    results["deploy"] = deployment_result
    
    # Test 5: Track deployment
    print("Test 5: Track deployment")
    if "contractAddress" in deployment_result:
        track_result = hardhat.track_deployment(
            plan=plan,
            contract_name="SimpleStorage",
            contract_address=deployment_result["contractAddress"],
            network="bloctopus",
            constructor_args=deployment_result["constructorArgs"]
        )
        results["track_deployment"] = track_result
    
    # Test 6: Verify the contract
    print("Test 6: Verify the contract")
    if "contractAddress" in deployment_result:
        verification_result = hardhat.verify(
            plan=plan,
            contract_address=deployment_result["contractAddress"],
            network="bloctopus",
            verification_url="https://eb9ad9faac334860ba32433d00ea3a19-blockscout.network.bloctopus.io",
            constructor_args=deployment_result["constructorArgs"]
        )
        results["verify"] = verification_result
    
    # Test 7: Interact with the contract
    print("Test 7: Interact with the contract")
    if "contractAddress" in deployment_result:
        interact_result = hardhat.interact(
            plan=plan,
            contract_address=deployment_result["contractAddress"],
            function_name="getValue",
            network="bloctopus"
        )
        results["interact"] = interact_result
    
    # Test 8: Gas optimization
    print("Test 8: Gas optimization")
    gas_result = hardhat.optimize_gas(
        plan=plan
    )
    results["optimize_gas"] = gas_result
    
    return results
