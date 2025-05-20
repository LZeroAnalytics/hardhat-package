# HardHat has problems with node 20 so we use an older version of node
NODE_ALPINE = "node:20.14.0-alpine"
HARDHAT_PROJECT_DIR = "/tmp/hardhat/"
HARDHAT_SERVICE_NAME = "hardhat"

# Creates a Node.js container with Hardhat project either from GitHub or local
def run(plan, project_url, env_vars={}, more_files={}):
    hardhat_project = plan.upload_files(src=project_url)

    files = {HARDHAT_PROJECT_DIR: hardhat_project}
    for filepath, file_artifact in more_files.items():
        files[filepath] = file_artifact

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
    plan.exec(
        service_name = "hardhat",
        recipe = ExecRecipe(
            command = ["/bin/sh", "-c", "npm install -g pnpm && cd {0} && pnpm install --shamefully-hoist".format(HARDHAT_PROJECT_DIR)]
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
def verify(plan, contract_address, network="bloctopus", verification_url=None, constructor_args=None, contract_path=None):
    # Prepare environment variables
    env_vars = {}
    if verification_url:
        env_vars["VERIFICATION_URL"] = verification_url
    if network:
        env_vars["NETWORK"] = network
    
    # Install hardhat-verify plugin if needed
    cmd = "cd {0} && npm install --save-dev @nomicfoundation/hardhat-verify".format(HARDHAT_PROJECT_DIR)
    
    # Copy the verification config script to the container
    files_to_mount = {
        "./src/scripts/update-verification-config.js": "{0}update-verification-config.js".format(HARDHAT_PROJECT_DIR)
    }
    
    # Execute the config update script with environment variables
    cmd += " && node update-verification-config.js"
    
    # Build the verify command
    verify_cmd = "verify"
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
    return _hardhat_cmd(plan, verify_cmd, network, extraCmds=cmd, env_vars=env_vars, more_files=files_to_mount)

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
    
    # Copy the networks configuration script to the container
    files_to_mount = {
        "./src/scripts/configure-networks.js": "{0}configure-networks.js".format(HARDHAT_PROJECT_DIR)
    }
    
    # Execute the networks configuration script with environment variables
    cmd = "cd {0} && node configure-networks.js".format(HARDHAT_PROJECT_DIR)
    
    # Execute the command
    return _hardhat_cmd(plan, "", extraCmds=cmd, env_vars=env_vars, more_files=files_to_mount)

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
    
    # Copy the contract interaction script to the container
    files_to_mount = {
        "./src/scripts/contract-interact.js": "{0}contract-interact.js".format(HARDHAT_PROJECT_DIR)
    }
    
    # Execute the script with environment variables
    extract_keys_dict = {"result": "result"} if return_keys is None else return_keys
    return _hardhat_cmd(plan, "run contract-interact.js", network, extract_keys=extract_keys_dict, env_vars=env_vars, more_files=files_to_mount)

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
    
    # Copy the gas reporter script to the container
    files_to_mount = {
        "./src/scripts/enable-gas-reporter.js": "{0}enable-gas-reporter.js".format(HARDHAT_PROJECT_DIR)
    }
    
    # Execute the gas reporter configuration script
    cmd += " && node enable-gas-reporter.js"
    
    # Run the test command to generate gas reports
    test_cmd = "test"
    if contract_path:
        test_cmd += " " + contract_path
    
    # Execute the test command to generate gas reports
    return _hardhat_cmd(plan, test_cmd, extraCmds=cmd + " && cat gas-report.txt", env_vars=env_vars, more_files=files_to_mount)

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
    
    # Copy the deployment tracking script to the container
    files_to_mount = {
        "./src/scripts/track-deployment.js": "{0}track-deployment.js".format(HARDHAT_PROJECT_DIR)
    }
    
    # Create deployments directory if it doesn't exist
    cmd = "cd {0} && mkdir -p deployments/{1} && node track-deployment.js".format(HARDHAT_PROJECT_DIR, network)
    
    # Execute the tracking command
    return _hardhat_cmd(plan, "", extraCmds=cmd, env_vars=env_vars, more_files=files_to_mount)

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
