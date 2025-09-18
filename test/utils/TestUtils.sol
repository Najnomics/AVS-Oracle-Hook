// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {PoolId, PoolIdLibrary} from "v4-core/types/PoolId.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";

/**
 * @title TestUtils
 * @notice Utility functions for testing
 */
library TestUtils {
    using PoolIdLibrary for PoolKey;
    
    // Common test tokens
    address constant USDC = 0xA0b86a33E6417c8a9bbe78fe047ce5C17aEd0Ada;
    address constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address constant WBTC = 0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599;
    address constant DAI = 0x6B175474E89094C44Da98b954EedeAC495271d0F;
    
    /**
     * @notice Create a test pool key
     */
    function createPoolKey(
        address token0,
        address token1,
        uint24 fee,
        int24 tickSpacing,
        address hooks
    ) internal pure returns (PoolKey memory) {
        return PoolKey({
            currency0: Currency.wrap(token0),
            currency1: Currency.wrap(token1),
            fee: fee,
            tickSpacing: tickSpacing,
            hooks: IHooks(hooks)
        });
    }
    
    /**
     * @notice Create USDC/WETH pool key
     */
    function createUSDCWETHPoolKey(address hooks) internal pure returns (PoolKey memory) {
        return createPoolKey(USDC, WETH, 3000, 60, hooks);
    }
    
    /**
     * @notice Create WBTC/WETH pool key
     */
    function createWBTCWETHPoolKey(address hooks) internal pure returns (PoolKey memory) {
        return createPoolKey(WBTC, WETH, 3000, 60, hooks);
    }
    
    /**
     * @notice Create swap parameters
     */
    function createSwapParams(
        bool zeroForOne,
        int256 amountSpecified,
        uint160 sqrtPriceLimitX96
    ) internal pure returns (IPoolManager.SwapParams memory) {
        return IPoolManager.SwapParams({
            zeroForOne: zeroForOne,
            amountSpecified: amountSpecified,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });
    }
    
    /**
     * @notice Create basic swap parameters
     */
    function createBasicSwapParams(int256 amountSpecified) internal pure returns (IPoolManager.SwapParams memory) {
        return createSwapParams(true, amountSpecified, 0);
    }
    
    /**
     * @notice Calculate percentage difference between two values
     */
    function calculatePercentageDiff(uint256 value1, uint256 value2) internal pure returns (uint256) {
        if (value2 == 0) return 10000; // 100% if denominator is 0
        
        uint256 diff = value1 > value2 ? value1 - value2 : value2 - value1;
        return (diff * 10000) / value2;
    }
    
    /**
     * @notice Create attestation data for testing
     */
    function createAttestationData(
        address operator,
        uint256 price,
        uint256 stake,
        uint256 reliability
    ) internal view returns (bytes memory) {
        return abi.encode(operator, price, stake, block.timestamp, reliability);
    }
    
    /**
     * @notice Generate mock BLS signature
     */
    function mockBLSSignature() internal pure returns (bytes memory) {
        return abi.encodePacked(
            bytes32(0x1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef),
            bytes32(0xfedcba0987654321fedcba0987654321fedcba0987654321fedcba0987654321)
        );
    }
    
    /**
     * @notice Create array of test operators
     */
    function createTestOperators() internal pure returns (address[] memory) {
        address[] memory operators = new address[](5);
        operators[0] = address(0x1111111111111111111111111111111111111111);
        operators[1] = address(0x2222222222222222222222222222222222222222);
        operators[2] = address(0x3333333333333333333333333333333333333333);
        operators[3] = address(0x4444444444444444444444444444444444444444);
        operators[4] = address(0x5555555555555555555555555555555555555555);
        return operators;
    }
    
    /**
     * @notice Create array of test prices with small variations
     */
    function createConvergentPrices(uint256 basePrice, uint256 count) internal pure returns (uint256[] memory) {
        uint256[] memory prices = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            // Add small random variation (±2%)
            uint256 variation = (basePrice * (50 + (i * 23) % 100)) / 10000; // 0.5% to 1.5%
            if (i % 2 == 0) {
                prices[i] = basePrice + variation;
            } else {
                prices[i] = basePrice - variation;
            }
        }
        return prices;
    }
    
    /**
     * @notice Create array of test prices with outliers
     */
    function createPricesWithOutliers(uint256 basePrice, uint256 count) internal pure returns (uint256[] memory) {
        uint256[] memory prices = new uint256[](count);
        for (uint256 i = 0; i < count; i++) {
            if (i == count - 1) {
                // Last price is an outlier (20% off)
                prices[i] = basePrice * 120 / 100;
            } else {
                // Normal variation
                uint256 variation = (basePrice * (20 + (i * 13) % 40)) / 10000; // 0.2% to 0.6%
                prices[i] = i % 2 == 0 ? basePrice + variation : basePrice - variation;
            }
        }
        return prices;
    }
    
    /**
     * @notice Create timestamps array
     */
    function createTimestamps(uint256 count, uint256 intervalSeconds) internal view returns (uint256[] memory) {
        uint256[] memory timestamps = new uint256[](count);
        uint256 totalInterval = count * intervalSeconds;
        uint256 baseTime = block.timestamp > totalInterval ? 
            block.timestamp - totalInterval : 
            1000000; // Use a safe base time if underflow would occur
        
        for (uint256 i = 0; i < count; i++) {
            timestamps[i] = baseTime + (i * intervalSeconds);
        }
        return timestamps;
    }
}