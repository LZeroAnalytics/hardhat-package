/**
 * Verification Configuration Script
 * 
f * This script updates the hardhat.config.js/ts file to include verification settings
 * for Blockscout or other explorers. It supports both JS and TS projects.
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

// Check for both .js and .ts config files
const jsConfigPath = path.join(process.cwd(), 'hardhat.config.js');
const tsConfigPath = path.join(process.cwd(), 'hardhat.config.ts');
let configPath = null;
let isTypeScript = false;

if (fs.existsSync(tsConfigPath)) {
  configPath = tsConfigPath;
  isTypeScript = true;
} else if (fs.existsSync(jsConfigPath)) {
  configPath = jsConfigPath;
  isTypeScript = false;
} else {
  // Create new TS config by default
  configPath = tsConfigPath;
  isTypeScript = true;
}

let config = {};

if (fs.existsSync(configPath)) {
  try {
    fs.copyFileSync(configPath, configPath + '.backup');
    
    const configContent = fs.readFileSync(configPath, 'utf8');
    
    // For TypeScript, we need to handle different export patterns
    let moduleExportsMatch;
    if (isTypeScript) {
      // Handle both export default and module.exports patterns
      moduleExportsMatch = configContent.match(/(?:export default|module\.exports\s*=)\s*(\{[\s\S]*\})/);
    } else {
      moduleExportsMatch = configContent.match(/module\.exports\s*=\s*(\{[\s\S]*\})/);
    }
    
    if (moduleExportsMatch) {
      try {
        // Clean the config string for evaluation
        let configString = moduleExportsMatch[1];
        
        // Handle TypeScript specific syntax - remove type annotations
        configString = configString.replace(/:\s*HardhatUserConfig/g, '');
        configString = configString.replace(/as\s+HardhatUserConfig/g, '');
        
        // Simple evaluation for basic config objects
        const configObject = eval('(' + configString + ')');
        config = configObject;
      } catch (evalError) {
        console.warn('Could not parse existing config, creating new one');
      }
    }
  } catch (error) {
    console.error('Error reading existing hardhat config:', error);
  }
}

// Ensure required structure exists
config.networks = config.networks || {};
config.etherscan = config.etherscan || {};
config.etherscan.apiKey = config.etherscan.apiKey || {};
config.etherscan.customChains = config.etherscan.customChains || [];

// Add/update network configuration
config.networks[network] = config.networks[network] || {
  url: rpcUrl,
  chainId: chainId,
  accounts: process.env.PRIVATE_KEY ? [process.env.PRIVATE_KEY] : []
};

// Add etherscan API key
config.etherscan.apiKey[network] = 'empty';

// Handle custom chains for verification
const existingChainIndex = config.etherscan.customChains.findIndex(
  chain => chain.network === network
);

const isBlockscout = verificationUrl.includes('blockscout');
const apiUrl = isBlockscout 
  ? verificationUrl.replace('blockscout', 'blockscout-backend') + '/api'
  : `${verificationUrl}/api`;

const customChain = {
  network: network,
  chainId: chainId,
  urls: {
    apiURL: apiUrl,
    browserURL: verificationUrl
  }
};

if (existingChainIndex >= 0) {
  config.etherscan.customChains[existingChainIndex] = customChain;
} else {
  config.etherscan.customChains.push(customChain);
}

// Generate the updated config content
let updatedContent;
const configJson = JSON.stringify(config, null, 2);

if (fs.existsSync(configPath)) {
  const originalContent = fs.readFileSync(configPath, 'utf8');
  
  // Check if hardhat-verify is already imported
  const hasVerifyImport = originalContent.includes('@nomicfoundation/hardhat-verify');
  
  let importsSection = '';
  if (!hasVerifyImport) {
    if (isTypeScript) {
      importsSection = `import "@nomicfoundation/hardhat-verify";\nimport { HardhatUserConfig } from "hardhat/config";\n\n`;
    } else {
      importsSection = `require("@nomicfoundation/hardhat-verify");\n\n`;
    }
  }
  
  // Replace the config export
  if (isTypeScript) {
    // Handle both export default and module.exports patterns
    if (originalContent.includes('export default')) {
      updatedContent = originalContent.replace(
        /export default\s*\{[\s\S]*?\}[;\s]*$/m,
        `export default ${configJson} satisfies HardhatUserConfig;`
      );
    } else {
      updatedContent = originalContent.replace(
        /module\.exports\s*=\s*\{[\s\S]*?\}[;\s]*$/m,
        `module.exports = ${configJson};`
      );
    }
    
    // Add imports if needed
    if (!hasVerifyImport) {
      updatedContent = importsSection + updatedContent;
    }
  } else {
    updatedContent = originalContent.replace(
      /module\.exports\s*=\s*\{[\s\S]*?\}[;\s]*$/m,
      `module.exports = ${configJson};`
    );
    
    // Add require if needed
    if (!hasVerifyImport) {
      updatedContent = importsSection + updatedContent;
    }
  }
} else {
  // Create new config file
  if (isTypeScript) {
    updatedContent = `import "@nomicfoundation/hardhat-verify";
import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = ${configJson};

export default config;
`;
  } else {
    updatedContent = `require("@nomicfoundation/hardhat-verify");

module.exports = ${configJson};
`;
  }
}

fs.writeFileSync(configPath, updatedContent);
console.log(`Hardhat config updated successfully for verification (${isTypeScript ? 'TypeScript' : 'JavaScript'})`);
