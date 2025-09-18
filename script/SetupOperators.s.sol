// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {OracleAVSServiceManager} from "../src/OracleAVSServiceManager.sol";

/**
 * @title SetupOperators
 * @notice Script to register and configure Oracle operators
 */
contract SetupOperators is Script {
    
    OracleAVSServiceManager public avsManager;
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address avsAddress = vm.envAddress("ORACLE_AVS_ADDRESS");
        
        require(avsAddress != address(0), "ORACLE_AVS_ADDRESS not set");
        
        avsManager = OracleAVSServiceManager(avsAddress);
        
        console.log("=== SETTING UP OPERATORS ===");
        console.log("Oracle AVS:", avsAddress);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Register test operators
        registerTestOperators();
        
        // Submit initial price attestations
        submitInitialAttestations();
        
        vm.stopBroadcast();
        
        console.log("=== OPERATOR SETUP COMPLETE ===");
    }
    
    function registerTestOperators() internal {
        console.log("Registering test operators...");
        
        // Register operator with minimum stake
        avsManager.registerOperator{value: 5 ether}();
        console.log("Operator registered with 5 ETH stake");
        
        // Add more stake
        avsManager.addStake{value: 5 ether}();
        console.log("Added 5 ETH more stake (total: 10 ETH)");
    }
    
    function submitInitialAttestations() internal {
        console.log("Submitting initial price attestations...");
        
        // Submit test price for ETH-USDC pool
        bytes32 poolId = keccak256("ETH-USDC-3000");
        uint256 price = 2105 * 1e18; // $2,105
        bytes32 sourceHash = keccak256("binance,coinbase,kraken");
        bytes memory signature = hex"1234567890"; // Mock signature
        
        avsManager.submitPriceAttestation(
            poolId,
            price,
            sourceHash,
            signature
        );
        
        console.log("Submitted price attestation for ETH-USDC pool");
        console.log("Price:", price);
    }
}