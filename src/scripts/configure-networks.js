const fs = require('fs');
const path = require('path');

const configPath = path.join(process.cwd(), 'hardhat.config.js');
let config = {};

const networks = JSON.parse(process.env.NETWORKS_CONFIG);

if (fs.existsSync(configPath)) {
  try {
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

Object.keys(networks).forEach(networkName => {
  const network = networks[networkName];
  
  config.networks[networkName] = {
    url: network.rpc_url,
    chainId: network.chain_id,
    accounts: network.private_key ? [network.private_key] : []
  };
  
  if (network.verification_url) {
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
  
  const needsVerification = Object.values(networks).some(network => network.verification_url);
  
  if (needsVerification && !originalContent.includes('@nomicfoundation/hardhat-verify')) {
    updatedContent = `require("@nomicfoundation/hardhat-verify");\n\n${originalContent}`;
    updatedContent = updatedContent.replace(/module\.exports\s*=\s*\{[\s\S]*\}/, `module.exports = ${JSON.stringify(config, null, 2)}`);
  } else {
    updatedContent = originalContent.replace(/module\.exports\s*=\s*\{[\s\S]*\}/, `module.exports = ${JSON.stringify(config, null, 2)}`);
  }
} else {
  const needsVerification = Object.values(networks).some(network => network.verification_url);
  const requireStatements = needsVerification ? 'require("@nomicfoundation/hardhat-verify");\n\n' : '';
  updatedContent = `${requireStatements}module.exports = ${JSON.stringify(config, null, 2)};`;
}

fs.writeFileSync(configPath, updatedContent);
console.log('Hardhat config updated with multiple networks');
