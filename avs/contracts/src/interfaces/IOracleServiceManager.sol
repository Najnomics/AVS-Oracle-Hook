// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IOracleServiceManager
 * @notice Interface for Oracle Service Manager
 * @dev Defines the interface for the main Oracle AVS service manager that handles
 * price attestations, consensus formation, and operator management
 */
interface IOracleServiceManager {
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct PriceAttestation {
        address operator;           // AVS operator submitting price
        bytes32 poolId;            // Pool this price applies to
        uint256 price;             // Reported price (18 decimals)
        uint256 timestamp;         // When price was observed
        uint256 stakeAmount;       // Operator's stake backing this price
        bytes32 sourceHash;        // Hash of price sources used
        bytes signature;           // BLS signature of attestation
        bool isValid;              // Whether attestation passed validation
    }
    
    struct ConsensusResult {
        bytes32 poolId;            // Pool ID
        uint256 weightedPrice;     // Stake-weighted consensus price
        uint256 totalStake;        // Total stake behind consensus
        uint256 attestationCount;  // Number of valid attestations
        uint256 confidenceLevel;   // Confidence in consensus (0-10000)
        uint256 consensusTimestamp; // When consensus was reached
        bool isValid;              // Whether consensus is valid
    }
    
    struct OperatorPerformance {
        uint256 totalAttestations;     // Total attestations submitted
        uint256 accurateAttestations;  // Attestations within consensus
        uint256 totalStakeSlashed;     // Total stake slashed for inaccuracy
        uint256 reliabilityScore;      // Reliability score (0-10000)
        uint256 lastAttestationTime;   // Last attestation timestamp
    }
    
    /*//////////////////////////////////////////////////////////////
                            OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Register an operator specifically for Oracle tasks
     * @param operator The operator address to register
     * @param operatorSignature The operator's signature for EigenLayer
     */
    function registerOracleOperator(
        address operator,
        bytes calldata operatorSignature
    ) external payable;

    /**
     * @notice Deregister an operator from Oracle tasks
     * @param operator The operator address to deregister
     */
    function deregisterOracleOperator(address operator) external;

    /**
     * @notice Check if an operator meets Oracle requirements
     * @param operator The operator address to check
     * @return Whether the operator is qualified for Oracle operations
     */
    function isOracleOperatorQualified(address operator) external view returns (bool);
    
    /*//////////////////////////////////////////////////////////////
                            PRICE ATTESTATIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Submit a price attestation
     * @param poolId The pool ID this price applies to
     * @param price The observed price (18 decimals)
     * @param sourceHash Hash of price sources used
     * @param signature BLS signature of the attestation
     */
    function submitPriceAttestation(
        bytes32 poolId,
        uint256 price,
        bytes32 sourceHash,
        bytes calldata signature
    ) external;
    
    /*//////////////////////////////////////////////////////////////
                            CONSENSUS QUERIES
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Get current consensus for a pool
     * @param poolId The pool ID
     * @return hasConsensus Whether valid consensus exists
     * @return consensusPrice The consensus price
     * @return totalStake Total stake backing consensus
     * @return confidenceLevel Confidence level (0-10000)
     */
    function getCurrentConsensus(bytes32 poolId) external view returns (
        bool hasConsensus,
        uint256 consensusPrice,
        uint256 totalStake,
        uint256 confidenceLevel
    );

    /**
     * @notice Get operators participating in consensus for a pool
     * @param poolId The pool ID
     * @return Array of operator addresses
     */
    function getConsensusOperators(bytes32 poolId) external view returns (address[] memory);

    /**
     * @notice Get operator performance data
     * @param operator The operator address
     * @return totalAttestations Total attestations submitted
     * @return accuracyRate Accuracy rate (0-10000)
     * @return reliabilityScore Reliability score (0-10000)
     * @return totalSlashed Total stake slashed
     */
    function getOperatorPerformance(address operator) external view returns (
        uint256 totalAttestations,
        uint256 accuracyRate,
        uint256 reliabilityScore,
        uint256 totalSlashed
    );

    /**
     * @notice Get the Oracle Hook contract address
     * @return The address of the Oracle Hook contract
     */
    function getOracleHook() external view returns (address);
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event OracleOperatorRegistered(address indexed operator, bytes32 indexed operatorId);
    event OracleOperatorDeregistered(address indexed operator, bytes32 indexed operatorId);
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
    event OperatorSlashed(
        address indexed operator,
        bytes32 indexed poolId,
        uint256 slashAmount,
        uint256 reportedPrice,
        uint256 consensusPrice
    );
    event AttestationRewarded(
        address indexed operator,
        uint256 rewardAmount,
        uint256 accuracyBonus
    );
}