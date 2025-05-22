/**
 * Contract Interaction Script
 * 
 * This script interacts with a deployed contract by calling a specified function
 * with provided parameters. It follows the pattern used in layerzero-oapp for
 * contract interaction.
 * 
 * Environment variables:
 * - CONTRACT_ADDRESS: Address of the deployed contract (required)
 * - FUNCTION_NAME: Name of the function to call (required)
 * - FUNCTION_PARAMS: JSON string of parameters to pass to the function (optional)
 * - CONTRACT_NAME: Name of the contract ABI to use (default: "Contract")
 */

const hre = require("hardhat");

async function main() {
  const contractAddress = process.env.CONTRACT_ADDRESS;
  const functionName = process.env.FUNCTION_NAME;
  const contractName = process.env.CONTRACT_NAME || "Contract";
  const params = process.env.FUNCTION_PARAMS ? JSON.parse(process.env.FUNCTION_PARAMS) : [];
  
  if (!contractAddress) {
    console.error('Error: CONTRACT_ADDRESS environment variable is required');
    process.exit(1);
  }
  
  if (!functionName) {
    console.error('Error: FUNCTION_NAME environment variable is required');
    process.exit(1);
  }
  
  try {
    const contract = await hre.ethers.getContractAt(contractName, contractAddress);
    
    const result = await contract[functionName](...params);
    
    console.log(JSON.stringify({ 
      success: true,
      result: result.toString(),
      contractAddress,
      functionName,
      params
    }));
  } catch (error) {
    console.error(JSON.stringify({
      success: false,
      error: error.message,
      contractAddress,
      functionName,
      params
    }));
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
