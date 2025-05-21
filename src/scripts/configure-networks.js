/**
 * Network Configuration Script
 * 
 * This script configures multiple networks in hardhat.config.js for deployment and verification.
 * It follows the pattern used in layerzero-oapp for multi-chain deployments.
 * 
 * Environment variables:
 * - NETWORKS_CONFIG: JSON string containing network configurations with the following structure:
 *   {
 *     "networkName": {
 *       "rpc_url": "http://example.com:8545",
 *       "chain_id": 1337,
 *       "private_key": "0x123...",
 *       "verification_url": "http://blockscout.example.com"
 *     },
 *     ...
 *   }
 */

const fs = require('fs');
const path = require('path');

let networks;
try {
  networks = JSON.parse(process.env.NETWORKS_CONFIG);
  if (!networks || typeof networks !== 'object' || Object.keys(networks).length === 0) {
    throw new Error('Invalid network configuration');
  }
} catch (error) {
  console.error('Error parsing NETWORKS_CONFIG environment variable:', error.message);
  process.exit(1);
}

const configPath = path.join(process.cwd(), 'hardhat.config.js');
let config = {};

if (fs.existsSync(configPath)) {
  try {
    fs.copyFileSync(configPath, configPath + '.backup');
    
    const configContent = fs.readFileSync(configPath, 'utf8');
    const moduleExportsMatch = configContent.match(/module\.exports\s*=\s*(\{[\s\S]*\})/);
    if (moduleExportsMatch) {
      const configObject = eval('(' + moduleExportsMatch[1] + ')');
      config = configObject;
    }
  } catch (error) {
    console.error('Error reading existing hardhat.config.js:', error);
  }
}

config.networks = config.networks || {};
config.etherscan = config.etherscan || {};
config.etherscan.apiKey = config.etherscan.apiKey || {};
config.etherscan.customChains = config.etherscan.customChains || [];

let needsVerification = false;

Object.keys(networks).forEach(networkName => {
  const network = networks[networkName];
  
  if (!network.rpc_url || !network.chain_id) {
    console.warn(`Warning: Network ${networkName} is missing required parameters (rpc_url or chain_id)`);
  }
  
  config.networks[networkName] = {
    url: network.rpc_url,
    chainId: network.chain_id,
    accounts: network.private_key ? [network.private_key] : []
  };
  
  if (network.verification_url) {
    needsVerification = true;
    
    config.etherscan.apiKey[networkName] = 'blockscout';
    
    const existingChainIndex = config.etherscan.customChains.findIndex(
      chain => chain.network === networkName
    );
    
    const customChain = {
      network: networkName,
      chainId: network.chain_id,
      urls: {
        apiURL: `${network.verification_url}/api`,
        browserURL: network.verification_url
      }
    };
    
    if (existingChainIndex >= 0) {
      config.etherscan.customChains[existingChainIndex] = customChain;
    } else {
      config.etherscan.customChains.push(customChain);
    }
  }
});

let updatedContent;
if (fs.existsSync(configPath)) {
  const originalContent = fs.readFileSync(configPath, 'utf8');
  
  if (needsVerification && !originalContent.includes('@nomicfoundation/hardhat-verify')) {
    updatedContent = `require("@nomicfoundation/hardhat-verify");\n\n${originalContent}`;
    updatedContent = updatedContent.replace(/module\.exports\s*=\s*\{[\s\S]*\}/, `module.exports = ${JSON.stringify(config, null, 2)}`);
  } else {
    updatedContent = originalContent.replace(/module\.exports\s*=\s*\{[\s\S]*\}/, `module.exports = ${JSON.stringify(config, null, 2)}`);
  }
} else {
  const requireStatements = needsVerification ? 'require("@nomicfoundation/hardhat-verify");\n\n' : '';
  updatedContent = `${requireStatements}module.exports = ${JSON.stringify(config, null, 2)};`;
}

fs.writeFileSync(configPath, updatedContent);
console.log('Hardhat config updated with multiple networks');
