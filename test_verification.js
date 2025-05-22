const { ethers } = require("hardhat");

async function main() {
  console.log("Deploying SimpleStorage contract to Bloctopus network...");
  
  const [deployer] = await ethers.getSigners();
  console.log("Deploying with account:", deployer.address);
  
  const SimpleStorage = await ethers.getContractFactory("SimpleStorage");
  const initialValue = 42;
  const simpleStorage = await SimpleStorage.deploy(initialValue);
  
  await simpleStorage.waitForDeployment();
  
  const contractAddress = await simpleStorage.getAddress();
  console.log("SimpleStorage deployed to:", contractAddress);
  
  console.log(JSON.stringify({
    contractAddress: contractAddress,
    constructorArgs: [initialValue]
  }));
  
  return {
    contractAddress: contractAddress,
    constructorArgs: [initialValue]
  };
}

main()
  .then((result) => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
