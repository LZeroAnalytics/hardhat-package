/**
 * Contract Interaction Script
 * 
 * This script interacts with a deployed contract by calling a specified function
 * with provided parameters and outputs the result in the format expected by main.star.
 * 
 * Environment variables:
 * - CONTRACT_ADDRESS: Address of the deployed contract (required)
 * - FUNCTION_NAME: Name of the function to call (required)
 * - FUNCTION_PARAMS: JSON string of parameters to pass to the function (optional)
 * - CONTRACT_NAME: Name of the contract ABI to use (default: "Contract")
 * 
 * Expected output: JSON with result, txHash, gasUsed
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
  
  // Get the contract instance
  const contract = await hre.ethers.getContractAt(contractName, contractAddress);
  
  // Call the function
  const result = await contract[functionName](...params);
  
  // Check if this is a transaction (has wait method) or a view function
  if (result && typeof result.wait === 'function') {
    // It's a transaction - wait for it to be mined
    const receipt = await result.wait();
    
    console.log(JSON.stringify({ 
      result: result.toString(),
      txHash: result.hash,
      gasUsed: receipt.gasUsed.toString()
    }));
  } else {
    // It's a view function - just return the result
    console.log(JSON.stringify({ 
      result: result.toString(),
      txHash: null,
      gasUsed: "0"
    }));
  }
}

// Let it fail naturally - no try/catch
main();
