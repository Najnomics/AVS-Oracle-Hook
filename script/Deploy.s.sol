// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console} from "forge-std/Script.sol";
import {AVSOracleHook} from "../src/AVSOracleHook.sol";
import {OracleAVSServiceManager} from "../src/OracleAVSServiceManager.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {Currency} from "v4-core/types/Currency.sol";

/**
 * @title Deploy
 * @notice Deployment script for AVS Oracle Hook and related contracts
 * @dev This script deploys the complete Oracle Hook system including:
 *      1. Oracle AVS Service Manager
 *      2. Oracle Hook contract
 *      3. Configuration and initialization
 */
contract Deploy is Script {
    
    /*//////////////////////////////////////////////////////////////
                            CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    
    // Mainnet addresses
    address constant MAINNET_POOL_MANAGER = 0x0000000000000000000000000000000000000000; // TODO: Update with actual address
    
    // Testnet addresses (Sepolia)
    address constant SEPOLIA_POOL_MANAGER = 0x0000000000000000000000000000000000000000; // TODO: Update with actual address
    
    // Local addresses (Anvil)
    address constant LOCAL_POOL_MANAGER = 0x0000000000000000000000000000000000000000; // TODO: Update with actual address
    
    /*//////////////////////////////////////////////////////////////
                               STORAGE
    //////////////////////////////////////////////////////////////*/
    
    OracleAVSServiceManager public oracleAVS;
    AVSOracleHook public oracleHook;
    
    /*//////////////////////////////////////////////////////////////
                           DEPLOYMENT FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);
        
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);
        
        vm.startBroadcast(deployerPrivateKey);
        
        // Deploy the complete system
        (OracleAVSServiceManager avsManager, AVSOracleHook hook) = deployOracleSystem();
        
        vm.stopBroadcast();
        
        // Log deployment information
        logDeploymentInfo(avsManager, hook);
    }
    
    /**
     * @notice Deploy the complete Oracle system
     * @return avsManager The deployed Oracle AVS Service Manager
     * @return hook The deployed Oracle Hook
     */
    function deployOracleSystem() 
        public 
        returns (OracleAVSServiceManager avsManager, AVSOracleHook hook) 
    {
        console.log("Starting Oracle system deployment...");
        
        // Get Pool Manager address based on chain
        address poolManager = getPoolManagerAddress();
        require(poolManager != address(0), "Pool Manager address not configured");
        
        console.log("Using Pool Manager at:", poolManager);
        
        // Step 1: Deploy Oracle AVS Service Manager
        console.log("Deploying Oracle AVS Service Manager...");
        avsManager = new OracleAVSServiceManager(address(0)); // Will be updated after hook deployment
        console.log("Oracle AVS Service Manager deployed at:", address(avsManager));
        
        // Step 2: Deploy Oracle Hook
        console.log("Deploying Oracle Hook...");
        hook = new AVSOracleHook(
            IPoolManager(poolManager),
            address(avsManager)
        );
        console.log("Oracle Hook deployed at:", address(hook));
        
        console.log("Oracle system deployment completed successfully!");
        
        return (avsManager, hook);
    }
    
    /**
     * @notice Get Pool Manager address for current chain
     * @return poolManager The Pool Manager address
     */
    function getPoolManagerAddress() internal view returns (address poolManager) {
        uint256 chainId = block.chainid;
        
        if (chainId == 1) {
            // Ethereum Mainnet
            poolManager = MAINNET_POOL_MANAGER;
        } else if (chainId == 11155111) {
            // Sepolia Testnet
            poolManager = SEPOLIA_POOL_MANAGER;
        } else if (chainId == 31337) {
            // Local Anvil
            poolManager = LOCAL_POOL_MANAGER;
        } else {
            // Unsupported chain
            poolManager = address(0);
        }
        
        return poolManager;
    }
    
    /**
     * @notice Log deployment information
     * @param avsManager The Oracle AVS Service Manager
     * @param hook The Oracle Hook
     */
    function logDeploymentInfo(
        OracleAVSServiceManager avsManager,
        AVSOracleHook hook
    ) internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);
        console.log("Timestamp:", block.timestamp);
        console.log("");
        console.log("=== DEPLOYED CONTRACTS ===");
        console.log("Oracle AVS Service Manager:", address(avsManager));
        console.log("Oracle Hook:", address(hook));
        console.log("");
        console.log("=== CONFIGURATION ===");
        console.log("Pool Manager:", getPoolManagerAddress());
        console.log("Oracle AVS:", address(avsManager));
        console.log("");
        console.log("=== NEXT STEPS ===");
        console.log("1. Register operators with the Oracle AVS");
        console.log("2. Configure oracle settings for desired pools");
        console.log("3. Test price validation functionality");
        console.log("4. Monitor consensus and operator performance");
        console.log("==========================");
    }
}

/**
 * @title DeployLocal
 * @notice Local deployment script for testing
 */
contract DeployLocal is Script {
    function run() external {
        vm.startBroadcast();
        
        // For local deployment, use a placeholder address
        address mockPoolManager = address(0x1234567890123456789012345678901234567890);
        console.log("Using mock Pool Manager at:", mockPoolManager);
        
        // Deploy Oracle system
        OracleAVSServiceManager avsManager = new OracleAVSServiceManager(address(0));
        AVSOracleHook hook = new AVSOracleHook(
            IPoolManager(mockPoolManager),
            address(avsManager)
        );
        
        console.log("Oracle AVS Service Manager:", address(avsManager));
        console.log("Oracle Hook:", address(hook));
        
        vm.stopBroadcast();
    }
}