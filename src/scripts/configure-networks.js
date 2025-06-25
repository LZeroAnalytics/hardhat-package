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
  // First try: Enhanced parsing with improved cleanup
  try {
    const tempFileName = `temp_config_${Date.now()}.js`;
    const tempFilePath = path.join(process.cwd(), tempFileName);
    
    let tempContent;
    if (isTypeScript) {
      // Convert TypeScript to JavaScript for evaluation with comprehensive cleanup
      tempContent = content
        // Remove all import statements (comprehensive patterns)
        .replace(/import\s+\{[^}]*\}\s+from\s+['"][^'"]*['"];?\s*\n?/g, '') // Named imports
        .replace(/import\s+\*\s+as\s+\w+\s+from\s+['"][^'"]*['"];?\s*\n?/g, '') // Namespace imports
        .replace(/import\s+\w+\s+from\s+['"][^'"]*['"];?\s*\n?/g, '') // Default imports
        .replace(/import\s+['"][^'"]*['"];?\s*\n?/g, '') // Side-effect imports
        .replace(/import\s+.*?from\s+['"][^'"]*['"];?\s*\n?/g, '') // Any other imports
        
        // Convert export to module.exports
        .replace(/export\s+default\s+/g, 'module.exports = ')
        
        // Remove TypeScript annotations
        .replace(/:\s*HardhatUserConfig/g, '')
        .replace(/satisfies\s+HardhatUserConfig/g, '')
        .replace(/as\s+HardhatUserConfig/g, '')
        
        // Remove problematic function calls that reference undefined variables
        .replace(/dotenv\.config\(\);?\s*\n?/g, '') // Remove dotenv.config()
        .replace(/[a-zA-Z_$][a-zA-Z0-9_$]*\.config\(\);?\s*\n?/g, '') // Remove any .config() calls
        
        // Remove comments that might contain problematic code
        .replace(/\/\/.*$/gm, '') // Single line comments
        .replace(/\/\*[\s\S]*?\*\//g, '') // Multi-line comments
        
        // Clean up any remaining semicolons and extra whitespace
        .replace(/^\s*\n/gm, '') // Remove empty lines
        .trim();
    } else {
      // For JavaScript files
      tempContent = content
        .replace(/require\s*\(\s*['"][^'"]*['"]\s*\);?\s*\n?/g, '') // Remove requires
        .replace(/\/\/.*$/gm, '') // Remove comments
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .trim();
    }
    
    console.log('Attempting enhanced parsing method...');
    
    // Validate that we have a valid config structure before writing temp file
    if (!tempContent.includes('module.exports =') || !tempContent.includes('{')) {
      throw new Error('Converted content does not contain valid module.exports structure');
    }
    
    // Write temporary file and require it
    fs.writeFileSync(tempFilePath, tempContent);
    
    // Clear require cache and require the temp file
    delete require.cache[path.resolve(tempFilePath)];
    const loadedConfig = require(path.resolve(tempFilePath));
    
    // Clean up temp file
    fs.unlinkSync(tempFilePath);
    
    // Validate that we got a proper config object
    if (!loadedConfig || typeof loadedConfig !== 'object') {
      throw new Error('Loaded config is not a valid object');
    }
    
    console.log('Enhanced parsing successful!');
    return loadedConfig;
    
  } catch (error) {
    console.log('Enhanced parsing failed:', error.message);
    console.log('Attempting improved regex parsing...');
    
    // Second try: Improved regex-based parsing specifically for your config structure
    try {
      let configMatch;
      
      if (isTypeScript) {
        // More comprehensive regex for TypeScript export default patterns
        configMatch = content.match(/export\s+default\s+(\{[\s\S]*?\})\s*(?:satisfies\s+HardhatUserConfig)?\s*;?/);
        
        if (!configMatch) {
          // Try alternative patterns
          configMatch = content.match(/module\.exports\s*=\s*(\{[\s\S]*?\})\s*;?/);
        }
      } else {
        configMatch = content.match(/module\.exports\s*=\s*(\{[\s\S]*?\})\s*;?/);
      }
      
      if (configMatch) {
        let configString = configMatch[1];
        
        // Clean the config string more thoroughly
        configString = configString
          .replace(/:\s*HardhatUserConfig/g, '') // Remove type annotations
          .replace(/as\s+HardhatUserConfig/g, '') // Remove as clauses
          .replace(/satisfies\s+HardhatUserConfig/g, '') // Remove satisfies
          .replace(/\/\/.*$/gm, '') // Remove single line comments
          .replace(/\/\*[\s\S]*?\*\//g, '') // Remove multi-line comments
          .trim();
        
        console.log('Evaluating config string with regex method...');
        
        // Create a safer evaluation environment
        const configObject = (function() {
          'use strict';
          return eval('(' + configString + ')');
        })();
        
        if (configObject && typeof configObject === 'object') {
          console.log('Regex parsing successful!');
          return configObject;
        }
      }
      
      throw new Error('No valid config pattern found');
      
    } catch (evalError) {
      console.log('Regex parsing also failed:', evalError.message);
      
             // Third try: Manual parsing for your specific structure
       console.log('Attempting manual parsing for known structure...');
       
       try {
         const manualConfig = {};
         
         // More robust parsing using bracket counting for nested objects
         function extractSectionWithBrackets(content, sectionName) {
           const sectionRegex = new RegExp(`["']?${sectionName}["']?\\s*:\\s*\\{`);
           const match = content.match(sectionRegex);
           if (!match) return null;
           
           const startIndex = match.index + match[0].length - 1; // Position of opening {
           let bracketCount = 0;
           let endIndex = startIndex;
           
           for (let i = startIndex; i < content.length; i++) {
             if (content[i] === '{') bracketCount++;
             if (content[i] === '}') bracketCount--;
             if (bracketCount === 0) {
               endIndex = i;
               break;
             }
           }
           
           return content.substring(startIndex, endIndex + 1);
         }
         
         // Extract each section with proper bracket matching
         const soliditySection = extractSectionWithBrackets(content, 'solidity');
         const networksSection = extractSectionWithBrackets(content, 'networks');
         const etherscanSection = extractSectionWithBrackets(content, 'etherscan');
         
         if (soliditySection) {
           try {
             manualConfig.solidity = eval('(' + soliditySection + ')');
             console.log('✅ Solidity section parsed successfully');
           } catch (e) {
             console.log('❌ Could not parse solidity section:', e.message);
           }
         }
         
         if (networksSection) {
           try {
             manualConfig.networks = eval('(' + networksSection + ')');
             console.log('✅ Networks section parsed successfully');
           } catch (e) {
             console.log('❌ Could not parse networks section:', e.message);
           }
         }
         
         if (etherscanSection) {
           try {
             manualConfig.etherscan = eval('(' + etherscanSection + ')');
             console.log('✅ Etherscan section parsed successfully');
           } catch (e) {
             console.log('❌ Could not parse etherscan section:', e.message);
           }
         }
         
         if (Object.keys(manualConfig).length > 0) {
           console.log('Manual parsing successful! Extracted sections:', Object.keys(manualConfig));
           return manualConfig;
         }
        
        throw new Error('Manual parsing failed');
        
      } catch (manualError) {
        console.warn('All parsing methods failed. Creating new config. Error:', manualError.message);
        return {};
      }
    }
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
