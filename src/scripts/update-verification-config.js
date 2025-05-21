/**
 * Verification Configuration Script
 * 
 * This script updates the hardhat.config.js file to include verification settings
 * for Blockscout or other explorers. It follows the pattern used in layerzero-oapp.
 * 
 * Environment variables:
 * - VERIFICATION_URL: URL of the verification service (required)
 * - NETWORK: Network name (default: 'bloctopus')
 * - CHAIN_ID: Chain ID (default: 1337)
 * - RPC_URL: RPC URL (default: 'http://localhost:8545')
 * - PRIVATE_KEY: Private key for deployment (optional)
 */

const fs = require('fs');
const path = require('path');

const verificationUrl = process.env.VERIFICATION_URL;
const network = process.env.NETWORK || 'bloctopus';
const chainId = process.env.CHAIN_ID ? parseInt(process.env.CHAIN_ID) : 1337;
const rpcUrl = process.env.RPC_URL || 'http://localhost:8545';

if (!verificationUrl) {
  console.error('Error: VERIFICATION_URL environment variable is required');
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

config.networks[network] = config.networks[network] || {
  url: rpcUrl,
  chainId: chainId,
  accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : []
};

config.etherscan.apiKey[network] = 'blockscout';

const existingChainIndex = config.etherscan.customChains.findIndex(
  chain => chain.network === network
);

const customChain = {
  network: network,
  chainId: chainId,
  urls: {
    apiURL: `${verificationUrl}/api`,
    browserURL: verificationUrl
  }
};

if (existingChainIndex >= 0) {
  config.etherscan.customChains[existingChainIndex] = customChain;
} else {
  config.etherscan.customChains.push(customChain);
}

let updatedContent;
if (fs.existsSync(configPath)) {
  const originalContent = fs.readFileSync(configPath, 'utf8');
  
  if (!originalContent.includes('@nomicfoundation/hardhat-verify')) {
    updatedContent = `require("@nomicfoundation/hardhat-verify");\n\n${originalContent}`;
    updatedContent = updatedContent.replace(/module\.exports\s*=\s*\{[\s\S]*\}/, `module.exports = ${JSON.stringify(config, null, 2)}`);
  } else {
    updatedContent = originalContent.replace(/module\.exports\s*=\s*\{[\s\S]*\}/, `module.exports = ${JSON.stringify(config, null, 2)}`);
  }
} else {
  updatedContent = `require("@nomicfoundation/hardhat-verify");\n\nmodule.exports = ${JSON.stringify(config, null, 2)};`;
}

fs.writeFileSync(configPath, updatedContent);
console.log('Hardhat config updated successfully for verification');
