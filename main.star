NODE_ALPINE = "node:20.14.0-alpine"
HARDHAT_PROJECT_DIR = "/tmp/hardhat/"
HARDHAT_SERVICE_NAME = "hardhat"
HARDHAT_SCRIPTS_UTILS = "/tmp/hardhat-scripts-utils"

def run(plan, project_url=None, env_vars={}, more_files={}, image=None):
    files = {}
    if project_url:
        hardhat_project = plan.upload_files(src=project_url)
        files = {HARDHAT_PROJECT_DIR: hardhat_project}

    for filepath, file_artifact in more_files.items():
        files[filepath] = file_artifact
    # Mount utility scripts in separate directory to avoid conflicts with project
    scripts_artifact = plan.upload_files(src="./src/scripts")
    files[HARDHAT_SCRIPTS_UTILS] = scripts_artifact

    hardhat_service = plan.add_service(
        name = "hardhat",
        config = ServiceConfig(
            image = image if image else NODE_ALPINE,
            files = files,
            env_vars = env_vars,
            entrypoint = ["tail", "-f", "/dev/null"]
        )
    )

    # Skip install for prebuilt images
    if (project_url) and (image == None):
        plan.exec(
            service_name = "hardhat",
            recipe = ExecRecipe(
                command = ["/bin/sh", "-c", "npm install -g pnpm && cd {0} && pnpm install --shamefully-hoist".format(HARDHAT_PROJECT_DIR)]
            )
        )

    return hardhat_service

def script(plan, script, network="bloctopus", return_keys=None, params=None, extraCmds=None):
    return _hardhat_cmd(plan, "run {0}".format(script), network, params, return_keys, extraCmds)

def task(plan, task_name, network="bloctopus", params=None):
    return _hardhat_cmd(plan, task_name, network, params)

def test(plan, smart_contract=None, network="bloctopus"):
    cmd = "test {0}".format(smart_contract) if smart_contract else "test"
    result = _hardhat_cmd(plan, cmd, network)
    return result.get("output", result)

def compile(plan):
    return _hardhat_cmd(plan, "compile")

def verify(plan, contract_address, network="bloctopus", verification_url=None, constructor_args=None, contract_path=None, chain_id=None):
    env_vars = {}
    if verification_url:
        env_vars["VERIFICATION_URL"] = verification_url
    if network:
        env_vars["NETWORK"] = network
    if chain_id:
        env_vars["CHAIN_ID"] = str(chain_id)
    
    verify_cmd = "verify --force"
    if contract_path:
        verify_cmd += " --contract {0}".format(contract_path)
    verify_cmd += " {0}".format(contract_address)
    
    if constructor_args:
        verify_cmd += " " + " ".join(['"{0}"'.format(arg) for arg in constructor_args])
    
    result = _hardhat_cmd(
        plan, 
        verify_cmd, 
        network=network, 
        params=env_vars,
        prefix_cmds="npm install --save-dev @nomicfoundation/hardhat-verify && node {0}/update-verification-config.js".format(HARDHAT_SCRIPTS_UTILS)
    )
    
    explorer_url = ""
    if verification_url and contract_address:
        explorer_url = "{0}/address/{1}".format(verification_url, contract_address)
    
    return {
        "explorer_contract_url": explorer_url,
        "result": result
    }

def configure_networks(plan, networks):
    env_vars = {
        "NETWORKS_CONFIG": json.encode(networks)
    }
    
    result = _hardhat_cmd(
        plan, 
        "", 
        params=env_vars,
        custom_cmd="node {0}/configure-networks.js".format(HARDHAT_SCRIPTS_UTILS)
    )
    
    return {
        "networks": networks,
        "networks_count": len(networks),
        "network_names": list(networks.keys()),
        "output": result
    }

def interact(plan, contract_address, function_name, network="bloctopus", params=None, return_keys=None):
    env_vars = {
        "CONTRACT_ADDRESS": contract_address,
        "FUNCTION_NAME": function_name,
        "FUNCTION_PARAMS": json.encode(params) if params else "[]",
        "NETWORK": network
    }
    
    extract_keys_dict = {"result": "result", "tx_hash": "txHash", "gas_used": "gasUsed"} if return_keys else return_keys

    
    result = _hardhat_cmd(
        plan, 
        "run {0}/contract-interact.js".format(HARDHAT_SCRIPTS_UTILS), 
        network=network, 
        params=env_vars, 
        extract_keys=extract_keys_dict
    )
    
    return {
        "transaction_hash": result["extract.tx_hash"],
        "gas_used": result["extract.gas_used"], 
        "return_value": result["extract.result"],
        "kurtosis_result": result
    }

def optimize_gas(plan, contract_path=None):
    env_vars = {}
    if contract_path:
        env_vars["CONTRACT_PATH"] = contract_path
    
    test_cmd = "test"
    if contract_path:
        test_cmd += " " + contract_path
    
    result = _hardhat_cmd(
        plan, 
        test_cmd,
        params=env_vars,
        prefix_cmds="npm install --save-dev hardhat-gas-reporter && node {0}/enable-gas-reporter.js".format(HARDHAT_SCRIPTS_UTILS),
        post_cmds="cat gas-report.txt"
    )
    
    return {
        "contract_path": contract_path,
        "gas_report": result.get("output", ""),
        "output": result
    }

def cleanup(plan):
    plan.remove_service(HARDHAT_SERVICE_NAME)

def _hardhat_cmd(plan, command_str, network=None, params=None, extract_keys=None, extraCmds=None, prefix_cmds=None, custom_cmd=None):
    cmd = "cd {0}".format(HARDHAT_PROJECT_DIR)
    
    # Export environment variables
    if params:
        cmd += " && " + " ".join(["export {0}='{1}'".format(k, v) for k, v in params.items()])
    
    # Add prefix commands (setup, installs, etc.)
    if prefix_cmds:
        cmd += " && {0}".format(prefix_cmds)
    
    # Main command - either custom or hardhat
    if custom_cmd:
        cmd += " && {0}".format(custom_cmd)
    elif command_str:  # Only add hardhat command if command_str is not empty
        cmd += " && npx --silent hardhat"
        # Parse command to insert --network in the right place
        if network:
            # Split command to get task name and rest
            parts = command_str.split(' ', 1)
            task_name = parts[0]  # e.g., "run"
            rest = parts[1] if len(parts) > 1 else ""  # e.g., "scripts/..."
            
            cmd += " {0} --network {1}".format(task_name, network)
            if rest:
                cmd += " {0}".format(rest)
        else:
            cmd += " {0}".format(command_str)
    
    # Legacy extraCmds support (for backward compatibility)
    if extraCmds:
        cmd += extraCmds
    
    args = {"command": ["/bin/sh", "-c", cmd]}
    
    if extract_keys:
        extractions = {}
        for key, value in extract_keys.items():
            extractions[key] = "fromjson | .{0}".format(value)
        args["extract"] = extractions
    
    return plan.exec(service_name=HARDHAT_SERVICE_NAME, recipe=ExecRecipe(**args)) 