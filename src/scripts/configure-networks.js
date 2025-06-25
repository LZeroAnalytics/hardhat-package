/**
 * Network Configuration Script
 * 
 * This script configures multiple networks in hardhat.config.js/ts for deployment and verification.
 * It supports both JavaScript and TypeScript projects.
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

// Function to safely extract configuration from file content
function extractConfigFromContent(content, isTypeScript) {
  try {
    // Create a temporary file to require/import and get the actual config
    const tempFileName = `temp_config_${Date.now()}.js`;
    const tempFilePath = path.join(process.cwd(), tempFileName);
    
    let tempContent;
    if (isTypeScript) {
      // Convert TypeScript to JavaScript for evaluation
      tempContent = content
        .replace(/import\s+.*?from\s+['"][^'"]*['"];?\s*\n?/g, '') // Remove imports
        .replace(/import\s+['"][^'"]*['"];?\s*\n?/g, '') // Remove side-effect imports
        .replace(/export\s+default\s+/g, 'module.exports = ') // Convert export default
        .replace(/:\s*HardhatUserConfig/g, '') // Remove type annotations
        .replace(/satisfies\s+HardhatUserConfig/g, '') // Remove satisfies
        .replace(/as\s+HardhatUserConfig/g, ''); // Remove as clauses
    } else {
      // For JavaScript files, we need to handle requires
      tempContent = content
        .replace(/require\s*\(\s*['"][^'"]*['"]\s*\);?\s*\n?/g, ''); // Remove requires for parsing
    }
    
    // Write temporary file and require it
    fs.writeFileSync(tempFilePath, tempContent);
    
    // Clear require cache and require the temp file
    delete require.cache[path.resolve(tempFilePath)];
    const loadedConfig = require(path.resolve(tempFilePath));
    
    // Clean up temp file
    fs.unlinkSync(tempFilePath);
    
    return loadedConfig || {};
  } catch (error) {
    console.warn('Could not parse existing config using safer method, attempting fallback parsing');
    
    // Fallback to regex-based parsing
    let moduleExportsMatch;
    if (isTypeScript) {
      // Handle both export default and module.exports patterns
      moduleExportsMatch = content.match(/(?:export default|module\.exports\s*=)\s*(\{[\s\S]*\})/);
    } else {
      moduleExportsMatch = content.match(/module\.exports\s*=\s*(\{[\s\S]*\})/);
    }
    
    if (moduleExportsMatch) {
      try {
        // Clean the config string for evaluation
        let configString = moduleExportsMatch[1];
        
        // Handle TypeScript specific syntax - remove type annotations
        configString = configString.replace(/:\s*HardhatUserConfig/g, '');
        configString = configString.replace(/as\s+HardhatUserConfig/g, '');
        configString = configString.replace(/satisfies\s+HardhatUserConfig/g, '');
        
        // Simple evaluation for basic config objects
        const configObject = eval('(' + configString + ')');
        return configObject || {};
      } catch (evalError) {
        console.warn('Could not parse existing config with fallback method either, creating new config');
        return {};
      }
    }
    
    return {};
  }
}

if (fs.existsSync(configPath)) {
  try {
    fs.copyFileSync(configPath, configPath + '.backup');
    
    const configContent = fs.readFileSync(configPath, 'utf8');
    config = extractConfigFromContent(configContent, isTypeScript);
    
    console.log('Successfully parsed existing config. Preserving:', Object.keys(config).join(', '));
  } catch (error) {
    console.error('Error reading existing hardhat config:', error);
  }
}

// Ensure required sections exist, preserving existing ones
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
    
    const isBlockscout = network.verification_url.includes('blockscout');
    const apiUrl = isBlockscout 
      ? network.verification_url.replace('blockscout', 'blockscout-backend') + '/api'
      : `${network.verification_url}/api`;
    
    const customChain = {
      network: networkName,
      chainId: network.chain_id,
      urls: {
        apiURL: apiUrl,
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

// Generate the updated config content
let updatedContent;
const configJson = JSON.stringify(config, null, 2);

if (fs.existsSync(configPath)) {
  const originalContent = fs.readFileSync(configPath, 'utf8');
  
  // Check if hardhat-verify is already imported
  const hasVerifyImport = originalContent.includes('@nomicfoundation/hardhat-verify');
  
  let importsSection = '';
  if (needsVerification && !hasVerifyImport) {
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
        /export default\s*\{[\s\S]*\}\s*(?:satisfies\s+[A-Za-z0-9_.]+\s*)?;?/m,
        `export default ${configJson} satisfies HardhatUserConfig;`
      );
    } else {
      // Handle both direct object exports and variable exports
      updatedContent = originalContent.replace(
        /module\.exports\s*=\s*(?:\{[\s\S]*\}|[^;]+);?/m,
        `module.exports = ${configJson};`
      );
    }
    
    // Add imports if needed
    if (needsVerification && !hasVerifyImport) {
      updatedContent = importsSection + updatedContent;
    }
  } else {
    // Handle both direct object exports and variable exports
    updatedContent = originalContent.replace(
      /module\.exports\s*=\s*(?:\{[\s\S]*\}|[^;]+);?/m,
      `module.exports = ${configJson};`
    );
    
    // Add require if needed
    if (needsVerification && !hasVerifyImport) {
      updatedContent = importsSection + updatedContent;
    }
  }
} else {
  // Create new config file
  if (isTypeScript) {
    const imports = needsVerification 
      ? `import "@nomicfoundation/hardhat-verify";\nimport { HardhatUserConfig } from "hardhat/config";\n\n`
      : `import { HardhatUserConfig } from "hardhat/config";\n\n`;
    
    updatedContent = `${imports}const config: HardhatUserConfig = ${configJson};

export default config;
`;
  } else {
    const requires = needsVerification ? 'require("@nomicfoundation/hardhat-verify");\n\n' : '';
    updatedContent = `${requires}module.exports = ${configJson};`;
  }
}

fs.writeFileSync(configPath, updatedContent);
console.log(`Hardhat config updated with ${Object.keys(networks).length} networks (${isTypeScript ? 'TypeScript' : 'JavaScript'})`);
console.log('Preserved config sections:', Object.keys(config).filter(key => key !== 'networks' && key !== 'etherscan').join(', '));
