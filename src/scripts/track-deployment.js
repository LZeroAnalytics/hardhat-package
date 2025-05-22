/**
 * Deployment Tracking Script
 * 
 * This script tracks deployed contracts for future reference and verification.
 * It follows the pattern used in layerzero-oapp for deployment management.
 * 
 * Environment variables:
 * - CONTRACT_NAME: Name of the contract (required)
 * - CONTRACT_ADDRESS: Address of the deployed contract (required)
 * - NETWORK: Network where the contract is deployed (required)
 * - CONSTRUCTOR_ARGS: JSON string of constructor arguments used for deployment (optional)
 * - CONTRACT_PATH: Path to the contract if it's in a non-standard location (optional)
 */

const fs = require('fs');
const path = require('path');

const contractName = process.env.CONTRACT_NAME;
const contractAddress = process.env.CONTRACT_ADDRESS;
const network = process.env.NETWORK;
const constructorArgs = process.env.CONSTRUCTOR_ARGS ? JSON.parse(process.env.CONSTRUCTOR_ARGS) : [];
const contractPath = process.env.CONTRACT_PATH || '';

if (!contractName) {
  console.error('Error: CONTRACT_NAME environment variable is required');
  process.exit(1);
}

if (!contractAddress) {
  console.error('Error: CONTRACT_ADDRESS environment variable is required');
  process.exit(1);
}

if (!network) {
  console.error('Error: NETWORK environment variable is required');
  process.exit(1);
}

const deploymentsDir = path.join(process.cwd(), 'deployments', network);
if (!fs.existsSync(deploymentsDir)) {
  fs.mkdirSync(deploymentsDir, { recursive: true });
}

const deploymentInfo = {
  contractName: contractName,
  address: contractAddress,
  network: network,
  deploymentTime: new Date().toISOString(),
  constructorArgs: constructorArgs,
  contractPath: contractPath,
  blockNumber: process.env.BLOCK_NUMBER,
  txHash: process.env.TX_HASH
};

const deploymentFile = path.join(deploymentsDir, `${contractName}.json`);
fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));

console.log(`Deployment tracked: ${deploymentFile}`);

const allDeploymentsFile = path.join(process.cwd(), 'deployments', 'deployments.json');
let allDeployments = {};

if (fs.existsSync(allDeploymentsFile)) {
  try {
    allDeployments = JSON.parse(fs.readFileSync(allDeploymentsFile, 'utf8'));
  } catch (error) {
    console.error('Error reading existing deployments:', error);
  }
}

if (!allDeployments[network]) {
  allDeployments[network] = {};
}
allDeployments[network][contractName] = deploymentInfo;

fs.writeFileSync(allDeploymentsFile, JSON.stringify(allDeployments, null, 2));
console.log(`All deployments updated: ${allDeploymentsFile}`);
