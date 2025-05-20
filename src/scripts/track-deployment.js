const fs = require('fs');
const path = require('path');

const contractName = process.env.CONTRACT_NAME;
const contractAddress = process.env.CONTRACT_ADDRESS;
const network = process.env.NETWORK;
const constructorArgs = process.env.CONSTRUCTOR_ARGS ? JSON.parse(process.env.CONSTRUCTOR_ARGS) : [];
const contractPath = process.env.CONTRACT_PATH || '';

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
  contractPath: contractPath
};

const deploymentFile = path.join(deploymentsDir, `${contractName}.json`);
fs.writeFileSync(deploymentFile, JSON.stringify(deploymentInfo, null, 2));

console.log(`Deployment tracked: ${deploymentFile}`);
