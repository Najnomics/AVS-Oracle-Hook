// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title PriceValidation
 * @notice Library for validating prices and detecting manipulation attempts
 * @dev Provides utilities for price validation algorithms used by the Oracle Hook
 */
library PriceValidation {
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MAX_DEVIATION_BPS = 1000;  // 10% max deviation
    uint256 public constant MIN_CONFIDENCE = 5000;     // 50% minimum confidence
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct ValidationParams {
        uint256 currentPrice;
        uint256 consensusPrice;
        uint256 confidenceLevel;
        uint256 maxDeviationBps;
        uint256 minConfidence;
        uint256 timestamp;
        uint256 maxStaleness;
    }
    
    struct ValidationResult {
        bool isValid;
        uint256 deviation;
        string reason;
    }
    
    /*//////////////////////////////////////////////////////////////
                            VALIDATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Validate a price against consensus with comprehensive checks
     * @param params Validation parameters
     * @return result Validation result with status and details
     */
    function validatePrice(ValidationParams memory params) 
        internal 
        view 
        returns (ValidationResult memory result) 
    {
        // Check confidence level
        if (params.confidenceLevel < params.minConfidence) {
            return ValidationResult({
                isValid: false,
                deviation: 0,
                reason: "Low confidence"
            });
        }
        
        // Check staleness
        if (block.timestamp - params.timestamp > params.maxStaleness) {
            return ValidationResult({
                isValid: false,
                deviation: 0,
                reason: "Stale price data"
            });
        }
        
        // Calculate price deviation
        uint256 deviation = calculateDeviation(params.currentPrice, params.consensusPrice);
        
        // Check deviation threshold
        if (deviation > params.maxDeviationBps) {
            return ValidationResult({
                isValid: false,
                deviation: deviation,
                reason: "Price deviation too high"
            });
        }
        
        return ValidationResult({
            isValid: true,
            deviation: deviation,
            reason: ""
        });
    }
    
    /**
     * @notice Calculate percentage deviation between two prices
     * @param price1 First price
     * @param price2 Second price (reference)
     * @return deviation Absolute deviation in basis points
     */
    function calculateDeviation(uint256 price1, uint256 price2) 
        internal 
        pure 
        returns (uint256 deviation) 
    {
        if (price2 == 0) return BASIS_POINTS; // 100% deviation
        
        uint256 diff = price1 > price2 ? price1 - price2 : price2 - price1;
        deviation = (diff * BASIS_POINTS) / price2;
        
        return deviation;
    }
    
    /**
     * @notice Detect potential manipulation based on price movement patterns
     * @param prices Array of recent prices
     * @param timestamps Array of corresponding timestamps
     * @return isManipulation Whether manipulation is detected
     * @return suspicionLevel Manipulation suspicion level (0-10000)
     */
    function detectManipulation(
        uint256[] memory prices,
        uint256[] memory timestamps
    ) internal pure returns (bool isManipulation, uint256 suspicionLevel) {
        require(prices.length == timestamps.length, "Array length mismatch");
        require(prices.length >= 3, "Insufficient data points");
        
        uint256 totalVolatility = 0;
        uint256 maxDeviation = 0;
        
        // Calculate volatility and max deviation
        for (uint256 i = 1; i < prices.length; i++) {
            uint256 deviation = calculateDeviation(prices[i], prices[i-1]);
            totalVolatility += deviation;
            
            if (deviation > maxDeviation) {
                maxDeviation = deviation;
            }
        }
        
        uint256 avgVolatility = totalVolatility / (prices.length - 1);
        
        // High volatility + extreme deviation = potential manipulation
        suspicionLevel = (avgVolatility + maxDeviation) / 2;
        
        // Manipulation threshold: 20% average volatility or 50% max deviation
        isManipulation = avgVolatility > 2000 || maxDeviation > 5000;
        
        return (isManipulation, suspicionLevel);
    }
    
    /**
     * @notice Validate multiple price sources for consistency
     * @param sources Array of price sources
     * @param weights Array of source weights
     * @return weightedPrice Weighted average price
     * @return consistency Consistency score (0-10000)
     */
    function validateMultipleSources(
        uint256[] memory sources,
        uint256[] memory weights
    ) internal pure returns (uint256 weightedPrice, uint256 consistency) {
        require(sources.length == weights.length, "Array length mismatch");
        require(sources.length > 0, "No sources provided");
        
        uint256 totalWeight = 0;
        uint256 weightedSum = 0;
        
        // Calculate weighted average
        for (uint256 i = 0; i < sources.length; i++) {
            weightedSum += sources[i] * weights[i];
            totalWeight += weights[i];
        }
        
        weightedPrice = weightedSum / totalWeight;
        
        // Calculate consistency (lower deviation = higher consistency)
        uint256 totalDeviation = 0;
        for (uint256 i = 0; i < sources.length; i++) {
            uint256 deviation = calculateDeviation(sources[i], weightedPrice);
            totalDeviation += deviation * weights[i]; // Weight the deviations
        }
        
        uint256 avgDeviation = totalDeviation / totalWeight;
        
        // Consistency score: 100% - average deviation percentage
        consistency = avgDeviation >= BASIS_POINTS ? 0 : BASIS_POINTS - avgDeviation;
        
        return (weightedPrice, consistency);
    }
    
    /**
     * @notice Check if price movement is within normal bounds
     * @param previousPrice Previous price
     * @param currentPrice Current price
     * @param maxMovementBps Maximum allowed movement in basis points
     * @return isNormal Whether the movement is within normal bounds
     */
    function isNormalPriceMovement(
        uint256 previousPrice,
        uint256 currentPrice,
        uint256 maxMovementBps
    ) internal pure returns (bool isNormal) {
        uint256 deviation = calculateDeviation(currentPrice, previousPrice);
        return deviation <= maxMovementBps;
    }
}