const fs = require('fs');
const path = require('path');

const configPath = path.join(process.cwd(), 'hardhat.config.js');
let config = {};

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

config.gasReporter = {
  enabled: true,
  outputFile: 'gas-report.txt',
  noColors: true,
  excludeContracts: [],
  src: './contracts'
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
