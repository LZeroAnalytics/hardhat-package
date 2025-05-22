/**
 * Standalone Test Script for Hardhat Package Verification
 * 
 * This script tests the verification functionality without requiring Kurtosis.
 * It deploys a SimpleStorage contract to the Bloctopus network and verifies it.
 * 
 * Usage:
 * 1. Install dependencies: npm install --save-dev hardhat @nomicfoundation/hardhat-toolbox @nomicfoundation/hardhat-verify
 * 2. Run the script: node test_standalone.js
 */

const { execSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const BLOCTOPUS_RPC = "https://eb9ad9faac334860ba32433d00ea3a19-rpc.network.bloctopus.io";
const BLOCTOPUS_CHAIN_ID = 6129906;
const BLOCTOPUS_PRIVATE_KEY = "0xd29644a2fbc8649ef6831514c241af9ca09c16156ac159dc7cb9cd64466b2569";
const BLOCTOPUS_VERIFICATION_URL = "https://eb9ad9faac334860ba32433d00ea3a19-blockscout.network.bloctopus.io";

const TEST_DIR = path.join(__dirname, 'test-standalone');
if (!fs.existsSync(TEST_DIR)) {
    fs.mkdirSync(TEST_DIR, { recursive: true });
}

const CONTRACTS_DIR = path.join(TEST_DIR, 'contracts');
const SCRIPTS_DIR = path.join(TEST_DIR, 'scripts');
if (!fs.existsSync(CONTRACTS_DIR)) {
    fs.mkdirSync(CONTRACTS_DIR, { recursive: true });
}
if (!fs.existsSync(SCRIPTS_DIR)) {
    fs.mkdirSync(SCRIPTS_DIR, { recursive: true });
}

const simpleStorageContract = `// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract SimpleStorage {
    uint256 private value;
    
    constructor(uint256 initialValue) {
        value = initialValue;
    }
    
    function setValue(uint256 newValue) public {
        value = newValue;
    }
    
    function getValue() public view returns (uint256) {
        return value;
    }
}`;

fs.writeFileSync(path.join(CONTRACTS_DIR, 'SimpleStorage.sol'), simpleStorageContract);

const deployScript = `async function main() {
    const [deployer] = await ethers.getSigners();
    console.log("Deploying contracts with the account:", deployer.address);

    const SimpleStorage = await ethers.getContractFactory("SimpleStorage");
    const initialValue = 42;
    const simpleStorage = await SimpleStorage.deploy(initialValue);

    await simpleStorage.waitForDeployment();

    const contractAddress = await simpleStorage.getAddress();
    console.log("SimpleStorage deployed to:", contractAddress);
    console.log("Constructor arguments:", initialValue);
    
    return {
        contractAddress: contractAddress,
        constructorArgs: [initialValue]
    };
}

main()
    .then((result) => {
        console.log("Deployment successful:", JSON.stringify(result));
        const fs = require('fs');
        fs.writeFileSync('deployment.json', JSON.stringify(result));
        process.exit(0);
    })
    .catch((error) => {
        console.error(error);
        process.exit(1);
    });`;

fs.writeFileSync(path.join(SCRIPTS_DIR, 'deploy.js'), deployScript);

const hardhatConfig = `require("@nomicfoundation/hardhat-toolbox");
require("@nomicfoundation/hardhat-verify");

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.18",
  networks: {
    bloctopus: {
      url: "${BLOCTOPUS_RPC}",
      chainId: ${BLOCTOPUS_CHAIN_ID},
      accounts: ["${BLOCTOPUS_PRIVATE_KEY}"]
    }
  },
  etherscan: {
    apiKey: {
      bloctopus: "empty"
    },
    customChains: [
      {
        network: "bloctopus",
        chainId: ${BLOCTOPUS_CHAIN_ID},
        urls: {
          apiURL: "${BLOCTOPUS_VERIFICATION_URL.replace('blockscout', 'blockscout-backend')}/api",
          browserURL: "${BLOCTOPUS_VERIFICATION_URL}"
        }
      }
    ]
  }
};`;

fs.writeFileSync(path.join(TEST_DIR, 'hardhat.config.js'), hardhatConfig);

const packageJson = `{
  "name": "test-standalone",
  "version": "1.0.0",
  "description": "Test project for hardhat-package verification",
  "main": "index.js",
  "scripts": {
    "test": "echo \\"Error: no test specified\\" && exit 1"
  },
  "keywords": [],
  "author": "",
  "license": "ISC",
  "devDependencies": {
    "@nomicfoundation/hardhat-toolbox": "^2.0.0",
    "@nomicfoundation/hardhat-verify": "^1.0.0",
    "hardhat": "^2.14.0"
  }
}`;

fs.writeFileSync(path.join(TEST_DIR, 'package.json'), packageJson);

const verificationScript = `const fs = require('fs');
const { execSync } = require('child_process');

const deploymentInfo = JSON.parse(fs.readFileSync('deployment.json', 'utf8'));
const contractAddress = deploymentInfo.contractAddress;
const constructorArgs = deploymentInfo.constructorArgs;

console.log("Verifying contract at address:", contractAddress);
console.log("Constructor arguments:", constructorArgs);

try {
    const verifyCommand = \`npx hardhat verify --network bloctopus --force \${contractAddress} \${constructorArgs[0]}\`;
    console.log("Running command:", verifyCommand);
    const result = execSync(verifyCommand, { encoding: 'utf8' });
    console.log("Verification result:", result);
    console.log("Verification successful!");
    console.log("View the verified contract at: ${BLOCTOPUS_VERIFICATION_URL}/address/" + contractAddress + "#code");
} catch (error) {
    console.error("Verification failed:", error.message);
}`;

fs.writeFileSync(path.join(TEST_DIR, 'verify.js'), verificationScript);

const testRunnerScript = `const { execSync } = require('child_process');
const path = require('path');

process.chdir('${TEST_DIR}');

console.log("Installing dependencies...");
try {
    execSync('npm install', { stdio: 'inherit' });
} catch (error) {
    console.error("Failed to install dependencies:", error.message);
    process.exit(1);
}

console.log("Compiling contracts...");
try {
    execSync('npx hardhat compile', { stdio: 'inherit' });
} catch (error) {
    console.error("Failed to compile contracts:", error.message);
    process.exit(1);
}

console.log("Deploying contract...");
try {
    execSync('npx hardhat run scripts/deploy.js --network bloctopus', { stdio: 'inherit' });
} catch (error) {
    console.error("Failed to deploy contract:", error.message);
    process.exit(1);
}

console.log("Verifying contract...");
try {
    execSync('node verify.js', { stdio: 'inherit' });
} catch (error) {
    console.error("Failed to verify contract:", error.message);
    process.exit(1);
}

console.log("Test completed successfully!");`;

fs.writeFileSync(path.join(__dirname, 'run_test.js'), testRunnerScript);

console.log("Test scripts created successfully!");
console.log("To run the test, execute: node run_test.js");
