import json

def run(plan):
    """
    Test the hardhat-package verification functionality with the Bloctopus network.
    
    This function creates a simple Solidity contract, deploys it to the Bloctopus network,
    and verifies it using the hardhat-verify plugin.
    
    Args:
        plan: The Kurtosis plan
        
    Returns:
        The result of the verification test
    """
    # Import the hardhat-package
    hardhat = import_module("github.com/LZeroAnalytics/hardhat-package/main.star")
    
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
                
                    await simpleStorage.deployed();
                
                    console.log("SimpleStorage deployed to:", simpleStorage.address);
                    console.log(JSON.stringify({
                        contractAddress: simpleStorage.address,
                        constructorArgs: [initialValue]
                    }));
                
                    return {
                        contractAddress: simpleStorage.address,
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
                    "hardhat": "^2.14.0"
                  }
                }
            """
        }
    )
    
    # Initialize the hardhat project
    hardhat_service = hardhat.run(
        plan=plan,
        project_url=test_dir,
        env_vars={
            "RPC_URL": "https://eb9ad9faac334860ba32433d00ea3a19-rpc.network.bloctopus.io",
            "CHAIN_ID": "6129906",
            "PRIVATE_KEY": "0xd29644a2fbc8649ef6831514c241af9ca09c16156ac159dc7cb9cd64466b2569"
        }
    )
    
    # Compile the contract
    hardhat.compile(plan)
    
    # Deploy the contract
    deployment_result = hardhat.script(
        plan=plan,
        script="deploy.js",
        network="bloctopus",
        return_keys={
            "contractAddress": "fromjson | .contractAddress",
            "constructorArgs": "fromjson | .constructorArgs"
        }
    )
    
    # Verify the contract
    verification_result = hardhat.verify(
        plan=plan,
        contract_address=deployment_result["contractAddress"],
        network="bloctopus",
        verification_url="https://eb9ad9faac334860ba32433d00ea3a19-blockscout.network.bloctopus.io",
        constructor_args=deployment_result["constructorArgs"]
    )
    
    return {
        "deployment_result": deployment_result,
        "verification_result": verification_result
    }
