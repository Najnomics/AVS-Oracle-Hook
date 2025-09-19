// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {AVSOracleHook} from "../src/AVSOracleHook.sol";
import {OracleAVSServiceManager} from "../src/OracleAVSServiceManager.sol";
import {MockOracleAVS} from "../test/mocks/MockOracleAVS.sol";
import {MockPoolManager} from "../test/mocks/MockPoolManager.sol";
import {TestUtils} from "../test/utils/TestUtils.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";

/**
 * @title DeployAnvil
 * @notice Deployment script for Oracle Hook system on local Anvil network
 * @dev This script deploys and configures the complete Oracle Hook system for local development
 */
contract DeployAnvil is Script {
    using PoolIdLibrary for PoolKey;

    // Deployment artifacts
    AVSOracleHook public hook;
    OracleAVSServiceManager public avsManager;
    MockPoolManager public poolManager;
    MockOracleAVS public mockAVS;

    // Test pools
    PoolKey public ethUsdcPool;
    PoolKey public wbtcEthPool;
    PoolKey public daiUsdcPool;

    // Test accounts
    address public deployer;
    address public operator1;
    address public operator2;
    address public operator3;
    address public user1;
    address public user2;

    function run() external {
        // Setup test accounts
        setupAccounts();
        
        vm.startBroadcast(deployer);

        console.log("=== Deploying Oracle Hook System to Anvil ===");
        console.log("Deployer:", deployer);
        console.log("Block timestamp:", block.timestamp);
        console.log("Chain ID:", block.chainid);

        // Deploy core contracts
        deployContracts();
        
        // Setup test pools
        setupPools();
        
        // Configure operators
        setupOperators();
        
        // Setup initial price attestations
        setupInitialPrices();

        vm.stopBroadcast();

        // Log deployment information
        logDeploymentInfo();
        
        console.log("=== Deployment Complete ===");
    }

    function setupAccounts() internal {
        // Use deterministic addresses for local development
        deployer = vm.addr(1);
        operator1 = vm.addr(2); 
        operator2 = vm.addr(3);
        operator3 = vm.addr(4);
        user1 = vm.addr(5);
        user2 = vm.addr(6);

        // Fund accounts with ETH
        vm.deal(deployer, 1000 ether);
        vm.deal(operator1, 100 ether);
        vm.deal(operator2, 100 ether);
        vm.deal(operator3, 100 ether);
        vm.deal(user1, 10 ether);
        vm.deal(user2, 10 ether);

        console.log("Test accounts funded:");
        console.log("  Deployer:", deployer, "Balance:", deployer.balance);
        console.log("  Operator1:", operator1, "Balance:", operator1.balance);
        console.log("  Operator2:", operator2, "Balance:", operator2.balance);
        console.log("  Operator3:", operator3, "Balance:", operator3.balance);
    }

    function deployContracts() internal {
        console.log("\n--- Deploying Core Contracts ---");

        // Deploy Mock Pool Manager for local testing
        poolManager = new MockPoolManager();
        console.log("MockPoolManager deployed at:", address(poolManager));

        // Deploy Mock Oracle AVS for local testing
        mockAVS = new MockOracleAVS();
        console.log("MockOracleAVS deployed at:", address(mockAVS));

        // Deploy Oracle Hook
        hook = new AVSOracleHook(IPoolManager(address(poolManager)), address(mockAVS));
        console.log("AVSOracleHook deployed at:", address(hook));

        // Alternatively, deploy real AVS Service Manager (commented out for local dev)
        // avsManager = new OracleAVSServiceManager(address(hook));
        // console.log("OracleAVSServiceManager deployed at:", address(avsManager));
    }

    function setupPools() internal {
        console.log("\n--- Setting Up Test Pools ---");

        // Create test pools
        ethUsdcPool = TestUtils.createUSDCWETHPoolKey(address(hook));
        wbtcEthPool = TestUtils.createWBTCWETHPoolKey(address(hook));
        daiUsdcPool = PoolKey({
            currency0: Currency.wrap(TestUtils.DAI),
            currency1: Currency.wrap(TestUtils.USDC),
            fee: 500, // 0.05%
            tickSpacing: 10,
            hooks: IHooks(address(hook))
        });

        // Initialize pools in pool manager
        poolManager.initializePool(ethUsdcPool);
        poolManager.initializePool(wbtcEthPool);
        poolManager.initializePool(daiUsdcPool);

        // Initialize pools in hook
        hook.beforeInitialize(deployer, ethUsdcPool, 0, "");
        hook.beforeInitialize(deployer, wbtcEthPool, 0, "");
        hook.beforeInitialize(deployer, daiUsdcPool, 0, "");

        console.log("Test pools initialized:");
        console.log("  ETH/USDC Pool ID:", vm.toString(PoolId.unwrap(ethUsdcPool.toId())));
        console.log("  WBTC/ETH Pool ID:", vm.toString(PoolId.unwrap(wbtcEthPool.toId())));
        console.log("  DAI/USDC Pool ID:", vm.toString(PoolId.unwrap(daiUsdcPool.toId())));
    }

    function setupOperators() internal {
        console.log("\n--- Setting Up Test Operators ---");

        // For mock AVS, we just need to set up mock consensus data
        // In a real deployment, operators would register with the AVS Service Manager
        
        console.log("Test operators configured:");
        console.log("  Operator1:", operator1);
        console.log("  Operator2:", operator2);
        console.log("  Operator3:", operator3);
    }

    function setupInitialPrices() internal {
        console.log("\n--- Setting Up Initial Price Data ---");

        // Set mock consensus data for testing
        bytes32 ethUsdcPoolId = bytes32(uint256(PoolId.unwrap(ethUsdcPool.toId())));
        bytes32 wbtcEthPoolId = bytes32(uint256(PoolId.unwrap(wbtcEthPool.toId())));
        bytes32 daiUsdcPoolId = bytes32(uint256(PoolId.unwrap(daiUsdcPool.toId())));

        // ETH/USDC: $2,105 per ETH
        mockAVS.setMockConsensus(
            ethUsdcPoolId,
            2105 * 1e18, // price
            150 ether,    // total stake
            8500,         // confidence level (85%)
            true          // has consensus
        );

        // WBTC/ETH: 20.5 ETH per WBTC (≈$43,000)
        mockAVS.setMockConsensus(
            wbtcEthPoolId,
            20.5 * 1e18,  // price
            120 ether,    // total stake
            8200,         // confidence level (82%)
            true          // has consensus
        );

        // DAI/USDC: $1.001 per DAI
        mockAVS.setMockConsensus(
            daiUsdcPoolId,
            1.001 * 1e18, // price
            80 ether,     // total stake
            9200,         // confidence level (92%)
            true          // has consensus
        );

        console.log("Initial price data configured:");
        console.log("  ETH/USDC: $2,105 (85% confidence)");
        console.log("  WBTC/ETH: 20.5 ETH (82% confidence)");
        console.log("  DAI/USDC: $1.001 (92% confidence)");
    }

    function logDeploymentInfo() internal view {
        console.log("\n=== Deployment Summary ===");
        console.log("Network: Anvil (Local)");
        console.log("Chain ID:", block.chainid);
        console.log("Deployer:", deployer);
        console.log("");
        
        console.log("Core Contracts:");
        console.log("  MockPoolManager:", address(poolManager));
        console.log("  MockOracleAVS:", address(mockAVS));
        console.log("  AVSOracleHook:", address(hook));
        console.log("");
        
        console.log("Test Pools:");
        console.log("  ETH/USDC:", vm.toString(PoolId.unwrap(ethUsdcPool.toId())));
        console.log("  WBTC/ETH:", vm.toString(PoolId.unwrap(wbtcEthPool.toId())));
        console.log("  DAI/USDC:", vm.toString(PoolId.unwrap(daiUsdcPool.toId())));
        console.log("");
        
        console.log("Test Accounts:");
        console.log("  Operator1:", operator1);
        console.log("  Operator2:", operator2);
        console.log("  Operator3:", operator3);
        console.log("  User1:", user1);
        console.log("  User2:", user2);
        console.log("");
        
        console.log("Usage Examples:");
        console.log("# Test oracle validation");
        console.log("cast call %s getConsensusData(bytes32) %s", address(hook), vm.toString(PoolId.unwrap(ethUsdcPool.toId())));
        console.log("");
        console.log("# Check pool configuration");
        console.log("cast call %s poolConfigs(bytes32) %s", address(hook), vm.toString(PoolId.unwrap(ethUsdcPool.toId())));
        console.log("");
        console.log("# Update mock consensus (for testing)");
        console.log("cast send %s setMockConsensus(bytes32,uint256,uint256,uint256,bool) %s 2200000000000000000000 200000000000000000000 9000 true", 
                   address(mockAVS), vm.toString(PoolId.unwrap(ethUsdcPool.toId())));
    }
}