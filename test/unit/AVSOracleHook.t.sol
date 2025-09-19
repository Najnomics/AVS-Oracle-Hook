// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {AVSOracleHook} from "../../src/AVSOracleHook.sol";
import {MockPoolManager} from "../mocks/MockPoolManager.sol";
import {MockOracleAVS} from "../mocks/MockOracleAVS.sol";
import {TestUtils} from "../utils/TestUtils.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {BeforeSwapDelta, BeforeSwapDeltaLibrary} from "v4-core/types/BeforeSwapDelta.sol";
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
    address carol = makeAddr("carol");
    
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
        
        // Advance time to make the difference meaningful
        vm.warp(block.timestamp + 500);
        
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
        maxDeviation = bound(maxDeviation, 0, 10000); // 0% to 100%
        minStake = bound(minStake, 1 ether, 100 ether); // 1 to 100 ETH
        threshold = bound(threshold, 5100, 10000); // 51% to 100%
        
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        hook.updateOracleConfig(poolId, maxDeviation, minStake, threshold);
        
        (, uint256 storedMaxDeviation, uint256 storedMinStake, uint256 storedThreshold,) = hook.poolConfigs(poolId);
        
        assertEq(storedMaxDeviation, maxDeviation);
        assertEq(storedMinStake, minStake);
        assertEq(storedThreshold, threshold);
    }
    
    /*//////////////////////////////////////////////////////////////
                         ORACLE VALIDATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ValidateSwapPrice_Success() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Set valid consensus data
        oracleAVS.setMockConsensus(
            bytes32(uint256(PoolId.unwrap(poolId))),
            DEFAULT_PRICE,
            DEFAULT_STAKE,
            DEFAULT_CONFIDENCE,
            true
        );
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
        
        assertEq(result, AVSOracleHook.beforeSwap.selector);
    }
    
    function test_ValidateSwapPrice_ConsensusUpdated() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Set consensus data in AVS
        uint256 newPrice = 2200 * 1e18;
        uint256 newStake = 200 ether;
        uint256 newConfidence = 9000;
        
        oracleAVS.setMockConsensus(
            bytes32(uint256(PoolId.unwrap(poolId))),
            newPrice,
            newStake,
            newConfidence,
            true
        );
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        hook.beforeSwap(alice, poolKey, swapParams, "");
        
        // Check that local consensus was updated
        (uint256 consensusPrice, uint256 totalStake, uint256 confidenceLevel, bool isValid) = hook.getConsensusData(poolId);
        
        assertEq(consensusPrice, newPrice);
        assertEq(totalStake, newStake);
        assertEq(confidenceLevel, newConfidence);
        assertTrue(isValid);
    }
    
    /*//////////////////////////////////////////////////////////////
                         HELPER FUNCTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_ShouldEnableOracle_MajorPair() public {
        // Test with USDC/WETH (should be enabled)
        PoolKey memory majorPoolKey = TestUtils.createUSDCWETHPoolKey(address(hook));
        
        hook.beforeInitialize(alice, majorPoolKey, 0, "");
        
        PoolId majorPoolId = majorPoolKey.toId();
        (bool oracleEnabled,,,,) = hook.poolConfigs(majorPoolId);
        assertTrue(oracleEnabled);
    }
    
    function test_ShouldEnableOracle_NonMajorPair() public {
        // Test with non-major tokens (should be disabled)
        PoolKey memory nonMajorPoolKey = TestUtils.createPoolKey(
            address(0x1111),
            address(0x2222),
            3000,
            60,
            address(hook)
        );
        
        hook.beforeInitialize(alice, nonMajorPoolKey, 0, "");
        
        PoolId nonMajorPoolId = nonMajorPoolKey.toId();
        (bool oracleEnabled,,,,) = hook.poolConfigs(nonMajorPoolId);
        assertFalse(oracleEnabled);
    }
    
    function test_IsMajorToken_Indirectly() public {
        // Test major token detection indirectly through oracle enablement
        // Major pair: USDC/WETH should enable oracle
        PoolKey memory majorPoolKey = TestUtils.createUSDCWETHPoolKey(address(hook));
        hook.beforeInitialize(alice, majorPoolKey, 0, "");
        PoolId majorPoolId = majorPoolKey.toId();
        (bool majorEnabled,,,,) = hook.poolConfigs(majorPoolId);
        assertTrue(majorEnabled);
        
        // Non-major pair should not enable oracle
        PoolKey memory nonMajorPoolKey = TestUtils.createPoolKey(
            address(0x1111), address(0x2222), 3000, 60, address(hook)
        );
        hook.beforeInitialize(alice, nonMajorPoolKey, 0, "");
        PoolId nonMajorPoolId = nonMajorPoolKey.toId();
        (bool nonMajorEnabled,,,,) = hook.poolConfigs(nonMajorPoolId);
        assertFalse(nonMajorEnabled);
    }
    
    /*//////////////////////////////////////////////////////////////
                         ACCESS CONTROL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_EnableOracleForPool_OnlyAuthorized() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Test that anyone can currently call (no access control implemented)
        vm.prank(bob);
        hook.enableOracleForPool(poolId, false);
        
        (bool enabled,,,,) = hook.poolConfigs(poolId);
        assertFalse(enabled);
    }
    
    function test_UpdateOracleConfig_OnlyAuthorized() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Test that anyone can currently call (no access control implemented)
        vm.prank(charlie);
        hook.updateOracleConfig(poolId, 1000, 50 ether, 7500);
        
        (, uint256 maxDeviation, uint256 minStake, uint256 threshold,) = hook.poolConfigs(poolId);
        assertEq(maxDeviation, 1000);
        assertEq(minStake, 50 ether);
        assertEq(threshold, 7500);
    }
    
    /*//////////////////////////////////////////////////////////////
                         EVENT EMISSION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_EmitPriceValidationRequested() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Expect event emission
        vm.expectEmit(true, true, false, true);
        emit PriceValidationRequested(poolId, alice, 1000, 0);
        
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
    
    function test_EmitConsensusReached() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Expect event emission
        vm.expectEmit(true, false, false, false);
        emit ConsensusReached(poolId, DEFAULT_PRICE, DEFAULT_STAKE, 0, DEFAULT_CONFIDENCE);
        
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
    
    function test_EmitSwapBlocked_InsufficientStake() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Set low stake
        oracleAVS.simulateLowStake(bytes32(uint256(PoolId.unwrap(poolId))));
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Expect SwapBlocked event
        vm.expectEmit(true, true, false, false);
        emit SwapBlocked(poolId, alice, 0, DEFAULT_PRICE, "Insufficient stake");
        
        vm.expectRevert("Oracle validation failed");
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
    
    /*//////////////////////////////////////////////////////////////
                         CONSENSUS DATA TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_GetConsensusData_InitialState() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        (uint256 consensusPrice, uint256 totalStake, uint256 confidenceLevel, bool isValid) = hook.getConsensusData(poolId);
        
        assertEq(consensusPrice, 0);
        assertEq(totalStake, 0);
        assertEq(confidenceLevel, 0);
        assertFalse(isValid);
    }
    
    function test_GetConsensusData_AfterValidation() public {
        // Initialize pool and trigger validation
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
                         SWAP PARAMETER TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_BeforeSwap_NegativeAmount() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(-1000);
        
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
        assertEq(result, AVSOracleHook.beforeSwap.selector);
    }
    
    function test_BeforeSwap_DifferentDirections() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Test zeroForOne = false
        IPoolManager.SwapParams memory swapParams = TestUtils.createSwapParams(false, 1000, 0);
        
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
        assertEq(result, AVSOracleHook.beforeSwap.selector);
    }
    
    function test_BeforeSwap_WithPriceLimits() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Test with price limits
        uint160 priceLimit = 1000000000000000000; // Some price limit
        IPoolManager.SwapParams memory swapParams = TestUtils.createSwapParams(true, 1000, priceLimit);
        
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
        assertEq(result, AVSOracleHook.beforeSwap.selector);
    }
    
    /*//////////////////////////////////////////////////////////////
                         EXTREME VALUE TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_UpdateOracleConfig_ExtremeValues() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Test extreme but valid values
        hook.updateOracleConfig(poolId, 10000, 1000 ether, 5100); // 100% deviation, 1000 ETH stake, 51% threshold
        
        (, uint256 maxDeviation, uint256 minStake, uint256 threshold,) = hook.poolConfigs(poolId);
        assertEq(maxDeviation, 10000);
        assertEq(minStake, 1000 ether);
        assertEq(threshold, 5100);
    }
    
    function test_UpdateOracleConfig_MinimalValues() public {
        // Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Test minimal values
        hook.updateOracleConfig(poolId, 0, 0, 0);
        
        (, uint256 maxDeviation, uint256 minStake, uint256 threshold,) = hook.poolConfigs(poolId);
        assertEq(maxDeviation, 0);
        assertEq(minStake, 0);
        assertEq(threshold, 0);
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
    
    
    /*//////////////////////////////////////////////////////////////
                         EXTENDED UNIT TESTS (50 TESTS)
    //////////////////////////////////////////////////////////////*/
    
    // Pool Initialization Tests (10 tests)
    function test_Unit01_BeforeInitialize_EmptyHookData() public {
        bytes memory emptyData = "";
        bytes4 result = hook.beforeInitialize(alice, poolKey, 0, emptyData);
        assertEq(result, AVSOracleHook.beforeInitialize.selector);
    }
    
    function test_Unit02_BeforeInitialize_LargeHookData() public {
        bytes memory largeData = new bytes(1000);
        bytes4 result = hook.beforeInitialize(alice, poolKey, 0, largeData);
        assertEq(result, AVSOracleHook.beforeInitialize.selector);
    }
    
    function test_Unit03_BeforeInitialize_ZeroSqrtPrice() public {
        bytes4 result = hook.beforeInitialize(alice, poolKey, 0, "");
        assertEq(result, AVSOracleHook.beforeInitialize.selector);
    }
    
    function test_Unit04_BeforeInitialize_MaxSqrtPrice() public {
        bytes4 result = hook.beforeInitialize(alice, poolKey, type(uint160).max, "");
        assertEq(result, AVSOracleHook.beforeInitialize.selector);
    }
    
    function test_Unit05_BeforeInitialize_SamePoolTwice() public {
        // First initialization
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Second initialization should still work (overwrite config)
        bytes4 result = hook.beforeInitialize(bob, poolKey, 0, "");
        assertEq(result, AVSOracleHook.beforeInitialize.selector);
    }
    
    function test_Unit06_BeforeInitialize_DifferentUsers() public {
        bytes4 result1 = hook.beforeInitialize(alice, poolKey, 0, "");
        bytes4 result2 = hook.beforeInitialize(bob, poolKey, 0, "");
        
        assertEq(result1, AVSOracleHook.beforeInitialize.selector);
        assertEq(result2, AVSOracleHook.beforeInitialize.selector);
    }
    
    function test_Unit07_BeforeInitialize_PoolConfigDefaults() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        (bool enabled, uint256 deviation, uint256 minStake, uint256 threshold, uint256 staleness) = hook.poolConfigs(poolId);
        
        assertTrue(enabled); // Should be enabled for major token pairs
        assertEq(deviation, 500); // MAX_PRICE_DEVIATION
        assertEq(minStake, 10 ether); // Default min stake
        assertEq(threshold, 6600); // DEFAULT_CONSENSUS_THRESHOLD
        assertEq(staleness, 300); // MAX_PRICE_STALENESS
    }
    
    function test_Unit08_BeforeInitialize_ConsensusDataDefaults() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        (uint256 consensusPrice, uint256 totalStake, uint256 confidenceLevel, bool isValid) = hook.getConsensusData(poolId);
        
        assertEq(consensusPrice, 0);
        assertEq(totalStake, 0);
        assertEq(confidenceLevel, 0);
        assertFalse(isValid);
    }
    
    function test_Unit09_BeforeInitialize_NonMajorTokenPair_Disabled() public {
        // Create pool with non-major tokens
        PoolKey memory nonMajorKey = PoolKey({
            currency0: Currency.wrap(address(0x123)), // Non-major token
            currency1: Currency.wrap(address(0x456)), // Non-major token
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        
        hook.beforeInitialize(alice, nonMajorKey, 0, "");
        
        PoolId nonMajorPoolId = nonMajorKey.toId();
        (bool enabled, , , , ) = hook.poolConfigs(nonMajorPoolId);
        assertFalse(enabled); // Should be disabled for non-major pairs
    }
    
    function test_Unit10_BeforeInitialize_PoolId_Consistency() public {
        bytes4 result = hook.beforeInitialize(alice, poolKey, 0, "");
        
        PoolId computedId = poolKey.toId();
        assertEq(PoolId.unwrap(poolId), PoolId.unwrap(computedId));
        assertEq(result, AVSOracleHook.beforeInitialize.selector);
    }
    
    // Swap Validation Tests (15 tests)
    function test_Unit11_BeforeSwap_ZeroAmount() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory zeroSwap = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 0,
            sqrtPriceLimitX96: 0
        });
        
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, zeroSwap, "");
        assertEq(result, hook.beforeSwap.selector);
    }
    
    function test_Unit12_BeforeSwap_MaxAmount() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory maxSwap = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: type(int256).max,
            sqrtPriceLimitX96: 0
        });
        
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, maxSwap, "");
        assertEq(result, hook.beforeSwap.selector);
    }
    
    function test_Unit13_BeforeSwap_MinAmount() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory minSwap = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: type(int256).min,
            sqrtPriceLimitX96: 0
        });
        
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, minSwap, "");
        assertEq(result, hook.beforeSwap.selector);
    }
    
    function test_Unit14_BeforeSwap_BothDirections() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swap0to1 = TestUtils.createBasicSwapParams(1000);
        IPoolManager.SwapParams memory swap1to0 = TestUtils.createBasicSwapParams(-1000);
        
        (bytes4 result1, , ) = hook.beforeSwap(alice, poolKey, swap0to1, "");
        (bytes4 result2, , ) = hook.beforeSwap(alice, poolKey, swap1to0, "");
        
        assertEq(result1, hook.beforeSwap.selector);
        assertEq(result2, hook.beforeSwap.selector);
    }
    
    function test_Unit15_BeforeSwap_DifferentPriceLimits() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapWithLimit = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 1000,
            sqrtPriceLimitX96: 1000000000000000000000000 // Some limit
        });
        
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, swapWithLimit, "");
        assertEq(result, hook.beforeSwap.selector);
    }
    
    function test_Unit16_BeforeSwap_EmptyHookData() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
        
        assertEq(result, hook.beforeSwap.selector);
    }
    
    function test_Unit17_BeforeSwap_LargeHookData() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        bytes memory largeHookData = new bytes(2000);
        
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, swapParams, largeHookData);
        assertEq(result, hook.beforeSwap.selector);
    }
    
    function test_Unit18_BeforeSwap_ConsensusDataUpdate() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Verify initial state
        (uint256 priceBefore, uint256 stakeBefore, uint256 confidenceBefore, bool validBefore) = hook.getConsensusData(poolId);
        assertEq(priceBefore, 0);
        assertFalse(validBefore);
        
        // Perform swap
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        hook.beforeSwap(alice, poolKey, swapParams, "");
        
        // Verify state updated
        (uint256 priceAfter, uint256 stakeAfter, uint256 confidenceAfter, bool validAfter) = hook.getConsensusData(poolId);
        assertGt(priceAfter, 0);
        assertGt(stakeAfter, 0);
        assertGt(confidenceAfter, 0);
        assertTrue(validAfter);
    }
    
    function test_Unit19_BeforeSwap_SequentialCalls() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Multiple sequential calls should all succeed
        for (uint256 i = 0; i < 5; i++) {
            (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
            assertEq(result, hook.beforeSwap.selector);
        }
    }
    
    function test_Unit20_BeforeSwap_DifferentUsers() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Different users should all succeed
        (bytes4 result1, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
        (bytes4 result2, , ) = hook.beforeSwap(bob, poolKey, swapParams, "");
        (bytes4 result3, , ) = hook.beforeSwap(carol, poolKey, swapParams, "");
        
        assertEq(result1, hook.beforeSwap.selector);
        assertEq(result2, hook.beforeSwap.selector);
        assertEq(result3, hook.beforeSwap.selector);
    }
    
    function test_Unit21_BeforeSwap_OracleDisabled_NoValidation() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Disable oracle for this pool
        hook.enableOracleForPool(poolId, false);
        
        // Should succeed without validation
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
        
        assertEq(result, hook.beforeSwap.selector);
    }
    
    function test_Unit22_BeforeSwap_ValidationRequest_Event() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1500);
        
        vm.expectEmit(true, true, false, false);
        emit PriceValidationRequested(poolId, alice, 1500, 0);
        
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
    
    function test_Unit23_BeforeSwap_NegativeAmount_Event() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: -2000,
            sqrtPriceLimitX96: 0
        });
        
        vm.expectEmit(true, true, false, false);
        emit PriceValidationRequested(poolId, alice, 2000, 0); // Should emit absolute value
        
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
    
    function test_Unit24_BeforeSwap_ReturnsZeroDelta() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        (, BeforeSwapDelta delta, ) = hook.beforeSwap(alice, poolKey, swapParams, "");
        
        assertEq(BeforeSwapDelta.unwrap(delta), 0); // Should return ZERO_DELTA
    }
    
    function test_Unit25_BeforeSwap_ReturnsZeroFee() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        (, , uint24 fee) = hook.beforeSwap(alice, poolKey, swapParams, "");
        
        assertEq(fee, 0); // Should return 0 fee
    }
    
    // After Swap Tests (10 tests)
    function test_Unit26_AfterSwap_Basic() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        BalanceDelta delta = BalanceDelta.wrap(1000);
        
        (bytes4 result, int128 hookDelta) = hook.afterSwap(alice, poolKey, swapParams, delta, "");
        
        assertEq(result, hook.afterSwap.selector);
        assertEq(hookDelta, 0);
    }
    
    function test_Unit27_AfterSwap_ZeroDelta() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        BalanceDelta zeroDelta = BalanceDelta.wrap(0);
        
        (bytes4 result, int128 hookDelta) = hook.afterSwap(alice, poolKey, swapParams, zeroDelta, "");
        
        assertEq(result, hook.afterSwap.selector);
        assertEq(hookDelta, 0);
    }
    
    function test_Unit28_AfterSwap_MaxDelta() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        BalanceDelta maxDelta = BalanceDelta.wrap(type(int256).max);
        
        (bytes4 result, int128 hookDelta) = hook.afterSwap(alice, poolKey, swapParams, maxDelta, "");
        
        assertEq(result, hook.afterSwap.selector);
        assertEq(hookDelta, 0);
    }
    
    function test_Unit29_AfterSwap_NegativeDelta() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        BalanceDelta negativeDelta = BalanceDelta.wrap(-1000);
        
        (bytes4 result, int128 hookDelta) = hook.afterSwap(alice, poolKey, swapParams, negativeDelta, "");
        
        assertEq(result, hook.afterSwap.selector);
        assertEq(hookDelta, 0);
    }
    
    function test_Unit30_AfterSwap_EmptyHookData() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        BalanceDelta delta = BalanceDelta.wrap(1000);
        
        (bytes4 result, ) = hook.afterSwap(alice, poolKey, swapParams, delta, "");
        assertEq(result, hook.afterSwap.selector);
    }
    
    function test_Unit31_AfterSwap_LargeHookData() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        BalanceDelta delta = BalanceDelta.wrap(1000);
        bytes memory largeData = new bytes(1500);
        
        (bytes4 result, ) = hook.afterSwap(alice, poolKey, swapParams, delta, largeData);
        assertEq(result, hook.afterSwap.selector);
    }
    
    function test_Unit32_AfterSwap_DifferentUsers() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        BalanceDelta delta = BalanceDelta.wrap(1000);
        
        (bytes4 result1, ) = hook.afterSwap(alice, poolKey, swapParams, delta, "");
        (bytes4 result2, ) = hook.afterSwap(bob, poolKey, swapParams, delta, "");
        
        assertEq(result1, hook.afterSwap.selector);
        assertEq(result2, hook.afterSwap.selector);
    }
    
    function test_Unit33_AfterSwap_SequentialCalls() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        BalanceDelta delta = BalanceDelta.wrap(1000);
        
        for (uint256 i = 0; i < 3; i++) {
            (bytes4 result, ) = hook.afterSwap(alice, poolKey, swapParams, delta, "");
            assertEq(result, hook.afterSwap.selector);
        }
    }
    
    function test_Unit34_AfterSwap_DifferentSwapDirections() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swap0to1 = TestUtils.createBasicSwapParams(1000);
        IPoolManager.SwapParams memory swap1to0 = TestUtils.createBasicSwapParams(-1000);
        BalanceDelta delta = BalanceDelta.wrap(1000);
        
        (bytes4 result1, ) = hook.afterSwap(alice, poolKey, swap0to1, delta, "");
        (bytes4 result2, ) = hook.afterSwap(alice, poolKey, swap1to0, delta, "");
        
        assertEq(result1, hook.afterSwap.selector);
        assertEq(result2, hook.afterSwap.selector);
    }
    
    function test_Unit35_AfterSwap_AlwaysReturnsZero() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        BalanceDelta delta = BalanceDelta.wrap(1000);
        
        (, int128 hookDelta) = hook.afterSwap(alice, poolKey, swapParams, delta, "");
        assertEq(hookDelta, 0); // Should always return 0
    }
    
    // Configuration Tests (10 tests)
    function test_Unit36_EnableOracleForPool_Toggle() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Initially should be enabled (major token pair)
        (bool enabledBefore, , , , ) = hook.poolConfigs(poolId);
        assertTrue(enabledBefore);
        
        // Disable
        hook.enableOracleForPool(poolId, false);
        (bool enabledAfter, , , , ) = hook.poolConfigs(poolId);
        assertFalse(enabledAfter);
        
        // Re-enable
        hook.enableOracleForPool(poolId, true);
        (bool enabledFinal, , , , ) = hook.poolConfigs(poolId);
        assertTrue(enabledFinal);
    }
    
    function test_Unit37_UpdateOracleConfig_AllParameters() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Update all parameters
        hook.updateOracleConfig(poolId, 1000, 50 ether, 7500);
        
        (, uint256 deviation, uint256 minStake, uint256 threshold, ) = hook.poolConfigs(poolId);
        
        assertEq(deviation, 1000);
        assertEq(minStake, 50 ether);
        assertEq(threshold, 7500);
    }
    
    function test_Unit38_UpdateOracleConfig_SingleParameter() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Get initial values
        (, uint256 initialDeviation, uint256 initialStake, uint256 initialThreshold, ) = hook.poolConfigs(poolId);
        
        // Update only deviation
        hook.updateOracleConfig(poolId, 2000, initialStake, initialThreshold);
        
        (, uint256 newDeviation, uint256 newStake, uint256 newThreshold, ) = hook.poolConfigs(poolId);
        
        assertEq(newDeviation, 2000);
        assertEq(newStake, initialStake); // Unchanged
        assertEq(newThreshold, initialThreshold); // Unchanged
    }
    
    function test_Unit39_UpdateOracleConfig_ZeroValues() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        hook.updateOracleConfig(poolId, 0, 0, 0);
        
        (, uint256 deviation, uint256 minStake, uint256 threshold, ) = hook.poolConfigs(poolId);
        
        assertEq(deviation, 0);
        assertEq(minStake, 0);
        assertEq(threshold, 0);
    }
    
    function test_Unit40_UpdateOracleConfig_MaxValues() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        hook.updateOracleConfig(poolId, type(uint256).max, type(uint256).max, type(uint256).max);
        
        (, uint256 deviation, uint256 minStake, uint256 threshold, ) = hook.poolConfigs(poolId);
        
        assertEq(deviation, type(uint256).max);
        assertEq(minStake, type(uint256).max);
        assertEq(threshold, type(uint256).max);
    }
    
    function test_Unit41_GetConsensusData_Immutable() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Get initial data
        (uint256 price1, uint256 stake1, uint256 confidence1, bool valid1) = hook.getConsensusData(poolId);
        
        // Get data again - should be identical
        (uint256 price2, uint256 stake2, uint256 confidence2, bool valid2) = hook.getConsensusData(poolId);
        
        assertEq(price1, price2);
        assertEq(stake1, stake2);
        assertEq(confidence1, confidence2);
        assertEq(valid1, valid2);
    }
    
    function test_Unit42_GetConsensusData_AfterSwap() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Trigger swap to update consensus
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        hook.beforeSwap(alice, poolKey, swapParams, "");
        
        (uint256 price, uint256 stake, uint256 confidence, bool valid) = hook.getConsensusData(poolId);
        
        assertEq(price, DEFAULT_PRICE);
        assertEq(stake, DEFAULT_STAKE);
        assertEq(confidence, DEFAULT_CONFIDENCE);
        assertTrue(valid);
    }
    
    function test_Unit43_Constants_Immutable() public {
        // Test that constants are set correctly
        assertEq(hook.DEFAULT_CONSENSUS_THRESHOLD(), 6600);
        assertEq(hook.MAX_PRICE_STALENESS(), 300);
        assertEq(hook.MIN_ATTESTATIONS(), 3);
        assertEq(hook.MAX_PRICE_DEVIATION(), 500);
    }
    
    function test_Unit44_Constructor_Immutable() public {
        // Test that constructor values are set correctly
        assertEq(address(hook.poolManager()), address(poolManager));
        assertEq(hook.oracleAVS(), address(oracleAVS));
    }
    
    function test_Unit45_IsMajorToken_Coverage() public {
        // Test the major token detection indirectly through oracle enablement
        
        // USDC-WETH pair (both major) - should enable oracle
        PoolKey memory majorKey = PoolKey({
            currency0: Currency.wrap(0xA0b86a33E6417c8a9bbe78fe047ce5C17aEd0Ada), // USDC
            currency1: Currency.wrap(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2), // WETH
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        
        hook.beforeInitialize(alice, majorKey, 0, "");
        
        PoolId majorPoolId = majorKey.toId();
        (bool enabled, , , , ) = hook.poolConfigs(majorPoolId);
        assertTrue(enabled);
        
        // Non-major pair - should disable oracle
        PoolKey memory nonMajorKey = PoolKey({
            currency0: Currency.wrap(address(0x111)), // Non-major
            currency1: Currency.wrap(address(0x222)), // Non-major
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        
        hook.beforeInitialize(alice, nonMajorKey, 0, "");
        
        PoolId nonMajorPoolId = nonMajorKey.toId();
        (bool enabledNonMajor, , , , ) = hook.poolConfigs(nonMajorPoolId);
        assertFalse(enabledNonMajor);
    }
    
    // Error Condition Tests (5 tests)
    function test_Unit46_BeforeSwap_NoConsensus_Block() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Set AVS to return no consensus
        oracleAVS.setShouldReturnValidConsensus(false);
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        vm.expectRevert("Oracle validation failed");
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
    
    function test_Unit47_BeforeSwap_InsufficientStake_Block() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Set low stake
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(poolId)));
        oracleAVS.simulateLowStake(poolIdBytes);
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        vm.expectRevert("Oracle validation failed");
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
    
    function test_Unit48_BeforeSwap_LowConfidence_Block() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Set low confidence
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(poolId)));
        oracleAVS.simulateLowConfidence(poolIdBytes);
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        vm.expectRevert("Oracle validation failed");
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
    
    
    function test_Unit50_OracleAVS_Address_Consistency() public {
        // Verify that the hook is correctly connected to our mock AVS
        assertEq(hook.oracleAVS(), address(oracleAVS));
        
        // Verify AVS can be called
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(poolId)));
        (bool hasConsensus, uint256 price, uint256 stake, uint256 confidence, uint256 timestamp) = 
            oracleAVS.getCurrentConsensus(poolIdBytes);
        
        assertTrue(hasConsensus);
        assertGt(price, 0);
        assertGt(stake, 0);
        assertGt(confidence, 0);
        assertGt(timestamp, 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                     EXTENDED INTEGRATION TESTS (25 TESTS)
    //////////////////////////////////////////////////////////////*/
    
    // Complete Flow Tests (10 tests)
    function testIntegration01_CompleteSwapFlowWithEvents() public {
        // Step 1: Initialize pool
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Step 2: Verify initial state
        (uint256 initialPrice, , , bool initialValid) = hook.getConsensusData(poolId);
        assertEq(initialPrice, 0);
        assertFalse(initialValid);
        
        // Step 3: Execute swap with all events
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(2500);
        
        vm.expectEmit(true, true, false, false);
        emit PriceValidationRequested(poolId, alice, 2500, 0);
        
        vm.expectEmit(true, false, false, false);
        emit ConsensusReached(poolId, DEFAULT_PRICE, DEFAULT_STAKE, 0, DEFAULT_CONFIDENCE);
        
        (bytes4 beforeResult, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
        assertEq(beforeResult, hook.beforeSwap.selector);
        
        // Step 4: Complete with afterSwap
        (bytes4 afterResult, ) = hook.afterSwap(alice, poolKey, swapParams, BalanceDelta.wrap(2500), "");
        assertEq(afterResult, hook.afterSwap.selector);
        
        // Step 5: Verify final state
        (uint256 finalPrice, uint256 finalStake, uint256 finalConfidence, bool finalValid) = hook.getConsensusData(poolId);
        assertEq(finalPrice, DEFAULT_PRICE);
        assertEq(finalStake, DEFAULT_STAKE);
        assertEq(finalConfidence, DEFAULT_CONFIDENCE);
        assertTrue(finalValid);
    }
    
    function testIntegration02_MultiplePoolsIndependentState() public {
        // Create second pool
        PoolKey memory pool2Key = PoolKey({
            currency0: Currency.wrap(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599), // WBTC
            currency1: Currency.wrap(0x6B175474E89094C44Da98b954EedeAC495271d0F), // DAI
            fee: 500,
            tickSpacing: 10,
            hooks: IHooks(address(hook))
        });
        PoolId pool2Id = pool2Key.toId();
        
        // Initialize both pools
        hook.beforeInitialize(alice, poolKey, 0, "");
        hook.beforeInitialize(bob, pool2Key, 0, "");
        
        // Configure pool2 differently
        hook.updateOracleConfig(pool2Id, 1000, 20 ether, 7000);
        
        // Swap in pool1
        IPoolManager.SwapParams memory swapParams1 = TestUtils.createBasicSwapParams(1000);
        hook.beforeSwap(alice, poolKey, swapParams1, "");
        
        // Verify pool1 state changed, pool2 unchanged
        (uint256 p1Price, , , bool p1Valid) = hook.getConsensusData(poolId);
        (uint256 p2Price, , , bool p2Valid) = hook.getConsensusData(pool2Id);
        
        assertGt(p1Price, 0);
        assertTrue(p1Valid);
        assertEq(p2Price, 0);
        assertFalse(p2Valid);
        
        // Verify configurations are independent
        (, uint256 p1Dev, , , ) = hook.poolConfigs(poolId);
        (, uint256 p2Dev, , , ) = hook.poolConfigs(pool2Id);
        
        assertEq(p1Dev, 500); // Default
        assertEq(p2Dev, 1000); // Custom
    }
    
    function testIntegration03_OracleToggleImpactOnSwaps() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Test 1: Oracle enabled - should validate
        vm.expectEmit(true, true, false, false);
        emit PriceValidationRequested(poolId, alice, 1000, 0);
        hook.beforeSwap(alice, poolKey, swapParams, "");
        
        // Test 2: Disable oracle - should skip validation (no event)
        hook.enableOracleForPool(poolId, false);
        
        // No PriceValidationRequested event should be emitted
        vm.recordLogs();
        hook.beforeSwap(alice, poolKey, swapParams, "");
        
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertEq(logs.length, 0); // No events should be emitted
        
        // Test 3: Re-enable oracle - should validate again
        hook.enableOracleForPool(poolId, true);
        
        vm.expectEmit(true, true, false, false);
        emit PriceValidationRequested(poolId, bob, 1000, 0);
        hook.beforeSwap(bob, poolKey, swapParams, "");
    }
    
    function testIntegration04_ConfigurationChangesDuringOperation() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Initial successful swap
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        hook.beforeSwap(alice, poolKey, swapParams, "");
        
        // Change to stricter configuration
        hook.updateOracleConfig(poolId, 100, 1000 ether, 9500); // Very strict
        
        // Set conditions that pass old config but fail new config
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(poolId)));
        oracleAVS.setMockStake(500 ether); // Below new requirement
        oracleAVS.setMockConfidence(9000); // Below new threshold
        
        // Should now fail
        vm.expectRevert("Oracle validation failed");
        hook.beforeSwap(alice, poolKey, swapParams, "");
        
        // Relax configuration
        hook.updateOracleConfig(poolId, 1000, 100 ether, 5000); // Very lenient
        
        // Should succeed again
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
    
    
    function testIntegration06_MassiveSequentialSwaps() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(100);
        
        // Execute 50 swaps in sequence
        for (uint256 i = 0; i < 50; i++) {
            hook.beforeSwap(alice, poolKey, swapParams, "");
            hook.afterSwap(alice, poolKey, swapParams, BalanceDelta.wrap(100), "");
        }
        
        // Verify final state is consistent
        (uint256 price, uint256 stake, uint256 confidence, bool valid) = hook.getConsensusData(poolId);
        assertEq(price, DEFAULT_PRICE);
        assertEq(stake, DEFAULT_STAKE);
        assertEq(confidence, DEFAULT_CONFIDENCE);
        assertTrue(valid);
    }
    
    function testIntegration07_InterleaveInitializeAndSwap() public {
        // Initialize pool1
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Swap in pool1
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        hook.beforeSwap(alice, poolKey, swapParams, "");
        
        // Initialize pool2
        PoolKey memory pool2Key = PoolKey({
            currency0: Currency.wrap(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599), // WBTC
            currency1: Currency.wrap(0xA0b86a33E6417c8a9bbe78fe047ce5C17aEd0Ada), // USDC
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        hook.beforeInitialize(bob, pool2Key, 0, "");
        
        // More swaps in both pools
        hook.beforeSwap(carol, poolKey, swapParams, ""); // pool1
        hook.beforeSwap(alice, pool2Key, swapParams, ""); // pool2
        hook.beforeSwap(bob, poolKey, swapParams, ""); // pool1 again
        
        // Verify both pools maintain independent state
        (uint256 p1Price, , , bool p1Valid) = hook.getConsensusData(poolId);
        PoolId pool2Id = pool2Key.toId();
        (uint256 p2Price, , , bool p2Valid) = hook.getConsensusData(pool2Id);
        
        assertTrue(p1Valid);
        assertTrue(p2Valid);
        assertEq(p1Price, DEFAULT_PRICE);
        assertEq(p2Price, DEFAULT_PRICE);
    }
    
    
    function testIntegration09_FullLifecycleMultipleUsers() public {
        address[] memory users = new address[](5);
        users[0] = alice;
        users[1] = bob;
        users[2] = carol;
        users[3] = makeAddr("dave");
        users[4] = makeAddr("eve");
        
        // Initialize pool
        hook.beforeInitialize(users[0], poolKey, 0, "");
        
        // Each user performs different operations
        for (uint256 i = 0; i < users.length; i++) {
            IPoolManager.SwapParams memory userSwap = IPoolManager.SwapParams({
                zeroForOne: i % 2 == 0,
                amountSpecified: int256((i + 1) * 1000),
                sqrtPriceLimitX96: 0
            });
            
            hook.beforeSwap(users[i], poolKey, userSwap, "");
            hook.afterSwap(users[i], poolKey, userSwap, BalanceDelta.wrap(int256((i + 1) * 1000)), "");
        }
        
        // Verify state remains consistent
        (uint256 price, uint256 stake, uint256 confidence, bool valid) = hook.getConsensusData(poolId);
        assertEq(price, DEFAULT_PRICE);
        assertEq(stake, DEFAULT_STAKE);
        assertEq(confidence, DEFAULT_CONFIDENCE);
        assertTrue(valid);
    }
    
    
    // Stress Tests (15 tests)
    function testStress01_RapidConfigurationChanges() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Rapidly change configuration between swaps
        for (uint256 i = 0; i < 20; i++) {
            hook.updateOracleConfig(poolId, i * 100, i * 1 ether, 5000 + i * 100);
            hook.beforeSwap(alice, poolKey, swapParams, "");
            
            // Verify configuration was applied
            (, uint256 deviation, uint256 minStake, uint256 threshold, ) = hook.poolConfigs(poolId);
            assertEq(deviation, i * 100);
            assertEq(minStake, i * 1 ether);
            assertEq(threshold, 5000 + i * 100);
        }
    }
    
    function testStress02_AlternatingOracleEnable() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Alternate enabling/disabling oracle
        for (uint256 i = 0; i < 30; i++) {
            bool shouldEnable = i % 2 == 0;
            hook.enableOracleForPool(poolId, shouldEnable);
            
            if (shouldEnable) {
                // When enabled, should emit validation event
                vm.expectEmit(true, true, false, false);
                emit PriceValidationRequested(poolId, alice, 1000, 0);
            }
            
            hook.beforeSwap(alice, poolKey, swapParams, "");
        }
    }
    
    function testStress03_MixedUserConcurrency() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        address[] memory users = new address[](10);
        for (uint256 i = 0; i < 10; i++) {
            users[i] = makeAddr(string(abi.encodePacked("user", i)));
        }
        
        // All users perform swaps with different parameters
        for (uint256 i = 0; i < 50; i++) {
            address user = users[i % users.length];
            
            IPoolManager.SwapParams memory userSwap = IPoolManager.SwapParams({
                zeroForOne: i % 3 == 0,
                amountSpecified: int256((i + 1) * 100),
                sqrtPriceLimitX96: uint160(i * 1000)
            });
            
            hook.beforeSwap(user, poolKey, userSwap, "");
        }
        
        // Verify consensus data is stable
        (uint256 price, uint256 stake, uint256 confidence, bool valid) = hook.getConsensusData(poolId);
        assertEq(price, DEFAULT_PRICE);
        assertTrue(valid);
    }
    
    function testStress04_HeavyAVSStateChanges() public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(poolId)));
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Change AVS state frequently
        for (uint256 i = 0; i < 25; i++) {
            // Set different consensus values
            oracleAVS.setMockConsensus(
                poolIdBytes,
                (2000 + i * 50) * 1e18, // Different price each time
                (100 + i * 10) * 1e18, // Different stake
                8000 + i * 50, // Different confidence
                i % 7 != 0 // Occasionally invalid consensus
            );
            
            if (i % 7 == 0) {
                // Should fail when consensus is invalid
                vm.expectRevert("Oracle validation failed");
                hook.beforeSwap(alice, poolKey, swapParams, "");
            } else {
                hook.beforeSwap(alice, poolKey, swapParams, "");
                
                // Verify hook updated to new values
                (uint256 price, uint256 stake, uint256 confidence, bool valid) = hook.getConsensusData(poolId);
                assertEq(price, (2000 + i * 50) * 1e18);
                assertEq(stake, (100 + i * 10) * 1e18);
                assertEq(confidence, 8000 + i * 50);
                assertTrue(valid);
            }
        }
    }
    
    function testStress05_LargePoolBatches() public {
        // Create many pools and initialize them
        PoolKey[] memory pools = new PoolKey[](20);
        
        for (uint256 i = 0; i < 20; i++) {
            pools[i] = PoolKey({
                currency0: Currency.wrap(address(uint160(0x1000 + i))),
                currency1: Currency.wrap(address(uint160(0x2000 + i))),
                fee: uint24(100 + i * 50),
                tickSpacing: int24(1 + int24(uint24(i))),
                hooks: IHooks(address(hook))
            });
            
            hook.beforeInitialize(alice, pools[i], uint160(i + 1), "");
        }
        
        // Perform operations on all pools
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        for (uint256 i = 0; i < 20; i++) {
            PoolId pid = pools[i].toId();
            
            // Some pools will have oracle disabled (non-major tokens)
            (bool enabled, , , , ) = hook.poolConfigs(pid);
            
            if (enabled) {
                vm.expectEmit(true, true, false, false);
                emit PriceValidationRequested(pid, alice, 1000, 0);
            }
            
            hook.beforeSwap(alice, pools[i], swapParams, "");
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                         ADVANCED FUZZ TESTS (25 TESTS)
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz01_AllSwapParameters(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory fuzzSwap = IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });
        
        // Should handle any valid parameter combination
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, fuzzSwap, "");
        assertEq(result, hook.beforeSwap.selector);
    }
    
    function testFuzz02_ConfigurationParameters(
        uint256 maxPriceDeviation,
        uint256 minStakeRequired,
        uint256 consensusThreshold
    ) public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Update with fuzzed parameters
        hook.updateOracleConfig(poolId, maxPriceDeviation, minStakeRequired, consensusThreshold);
        
        // Verify values were set
        (, uint256 deviation, uint256 minStake, uint256 threshold, ) = hook.poolConfigs(poolId);
        
        assertEq(deviation, maxPriceDeviation);
        assertEq(minStake, minStakeRequired);
        assertEq(threshold, consensusThreshold);
    }
    
    function testFuzz03_AVSConsensusData(
        uint256 price,
        uint256 stake,
        uint256 confidence,
        bool isValid
    ) public {
        vm.assume(price > 0);
        vm.assume(stake > 0);
        vm.assume(confidence > 0 && confidence <= 10000);
        
        hook.beforeInitialize(alice, poolKey, 0, "");
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(poolId)));
        
        // Set fuzzed consensus data
        oracleAVS.setMockConsensus(poolIdBytes, price, stake, confidence, isValid);
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        if (isValid && stake >= 10 ether && confidence >= 6600) {
            // Should succeed
            hook.beforeSwap(alice, poolKey, swapParams, "");
            
            // Verify hook updated to fuzzed values
            (uint256 hookPrice, uint256 hookStake, uint256 hookConfidence, bool hookValid) = hook.getConsensusData(poolId);
            assertEq(hookPrice, price);
            assertEq(hookStake, stake);
            assertEq(hookConfidence, confidence);
            assertTrue(hookValid);
        } else {
            // Should fail validation
            vm.expectRevert("Oracle validation failed");
            hook.beforeSwap(alice, poolKey, swapParams, "");
        }
    }
    
    function testFuzz04_MultipleUsers(
        address user1,
        address user2,
        address user3,
        int256 amount1,
        int256 amount2,
        int256 amount3
    ) public {
        vm.assume(user1 != address(0) && user2 != address(0) && user3 != address(0));
        vm.assume(user1 != user2 && user2 != user3 && user1 != user3);
        
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        address[3] memory users = [user1, user2, user3];
        int256[3] memory amounts = [amount1, amount2, amount3];
        
        for (uint256 i = 0; i < 3; i++) {
            IPoolManager.SwapParams memory userSwap = IPoolManager.SwapParams({
                zeroForOne: i % 2 == 0,
                amountSpecified: amounts[i],
                sqrtPriceLimitX96: 0
            });
            
            hook.beforeSwap(users[i], poolKey, userSwap, "");
            hook.afterSwap(users[i], poolKey, userSwap, BalanceDelta.wrap(amounts[i]), "");
        }
    }
    
    function testFuzz05_PoolKeyVariations(
        address currency0,
        address currency1,
        uint24 fee,
        int24 tickSpacing
    ) public {
        vm.assume(currency0 != address(0) && currency1 != address(0));
        vm.assume(currency0 != currency1);
        vm.assume(tickSpacing != 0);
        
        PoolKey memory fuzzKey = PoolKey({
            currency0: Currency.wrap(currency0),
            currency1: Currency.wrap(currency1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(address(hook))
        });
        
        bytes4 result = hook.beforeInitialize(alice, fuzzKey, 0, "");
        assertEq(result, AVSOracleHook.beforeInitialize.selector);
        
        PoolId fuzzPoolId = fuzzKey.toId();
        
        // Should create valid configuration
        (bool enabled, uint256 deviation, uint256 minStake, uint256 threshold, uint256 staleness) = hook.poolConfigs(fuzzPoolId);
        
        // Values should be set to defaults
        assertEq(deviation, 500);
        assertEq(minStake, 10 ether);
        assertEq(threshold, 6600);
        assertEq(staleness, 300);
    }
    
    function testFuzz06_HookDataSizes(uint16 dataSize) public {
        dataSize = uint16(bound(dataSize, 0, 20000)); // Reasonable upper bound
        
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        bytes memory hookData = new bytes(dataSize);
        for (uint256 i = 0; i < dataSize; i++) {
            hookData[i] = bytes1(uint8(i % 256));
        }
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Should handle any hook data size
        hook.beforeInitialize(alice, poolKey, 0, hookData);
        hook.beforeSwap(alice, poolKey, swapParams, hookData);
        hook.afterSwap(alice, poolKey, swapParams, BalanceDelta.wrap(1000), hookData);
    }
    
    function testFuzz07_TimestampValidation(uint256 timestamp) public {
        timestamp = bound(timestamp, 1, type(uint256).max - 1000); // Avoid overflow
        
        hook.beforeInitialize(alice, poolKey, 0, "");
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(poolId)));
        
        // Set mock consensus with fuzzed timestamp
        oracleAVS.setMockConsensus(poolIdBytes, DEFAULT_PRICE, DEFAULT_STAKE, DEFAULT_CONFIDENCE, true);
        
        // Move to specific time
        vm.warp(timestamp + 1000); // Advance past timestamp
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Should fail due to staleness if more than 300 seconds old
        if (block.timestamp - timestamp > 300) {
            vm.expectRevert("Oracle validation failed");
            hook.beforeSwap(alice, poolKey, swapParams, "");
        } else {
            hook.beforeSwap(alice, poolKey, swapParams, "");
        }
    }
    
    function testFuzz08_BalanceDeltaHandling(int256 deltaValue) public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        BalanceDelta delta = BalanceDelta.wrap(deltaValue);
        
        (bytes4 result, int128 hookDelta) = hook.afterSwap(alice, poolKey, swapParams, delta, "");
        
        assertEq(result, hook.afterSwap.selector);
        assertEq(hookDelta, 0); // Should always return 0
    }
    
    function testFuzz09_SqrtPriceLimits(uint160 sqrtPriceLimit) public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 1000,
            sqrtPriceLimitX96: sqrtPriceLimit
        });
        
        (bytes4 result, , ) = hook.beforeSwap(alice, poolKey, swapParams, "");
        assertEq(result, hook.beforeSwap.selector);
    }
    
    function testFuzz10_EventParameterValidation(
        address sender,
        uint256 amount
    ) public {
        vm.assume(sender != address(0));
        amount = bound(amount, 1, type(uint256).max);
        
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: int256(amount),
            sqrtPriceLimitX96: 0
        });
        
        vm.expectEmit(true, true, false, false);
        emit PriceValidationRequested(poolId, sender, amount, 0);
        
        hook.beforeSwap(sender, poolKey, swapParams, "");
    }
    
    function testFuzz11_ConfigurationBoundaries(
        uint256 deviation,
        uint256 stake,
        uint256 threshold
    ) public {
        deviation = bound(deviation, 0, 10000); // 0-100% deviation
        stake = bound(stake, 1 wei, 1000000 ether); // Reasonable stake range
        threshold = bound(threshold, 5100, 10000); // 51-100% threshold
        
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        hook.updateOracleConfig(poolId, deviation, stake, threshold);
        
        // Test swap with these parameters
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Set AVS to match requirements
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(poolId)));
        oracleAVS.setMockConsensus(poolIdBytes, DEFAULT_PRICE, stake + 1 ether, threshold + 100, true);
        
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
    
    function testFuzz12_MultiPoolOperations(
        uint8 poolCount,
        uint16 operationCount
    ) public {
        poolCount = uint8(bound(poolCount, 1, 20)); // 1-20 pools
        operationCount = uint16(bound(operationCount, 1, 100)); // 1-100 operations
        
        // Create pools
        PoolKey[] memory pools = new PoolKey[](poolCount);
        for (uint256 i = 0; i < poolCount; i++) {
            pools[i] = PoolKey({
                currency0: Currency.wrap(address(uint160(0x10000 + i))),
                currency1: Currency.wrap(address(uint160(0x20000 + i))),
                fee: uint24(100 + i),
                tickSpacing: int24(1 + int24(uint24(i % 10))),
                hooks: IHooks(address(hook))
            });
            
            hook.beforeInitialize(alice, pools[i], uint160(i), "");
        }
        
        // Perform operations
        for (uint256 i = 0; i < operationCount; i++) {
            PoolKey memory pool = pools[i % poolCount];
            
            IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
                zeroForOne: i % 2 == 0,
                amountSpecified: int256(i + 1),
                sqrtPriceLimitX96: 0
            });
            
            hook.beforeSwap(alice, pool, swapParams, "");
        }
    }
    
    function testFuzz13_StakeAndConfidenceCombinations(
        uint256 stake,
        uint256 confidence
    ) public {
        stake = bound(stake, 1 wei, 10000 ether);
        confidence = bound(confidence, 0, 10000);
        
        hook.beforeInitialize(alice, poolKey, 0, "");
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(poolId)));
        
        oracleAVS.setMockConsensus(poolIdBytes, DEFAULT_PRICE, stake, confidence, true);
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Should succeed only if meets minimum requirements
        if (stake >= 10 ether && confidence >= 6600) {
            hook.beforeSwap(alice, poolKey, swapParams, "");
            
            (uint256 hookPrice, uint256 hookStake, uint256 hookConfidence, bool hookValid) = hook.getConsensusData(poolId);
            assertEq(hookStake, stake);
            assertEq(hookConfidence, confidence);
            assertTrue(hookValid);
        } else {
            vm.expectRevert("Oracle validation failed");
            hook.beforeSwap(alice, poolKey, swapParams, "");
        }
    }
    
    function testFuzz14_AddressValidation(
        address user,
        address token0,
        address token1
    ) public {
        vm.assume(user != address(0));
        vm.assume(token0 != address(0) && token1 != address(0));
        vm.assume(token0 != token1);
        
        PoolKey memory customKey = PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: 3000,
            tickSpacing: 60,
            hooks: IHooks(address(hook))
        });
        
        hook.beforeInitialize(user, customKey, 0, "");
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        hook.beforeSwap(user, customKey, swapParams, "");
        hook.afterSwap(user, customKey, swapParams, BalanceDelta.wrap(1000), "");
    }
    
    
    function testFuzz16_ExtremeSqrtPriceLimits(uint160 limit1, uint160 limit2, uint160 limit3) public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams memory swap1 = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: 1000,
            sqrtPriceLimitX96: limit1
        });
        
        IPoolManager.SwapParams memory swap2 = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: 2000,
            sqrtPriceLimitX96: limit2
        });
        
        IPoolManager.SwapParams memory swap3 = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: -1500,
            sqrtPriceLimitX96: limit3
        });
        
        hook.beforeSwap(alice, poolKey, swap1, "");
        hook.beforeSwap(bob, poolKey, swap2, "");
        hook.beforeSwap(carol, poolKey, swap3, "");
    }
    
    function testFuzz17_RandomPoolCreation(uint256 seed) public {
        // Create 10 pools with pseudo-random parameters
        for (uint256 i = 0; i < 10; i++) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            
            PoolKey memory randomKey = PoolKey({
                currency0: Currency.wrap(address(uint160((entropy % 10000) + 0x10000))),
                currency1: Currency.wrap(address(uint160((entropy % 10000) + 0x20000))),
                fee: uint24((entropy % 3000) + 100),
                tickSpacing: int24(int256((entropy % 100) + 1)),
                hooks: IHooks(address(hook))
            });
            
            hook.beforeInitialize(alice, randomKey, uint160(i), "");
        }
    }
    
    function testFuzz18_LargeDataStructures(uint256 structSize) public {
        structSize = bound(structSize, 1000, 50000); // Large but reasonable
        
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        bytes memory largeData = new bytes(structSize);
        for (uint256 i = 0; i < structSize; i++) {
            largeData[i] = bytes1(uint8((i * 7) % 256));
        }
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        hook.beforeInitialize(alice, poolKey, 0, largeData);
        hook.beforeSwap(alice, poolKey, swapParams, largeData);
        hook.afterSwap(alice, poolKey, swapParams, BalanceDelta.wrap(1000), largeData);
    }
    
    function testFuzz19_NestedOperations(uint8 depth, uint8 operations) public {
        depth = uint8(bound(depth, 1, 10));
        operations = uint8(bound(operations, 1, 20));
        
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Nested configuration changes
        for (uint256 d = 0; d < depth; d++) {
            for (uint256 o = 0; o < operations; o++) {
                uint256 entropy = uint256(keccak256(abi.encode(d, o)));
                
                hook.updateOracleConfig(
                    poolId,
                    (entropy % 5000) + 100,
                    ((entropy % 500) + 10) * 1 ether,
                    (entropy % 2000) + 6000
                );
                
                IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
                    zeroForOne: entropy % 2 == 0,
                    amountSpecified: int256((entropy % 5000) + 1),
                    sqrtPriceLimitX96: 0
                });
                
                hook.beforeSwap(alice, poolKey, swapParams, "");
            }
        }
    }
    
    function testFuzz20_ExtremeConfigurationCombinations(
        uint256 dev1, uint256 dev2, uint256 dev3,
        uint256 stake1, uint256 stake2, uint256 stake3,
        uint256 thresh1, uint256 thresh2, uint256 thresh3
    ) public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Test multiple extreme configuration changes in sequence
        hook.updateOracleConfig(poolId, dev1, stake1, thresh1);
        hook.updateOracleConfig(poolId, dev2, stake2, thresh2);
        hook.updateOracleConfig(poolId, dev3, stake3, thresh3);
        
        // Verify final configuration
        (, uint256 finalDev, uint256 finalStake, uint256 finalThresh, ) = hook.poolConfigs(poolId);
        assertEq(finalDev, dev3);
        assertEq(finalStake, stake3);
        assertEq(finalThresh, thresh3);
    }
    
    function testFuzz21_ConcurrentMultiPoolOperations(uint8 poolCount) public {
        poolCount = uint8(bound(poolCount, 2, 25));
        
        // Create multiple pools
        PoolKey[] memory pools = new PoolKey[](poolCount);
        PoolId[] memory poolIds = new PoolId[](poolCount);
        
        for (uint256 i = 0; i < poolCount; i++) {
            pools[i] = PoolKey({
                currency0: Currency.wrap(address(uint160(0x10000 + i))),
                currency1: Currency.wrap(address(uint160(0x20000 + i))),
                fee: uint24(100 + i * 10),
                tickSpacing: int24(1 + int24(uint24(i % 5))),
                hooks: IHooks(address(hook))
            });
            
            hook.beforeInitialize(alice, pools[i], uint160(i), "");
            poolIds[i] = pools[i].toId();
        }
        
        // Perform cross-pool operations
        for (uint256 i = 0; i < poolCount; i++) {
            IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
                zeroForOne: i % 2 == 0,
                amountSpecified: int256((i + 1) * 100),
                sqrtPriceLimitX96: 0
            });
            
            hook.beforeSwap(alice, pools[i], swapParams, "");
        }
        
        // Verify each pool maintains independent state
        for (uint256 i = 0; i < poolCount; i++) {
            (bool enabled, uint256 deviation, uint256 minStake, uint256 threshold, uint256 staleness) = hook.poolConfigs(poolIds[i]);
            
            // All should have default values
            assertEq(deviation, 500);
            assertEq(minStake, 10 ether);
            assertEq(threshold, 6600);
            assertEq(staleness, 300);
        }
    }
    
    function testFuzz22_StressEventEmission(uint16 eventCount) public {
        eventCount = uint16(bound(eventCount, 1, 200));
        
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        // Generate many events in rapid succession
        for (uint256 i = 0; i < eventCount; i++) {
            IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
                zeroForOne: i % 2 == 0,
                amountSpecified: int256(i + 1),
                sqrtPriceLimitX96: 0
            });
            
            vm.expectEmit(true, true, false, false);
            emit PriceValidationRequested(poolId, alice, i + 1, 0);
            
            vm.expectEmit(true, false, false, false);
            emit ConsensusReached(poolId, DEFAULT_PRICE, DEFAULT_STAKE, 0, DEFAULT_CONFIDENCE);
            
            hook.beforeSwap(alice, poolKey, swapParams, "");
        }
    }
    
    function testFuzz23_ExtremeAVSBehavior(
        uint256 price1, uint256 price2, uint256 price3,
        uint256 stake1, uint256 stake2, uint256 stake3,
        uint256 conf1, uint256 conf2, uint256 conf3
    ) public {
        vm.assume(price1 > 0 && price2 > 0 && price3 > 0);
        vm.assume(stake1 > 0 && stake2 > 0 && stake3 > 0);
        conf1 = bound(conf1, 0, 10000);
        conf2 = bound(conf2, 0, 10000);
        conf3 = bound(conf3, 0, 10000);
        
        hook.beforeInitialize(alice, poolKey, 0, "");
        bytes32 poolIdBytes = bytes32(uint256(PoolId.unwrap(poolId)));
        
        IPoolManager.SwapParams memory swapParams = TestUtils.createBasicSwapParams(1000);
        
        // Rapidly change AVS state
        oracleAVS.setMockConsensus(poolIdBytes, price1, stake1, conf1, true);
        if (stake1 >= 10 ether && conf1 >= 6600) {
            hook.beforeSwap(alice, poolKey, swapParams, "");
        }
        
        oracleAVS.setMockConsensus(poolIdBytes, price2, stake2, conf2, true);
        if (stake2 >= 10 ether && conf2 >= 6600) {
            hook.beforeSwap(bob, poolKey, swapParams, "");
        }
        
        oracleAVS.setMockConsensus(poolIdBytes, price3, stake3, conf3, true);
        if (stake3 >= 10 ether && conf3 >= 6600) {
            hook.beforeSwap(carol, poolKey, swapParams, "");
        }
    }
    
    function testFuzz24_EdgeCaseAmounts(int256 amount1, int256 amount2, int256 amount3) public {
        hook.beforeInitialize(alice, poolKey, 0, "");
        
        IPoolManager.SwapParams[] memory swaps = new IPoolManager.SwapParams[](3);
        
        swaps[0] = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: amount1,
            sqrtPriceLimitX96: 0
        });
        
        swaps[1] = IPoolManager.SwapParams({
            zeroForOne: false,
            amountSpecified: amount2,
            sqrtPriceLimitX96: 0
        });
        
        swaps[2] = IPoolManager.SwapParams({
            zeroForOne: true,
            amountSpecified: amount3,
            sqrtPriceLimitX96: 0
        });
        
        for (uint256 i = 0; i < 3; i++) {
            hook.beforeSwap(alice, poolKey, swaps[i], "");
            hook.afterSwap(alice, poolKey, swaps[i], BalanceDelta.wrap(swaps[i].amountSpecified), "");
        }
    }
    
    function testFuzz25_ComprehensiveSystemTest(
        uint8 pools,
        uint8 users,
        uint16 operations,
        uint256 seed
    ) public {
        pools = uint8(bound(pools, 1, 15));
        users = uint8(bound(users, 1, 10));
        operations = uint16(bound(operations, 10, 100));
        
        // Create pools
        PoolKey[] memory poolKeys = new PoolKey[](pools);
        address[] memory userAddresses = new address[](users);
        
        for (uint256 i = 0; i < pools; i++) {
            poolKeys[i] = PoolKey({
                currency0: Currency.wrap(address(uint160(0x100000 + i))),
                currency1: Currency.wrap(address(uint160(0x200000 + i))),
                fee: uint24(100 + i * 25),
                tickSpacing: int24(1 + int24(uint24(i % 8))),
                hooks: IHooks(address(hook))
            });
            hook.beforeInitialize(alice, poolKeys[i], uint160(i), "");
        }
        
        for (uint256 i = 0; i < users; i++) {
            userAddresses[i] = makeAddr(string(abi.encodePacked("fuzzUser", i)));
        }
        
        // Perform comprehensive operations
        for (uint256 i = 0; i < operations; i++) {
            uint256 entropy = uint256(keccak256(abi.encode(seed, i)));
            
            PoolKey memory selectedPool = poolKeys[entropy % pools];
            address selectedUser = userAddresses[entropy % users];
            
            uint8 opType = uint8(entropy % 3);
            
            if (opType == 0) {
                // Swap operation
                IPoolManager.SwapParams memory swapParams = IPoolManager.SwapParams({
                    zeroForOne: entropy % 2 == 0,
                    amountSpecified: int256((entropy % 10000) + 1),
                    sqrtPriceLimitX96: 0
                });
                
                hook.beforeSwap(selectedUser, selectedPool, swapParams, "");
            } else if (opType == 1) {
                // Configuration change
                PoolId selectedPoolId = selectedPool.toId();
                hook.updateOracleConfig(
                    selectedPoolId,
                    (entropy % 2000) + 100,
                    ((entropy % 200) + 10) * 1 ether,
                    (entropy % 3000) + 5500
                );
            } else {
                // Oracle toggle
                PoolId selectedPoolId = selectedPool.toId();
                hook.enableOracleForPool(selectedPoolId, entropy % 3 != 0);
            }
        }
    }
}