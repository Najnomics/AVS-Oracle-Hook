// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {PoolId} from "v4-core/types/PoolId.sol";

/**
 * @title IAVSOracleHook
 * @notice Interface for the main AVS Oracle Hook
 * @dev Defines the interface for Oracle functionality integrated with Uniswap V4
 */
interface IAVSOracleHook {
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct PriceAttestation {
        uint256 price;                       // Price in wei (18 decimals)
        uint256 timestamp;                   // When attestation was created
        address operator;                    // AVS operator address
        uint256 stakeAmount;                 // Operator's stake backing this price
        bytes signature;                     // BLS signature of price data
        uint256 confidence;                  // Confidence score (0-10000)
    }
    
    struct ConsensusData {
        uint256 weightedPrice;               // Stake-weighted consensus price
        uint256 totalStake;                  // Total stake behind consensus
        uint256 attestationCount;            // Number of attestations received
        uint256 confidenceLevel;             // Overall confidence (0-10000)
        uint256 lastUpdateTimestamp;         // When consensus was last updated
        bool isValid;                        // Whether consensus is valid for trading
    }
    
    struct PoolOracleConfig {
        bool oracleEnabled;                  // Whether oracle validation is enabled
        uint256 maxPriceDeviation;          // Max allowed price deviation (BPS)
        uint256 minStakeRequired;            // Minimum stake required for consensus
        uint256 consensusThreshold;          // Minimum consensus percentage (6600 = 66%)
        uint256 maxStaleness;                // Maximum age of price data (seconds)
    }
    
    /*//////////////////////////////////////////////////////////////
                            ORACLE FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get consensus data for a pool
     * @param poolId The pool ID
     * @return consensusPrice The consensus price
     * @return totalStake Total stake backing consensus
     * @return confidenceLevel Confidence level (0-10000)
     * @return isValid Whether consensus is valid
     */
    function getConsensusData(PoolId poolId) external view returns (
        uint256 consensusPrice,
        uint256 totalStake,
        uint256 confidenceLevel,
        bool isValid
    );
    
    /**
     * @notice Enable or disable oracle validation for a pool
     * @param poolId The pool ID
     * @param enabled Whether to enable oracle validation
     */
    function enableOracleForPool(PoolId poolId, bool enabled) external;
    
    /**
     * @notice Update oracle configuration for a pool
     * @param poolId The pool ID
     * @param maxPriceDeviation Maximum allowed price deviation (BPS)
     * @param minStakeRequired Minimum stake required for consensus
     * @param consensusThreshold Consensus threshold percentage
     */
    function updateOracleConfig(
        PoolId poolId,
        uint256 maxPriceDeviation,
        uint256 minStakeRequired,
        uint256 consensusThreshold
    ) external;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
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
    
    event ManipulationDetected(
        PoolId indexed poolId,
        address indexed suspiciousOperator,
        uint256 reportedPrice,
        uint256 consensusPrice,
        uint256 deviation
    );
}