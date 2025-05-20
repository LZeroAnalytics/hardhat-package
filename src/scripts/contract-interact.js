const hre = require("hardhat");

async function main() {
  const contractAddress = process.env.CONTRACT_ADDRESS;
  const functionName = process.env.FUNCTION_NAME;
  const params = process.env.FUNCTION_PARAMS ? JSON.parse(process.env.FUNCTION_PARAMS) : [];
  
  const contract = await hre.ethers.getContractAt("Contract", contractAddress);
  
  const result = await contract[functionName](...params);
  
  console.log(JSON.stringify({ result: result.toString() }));
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
