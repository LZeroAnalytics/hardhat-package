/**
 * Gas Reporter Configuration Script
 * 
 * This script enables the hardhat-gas-reporter plugin to analyze gas usage
 * of smart contracts. It supports both JavaScript and TypeScript projects.
 * 
 * Environment variables:
 * - OUTPUT_FILE: Path to output file (default: 'gas-report.txt')
 * - EXCLUDE_CONTRACTS: Comma-separated list of contracts to exclude (optional)
 * - CONTRACTS_SRC: Path to contracts directory (default: './contracts')
 */

const fs = require('fs');
const path = require('path');

const outputFile = process.env.OUTPUT_FILE || 'gas-report.txt';
const excludeContracts = process.env.EXCLUDE_CONTRACTS ? process.env.EXCLUDE_CONTRACTS.split(',') : [];
const contractsSrc = process.env.CONTRACTS_SRC || './contracts';

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

config.gasReporter = {
  enabled: true,
  outputFile: outputFile,
  noColors: true,
  excludeContracts: excludeContracts,
  src: contractsSrc,
  coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  currency: 'USD',
};

// Generate the updated config content
let updatedContent;
const configJson = JSON.stringify(config, null, 2);

if (fs.existsSync(configPath)) {
  const originalContent = fs.readFileSync(configPath, 'utf8');
  
  // Check if hardhat-gas-reporter is already imported
  const hasGasReporterImport = originalContent.includes('hardhat-gas-reporter');
  
  let importsSection = '';
  if (!hasGasReporterImport) {
    if (isTypeScript) {
      importsSection = `import "hardhat-gas-reporter";\nimport { HardhatUserConfig } from "hardhat/config";\n\n`;
    } else {
      importsSection = `require("hardhat-gas-reporter");\n\n`;
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
    if (!hasGasReporterImport) {
      updatedContent = importsSection + updatedContent;
    }
  } else {
    updatedContent = originalContent.replace(
      /module\.exports\s*=\s*\{[\s\S]*?\}[;\s]*$/m,
      `module.exports = ${configJson};`
    );
    
    // Add require if needed
    if (!hasGasReporterImport) {
      updatedContent = importsSection + updatedContent;
    }
  }
} else {
  // Create new config file
  if (isTypeScript) {
    updatedContent = `import "hardhat-gas-reporter";
import { HardhatUserConfig } from "hardhat/config";

const config: HardhatUserConfig = ${configJson};

export default config;
`;
  } else {
    updatedContent = `require("hardhat-gas-reporter");

module.exports = ${configJson};`;
  }
}

fs.writeFileSync(configPath, updatedContent);
console.log(`Gas reporter enabled (${isTypeScript ? 'TypeScript' : 'JavaScript'})`);
