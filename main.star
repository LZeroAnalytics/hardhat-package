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
    # Prepare command options
    cmd = ""
    if verification_url:
        # Install hardhat-verify plugin if needed
        cmd += "cd {0} && npm install --save-dev @nomicfoundation/hardhat-verify && ".format(HARDHAT_PROJECT_DIR)
        
        # Create a script to modify or create hardhat.config.js
        cmd += """cat > {0}update-config.js << 'EOL'
const fs = require('fs');
const path = require('path');

// Path to hardhat.config.js
const configPath = path.join(process.cwd(), 'hardhat.config.js');
let config = {};

// Check if hardhat.config.js exists
if (fs.existsSync(configPath)) {
  try {
    // Back up the existing config
    fs.copyFileSync(configPath, configPath + '.backup');
    
    // Read and evaluate the existing config file
    const configContent = fs.readFileSync(configPath, 'utf8');
    // Extract the module.exports object
    const moduleExportsMatch = configContent.match(/module\.exports\\s*=\\s*(\\{{[\\s\\S]*\\}})/);
    if (moduleExportsMatch) {
      // Parse the module.exports object
      const configObject = eval('(' + moduleExportsMatch[1] + ')');
      config = configObject;
    }
  } catch (error) {
    console.error('Error reading existing hardhat.config.js:', error);
  }
}

// Ensure required structures exist
config.networks = config.networks || {};
config.etherscan = config.etherscan || {};
config.etherscan.apiKey = config.etherscan.apiKey || {};
config.etherscan.customChains = config.etherscan.customChains || [];

// Add or update network configuration using environment variables
config.networks['{2}'] = config.networks['{2}'] || {{
  url: process.env.RPC_URL || 'http://localhost:8545',
  chainId: process.env.CHAIN_ID ? parseInt(process.env.CHAIN_ID) : 1337,
  accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : []
}};

// Add or update etherscan configuration
config.etherscan.apiKey['{2}'] = 'blockscout';

// Check if verification URL exists in customChains
const existingChainIndex = config.etherscan.customChains.findIndex(
  chain => chain.network === '{2}'
);

// Add or update custom chain configuration
const customChain = {{
  network: '{2}',
  chainId: process.env.CHAIN_ID ? parseInt(process.env.CHAIN_ID) : 1337,
  urls: {{
    apiURL: '{1}/api',
    browserURL: '{1}'
  }}
}};

if (existingChainIndex >= 0) {{
  config.etherscan.customChains[existingChainIndex] = customChain;
}} else {{
  config.etherscan.customChains.push(customChain);
}}

// Ensure hardhat-verify plugin is included
let updatedContent;
if (fs.existsSync(configPath)) {{
  // Read the original file
  const originalContent = fs.readFileSync(configPath, 'utf8');
  // Check if hardhat-verify plugin is already required
  if (!originalContent.includes('@nomicfoundation/hardhat-verify')) {{
    // Add require statement at the beginning
    updatedContent = `require("@nomicfoundation/hardhat-verify");\\n\\n${originalContent}`;
    // If module.exports exists, replace it with our updated config
    updatedContent = updatedContent.replace(/module\.exports\\s*=\\s*\\{{[\\s\\S]*\\}}/, `module.exports = ${JSON.stringify(config, null, 2)}`);
  }} else {{
    // Just update the module.exports part
    updatedContent = originalContent.replace(/module\.exports\\s*=\\s*\\{{[\\s\\S]*\\}}/, `module.exports = ${JSON.stringify(config, null, 2)}`);
  }}
}} else {{
  // Create new config file from scratch
  updatedContent = `require("@nomicfoundation/hardhat-verify");\\n\\nmodule.exports = ${JSON.stringify(config, null, 2)};`;
}}

// Write the updated config
fs.writeFileSync(configPath, updatedContent);
console.log('Hardhat config updated successfully');
EOL
""".format(HARDHAT_PROJECT_DIR, verification_url, network)
        
        # Execute the config update script
        cmd += "cd {0} && node update-config.js && ".format(HARDHAT_PROJECT_DIR)
    
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
    return _hardhat_cmd(plan, verify_cmd, network, extraCmds=None)

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
    cmd = "cd {0} && ".format(HARDHAT_PROJECT_DIR)
    
    # Create a script to update hardhat.config.js with multiple networks
    cmd += """cat > {0}configure-networks.js << 'EOL'
const fs = require('fs');
const path = require('path');

// Path to hardhat.config.js
const configPath = path.join(process.cwd(), 'hardhat.config.js');
let config = {};

// Networks to configure
const networks = {1};

// Check if hardhat.config.js exists
if (fs.existsSync(configPath)) {{
  try {{
    // Read and evaluate the existing config file
    const configContent = fs.readFileSync(configPath, 'utf8');
    // Extract the module.exports object
    const moduleExportsMatch = configContent.match(/module\.exports\\s*=\\s*(\\{{[\\s\\S]*\\}})/);
    if (moduleExportsMatch) {{
      // Parse the module.exports object
      const configObject = eval('(' + moduleExportsMatch[1] + ')');
      config = configObject;
    }}
  }} catch (error) {{
    console.error('Error reading existing hardhat.config.js:', error);
  }}
}}

// Ensure required structures exist
config.networks = config.networks || {{}};
config.etherscan = config.etherscan || {{}};
config.etherscan.apiKey = config.etherscan.apiKey || {{}};
config.etherscan.customChains = config.etherscan.customChains || [];

// Configure each network
Object.keys(networks).forEach(networkName => {{
  const network = networks[networkName];
  
  // Add network configuration
  config.networks[networkName] = {{
    url: network.rpc_url,
    chainId: network.chain_id,
    accounts: network.private_key ? [network.private_key] : []
  }};
  
  // Add verification configuration if provided
  if (network.verification_url) {{
    config.etherscan.apiKey[networkName] = 'blockscout';
    
    // Check if verification URL exists in customChains
    const existingChainIndex = config.etherscan.customChains.findIndex(
      chain => chain.network === networkName
    );
    
    // Add or update custom chain configuration
    const customChain = {{
      network: networkName,
      chainId: network.chain_id,
      urls: {{
        apiURL: `${{network.verification_url}}/api`,
        browserURL: network.verification_url
      }}
    }};
    
    if (existingChainIndex >= 0) {{
      config.etherscan.customChains[existingChainIndex] = customChain;
    }} else {{
      config.etherscan.customChains.push(customChain);
    }}
  }}
}});

// Ensure hardhat-verify plugin is included if needed
let updatedContent;
if (fs.existsSync(configPath)) {{
  // Read the original file
  const originalContent = fs.readFileSync(configPath, 'utf8');
  
  // Check if we need verification and if hardhat-verify plugin is already required
  const needsVerification = Object.values(networks).some(network => network.verification_url);
  
  if (needsVerification && !originalContent.includes('@nomicfoundation/hardhat-verify')) {{
    // Add require statement at the beginning
    updatedContent = `require("@nomicfoundation/hardhat-verify");\\n\\n${originalContent}`;
    // If module.exports exists, replace it with our updated config
    updatedContent = updatedContent.replace(/module\.exports\\s*=\\s*\\{{[\\s\\S]*\\}}/, `module.exports = ${JSON.stringify(config, null, 2)}`);
  }} else {{
    // Just update the module.exports part
    updatedContent = originalContent.replace(/module\.exports\\s*=\\s*\\{{[\\s\\S]*\\}}/, `module.exports = ${JSON.stringify(config, null, 2)}`);
  }}
}} else {{
  // Create new config file from scratch
  const needsVerification = Object.values(networks).some(network => network.verification_url);
  const requireStatements = needsVerification ? 'require("@nomicfoundation/hardhat-verify");\\n\\n' : '';
  updatedContent = `${requireStatements}module.exports = ${JSON.stringify(config, null, 2)};`;
}}

// Write the updated config
fs.writeFileSync(configPath, updatedContent);
console.log('Hardhat config updated with multiple networks');
EOL
""".format(HARDHAT_PROJECT_DIR, json.dumps(networks))
    
    # Execute the networks configuration script
    return _hardhat_cmd(plan, "", extraCmds=" && node configure-networks.js")

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
    # Create a temporary script to interact with the contract
    script_content = """
const hre = require("hardhat");

async function main() {
  const contract = await hre.ethers.getContractAt("Contract", "${CONTRACT_ADDRESS}");
  const result = await contract.${FUNCTION_NAME}(${PARAMS});
  console.log(JSON.stringify({ result: result.toString() }));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
"""
    
    # Replace placeholders
    script_content = script_content.replace("${CONTRACT_ADDRESS}", contract_address)
    script_content = script_content.replace("${FUNCTION_NAME}", function_name)
    script_content = script_content.replace("${PARAMS}", params if params else "")
    
    # Write script to file
    cmd = "cd {0} && cat > interact.js << 'EOL'\n{1}\nEOL\n".format(HARDHAT_PROJECT_DIR, script_content)
    
    # Execute the script
    extract_keys_dict = {"result": "result"} if return_keys is None else return_keys
    return _hardhat_cmd(plan, "run interact.js", network, extract_keys=extract_keys_dict, extraCmds=" && rm interact.js")

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
    cmd = "cd {0} && npm install --save-dev hardhat-gas-reporter && ".format(HARDHAT_PROJECT_DIR)
    
    # Create a script to update hardhat.config.js with gas reporter
    cmd += """cat > {0}enable-gas-reporter.js << 'EOL'
const fs = require('fs');
const path = require('path');

// Path to hardhat.config.js
const configPath = path.join(process.cwd(), 'hardhat.config.js');
let config = {};

// Check if hardhat.config.js exists
if (fs.existsSync(configPath)) {
  try {
    // Read and evaluate the existing config file
    const configContent = fs.readFileSync(configPath, 'utf8');
    // Extract the module.exports object
    const moduleExportsMatch = configContent.match(/module\.exports\\s*=\\s*(\\{[\\s\\S]*\\})/);
    if (moduleExportsMatch) {
      // Parse the module.exports object
      const configObject = eval('(' + moduleExportsMatch[1] + ')');
      config = configObject;
    }
  } catch (error) {
    console.error('Error reading existing hardhat.config.js:', error);
  }
}

// Add gas reporter configuration
config.gasReporter = {
  enabled: true,
  outputFile: 'gas-report.txt',
  noColors: true,
  excludeContracts: [],
  src: './contracts'
};

// Ensure hardhat-gas-reporter plugin is included
let updatedContent;
if (fs.existsSync(configPath)) {
  // Read the original file
  const originalContent = fs.readFileSync(configPath, 'utf8');
  // Check if hardhat-gas-reporter plugin is already required
  if (!originalContent.includes('hardhat-gas-reporter')) {
    // Add require statement at the beginning
    updatedContent = `require("hardhat-gas-reporter");\\n\\n${originalContent}`;
    // If module.exports exists, replace it with our updated config
    updatedContent = updatedContent.replace(/module\.exports\\s*=\\s*\\{[\\s\\S]*\\}/, `module.exports = ${JSON.stringify(config, null, 2)}`);
  } else {
    // Just update the module.exports part
    updatedContent = originalContent.replace(/module\.exports\\s*=\\s*\\{[\\s\\S]*\\}/, `module.exports = ${JSON.stringify(config, null, 2)}`);
  }
} else {
  // Create new config file from scratch
  updatedContent = `require("hardhat-gas-reporter");\\n\\nmodule.exports = ${JSON.stringify(config, null, 2)};`;
}

// Write the updated config
fs.writeFileSync(configPath, updatedContent);
console.log('Gas reporter enabled');
EOL
""".format(HARDHAT_PROJECT_DIR)
    
    # Execute the gas reporter configuration script
    cmd += "node enable-gas-reporter.js && "
    
    # Run the test command to generate gas reports
    test_cmd = "test"
    if contract_path:
        test_cmd += " " + contract_path
    
    # Execute the test command to generate gas reports
    return _hardhat_cmd(plan, test_cmd, extraCmds=" && cat gas-report.txt")

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
    # Create a deployments directory if it doesn't exist
    cmd = "cd {0} && mkdir -p deployments/{1} && ".format(HARDHAT_PROJECT_DIR, network)
    
    # Create deployment info file
    deployment_info = {
        "contractName": contract_name,
        "address": contract_address,
        "network": network,
        "deploymentTime": "$(date -u +\"%Y-%m-%dT%H:%M:%SZ\")",
        "constructorArgs": constructor_args if constructor_args else [],
        "contractPath": contract_path if contract_path else ""
    }
    
    # Write deployment info to file
    cmd += "cat > deployments/{1}/{2}.json << 'EOL'\n{0}\nEOL\n".format(
        json.dumps(deployment_info, indent=2).replace('"$(date -u +"%Y-%m-%dT%H:%M:%SZ")"', '$(date -u +"%Y-%m-%dT%H:%M:%SZ")'),
        network,
        contract_name
    )
    
    # Execute the tracking command
    return _hardhat_cmd(plan, "", extraCmds=cmd)

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
