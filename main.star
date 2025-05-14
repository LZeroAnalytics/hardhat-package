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
            command = ["/bin/sh", "-c", "cd {0} && rm -rf node_modules package-lock.json && npm cache clean --force && npm install".format(HARDHAT_PROJECT_DIR)]
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