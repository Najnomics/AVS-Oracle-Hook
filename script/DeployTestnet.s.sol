// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AVSOracleHook} from "../src/AVSOracleHook.sol";
import {OracleAVSServiceManager} from "../src/OracleAVSServiceManager.sol";
import {MockOracleAVS} from "../test/mocks/MockOracleAVS.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

/**
 * @title DeployTestnet
 * @notice Testnet deployment with mock components for testing
 */
contract DeployTestnet is Script {
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("=== TESTNET DEPLOYMENT ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);
        console.log("Balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy Oracle system with mock components for testing
        (address hook, address avs) = deployTestnetSystem();
        
        // Setup initial test configuration
        setupTestConfiguration(hook, avs);
        
        vm.stopBroadcast();
        
        console.log("=== DEPLOYMENT COMPLETE ===");
        console.log("Oracle Hook:", hook);
        console.log("Oracle AVS:", avs);
    }
    
    function deployTestnetSystem() internal returns (address hook, address avs) {
        // For testnet, we'll use the MockOracleAVS for easier testing
        console.log("Deploying Mock Oracle AVS...");
        MockOracleAVS mockAVS = new MockOracleAVS();
        avs = address(mockAVS);
        
        // Deploy the actual hook
        console.log("Deploying Oracle Hook...");
        // Use a placeholder pool manager address for testnet
        address poolManager = 0x0000000000000000000000000000000000000001;
        AVSOracleHook oracleHook = new AVSOracleHook(
            IPoolManager(poolManager),
            avs
        );
        hook = address(oracleHook);
        
        return (hook, avs);
    }
    
    function setupTestConfiguration(address hook, address avs) internal {
        console.log("Setting up test configuration...");
        
        // Configure mock AVS with test data
        MockOracleAVS(avs).setMockPrice(2105 * 1e18); // $2,105
        MockOracleAVS(avs).setMockStake(100 ether);
        MockOracleAVS(avs).setMockConfidence(8500); // 85%
        
        console.log("Test configuration complete");
    }
}