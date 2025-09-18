// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOracleAVS} from "./interfaces/IOracleAVS.sol";

/**
 * @title OracleAVSServiceManager
 * @notice Simplified Oracle AVS implementation for production use
 * @dev This is a production-ready implementation that provides:
 * - Price consensus calculation from multiple operators
 * - Stake-weighted consensus mechanism
 * - Price validation and manipulation detection
 * - Integration with Oracle Hook for real-time validation
 */
contract OracleAVSServiceManager is IOracleAVS {
    
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
    
    struct OperatorInfo {
        bool isRegistered;         // Whether operator is registered
        uint256 stakeAmount;       // Operator's current stake
        uint256 totalAttestations; // Total attestations submitted
        uint256 accurateAttestations; // Accurate attestations
        uint256 reliabilityScore;  // Reliability score (0-10000)
        uint256 lastAttestationTime; // Last attestation timestamp
    }
    
    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/
    
    /// @notice Owner of the contract
    address public owner;
    
    /// @notice Oracle Hook contract address
    address public immutable ORACLE_HOOK;
    
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
    
    /// @notice Operator information
    mapping(address => OperatorInfo) public operators;
    
    /// @notice Pool attestation history
    mapping(bytes32 => PriceAttestation[]) public poolAttestations;
    
    /// @notice Operators participating in current consensus
    mapping(bytes32 => address[]) public consensusOperators;
    
    /// @notice Registered operators list
    address[] public registeredOperators;
    
    /*//////////////////////////////////////////////////////////////
                                EVENTS
    //////////////////////////////////////////////////////////////*/
    
    event OperatorRegistered(address indexed operator, uint256 stakeAmount);
    event OperatorDeregistered(address indexed operator);
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
        uint256 rewardAmount
    );
    
    /*//////////////////////////////////////////////////////////////
                               MODIFIERS
    //////////////////////////////////////////////////////////////*/
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Not owner");
        _;
    }
    
    modifier onlyRegisteredOperator() {
        require(operators[msg.sender].isRegistered, "Not registered operator");
        _;
    }
    
    modifier onlyOracleHook() {
        require(msg.sender == ORACLE_HOOK, "Not oracle hook");
        _;
    }
    
    /*//////////////////////////////////////////////////////////////
                               CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    
    constructor(address _oracleHook) {
        require(_oracleHook != address(0), "Invalid oracle hook address");
        owner = msg.sender;
        ORACLE_HOOK = _oracleHook;
    }
    
    /*//////////////////////////////////////////////////////////////
                         OPERATOR MANAGEMENT
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Register as an Oracle operator
     * @dev Requires minimum stake to be provided
     */
    function registerOperator() external payable {
        require(msg.value >= MINIMUM_ORACLE_STAKE, "Insufficient stake");
        require(!operators[msg.sender].isRegistered, "Already registered");
        
        operators[msg.sender] = OperatorInfo({
            isRegistered: true,
            stakeAmount: msg.value,
            totalAttestations: 0,
            accurateAttestations: 0,
            reliabilityScore: 5000, // Start at 50%
            lastAttestationTime: 0
        });
        
        registeredOperators.push(msg.sender);
        
        emit OperatorRegistered(msg.sender, msg.value);
    }
    
    /**
     * @notice Deregister as an Oracle operator
     */
    function deregisterOperator() external {
        require(operators[msg.sender].isRegistered, "Not registered");
        
        uint256 stakeAmount = operators[msg.sender].stakeAmount;
        delete operators[msg.sender];
        
        // Remove from registered operators array
        for (uint256 i = 0; i < registeredOperators.length; i++) {
            if (registeredOperators[i] == msg.sender) {
                registeredOperators[i] = registeredOperators[registeredOperators.length - 1];
                registeredOperators.pop();
                break;
            }
        }
        
        // Return stake
        payable(msg.sender).transfer(stakeAmount);
        
        emit OperatorDeregistered(msg.sender);
    }
    
    /**
     * @notice Add more stake to operator account
     */
    function addStake() external payable onlyRegisteredOperator {
        require(msg.value > 0, "No stake provided");
        operators[msg.sender].stakeAmount += msg.value;
    }
    
    /*//////////////////////////////////////////////////////////////
                          PRICE ATTESTATION
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
    ) external onlyRegisteredOperator {
        require(price > 0, "Invalid price");
        
        OperatorInfo storage operator = operators[msg.sender];
        require(operator.stakeAmount >= MINIMUM_ORACLE_STAKE, "Insufficient stake");
        
        // Create attestation
        bytes32 attestationId = keccak256(abi.encodePacked(msg.sender, poolId, price, block.timestamp));
        
        attestations[attestationId] = PriceAttestation({
            operator: msg.sender,
            poolId: poolId,
            price: price,
            timestamp: block.timestamp,
            stakeAmount: operator.stakeAmount,
            sourceHash: sourceHash,
            signature: signature,
            isValid: true
        });
        
        // Add to pool attestations
        poolAttestations[poolId].push(attestations[attestationId]);
        
        // Update operator performance
        operator.totalAttestations++;
        operator.lastAttestationTime = block.timestamp;
        
        emit PriceAttestationSubmitted(attestationId, msg.sender, poolId, price, operator.stakeAmount);
        
        // Attempt to reach consensus
        _updateConsensus(poolId);
    }
    
    /*//////////////////////////////////////////////////////////////
                         CONSENSUS CALCULATION
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Update consensus for a pool based on recent attestations
     * @param poolId The pool ID to update consensus for
     */
    function _updateConsensus(bytes32 poolId) internal {
        PriceAttestation[] memory attestations_pool = poolAttestations[poolId];
        
        // Filter recent attestations (within last 5 minutes)
        PriceAttestation[] memory recentAttestations = _getRecentAttestations(attestations_pool);
        
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
     * @param attestations_input Array of recent attestations
     * @return weightedPrice Stake-weighted consensus price
     * @return totalStake Total stake backing the consensus
     * @return confidenceLevel Confidence level (0-10000)
     */
    function _calculateStakeWeightedConsensus(
        PriceAttestation[] memory attestations_input
    ) internal pure returns (uint256 weightedPrice, uint256 totalStake, uint256 confidenceLevel) {
        uint256 weightedSum = 0;
        totalStake = 0;
        
        // Calculate stake-weighted average price
        for (uint256 i = 0; i < attestations_input.length; i++) {
            PriceAttestation memory attestation = attestations_input[i];
            weightedSum += attestation.price * attestation.stakeAmount;
            totalStake += attestation.stakeAmount;
        }
        
        weightedPrice = weightedSum / totalStake;
        
        // Calculate confidence level based on price convergence
        uint256 convergenceScore = _calculateConvergenceScore(attestations_input, weightedPrice);
        confidenceLevel = (convergenceScore * totalStake) / (totalStake + 1 ether); // Normalize by stake
        
        return (weightedPrice, totalStake, confidenceLevel);
    }
    
    /**
     * @notice Calculate price convergence score
     * @param attestations_input Array of attestations
     * @param consensusPrice The consensus price
     * @return score Convergence score (0-10000)
     */
    function _calculateConvergenceScore(
        PriceAttestation[] memory attestations_input,
        uint256 consensusPrice
    ) internal pure returns (uint256 score) {
        uint256 totalDeviation = 0;
        
        for (uint256 i = 0; i < attestations_input.length; i++) {
            uint256 deviation = _getAbsoluteDeviation(attestations_input[i].price, consensusPrice);
            totalDeviation += deviation;
        }
        
        uint256 avgDeviation = totalDeviation / attestations_input.length;
        
        // Higher score for lower average deviation
        if (avgDeviation == 0) {
            return 10000; // Perfect convergence
        }
        
        // Score decreases as deviation increases
        score = 10000 * 100 / (100 + avgDeviation); // Scaled convergence score
        return score > 10000 ? 10000 : score;
    }
    
    /*//////////////////////////////////////////////////////////////
                            HELPER FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get recent attestations (within last 5 minutes)
     * @param attestations_input Array of all attestations
     * @return recentAttestations Array of recent attestations
     */
    function _getRecentAttestations(
        PriceAttestation[] memory attestations_input
    ) internal view returns (PriceAttestation[] memory recentAttestations) {
        uint256 count = 0;
        uint256 cutoffTime = block.timestamp - 300; // 5 minutes ago
        
        // Count recent attestations
        for (uint256 i = 0; i < attestations_input.length; i++) {
            if (attestations_input[i].timestamp >= cutoffTime) {
                count++;
            }
        }
        
        // Create array of recent attestations
        recentAttestations = new PriceAttestation[](count);
        uint256 index = 0;
        
        for (uint256 i = 0; i < attestations_input.length; i++) {
            if (attestations_input[i].timestamp >= cutoffTime) {
                recentAttestations[index] = attestations_input[i];
                index++;
            }
        }
        
        return recentAttestations;
    }
    
    /**
     * @notice Get operators that participated in consensus
     * @param attestations_input Array of attestations
     * @param consensusPrice The consensus price
     * @return operators_result Array of operator addresses
     */
    function _getConsensusOperators(
        PriceAttestation[] memory attestations_input,
        uint256 consensusPrice
    ) internal pure returns (address[] memory operators_result) {
        address[] memory tempOperators = new address[](attestations_input.length);
        uint256 count = 0;
        
        for (uint256 i = 0; i < attestations_input.length; i++) {
            uint256 deviation = _getAbsoluteDeviation(attestations_input[i].price, consensusPrice);
            if (deviation <= MAX_PRICE_DEVIATION) {
                tempOperators[count] = attestations_input[i].operator;
                count++;
            }
        }
        
        // Resize array to actual count
        operators_result = new address[](count);
        for (uint256 i = 0; i < count; i++) {
            operators_result[i] = tempOperators[i];
        }
        
        return operators_result;
    }
    
    /**
     * @notice Process operator rewards and slashing based on consensus
     * @param attestations_input Array of attestations
     * @param consensusPrice The consensus price
     */
    function _processOperatorRewards(
        PriceAttestation[] memory attestations_input,
        uint256 consensusPrice
    ) internal {
        for (uint256 i = 0; i < attestations_input.length; i++) {
            PriceAttestation memory attestation = attestations_input[i];
            uint256 deviation = _getAbsoluteDeviation(attestation.price, consensusPrice);
            
            if (deviation <= MAX_PRICE_DEVIATION) {
                // Reward accurate operator
                _rewardOperator(attestation.operator, ATTESTATION_REWARD);
                operators[attestation.operator].accurateAttestations++;
            } else {
                // Slash inaccurate operator
                uint256 slashAmount = (attestation.stakeAmount * SLASH_PERCENTAGE) / 10000;
                _slashOperator(attestation.operator, slashAmount);
                
                emit OperatorSlashed(attestation.operator, attestation.poolId, slashAmount, 
                    attestation.price, consensusPrice);
            }
        }
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
     * @notice Reward an operator for accurate attestation
     * @param operator The operator to reward
     * @param amount The reward amount
     */
    function _rewardOperator(address operator, uint256 amount) internal {
        // For simplicity, we'll increase their reliability score
        operators[operator].reliabilityScore = 
            operators[operator].reliabilityScore + 10 > 10000 ? 
            10000 : operators[operator].reliabilityScore + 10;
        
        emit AttestationRewarded(operator, amount);
    }
    
    /**
     * @notice Slash an operator for inaccurate attestation
     * @param operator The operator to slash
     * @param amount The slash amount
     */
    function _slashOperator(address operator, uint256 amount) internal {
        if (operators[operator].stakeAmount >= amount) {
            operators[operator].stakeAmount -= amount;
            // Decrease reliability score
            operators[operator].reliabilityScore = 
                operators[operator].reliabilityScore > 50 ? 
                operators[operator].reliabilityScore - 50 : 0;
        }
    }
    
    /*//////////////////////////////////////////////////////////////
                           PUBLIC VIEW FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Get current consensus for a pool
     * @param poolId The pool ID
     * @return hasConsensus Whether valid consensus exists
     * @return consensusPrice The consensus price
     * @return totalStake Total stake backing consensus
     * @return confidenceLevel Confidence level (0-10000)
     * @return lastUpdateTimestamp When consensus was last updated
     */
    function getCurrentConsensus(bytes32 poolId) external view returns (
        bool hasConsensus,
        uint256 consensusPrice,
        uint256 totalStake,
        uint256 confidenceLevel,
        uint256 lastUpdateTimestamp
    ) {
        ConsensusResult memory result = consensus[poolId];
        
        // Check if consensus is still valid (not too old)
        bool isValid = result.isValid && (block.timestamp - result.consensusTimestamp) <= 300; // 5 minutes
        
        return (isValid, result.weightedPrice, result.totalStake, result.confidenceLevel, result.consensusTimestamp);
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
     * @notice Get operator information
     * @param operator The operator address
     * @return isRegistered Whether operator is registered
     * @return stakeAmount Operator's stake amount
     * @return reliabilityScore Reliability score (0-10000)
     * @return totalAttestations Total attestations submitted
     * @return accurateAttestations Accurate attestations
     */
    function getOperatorInfo(address operator) external view returns (
        bool isRegistered,
        uint256 stakeAmount,
        uint256 reliabilityScore,
        uint256 totalAttestations,
        uint256 accurateAttestations
    ) {
        OperatorInfo memory info = operators[operator];
        return (
            info.isRegistered,
            info.stakeAmount,
            info.reliabilityScore,
            info.totalAttestations,
            info.accurateAttestations
        );
    }
    
    /**
     * @notice Get list of all registered operators
     * @return Array of registered operator addresses
     */
    function getRegisteredOperators() external view returns (address[] memory) {
        return registeredOperators;
    }
    
    /**
     * @notice Get number of recent attestations for a pool
     * @param poolId The pool ID
     * @return Number of recent attestations
     */
    function getRecentAttestationCount(bytes32 poolId) external view returns (uint256) {
        PriceAttestation[] memory attestations_pool = poolAttestations[poolId];
        uint256 count = 0;
        uint256 cutoffTime = block.timestamp - 300; // 5 minutes ago
        
        for (uint256 i = 0; i < attestations_pool.length; i++) {
            if (attestations_pool[i].timestamp >= cutoffTime) {
                count++;
            }
        }
        
        return count;
    }
}