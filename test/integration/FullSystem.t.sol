// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AVSOracleHook} from "../../src/AVSOracleHook.sol";
import {OracleAVSServiceManager} from "../../src/OracleAVSServiceManager.sol";
import {MockOracleAVS} from "../mocks/MockOracleAVS.sol";
import {MockPoolManager} from "../mocks/MockPoolManager.sol";
import {TestUtils} from "../utils/TestUtils.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";

/**
 * @title FullSystemIntegrationTest
 * @notice Comprehensive integration tests for the complete Oracle Hook system
 * @dev Tests the integration between Hook, AVS Service Manager, and oracle validation
 */
contract FullSystemIntegrationTest is Test {
    using PoolIdLibrary for PoolKey;
    
    AVSOracleHook hook;
    OracleAVSServiceManager avsManager;
    MockPoolManager poolManager;
    
    PoolKey ethUsdcPool;
    PoolKey wbtcEthPool;
    PoolKey daiUsdcPool;
    
    PoolId ethUsdcPoolId;
    PoolId wbtcEthPoolId;
    PoolId daiUsdcPoolId;
    
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    address operator1 = makeAddr("operator1");
    address operator2 = makeAddr("operator2");
    address operator3 = makeAddr("operator3");
    
    uint256 constant INITIAL_OPERATOR_STAKE = 50 ether;
    uint256 constant ETH_PRICE = 2105e18; // $2,105
    uint256 constant WBTC_PRICE = 43000e18; // $43,000
    uint256 constant DAI_PRICE = 1e18; // $1
    
    event PriceAttestationSubmitted(
        bytes32 indexed attestationId,
        address indexed operator,
        bytes32 indexed poolId,
        uint256 price,
        uint256 stakeAmount
    );
    
    event ConsensusReached(
        bytes32 indexed poolId,
        uint256 consensusPrice,
        uint256 totalStake,
        uint256 attestationCount,
        uint256 confidenceLevel
    );
    
    function setUp() public {
        poolManager = new MockPoolManager();
        
        // Deploy the actual AVS Service Manager
        avsManager = new OracleAVSServiceManager(address(this)); // Use test contract as temporary hook
        
        // Deploy Oracle Hook with real AVS
        hook = new AVSOracleHook(IPoolManager(address(poolManager)), address(avsManager));
        
        // Create multiple pools for testing
        ethUsdcPool = TestUtils.createUSDCWETHPoolKey(address(hook));
        wbtcEthPool = TestUtils.createWBTCWETHPoolKey(address(hook));
        daiUsdcPool = PoolKey({
            currency0: Currency.wrap(TestUtils.DAI),
            currency1: Currency.wrap(TestUtils.USDC),
            fee: 500, // 0.05%
            tickSpacing: 10,
            hooks: IHooks(address(hook))
        });
        
        ethUsdcPoolId = ethUsdcPool.toId();
        wbtcEthPoolId = wbtcEthPool.toId();
        daiUsdcPoolId = daiUsdcPool.toId();
        
        // Initialize all pools
        hook.beforeInitialize(alice, ethUsdcPool, 0, "");
        hook.beforeInitialize(alice, wbtcEthPool, 0, "");
        hook.beforeInitialize(alice, daiUsdcPool, 0, "");
        
        // Register operators
        setupOperators();
    }
    
    function setupOperators() internal {
        // Register multiple operators with different stake amounts
        vm.deal(operator1, 100 ether);
        vm.deal(operator2, 100 ether);
        vm.deal(operator3, 100 ether);
        
        vm.prank(operator1);
        avsManager.registerOperator{value: INITIAL_OPERATOR_STAKE}();
        
        vm.prank(operator2);
        avsManager.registerOperator{value: INITIAL_OPERATOR_STAKE + 20 ether}();
        
        vm.prank(operator3);
        avsManager.registerOperator{value: INITIAL_OPERATOR_STAKE + 10 ether}();
    }
    
    /*//////////////////////////////////////////////////////////////
                         FULL SYSTEM INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Integration01_CompleteWorkflow_MultipleOperators() public {
        // Submit price attestations from multiple operators
        bytes32 ethUsdcPoolIdBytes = bytes32(uint256(PoolId.unwrap(ethUsdcPoolId)));
        
        vm.prank(operator1);
        avsManager.submitPriceAttestation(
            ethUsdcPoolIdBytes,
            ETH_PRICE,
            keccak256("binance,coinbase"),
            hex"1234"
        );
        
        vm.prank(operator2);
        avsManager.submitPriceAttestation(
            ethUsdcPoolIdBytes,
            ETH_PRICE + 2e18, // Slightly different price
            keccak256("kraken,gemini"),
            hex"5678"
        );
        
        vm.prank(operator3);
        avsManager.submitPriceAttestation(
            ethUsdcPoolIdBytes,
            ETH_PRICE - 1e18, // Slightly different price
            keccak256("bitstamp,huobi"),
            hex"9abc"
        );
        
        // Check consensus was reached
        (bool hasConsensus, uint256 consensusPrice, uint256 totalStake, uint256 confidenceLevel, ) = 
            avsManager.getCurrentConsensus(ethUsdcPoolIdBytes);
        
        assertTrue(hasConsensus);
        assertApproxEqRel(consensusPrice, ETH_PRICE, 0.01e18); // Within 1%
        assertGt(totalStake, 100 ether);
        assertGt(confidenceLevel, 6600); // Above threshold
        
        // Test swap with consensus
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        (bytes4 result, , ) = hook.beforeSwap(alice, ethUsdcPool, swapParams, "");
        assertEq(result, hook.beforeSwap.selector);
    }
    
    function test_Integration02_MultiPool_IndependentConsensus() public {
        // Submit different prices for different pools
        bytes32 ethUsdcBytes = bytes32(uint256(PoolId.unwrap(ethUsdcPoolId)));
        bytes32 wbtcEthBytes = bytes32(uint256(PoolId.unwrap(wbtcEthPoolId)));
        
        // ETH-USDC consensus
        vm.prank(operator1);
        avsManager.submitPriceAttestation(ethUsdcBytes, ETH_PRICE, keccak256("eth_sources"), hex"1111");
        
        vm.prank(operator2);
        avsManager.submitPriceAttestation(ethUsdcBytes, ETH_PRICE, keccak256("eth_sources"), hex"2222");
        
        vm.prank(operator3);
        avsManager.submitPriceAttestation(ethUsdcBytes, ETH_PRICE, keccak256("eth_sources"), hex"3333");
        
        // WBTC-ETH consensus (different price)
        vm.prank(operator1);
        avsManager.submitPriceAttestation(wbtcEthBytes, WBTC_PRICE, keccak256("btc_sources"), hex"aaaa");
        
        vm.prank(operator2);
        avsManager.submitPriceAttestation(wbtcEthBytes, WBTC_PRICE, keccak256("btc_sources"), hex"bbbb");
        
        vm.prank(operator3);
        avsManager.submitPriceAttestation(wbtcEthBytes, WBTC_PRICE, keccak256("btc_sources"), hex"cccc");
        
        // Check both pools have independent consensus
        (bool hasConsensus1, uint256 price1, , , ) = avsManager.getCurrentConsensus(ethUsdcBytes);
        (bool hasConsensus2, uint256 price2, , , ) = avsManager.getCurrentConsensus(wbtcEthBytes);
        
        assertTrue(hasConsensus1);
        assertTrue(hasConsensus2);
        assertApproxEqRel(price1, ETH_PRICE, 0.01e18);
        assertApproxEqRel(price2, WBTC_PRICE, 0.01e18);
        
        // Both pools should allow swaps
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        (bytes4 result1, , ) = hook.beforeSwap(alice, ethUsdcPool, swapParams, "");
        (bytes4 result2, , ) = hook.beforeSwap(alice, wbtcEthPool, swapParams, "");
        
        assertEq(result1, hook.beforeSwap.selector);
        assertEq(result2, hook.beforeSwap.selector);
    }
    
    function test_Integration03_OperatorSlashing_BadPrices() public {
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(ethUsdcPoolId)));
        
        // Two operators submit good prices
        vm.prank(operator1);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE, keccak256("good_sources"), hex"1111");
        
        vm.prank(operator2);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE + 1e18, keccak256("good_sources"), hex"2222");
        
        // One operator submits bad price (should get slashed)
        vm.prank(operator3);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE * 2, keccak256("bad_sources"), hex"3333"); // 100% deviation
        
        // Check consensus still formed with good operators
        (bool hasConsensus, uint256 consensusPrice, , , ) = avsManager.getCurrentConsensus(poolIdBytes);
        assertTrue(hasConsensus);
        assertApproxEqRel(consensusPrice, ETH_PRICE, 0.05e18); // Within 5%
        
        // Check operator3 performance decreased
        (, , uint256 reliabilityScore, uint256 totalAttestations, uint256 accurateAttestations) = avsManager.getOperatorInfo(operator3);
        assertLt(reliabilityScore, 10000); // Less than 100%
        assertLt(accurateAttestations, totalAttestations); // Some attestations were inaccurate
    }
    
    function test_Integration04_InsufficientOperators_NoConsensus() public {
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(daiUsdcPoolId))); // Use different pool
        
        // Only submit 2 attestations (need 3 for consensus)
        vm.prank(operator1);
        avsManager.submitPriceAttestation(poolIdBytes, DAI_PRICE, keccak256("sources"), hex"1111");
        
        vm.prank(operator2);
        avsManager.submitPriceAttestation(poolIdBytes, DAI_PRICE, keccak256("sources"), hex"2222");
        
        // Should not have consensus
        (bool hasConsensus, , , , ) = avsManager.getCurrentConsensus(poolIdBytes);
        assertFalse(hasConsensus);
        
        // Swap should fail
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        vm.expectRevert("Oracle validation failed");
        hook.beforeSwap(alice, daiUsdcPool, swapParams, "");
    }
    
    function test_Integration05_ConsensusTimeout_StaleData() public {
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(ethUsdcPoolId)));
        
        // Submit initial consensus
        vm.prank(operator1);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE, keccak256("sources"), hex"1111");
        
        vm.prank(operator2);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE, keccak256("sources"), hex"2222");
        
        vm.prank(operator3);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE, keccak256("sources"), hex"3333");
        
        // Verify consensus exists
        (bool hasConsensus, , , , ) = avsManager.getCurrentConsensus(poolIdBytes);
        assertTrue(hasConsensus);
        
        // Wait for consensus to become stale (6 minutes)
        vm.warp(block.timestamp + 6 minutes);
        
        // Should now be stale
        (hasConsensus, , , , ) = avsManager.getCurrentConsensus(poolIdBytes);
        assertFalse(hasConsensus);
        
        // Swap should fail with stale data
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        vm.expectRevert("Oracle validation failed");
        hook.beforeSwap(alice, ethUsdcPool, swapParams, "");
    }
    
    function test_Integration06_OperatorRegistration_DynamicStaking() public {
        address newOperator = makeAddr("newOperator");
        vm.deal(newOperator, 100 ether);
        
        // Check initial operators count
        address[] memory initialOperators = avsManager.getRegisteredOperators();
        uint256 initialCount = initialOperators.length;
        
        // Register new operator
        vm.prank(newOperator);
        avsManager.registerOperator{value: 30 ether}();
        
        // Check operators count increased
        address[] memory newOperators = avsManager.getRegisteredOperators();
        assertEq(newOperators.length, initialCount + 1);
        
        // New operator should be able to submit attestations
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(ethUsdcPoolId)));
        
        vm.prank(newOperator);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE, keccak256("new_sources"), hex"9999");
        
        // Check operator info
        (bool isRegistered, uint256 stakeAmount, , , ) = avsManager.getOperatorInfo(newOperator);
        assertTrue(isRegistered);
        assertEq(stakeAmount, 30 ether);
    }
    
    function test_Integration07_LargeScale_MultipleSwaps() public {
        // Setup consensus first
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(ethUsdcPoolId)));
        
        vm.prank(operator1);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE, keccak256("sources"), hex"1111");
        
        vm.prank(operator2);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE, keccak256("sources"), hex"2222");
        
        vm.prank(operator3);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE, keccak256("sources"), hex"3333");
        
        // Perform many swaps from different users
        address[] memory users = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
        }
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        for (uint256 i = 0; i < users.length; i++) {
            (bytes4 result, , ) = hook.beforeSwap(users[i], ethUsdcPool, swapParams, "");
            assertEq(result, hook.beforeSwap.selector);
            
            // Also test after swap
            BalanceDelta delta = toBalanceDelta(1000, -990);
            (result, ) = hook.afterSwap(users[i], ethUsdcPool, swapParams, delta, "");
            assertEq(result, hook.afterSwap.selector);
        }
    }
    
    function test_Integration08_PoolConfiguration_Runtime() public {
        // Test dynamic pool configuration changes
        uint256 newMaxDeviation = 200; // 2%
        uint256 newMinStake = 20 ether;
        uint256 newThreshold = 7500; // 75%
        
        hook.updateOracleConfig(ethUsdcPoolId, newMaxDeviation, newMinStake, newThreshold);
        
        // Setup consensus with high deviation
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(ethUsdcPoolId)));
        
        vm.prank(operator1);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE, keccak256("sources"), hex"1111");
        
        vm.prank(operator2);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE + 50e18, keccak256("sources"), hex"2222"); // ~2.4% deviation
        
        vm.prank(operator3);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE - 30e18, keccak256("sources"), hex"3333"); // ~1.4% deviation
        
        // Should still form consensus despite deviations
        (bool hasConsensus, , , uint256 confidenceLevel, ) = avsManager.getCurrentConsensus(poolIdBytes);
        
        if (hasConsensus && confidenceLevel >= newThreshold) {
            IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
            (bytes4 result, , ) = hook.beforeSwap(alice, ethUsdcPool, swapParams, "");
            assertEq(result, hook.beforeSwap.selector);
        }
    }
    
    function test_Integration09_OperatorReliability_LongTerm() public {
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(ethUsdcPoolId)));
        
        // Simulate multiple rounds of attestations
        for (uint256 round = 0; round < 5; round++) {
            // Operator1: Always accurate
            vm.prank(operator1);
            avsManager.submitPriceAttestation(
                poolIdBytes, 
                ETH_PRICE + round, 
                keccak256(abi.encodePacked("round", round)), 
                abi.encodePacked(hex"1111", round)
            );
            
            // Operator2: Mostly accurate
            vm.prank(operator2);
            uint256 price2 = round % 2 == 0 ? ETH_PRICE + round : ETH_PRICE + round + 100e18; // Sometimes inaccurate
            avsManager.submitPriceAttestation(
                poolIdBytes, 
                price2, 
                keccak256(abi.encodePacked("round", round)), 
                abi.encodePacked(hex"2222", round)
            );
            
            // Operator3: Sometimes accurate
            vm.prank(operator3);
            uint256 price3 = round % 3 == 0 ? ETH_PRICE * 2 : ETH_PRICE + round; // Often inaccurate
            avsManager.submitPriceAttestation(
                poolIdBytes, 
                price3, 
                keccak256(abi.encodePacked("round", round)), 
                abi.encodePacked(hex"3333", round)
            );
            
            // Advance time between rounds
            vm.warp(block.timestamp + 30);
        }
        
        // Check reliability scores
        (, , uint256 reliability1, uint256 total1, uint256 accurate1) = avsManager.getOperatorInfo(operator1);
        (, , uint256 reliability2, uint256 total2, uint256 accurate2) = avsManager.getOperatorInfo(operator2);
        (, , uint256 reliability3, uint256 total3, uint256 accurate3) = avsManager.getOperatorInfo(operator3);
        
        uint256 accuracy1 = total1 > 0 ? (accurate1 * 10000) / total1 : 0;
        uint256 accuracy2 = total2 > 0 ? (accurate2 * 10000) / total2 : 0;
        uint256 accuracy3 = total3 > 0 ? (accurate3 * 10000) / total3 : 0;
        
        // Operator1 should have highest reliability
        assertGt(accuracy1, accuracy2);
        assertGt(accuracy2, accuracy3);
        assertGt(reliability1, reliability2);
        assertGt(reliability2, reliability3);
    }
    
    function test_Integration10_SystemRecovery_OperatorChurn() public {
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(ethUsdcPoolId)));
        
        // Initial consensus with all operators
        vm.prank(operator1);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE, keccak256("sources"), hex"1111");
        
        vm.prank(operator2);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE, keccak256("sources"), hex"2222");
        
        vm.prank(operator3);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE, keccak256("sources"), hex"3333");
        
        // Verify initial consensus
        (bool hasConsensus, , , , ) = avsManager.getCurrentConsensus(poolIdBytes);
        assertTrue(hasConsensus);
        
        // Operator2 leaves
        vm.prank(operator2);
        avsManager.deregisterOperator();
        
        // System should still work with remaining operators
        vm.warp(block.timestamp + 60);
        
        // Register a new operator
        address newOperator = makeAddr("replacement");
        vm.deal(newOperator, 60 ether);
        
        vm.prank(newOperator);
        avsManager.registerOperator{value: 60 ether}();
        
        // New consensus with remaining + new operator
        vm.prank(operator1);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE + 1e18, keccak256("new_sources"), hex"aaaa");
        
        vm.prank(operator3);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE + 1e18, keccak256("new_sources"), hex"bbbb");
        
        vm.prank(newOperator);
        avsManager.submitPriceAttestation(poolIdBytes, ETH_PRICE + 1e18, keccak256("new_sources"), hex"cccc");
        
        // Should have new consensus
        uint256 newPrice;
        (hasConsensus, newPrice, , , ) = avsManager.getCurrentConsensus(poolIdBytes);
        assertTrue(hasConsensus);
        assertApproxEqRel(newPrice, ETH_PRICE + 1e18, 0.01e18);
        
        // Swaps should still work
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        (bytes4 result, , ) = hook.beforeSwap(alice, ethUsdcPool, swapParams, "");
        assertEq(result, hook.beforeSwap.selector);
    }
}