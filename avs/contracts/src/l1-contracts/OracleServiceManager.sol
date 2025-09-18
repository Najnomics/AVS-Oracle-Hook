// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.27;

import {IAllocationManager} from "@eigenlayer-contracts/src/contracts/interfaces/IAllocationManager.sol";
import {IKeyRegistrar} from "@eigenlayer-contracts/src/contracts/interfaces/IKeyRegistrar.sol";
import {IPermissionController} from "@eigenlayer-contracts/src/contracts/interfaces/IPermissionController.sol";
import {TaskAVSRegistrarBase} from "@eigenlayer-middleware/src/avs/task/TaskAVSRegistrarBase.sol";
import {IOracleServiceManager} from "../interfaces/IOracleServiceManager.sol";

/**
 * @title OracleServiceManager
 * @notice EigenLayer L1 service manager for Oracle AVS
 * @dev This is the main service manager for the Oracle AVS that handles:
 * - Price attestation coordination and consensus
 * - Operator registration with staking requirements
 * - Slashing conditions for manipulation/inaccuracy
 * - Reward distribution for accurate operators
 * - Integration with Oracle Hook contracts
 */
contract OracleServiceManager is TaskAVSRegistrarBase, IOracleServiceManager {
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Address of the Oracle Hook contract  
    address public immutable oracleHook;
    
    /// @notice Minimum stake required for Oracle operators
    uint256 public constant MINIMUM_ORACLE_STAKE = 5 ether;
    
    /// @notice Maximum price deviation allowed (in basis points)
    uint256 public constant MAX_PRICE_DEVIATION = 500; // 5%
    
    /// @notice Consensus threshold required (in basis points)
    uint256 public constant CONSENSUS_THRESHOLD = 6600; // 66%
    
    /// @notice Attestation reward amount
    uint256 public constant ATTESTATION_REWARD = 0.001 ether;
    
    /// @notice Slash percentage for inaccurate attestations
    uint256 public constant SLASH_PERCENTAGE = 100; // 1%
    
    /// @notice Price attestations by ID
    mapping(bytes32 => PriceAttestation) public attestations;
    
    /// @notice Current consensus data by pool ID
    mapping(bytes32 => ConsensusResult) public consensus;
    
    /// @notice Operator performance tracking
    mapping(address => OperatorPerformance) public operatorPerformance;
    
    /// @notice Pool attestation history
    mapping(bytes32 => PriceAttestation[]) public poolAttestations;
    
    /// @notice Operators participating in current consensus
    mapping(bytes32 => address[]) public consensusOperators;
    
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
    
    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Constructor that passes parameters to parent TaskAVSRegistrarBase
     * @param _allocationManager The AllocationManager contract address
     * @param _keyRegistrar The KeyRegistrar contract address
     * @param _permissionController The PermissionController contract address
     * @param _oracleHook The address of the Oracle Hook contract
     */
    constructor(
        IAllocationManager _allocationManager,
        IKeyRegistrar _keyRegistrar,
        IPermissionController _permissionController,
        address _oracleHook
    ) TaskAVSRegistrarBase(_allocationManager, _keyRegistrar, _permissionController) {
        require(_oracleHook != address(0), "Invalid oracle hook address");
        oracleHook = _oracleHook;
    }

    /*//////////////////////////////////////////////////////////////
                              INITIALIZATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @dev Initializer that calls parent initializer
     * @param _avs The address of the AVS
     * @param _owner The owner of the contract
     * @param _initialConfig The initial AVS configuration
     */
    function initialize(address _avs, address _owner, AvsConfig memory _initialConfig) external initializer {
        __TaskAVSRegistrarBase_init(_avs, _owner, _initialConfig);
    }

    /*//////////////////////////////////////////////////////////////
                         ORACLE-SPECIFIC FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Register an operator specifically for Oracle tasks
     * @dev This extends the base registration with Oracle-specific requirements
     * @param operator The operator address to register
     * @param operatorSignature The operator's signature for EigenLayer
     */
    function registerOracleOperator(
        address operator,
        bytes calldata operatorSignature
    ) external payable {
        require(msg.value >= MINIMUM_ORACLE_STAKE, "Insufficient stake for Oracle operations");
        
        // Call parent registration logic (handles EigenLayer integration)
        _registerOperator(operator, operatorSignature);
        
        // Initialize operator performance
        operatorPerformance[operator] = OperatorPerformance({
            totalAttestations: 0,
            accurateAttestations: 0,
            totalStakeSlashed: 0,
            reliabilityScore: 5000, // Start at 50% reliability
            lastAttestationTime: 0
        });
        
        bytes32 operatorId = keccak256(abi.encodePacked(operator, block.timestamp));
        emit OracleOperatorRegistered(operator, operatorId);
    }

    /**
     * @notice Deregister an operator from Oracle tasks
     * @param operator The operator address to deregister
     */
    function deregisterOracleOperator(address operator) external {
        // Call parent deregistration logic
        _deregisterOperator(operator);
        
        bytes32 operatorId = keccak256(abi.encodePacked(operator, block.timestamp));
        emit OracleOperatorDeregistered(operator, operatorId);
    }

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
    ) external {
        require(price > 0, "Invalid price");
        require(_isRegistered(msg.sender), "Operator not registered");
        
        // Get operator stake amount
        uint256 operatorStake = _getOperatorStake(msg.sender);
        require(operatorStake >= MINIMUM_ORACLE_STAKE, "Insufficient stake");
        
        // Create attestation
        bytes32 attestationId = keccak256(abi.encodePacked(msg.sender, poolId, price, block.timestamp));
        
        attestations[attestationId] = PriceAttestation({
            operator: msg.sender,
            poolId: poolId,
            price: price,
            timestamp: block.timestamp,
            stakeAmount: operatorStake,
            sourceHash: sourceHash,
            signature: signature,
            isValid: true
        });
        
        // Add to pool attestations
        poolAttestations[poolId].push(attestations[attestationId]);
        
        // Update operator performance
        operatorPerformance[msg.sender].totalAttestations++;
        operatorPerformance[msg.sender].lastAttestationTime = block.timestamp;
        
        emit PriceAttestationSubmitted(attestationId, msg.sender, poolId, price, operatorStake);
        
        // Attempt to reach consensus
        _updateConsensus(poolId);
    }

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
    ) {
        ConsensusResult memory result = consensus[poolId];
        
        // Check if consensus is still valid (not too old)
        bool isValid = result.isValid && (block.timestamp - result.consensusTimestamp) <= 300; // 5 minutes
        
        return (isValid, result.weightedPrice, result.totalStake, result.confidenceLevel);
    }

    /**
     * @notice Get operators participating in consensus for a pool
     * @param poolId The pool ID
     * @return Array of operator addresses
     */
    function getConsensusOperators(bytes32 poolId) external view returns (address[] memory) {
        return consensusOperators[poolId];
    }

    /**
     * @notice Check if an operator meets Oracle requirements
     * @param operator The operator address to check
     * @return Whether the operator is qualified for Oracle operations
     */
    function isOracleOperatorQualified(address operator) external view returns (bool) {
        return _isRegistered(operator) && _getOperatorStake(operator) >= MINIMUM_ORACLE_STAKE;
    }

    /**
     * @notice Get the Oracle Hook contract address
     * @return The address of the Oracle Hook contract
     */
    function getOracleHook() external view returns (address) {
        return oracleHook;
    }

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
    ) {
        OperatorPerformance memory perf = operatorPerformance[operator];
        
        accuracyRate = perf.totalAttestations > 0 ? 
            (perf.accurateAttestations * 10000) / perf.totalAttestations : 0;
        
        return (
            perf.totalAttestations,
            accuracyRate,
            perf.reliabilityScore,
            perf.totalStakeSlashed
        );
    }

    /*//////////////////////////////////////////////////////////////
                           INTERNAL FUNCTIONS
    //////////////////////////////////////////////////////////////*/

    /**
     * @notice Update consensus for a pool based on recent attestations
     * @param poolId The pool ID to update consensus for
     */
    function _updateConsensus(bytes32 poolId) internal {
        PriceAttestation[] memory attestations = poolAttestations[poolId];
        
        // Filter recent attestations (within last 5 minutes)
        PriceAttestation[] memory recentAttestations = _getRecentAttestations(attestations);
        
        if (recentAttestations.length < 3) {
            return; // Need at least 3 attestations for consensus
        }
        
        // Calculate stake-weighted consensus
        (uint256 weightedPrice, uint256 totalStake, uint256 confidenceLevel) = 
            _calculateStakeWeightedConsensus(recentAttestations);
        
        // Check if consensus meets threshold
        if (confidenceLevel >= CONSENSUS_THRESHOLD) {
            consensus[poolId] = ConsensusResult({
                poolId: poolId,
                weightedPrice: weightedPrice,
                totalStake: totalStake,
                attestationCount: recentAttestations.length,
                confidenceLevel: confidenceLevel,
                consensusTimestamp: block.timestamp,
                isValid: true
            });
            
            // Track operators in consensus
            consensusOperators[poolId] = _getConsensusOperators(recentAttestations, weightedPrice);
            
            // Reward accurate operators and slash inaccurate ones
            _processOperatorRewards(recentAttestations, weightedPrice);
            
            emit ConsensusReached(poolId, weightedPrice, totalStake, recentAttestations.length, confidenceLevel);
        }
    }
    
    /**
     * @notice Calculate stake-weighted consensus price
     * @param attestations Array of recent attestations
     * @return weightedPrice Stake-weighted consensus price
     * @return totalStake Total stake backing the consensus
     * @return confidenceLevel Confidence level (0-10000)
     */
    function _calculateStakeWeightedConsensus(
        PriceAttestation[] memory attestations
    ) internal pure returns (uint256 weightedPrice, uint256 totalStake, uint256 confidenceLevel) {
        uint256 weightedSum = 0;
        totalStake = 0;
        
        // Calculate stake-weighted average price
        for (uint256 i = 0; i < attestations.length; i++) {
            PriceAttestation memory attestation = attestations[i];
            weightedSum += attestation.price * attestation.stakeAmount;
            totalStake += attestation.stakeAmount;
        }
        
        weightedPrice = weightedSum / totalStake;
        
        // Calculate confidence level based on price convergence
        uint256 convergenceScore = _calculateConvergenceScore(attestations, weightedPrice);
        confidenceLevel = (convergenceScore * totalStake) / (totalStake + 1 ether); // Normalize by stake
        
        return (weightedPrice, totalStake, confidenceLevel);
    }
    
    /**
     * @notice Calculate price convergence score
     * @param attestations Array of attestations
     * @param consensusPrice The consensus price
     * @return score Convergence score (0-10000)
     */
    function _calculateConvergenceScore(
        PriceAttestation[] memory attestations,
        uint256 consensusPrice
    ) internal pure returns (uint256 score) {
        uint256 totalDeviation = 0;
        
        for (uint256 i = 0; i < attestations.length; i++) {
            uint256 deviation = _getAbsoluteDeviation(attestations[i].price, consensusPrice);
            totalDeviation += deviation;
        }
        
        uint256 avgDeviation = totalDeviation / attestations.length;
        
        // Higher score for lower average deviation
        if (avgDeviation == 0) {
            return 10000; // Perfect convergence
        }
        
        // Score decreases as deviation increases
        score = 10000 * 100 / (100 + avgDeviation); // Scaled convergence score
        return score > 10000 ? 10000 : score;
    }
    
    /**
     * @notice Process operator rewards and slashing based on consensus
     * @param attestations Array of attestations
     * @param consensusPrice The consensus price
     */
    function _processOperatorRewards(
        PriceAttestation[] memory attestations,
        uint256 consensusPrice
    ) internal {
        for (uint256 i = 0; i < attestations.length; i++) {
            PriceAttestation memory attestation = attestations[i];
            uint256 deviation = _getAbsoluteDeviation(attestation.price, consensusPrice);
            
            if (deviation <= MAX_PRICE_DEVIATION) {
                // Reward accurate operator
                _rewardOperator(attestation.operator, ATTESTATION_REWARD);
                operatorPerformance[attestation.operator].accurateAttestations++;
            } else {
                // Slash inaccurate operator
                uint256 slashAmount = (attestation.stakeAmount * SLASH_PERCENTAGE) / 10000;
                _slashOperator(attestation.operator, slashAmount);
                operatorPerformance[attestation.operator].totalStakeSlashed += slashAmount;
                
                emit OperatorSlashed(attestation.operator, attestation.poolId, slashAmount, 
                    attestation.price, consensusPrice);
            }
        }
    }
    
    /**
     * @notice Get recent attestations (within last 5 minutes)
     * @param attestations Array of all attestations
     * @return recentAttestations Array of recent attestations
     */
    function _getRecentAttestations(
        PriceAttestation[] memory attestations
    ) internal view returns (PriceAttestation[] memory recentAttestations) {
        uint256 count = 0;
        uint256 cutoffTime = block.timestamp - 300; // 5 minutes ago
        
        // Count recent attestations
        for (uint256 i = 0; i < attestations.length; i++) {
            if (attestations[i].timestamp >= cutoffTime) {
                count++;
            }
        }
        
        // Create array of recent attestations
        recentAttestations = new PriceAttestation[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < attestations.length; i++) {
            if (attestations[i].timestamp >= cutoffTime) {
                recentAttestations[index] = attestations[i];
                index++;
            }
        }
        
        return recentAttestations;
    }
    
    /**
     * @notice Get operators that participated in consensus
     * @param attestations Array of attestations
     * @param consensusPrice The consensus price
     * @return operators Array of operator addresses
     */
    function _getConsensusOperators(
        PriceAttestation[] memory attestations,
        uint256 consensusPrice
    ) internal pure returns (address[] memory operators) {
        address[] memory tempOperators = new address[](attestations.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < attestations.length; i++) {
            uint256 deviation = _getAbsoluteDeviation(attestations[i].price, consensusPrice);
            if (deviation <= MAX_PRICE_DEVIATION) {
                tempOperators[count] = attestations[i].operator;
                count++;
            }
        }
        
        // Resize array to actual count
        operators = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            operators[i] = tempOperators[i];
        }
        
        return operators;
    }
    
    /**
     * @notice Calculate absolute deviation between two prices
     * @param price1 First price
     * @param price2 Second price
     * @return deviation Absolute deviation in basis points
     */
    function _getAbsoluteDeviation(uint256 price1, uint256 price2) internal pure returns (uint256) {
        return price1 > price2 ? 
            ((price1 - price2) * 10000) / price2 : 
            ((price2 - price1) * 10000) / price1;
    }
    
    /**
     * @notice Internal function to check operator registration
     * @param operator The operator address
     * @return Whether the operator is registered
     */
    function _isRegistered(address operator) internal view returns (bool) {
        // Implementation depends on TaskAVSRegistrarBase structure
        // This is a placeholder - actual implementation would check registration status
        return true; // TODO: Implement based on TaskAVSRegistrarBase
    }

    /**
     * @notice Internal function to get operator stake
     * @param operator The operator address
     * @return The operator's stake amount
     */
    function _getOperatorStake(address operator) internal view returns (uint256) {
        // Implementation depends on TaskAVSRegistrarBase structure  
        // This is a placeholder - actual implementation would return stake
        return 10 ether; // TODO: Implement based on TaskAVSRegistrarBase
    }
    
    /**
     * @notice Reward an operator for accurate attestation
     * @param operator The operator to reward
     * @param amount The reward amount
     */
    function _rewardOperator(address operator, uint256 amount) internal {
        // Implementation for operator reward distribution
        emit AttestationRewarded(operator, amount, 0);
    }
    
    /**
     * @notice Slash an operator for inaccurate attestation
     * @param operator The operator to slash
     * @param amount The slash amount
     */
    function _slashOperator(address operator, uint256 amount) internal {
        // Implementation for operator slashing through EigenLayer
        // This would integrate with EigenLayer's slashing mechanism
    }
}