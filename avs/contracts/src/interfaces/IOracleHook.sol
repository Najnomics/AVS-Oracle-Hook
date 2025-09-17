// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IOracleHook
 * @notice Interface for Oracle Hook that integrates with Uniswap V4 pools
 * @dev Defines the interface for the Oracle Hook that validates prices before swaps
 */
interface IOracleHook {
    
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
                            ORACLE CONFIGURATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Enable or disable oracle validation for a pool
     * @param poolId The pool ID
     * @param enabled Whether to enable oracle validation
     */
    function enableOracleForPool(bytes32 poolId, bool enabled) external;

    /**
     * @notice Update oracle configuration for a pool
     * @param poolId The pool ID
     * @param maxPriceDeviation Maximum allowed price deviation (BPS)
     * @param minStakeRequired Minimum stake required for consensus
     * @param consensusThreshold Consensus threshold percentage
     */
    function updateOracleConfig(
        bytes32 poolId,
        uint256 maxPriceDeviation,
        uint256 minStakeRequired,
        uint256 consensusThreshold
    ) external;
    
    /*//////////////////////////////////////////////////////////////
                            PRICE VALIDATION
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get consensus data for a pool
     * @param poolId The pool ID
     * @return consensusPrice The consensus price
     * @return totalStake Total stake backing consensus
     * @return confidenceLevel Confidence level (0-10000)
     * @return isValid Whether consensus is valid
     */
    function getConsensusData(bytes32 poolId) external view returns (
        uint256 consensusPrice,
        uint256 totalStake,
        uint256 confidenceLevel,
        bool isValid
    );

    /**
     * @notice Get oracle configuration for a pool
     * @param poolId The pool ID
     * @return config The oracle configuration
     */
    function getOracleConfig(bytes32 poolId) external view returns (PoolOracleConfig memory config);

    /**
     * @notice Get operator reliability score
     * @param operator The operator address
     * @return The reliability score (0-10000)
     */
    function getOperatorReliabilityScore(address operator) external view returns (uint256);
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event PriceValidationRequested(
        bytes32 indexed poolId,
        address indexed trader,
        uint256 swapAmount,
        uint256 expectedPrice
    );
    
    event ConsensusReached(
        bytes32 indexed poolId,
        uint256 consensusPrice,
        uint256 totalStake,
        uint256 attestationCount,
        uint256 confidenceLevel
    );
    
    event SwapBlocked(
        bytes32 indexed poolId,
        address indexed trader,
        uint256 requestedPrice,
        uint256 consensusPrice,
        string reason
    );
    
    event ManipulationDetected(
        bytes32 indexed poolId,
        address indexed suspiciousOperator,
        uint256 reportedPrice,
        uint256 consensusPrice,
        uint256 deviation
    );
    
    event OracleConfigUpdated(
        bytes32 indexed poolId,
        uint256 maxPriceDeviation,
        uint256 minStakeRequired,
        uint256 consensusThreshold
    );
}