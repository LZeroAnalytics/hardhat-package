import os
import json

# HardHat has problems with node 20 so we use an older version of node
NODE_ALPINE = "node:20.14.0-alpine"
HARDHAT_PROJECT_DIR = "/tmp/hardhat/"
HARDHAT_SERVICE_NAME = "hardhat"

# Helper function to read script content from the local filesystem
def _read_script_file(path):
    with open(path, 'r') as file:
        return file.read()

# Create artifacts for all script files
SCRIPT_FILES = {
    "update-verification-config.js": _read_script_file("./src/scripts/update-verification-config.js"),
    "configure-networks.js": _read_script_file("./src/scripts/configure-networks.js"),
    "contract-interact.js": _read_script_file("./src/scripts/contract-interact.js"),
    "enable-gas-reporter.js": _read_script_file("./src/scripts/enable-gas-reporter.js"),
    "track-deployment.js": _read_script_file("./src/scripts/track-deployment.js")
}

# Creates a Node.js container with Hardhat project either from GitHub or local
def run(plan, project_url, env_vars={}, more_files={}, include_scripts=True):
    # Handle local paths vs remote URLs differently
    if project_url.startswith("/"):
        # For local paths, create a files artifact from the directory
        import os
        if not os.path.exists(project_url):
            raise Exception(f"Local path '{project_url}' does not exist")
        hardhat_project = plan.upload_files(src=project_url)
    else:
        # For remote URLs (like GitHub), use the URL directly
        hardhat_project = plan.upload_files(src=project_url)

    files = {HARDHAT_PROJECT_DIR: hardhat_project}
    for filepath, file_artifact in more_files.items():
        files[filepath] = file_artifact
    
    # Include script files if requested
    if include_scripts:
        script_dir = "{0}scripts/".format(HARDHAT_PROJECT_DIR)
        for script_name, script_content in SCRIPT_FILES.items():
            script_path = script_dir + script_name
            script_artifact = plan.upload_string(script_content)
            files[script_path] = script_artifact

    hardhat_service = plan.add_service(
        name = "hardhat",
        config = ServiceConfig(
            image = NODE_ALPINE,
            files = files,
            env_vars = env_vars,
            entrypoint = ["tail", "-f", "/dev/null"]
        )
    )

    # Clean npm cache and node_modules before installing
    cmds = [
        "npm install -g pnpm",
        "cd {0}".format(HARDHAT_PROJECT_DIR),
        "mkdir -p scripts",
        "pnpm install --shamefully-hoist"
    ]
    plan.exec(
        service_name = "hardhat",
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", " && ".join(cmds)]
        )
    )

    return hardhat_service

# runs npx hardhat run with the given script
def script(plan, script, network="bloctopus", return_keys=None, params=None, extraCmds=None):
    return _hardhat_cmd(plan, "run {0}".format(script), network, params, return_keys, extraCmds)

# runs npx hardhat task
def task(plan, task_name, network="bloctopus", params=None):
    return _hardhat_cmd(plan, task_name, network, params)

# runs npx hardhat test with the given contract
def test(plan, smart_contract=None, network="bloctopus"):
    if smart_contract:
        return _hardhat_cmd(plan, "test {0}".format(smart_contract), network)
    return _hardhat_cmd(plan, "test", network)

def compile(plan):
    return _hardhat_cmd(plan, "compile")

# verify deployed contract with blockscout or other explorers
def verify(plan, contract_address, network="bloctopus", verification_url=None, constructor_args=None, contract_path=None, chain_id=None):
    """
    Verify a deployed contract with Blockscout or other explorers
    
    Args:
        plan: The Kurtosis plan
        contract_address: The address of the deployed contract
        network: The network name configured in hardhat.config.js (default: "bloctopus")
        verification_url: Optional URL of the verification service (e.g., Blockscout)
        constructor_args: Optional constructor arguments used during deployment
                        Can be a list of arguments or a string of formatted arguments
        contract_path: Optional path to the contract if it's in a non-standard location
                     Format: "contracts/MyContract.sol:MyContract"
        chain_id: Optional chain ID for the network (default: derived from environment)
    
    Returns:
        Result of the verification operation
    """
    # Prepare environment variables
    env_vars = {}
    if verification_url:
        env_vars["VERIFICATION_URL"] = verification_url
    if network:
        env_vars["NETWORK"] = network
    if chain_id:
        env_vars["CHAIN_ID"] = str(chain_id)
    
    # Install hardhat-verify plugin if needed
    cmd = "cd {0} && npm install --save-dev @nomicfoundation/hardhat-verify".format(HARDHAT_PROJECT_DIR)
    
    # Execute the config update script with environment variables
    cmd += " && node scripts/update-verification-config.js"
    
    # Build the verify command
    verify_cmd = "verify --force"
    if contract_path:
        verify_cmd += " --contract {0}".format(contract_path)
    
    # Add the contract address
    verify_cmd += " {0}".format(contract_address)
    
    # Add constructor args if provided
    if constructor_args:
        if isinstance(constructor_args, list):
            verify_cmd += " " + " ".join(['"{0}"'.format(arg) for arg in constructor_args])
        else:
            verify_cmd += " {0}".format(constructor_args)
    
    # Execute the verification command
    return _hardhat_cmd(plan, verify_cmd, network, extraCmds=cmd, env_vars=env_vars)

# Configure multiple networks for deployment
def configure_networks(plan, networks):
    """
    Configure multiple networks for deployment
    
    Args:
        plan: The Kurtosis plan
        networks: A dictionary of network configurations, where keys are network names
                 and values are dictionaries with keys: rpc_url, chain_id, private_key, verification_url
    
    Example:
        networks = {
            "ethereum": {
                "rpc_url": "http://localhost:8545",
                "chain_id": 1337,
                "private_key": "0x123...",
                "verification_url": "http://localhost:8050"
            },
            "polygon": {
                "rpc_url": "http://localhost:8546",
                "chain_id": 80001,
                "private_key": "0x456...",
                "verification_url": "http://localhost:8051"
            }
        }
    """
    # Prepare environment variables
    env_vars = {
        "NETWORKS_CONFIG": json.dumps(networks)
    }
    
    # Execute the networks configuration script with environment variables
    cmd = "cd {0} && node scripts/configure-networks.js".format(HARDHAT_PROJECT_DIR)
    
    # Execute the command
    return _hardhat_cmd(plan, "", extraCmds=cmd, env_vars=env_vars)

# Helper function for contract interaction
def interact(plan, contract_address, function_name, network="bloctopus", params=None, return_keys=None):
    """
    Interact with a deployed contract
    
    Args:
        plan: The Kurtosis plan
        contract_address: The address of the deployed contract
        function_name: The name of the function to call
        network: The network to use
        params: Optional parameters to pass to the function
        return_keys: Optional keys to extract from the result
        
    Returns:
        The result of the function call
    """
    # Prepare environment variables
    env_vars = {
        "CONTRACT_ADDRESS": contract_address,
        "FUNCTION_NAME": function_name,
        "FUNCTION_PARAMS": json.dumps(params) if params else "[]",
        "NETWORK": network
    }
    
    # Create and run the contract interaction script
    cmd = "cd {0} && cp scripts/contract-interact.js . && npx hardhat run contract-interact.js --network {1}".format(HARDHAT_PROJECT_DIR, network)
    
    # Execute the script with environment variables
    extract_keys_dict = {"result": "result"} if return_keys is None else return_keys
    return _hardhat_cmd(plan, "", extraCmds=cmd, env_vars=env_vars, extract_keys=extract_keys_dict)

# Gas optimization utility
def optimize_gas(plan, contract_path=None):
    """
    Run gas optimization tools on contracts
    
    Args:
        plan: The Kurtosis plan
        contract_path: Optional path to specific contract to optimize
        
    Returns:
        Optimization report
    """
    # Prepare environment variables
    env_vars = {}
    if contract_path:
        env_vars["CONTRACT_PATH"] = contract_path
    
    # Install hardhat-gas-reporter
    cmd = "cd {0} && npm install --save-dev hardhat-gas-reporter".format(HARDHAT_PROJECT_DIR)
    
    # Execute the gas reporter configuration script
    cmd += " && node scripts/enable-gas-reporter.js"
    
    # Run the test command to generate gas reports
    test_cmd = "test"
    if contract_path:
        test_cmd += " " + contract_path
    
    # Execute the test command to generate gas reports
    return _hardhat_cmd(plan, test_cmd, extraCmds=cmd + " && cat gas-report.txt", env_vars=env_vars)

# Deployment tracking and management
def track_deployment(plan, contract_name, contract_address, network, constructor_args=None, contract_path=None):
    """
    Track a deployed contract for future reference and verification
    
    Args:
        plan: The Kurtosis plan
        contract_name: The name of the contract
        contract_address: The address of the deployed contract
        network: The network where the contract is deployed
        constructor_args: Optional constructor arguments used for deployment
        contract_path: Optional path to the contract
        
    Returns:
        Result of the tracking operation
    """
    # Prepare environment variables
    env_vars = {
        "CONTRACT_NAME": contract_name,
        "CONTRACT_ADDRESS": contract_address,
        "NETWORK": network,
        "CONSTRUCTOR_ARGS": json.dumps(constructor_args) if constructor_args else "[]",
        "CONTRACT_PATH": contract_path if contract_path else ""
    }
    
    # Create deployments directory if it doesn't exist
    cmd = "cd {0} && mkdir -p deployments/{1} && node scripts/track-deployment.js".format(HARDHAT_PROJECT_DIR, network)
    
    # Execute the tracking command
    return _hardhat_cmd(plan, "", extraCmds=cmd, env_vars=env_vars)

# Test verification on Bloctopus network
def test_bloctopus_verification(plan):
    """
    Test contract verification on the Bloctopus network
    
    Args:
        plan: The Kurtosis plan
        
    Returns:
        Result of the verification test
    """
    # Bloctopus network configuration
    bloctopus_network = {
        "bloctopus": {
            "rpc_url": "https://eb9ad9faac334860ba32433d00ea3a19-rpc.network.bloctopus.io",
            "chain_id": 6129906,
            "private_key": "0xd29644a2fbc8649ef6831514c241af9ca09c16156ac159dc7cb9cd64466b2569",
            "verification_url": "https://eb9ad9faac334860ba32433d00ea3a19-blockscout.network.bloctopus.io"
        }
    }
    
    # Create a Hardhat project with the Bloctopus network configuration
    hardhat_service = run(
        plan=plan,
        project_url="github.com/LZeroAnalytics/hardhat-package",
        env_vars={
            "RPC_URL": "https://eb9ad9faac334860ba32433d00ea3a19-rpc.network.bloctopus.io",
            "CHAIN_ID": "6129906",
            "PRIVATE_KEY": "0xd29644a2fbc8649ef6831514c241af9ca09c16156ac159dc7cb9cd64466b2569"
        }
    )
    
    # Configure the networks
    configure_networks(plan, bloctopus_network)
    
    # Create a simple test contract
    simple_contract = """
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
    """
    
    # Create the contract file
    cmd = "cd {0} && mkdir -p contracts && cat > contracts/SimpleStorage.sol << 'EOL'\n{1}\nEOL\n".format(
        HARDHAT_PROJECT_DIR,
        simple_contract
    )
    
    # Create a deployment script for testing
    deploy_script = """
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
    
        // Return the contract address and constructor args for verification
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
    """
    
    # Create the deploy script
    cmd += " && mkdir -p scripts && cat > scripts/deploy-test.js << 'EOL'\n{0}\nEOL\n".format(deploy_script)
    
    # Create hardhat.config.js
    hardhat_config = """
    require("@nomicfoundation/hardhat-toolbox");
    
    module.exports = {
      solidity: "0.8.18",
      networks: {
        bloctopus: {
          url: process.env.RPC_URL || "https://eb9ad9faac334860ba32433d00ea3a19-rpc.network.bloctopus.io",
          chainId: parseInt(process.env.CHAIN_ID || "6129906"),
          accounts: [process.env.PRIVATE_KEY || "0xd29644a2fbc8649ef6831514c241af9ca09c16156ac159dc7cb9cd64466b2569"]
        }
      }
    };
    """
    
    cmd += " && cat > hardhat.config.js << 'EOL'\n{0}\nEOL\n".format(hardhat_config)
    
    # Install dependencies
    cmd += " && npm install --save-dev @nomicfoundation/hardhat-toolbox"
    
    # Compile and deploy the contract
    cmd += " && npx hardhat compile"
    cmd += " && npx hardhat run scripts/deploy-test.js --network bloctopus"
    
    # Execute the deployment
    deployment_result = plan.exec(
        service_name="hardhat",
        recipe=ExecRecipe(
            command=["/bin/sh", "-c", cmd],
            extract={
                "contractAddress": "fromjson | .contractAddress",
                "constructorArgs": "fromjson | .constructorArgs"
            }
        )
    )
    
    # Verify the contract
    verification_result = verify(
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

# destroys the hardhat container; running this is optional
def cleanup(plan):
    plan.remove_service(HARDHAT_SERVICE_NAME)


# Execute Hardhat command
def _hardhat_cmd(plan, command_str, network=None, params=None, extract_keys=None, extraCmds=None):
    cmd = "cd {0} && ".format(HARDHAT_PROJECT_DIR)
    if params:
        cmd += " ".join(["export {0}={1} &&".format(k, v) for k, v in params.items()]) + " "
    cmd += "npx hardhat {0}".format(command_str)
    if network: cmd += " --network {0}".format(network)
    if extraCmds: cmd += extraCmds
    args = {"command": ["/bin/sh", "-c", cmd]}
    
    # Handle extraction - either single key (backwards compatibility) or multiple keys
    extractions = {}
    # Add multiple extract_keys if provided
    if extract_keys:
        for key, value in extract_keys.items():
            extractions[key] = "fromjson | .{0}".format(value)
        args["extract"] = extractions
    
    return plan.exec(service_name=HARDHAT_SERVICE_NAME, recipe=ExecRecipe(**args))
