// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {AVSOracleHook} from "../../src/AVSOracleHook.sol";
import {MockPoolManager} from "../mocks/MockPoolManager.sol";
import {MockOracleAVS} from "../mocks/MockOracleAVS.sol";
import {TestUtils} from "../utils/TestUtils.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
import {BalanceDelta, toBalanceDelta} from "v4-core/types/BalanceDelta.sol";

contract AVSOracleHookTest is Test {
    using PoolIdLibrary for PoolKey;
    
    AVSOracleHook hook;
    MockPoolManager poolManager;
    MockOracleAVS oracleAVS;
    
    PoolKey poolKey;
    PoolId poolId;
    
    address alice = makeAddr("alice");
    address bob = makeAddr("bob");
    address charlie = makeAddr("charlie");
    
    uint256 constant DEFAULT_PRICE = 2105 * 1e18; // $2,105
    uint256 constant DEFAULT_STAKE = 100 ether;
    uint256 constant DEFAULT_CONFIDENCE = 8500; // 85%
    
    event PriceValidationRequested(
        PoolId indexed poolId,
        address indexed trader,
        uint256 swapAmount,
        uint256 expectedPrice
    );
    
    event ConsensusReached(
        PoolId indexed poolId,
        uint256 consensusPrice,
        uint256 totalStake,
        uint256 attestationCount,
        uint256 confidenceLevel
    );
    
    event SwapBlocked(
        PoolId indexed poolId,
        address indexed trader,
        uint256 requestedPrice,
        uint256 consensusPrice,
        string reason
    );
    
    function setUp() public {
        // Deploy mocks
        poolManager = new MockPoolManager();
        oracleAVS = new MockOracleAVS();
        
        // Deploy hook
        hook = new AVSOracleHook(IPoolManager(address(poolManager)), address(oracleAVS));
        
        // Create pool key for USDC/WETH
        poolKey = TestUtils.createUSDCWETHPoolKey(address(hook));
        poolId = poolKey.toId();
        
        // Set up mock AVS with default values
        oracleAVS.setMockConsensus(
            bytes32(uint256(PoolId.unwrap(poolId))),
            DEFAULT_PRICE,
            DEFAULT_STAKE,
            DEFAULT_CONFIDENCE,
            true
        );
    }
    
    /*//////////////////////////////////////////////////////////////
                            DEPLOYMENT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_Constructor() public {
        assertEq(address(hook.poolManager()), address(poolManager));
        assertEq(hook.oracleAVS(), address(oracleAVS));
    }
    
    function test_GetHookPermissions() public {
        Hooks.Permissions memory permissions = hook.getHookPermissions();
        
        assertTrue(permissions.beforeInitialize);
        assertTrue(permissions.beforeSwap);
        assertTrue(permissions.afterSwap);
        
        assertFalse(permissions.afterInitialize);
        assertFalse(permissions.beforeAddLiquidity);
        assertFalse(permissions.afterAddLiquidity);
        assertFalse(permissions.beforeRemoveLiquidity);
        assertFalse(permissions.afterRemoveLiquidity);
        assertFalse(permissions.beforeDonate);
        assertFalse(permissions.afterDonate);
    }
    
    /*//////////////////////////////////////////////////////////////
                        POOL INITIALIZATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_BeforeInitialize_MajorTokenPair() public {
        bytes4 result = hook.beforeInitialize(alice, poolKey, 0, "");
        
        assertEq(result, AVSOracleHook.beforeInitialize.selector);
        
        // Check oracle config was set
        (bool oracleEnabled, uint256 maxPriceDeviation, uint256 minStakeRequired, uint256 consensusThreshold, uint256 maxStaleness) = hook.poolConfigs(poolId);
        
        assertTrue(oracleEnabled);
        assertEq(maxPriceDeviation, hook.MAX_PRICE_DEVIATION());
        assertEq(minStakeRequired, 10 ether);
        assertEq(consensusThreshold, hook.DEFAULT_CONSENSUS_THRESHOLD());
        assertEq(maxStaleness, hook.MAX_PRICE_STALENESS());
        
        // Check consensus data was initialized
        (uint256 weightedPrice, uint256 totalStake, uint256 confidenceLevel, bool isValid) = hook.getConsensusData(poolId);
        
        assertEq(weightedPrice, 0);
        assertEq(totalStake, 0);
        assertEq(confidenceLevel, 0);
        assertFalse(isValid);
    }
    
    function test_BeforeInitialize_NonMajorTokenPair() public {
        // Create pool with non-major tokens
        PoolKey memory nonMajorPoolKey = TestUtils.createPoolKey(
            makeAddr("token0"),
            makeAddr("token1"),
            3000,
            60,
            address(hook)
        );
        
        bytes4 result = hook.beforeInitialize(alice, nonMajorPoolKey, 0, "");
        assertEq(result, AVSOracleHook.beforeInitialize.selector);
        
        // Oracle should not be enabled for non-major tokens
        PoolId nonMajorPoolId = nonMajorPoolKey.toId();
        (bool oracleEnabled,,,,) = hook.poolConfigs(nonMajorPoolId);
        assertFalse(oracleEnabled);
    }
    
    /*//////////////////////////////////////////////////////////////
                           SWAP VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_BeforeSwap_OracleDisabled() public {
        // Initialize pool first
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Disable oracle for this pool
        hook.enableOracleForPool(poolId, false);
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        (bytes4 result, , uint24 lpFeeOverride) = hook.beforeSwap(alice, poolKey, swapParams, "");
        
        assertEq(result, AVSOracleHook.beforeSwap.selector);
        assertEq(lpFeeOverride, 0);
    }
    
    function test_BeforeSwap_ValidConsensus() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Should emit PriceValidationRequested
        vm.expectEmit(true, true, false, false);
        emit PriceValidationRequested(poolId, alice, 1000, 0);
        
        // Should emit ConsensusReached
        vm.expectEmit(true, false, false, false);
        emit ConsensusReached(poolId, DEFAULT_PRICE, DEFAULT_STAKE, 0, DEFAULT_CONFIDENCE);
        
        (bytes4 result, , uint24 lpFeeOverride) = hook.beforeSwap(alice, poolKey, swapParams, "");
        
        assertEq(result, AVSOracleHook.beforeSwap.selector);
        assertEq(lpFeeOverride, 0);
    }
    
    function test_BeforeSwap_InsufficientStake() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Set low stake in mock AVS
        oracleAVS.simulateLowStake(bytes32(uint256(PoolId.unwrap(poolId))));
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        vm.expectRevert("Oracle validation failed");
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
    
    function test_BeforeSwap_LowConfidence() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Set low confidence in mock AVS
        oracleAVS.simulateLowConfidence(bytes32(uint256(PoolId.unwrap(poolId))));
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        vm.expectRevert("Oracle validation failed");
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
    
    function test_BeforeSwap_StaleData() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Simulate stale data
        oracleAVS.simulateStaleData(bytes32(uint256(PoolId.unwrap(poolId))));
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        vm.expectRevert("Oracle validation failed");
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
    
    function test_BeforeSwap_NoConsensus() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Simulate consensus failure
        oracleAVS.simulateConsensusFailure();
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        vm.expectRevert("Oracle validation failed");
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
    
    /*//////////////////////////////////////////////////////////////
                         AFTER SWAP TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_AfterSwap_Success() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        BalanceDelta delta = toBalanceDelta(1000, -900);
        
        (bytes4 result, int128 hookDelta) = hook.afterSwap(alice, poolKey, swapParams, delta, "");
        
        assertEq(result, AVSOracleHook.afterSwap.selector);
        assertEq(hookDelta, 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                        ORACLE CONFIGURATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_EnableOracleForPool() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Disable oracle
        hook.enableOracleForPool(poolId, false);
        (bool enabled,,,,) = hook.poolConfigs(poolId);
        assertFalse(enabled);
        
        // Re-enable oracle
        hook.enableOracleForPool(poolId, true);
        (enabled,,,,) = hook.poolConfigs(poolId);
        assertTrue(enabled);
    }
    
    function test_UpdateOracleConfig() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        uint256 newMaxDeviation = 1000; // 10%
        uint256 newMinStake = 50 ether;
        uint256 newThreshold = 7500; // 75%
        
        hook.updateOracleConfig(poolId, newMaxDeviation, newMinStake, newThreshold);
        
        (, uint256 maxPriceDeviation, uint256 minStakeRequired, uint256 consensusThreshold,) = hook.poolConfigs(poolId);
        
        assertEq(maxPriceDeviation, newMaxDeviation);
        assertEq(minStakeRequired, newMinStake);
        assertEq(consensusThreshold, newThreshold);
    }
    
    function test_GetConsensusData() public {
        // Initialize pool and trigger consensus
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        hook.beforeSwap(alice, poolKey, swapParams, "");
        
        (uint256 consensusPrice, uint256 totalStake, uint256 confidenceLevel, bool isValid) = hook.getConsensusData(poolId);
        
        assertEq(consensusPrice, DEFAULT_PRICE);
        assertEq(totalStake, DEFAULT_STAKE);
        assertEq(confidenceLevel, DEFAULT_CONFIDENCE);
        assertTrue(isValid);
    }
    
    /*//////////////////////////////////////////////////////////////
                         EDGE CASE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_MultipleSwapsInSequence() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Multiple successful swaps
        for (uint256 i = 0; i < 5; i++) {
            (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
            assertEq(result, AVSOracleHook.beforeSwap.selector);
            
            BalanceDelta delta = toBalanceDelta(1000, -900);
            (result, ) = hook.afterSwap(alice, poolKey, swapParams, delta, "");
            assertEq(result, AVSOracleHook.afterSwap.selector);
        }
    }
    
    function test_DifferentSwapAmounts() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        uint256[] memory amounts = new uint256[](4);
        amounts[0] = 100;
        amounts[1] = 1000;
        amounts[2] = 10000;
        amounts[3] = 100000;
        
        for (uint256 i = 0; i < amounts.length; i++) {
            IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(int256(amounts[i]));
            
            (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
            assertEq(result, AVSOracleHook.beforeSwap.selector);
        }
    }
    
    function test_ZeroAmountSwap() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(0);
        
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
        assertEq(result, AVSOracleHook.beforeSwap.selector);
    }
    
    /*//////////////////////////////////////////////////////////////
                          FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_SwapAmounts(uint256 amount) public {
        vm.assume(amount > 0 && amount < type(uint128).max);
        
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(int256(amount));
        
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
        assertEq(result, AVSOracleHook.beforeSwap.selector);
    }
    
    function testFuzz_OracleConfig(
        uint256 maxDeviation,
        uint256 minStake,
        uint256 threshold
    ) public {
        vm.assume(maxDeviation <= 10000); // Max 100%
        vm.assume(minStake >= 1 ether && minStake <= 1000 ether);
        vm.assume(threshold >= 5100 && threshold <= 10000); // 51% to 100%
        
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        hook.updateOracleConfig(poolId, maxDeviation, minStake, threshold);
        
        (, uint256 storedMaxDeviation, uint256 storedMinStake, uint256 storedThreshold,) = hook.poolConfigs(poolId);
        
        assertEq(storedMaxDeviation, maxDeviation);
        assertEq(storedMinStake, minStake);
        assertEq(storedThreshold, threshold);
    }
    
    /*//////////////////////////////////////////////////////////////
                         INTEGRATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_FullSwapFlow() public {
        // 1. Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // 2. Verify initial state
        (uint256 initialPrice, uint256 initialStake, uint256 initialConfidence, bool initialValid) = hook.getConsensusData(poolId);
        assertEq(initialPrice, 0);
        assertFalse(initialValid);
        
        // 3. Perform swap (triggers consensus)
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        vm.expectEmit(true, true, false, false);
        emit PriceValidationRequested(poolId, alice, 1000, 0);
        
        vm.expectEmit(true, false, false, false);
        emit ConsensusReached(poolId, DEFAULT_PRICE, DEFAULT_STAKE, 0, DEFAULT_CONFIDENCE);
        
        (bytes4 beforeResult, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
        assertEq(beforeResult, hook.beforeSwap.selector);
        
        // 4. Verify consensus was updated
        (uint256 finalPrice, uint256 finalStake, uint256 finalConfidence, bool finalValid) = hook.getConsensusData(poolId);
        assertEq(finalPrice, DEFAULT_PRICE);
        assertEq(finalStake, DEFAULT_STAKE);
        assertEq(finalConfidence, DEFAULT_CONFIDENCE);
        assertTrue(finalValid);
        
        // 5. Complete swap
        BalanceDelta delta = toBalanceDelta(1000, -900);
        (bytes4 afterResult, ) = hook.afterSwap(alice, poolKey, swapParams, delta, "");
        assertEq(afterResult, hook.afterSwap.selector);
    }
}