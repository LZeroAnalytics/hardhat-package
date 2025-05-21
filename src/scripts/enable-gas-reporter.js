/**
 * Gas Reporter Configuration Script
 * 
 * This script enables the hardhat-gas-reporter plugin to analyze gas usage
 * of smart contracts. It follows the pattern used in layerzero-oapp for
 * gas optimization.
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

config.gasReporter = {
  enabled: true,
  outputFile: outputFile,
  noColors: true,
  excludeContracts: excludeContracts,
  src: contractsSrc,
  coinmarketcap: process.env.COINMARKETCAP_API_KEY,
  currency: 'USD',
};

let updatedContent;
if (fs.existsSync(configPath)) {
  const originalContent = fs.readFileSync(configPath, 'utf8');
  
  if (!originalContent.includes('hardhat-gas-reporter')) {
    updatedContent = `require("hardhat-gas-reporter");\n\n${originalContent}`;
    updatedContent = updatedContent.replace(/module\.exports\s*=\s*\{[\s\S]*\}/, `module.exports = ${JSON.stringify(config, null, 2)}`);
  } else {
    updatedContent = originalContent.replace(/module\.exports\s*=\s*\{[\s\S]*\}/, `module.exports = ${JSON.stringify(config, null, 2)}`);
  }
} else {
  updatedContent = `require("hardhat-gas-reporter");\n\nmodule.exports = ${JSON.stringify(config, null, 2)};`;
}

fs.writeFileSync(configPath, updatedContent);
console.log('Gas reporter enabled');
