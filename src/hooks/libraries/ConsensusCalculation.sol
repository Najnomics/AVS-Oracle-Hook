// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title ConsensusCalculation
 * @notice Library for calculating stake-weighted consensus and confidence levels
 * @dev Provides mathematical utilities for consensus formation in the Oracle system
 */
library ConsensusCalculation {
    
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/
    
    uint256 public constant BASIS_POINTS = 10000;
    uint256 public constant MIN_CONSENSUS_THRESHOLD = 5100;  // 51%
    uint256 public constant DEFAULT_CONSENSUS_THRESHOLD = 6600;  // 66%
    uint256 public constant SUPER_MAJORITY_THRESHOLD = 7500;  // 75%
    
    /*//////////////////////////////////////////////////////////////
                                STRUCTS
    //////////////////////////////////////////////////////////////*/
    
    struct AttestationData {
        address operator;
        uint256 price;
        uint256 stake;
        uint256 timestamp;
        uint256 reliability;  // Operator reliability score (0-10000)
    }
    
    struct ConsensusResult {
        uint256 consensusPrice;
        uint256 totalStake;
        uint256 participatingStake;
        uint256 confidenceLevel;
        uint256 convergenceScore;
        bool hasConsensus;
    }
    
    /*//////////////////////////////////////////////////////////////
                        CONSENSUS CALCULATION FUNCTIONS
    //////////////////////////////////////////////////////////////*/
    
    /**
     * @notice Calculate stake-weighted consensus from multiple attestations
     * @param attestations Array of price attestations with stake amounts
     * @param consensusThreshold Minimum threshold for consensus (in basis points)
     * @return result Comprehensive consensus result
     */
    function calculateConsensus(
        AttestationData[] memory attestations,
        uint256 consensusThreshold
    ) internal pure returns (ConsensusResult memory result) {
        require(attestations.length > 0, "No attestations provided");
        require(consensusThreshold >= MIN_CONSENSUS_THRESHOLD, "Threshold too low");
        
        // Calculate total stake
        uint256 totalStake = 0;
        for (uint256 i = 0; i < attestations.length; i++) {
            totalStake += attestations[i].stake;
        }
        
        if (totalStake == 0) {
            return ConsensusResult({
                consensusPrice: 0,
                totalStake: 0,
                participatingStake: 0,
                confidenceLevel: 0,
                convergenceScore: 0,
                hasConsensus: false
            });
        }
        
        // Calculate weighted average price
        uint256 weightedSum = 0;
        uint256 reliabilityWeightedSum = 0;
        uint256 totalReliabilityWeight = 0;
        
        for (uint256 i = 0; i < attestations.length; i++) {
            AttestationData memory attestation = attestations[i];
            
            // Standard stake weighting
            weightedSum += attestation.price * attestation.stake;
            
            // Reliability-adjusted weighting
            uint256 reliabilityWeight = attestation.stake * attestation.reliability / BASIS_POINTS;
            reliabilityWeightedSum += attestation.price * reliabilityWeight;
            totalReliabilityWeight += reliabilityWeight;
        }
        
        // Use reliability-adjusted price if available, otherwise use standard
        uint256 consensusPrice = totalReliabilityWeight > 0 ? 
            reliabilityWeightedSum / totalReliabilityWeight :
            weightedSum / totalStake;
        
        // Calculate convergence score (how tightly prices cluster)
        uint256 convergenceScore = calculateConvergence(attestations, consensusPrice);
        
        // Calculate confidence level
        uint256 confidenceLevel = calculateConfidenceLevel(
            attestations,
            consensusPrice,
            totalStake,
            convergenceScore
        );
        
        // Determine if consensus is reached
        bool hasConsensus = confidenceLevel >= consensusThreshold;
        
        return ConsensusResult({
            consensusPrice: consensusPrice,
            totalStake: totalStake,
            participatingStake: totalStake, // All stake participates in this implementation
            confidenceLevel: confidenceLevel,
            convergenceScore: convergenceScore,
            hasConsensus: hasConsensus
        });
    }
    
    /**
     * @notice Calculate how tightly prices converge around the consensus
     * @param attestations Array of attestations
     * @param consensusPrice The calculated consensus price
     * @return convergenceScore Score from 0-10000 (higher = better convergence)
     */
    function calculateConvergence(
        AttestationData[] memory attestations,
        uint256 consensusPrice
    ) internal pure returns (uint256 convergenceScore) {
        if (attestations.length == 0 || consensusPrice == 0) return 0;
        
        uint256 totalDeviation = 0;
        uint256 maxDeviation = 0;
        
        // Calculate average and maximum deviations
        for (uint256 i = 0; i < attestations.length; i++) {
            uint256 price = attestations[i].price;
            uint256 deviation = price > consensusPrice ? 
                ((price - consensusPrice) * BASIS_POINTS) / consensusPrice :
                ((consensusPrice - price) * BASIS_POINTS) / consensusPrice;
            
            totalDeviation += deviation;
            if (deviation > maxDeviation) {
                maxDeviation = deviation;
            }
        }
        
        uint256 avgDeviation = totalDeviation / attestations.length;
        
        // Convergence score decreases with higher deviation
        // Perfect convergence (0 deviation) = 10000
        // 10% average deviation = ~5000 score
        // 25% average deviation = ~2000 score
        if (avgDeviation >= BASIS_POINTS) return 0;
        
        uint256 baseScore = BASIS_POINTS - avgDeviation;
        
        // Penalty for high maximum deviation (prevents outlier manipulation)
        uint256 outlierPenalty = maxDeviation > 2000 ? (maxDeviation - 2000) / 2 : 0;
        
        convergenceScore = baseScore > outlierPenalty ? baseScore - outlierPenalty : 0;
        
        return convergenceScore;
    }
    
    /**
     * @notice Calculate overall confidence level for the consensus
     * @param attestations Array of attestations
     * @param consensusPrice The calculated consensus price
     * @param totalStake Total stake participating
     * @param convergenceScore How well prices converge
     * @return confidenceLevel Overall confidence (0-10000)
     */
    function calculateConfidenceLevel(
        AttestationData[] memory attestations,
        uint256 consensusPrice,
        uint256 totalStake,
        uint256 convergenceScore
    ) internal pure returns (uint256 confidenceLevel) {
        
        // Base confidence from convergence (40% weight)
        uint256 convergenceComponent = (convergenceScore * 4000) / BASIS_POINTS;
        
        // Stake distribution component (30% weight)
        uint256 stakeComponent = calculateStakeDistributionScore(attestations, totalStake);
        stakeComponent = (stakeComponent * 3000) / BASIS_POINTS;
        
        // Operator count component (20% weight)
        uint256 operatorComponent = calculateOperatorCountScore(attestations.length);
        operatorComponent = (operatorComponent * 2000) / BASIS_POINTS;
        
        // Reliability component (10% weight)
        uint256 reliabilityComponent = calculateAverageReliability(attestations);
        reliabilityComponent = (reliabilityComponent * 1000) / BASIS_POINTS;
        
        confidenceLevel = convergenceComponent + stakeComponent + operatorComponent + reliabilityComponent;
        
        return confidenceLevel > BASIS_POINTS ? BASIS_POINTS : confidenceLevel;
    }
    
    /**
     * @notice Calculate score based on stake distribution (prevents centralization)
     * @param attestations Array of attestations
     * @param totalStake Total stake amount
     * @return distributionScore Score from 0-10000
     */
    function calculateStakeDistributionScore(
        AttestationData[] memory attestations,
        uint256 totalStake
    ) internal pure returns (uint256 distributionScore) {
        if (attestations.length <= 1 || totalStake == 0) return 0;
        
        // Calculate Gini coefficient for stake distribution
        uint256 sumOfAbsoluteDifferences = 0;
        
        for (uint256 i = 0; i < attestations.length; i++) {
            for (uint256 j = i + 1; j < attestations.length; j++) {
                uint256 diff = attestations[i].stake > attestations[j].stake ?
                    attestations[i].stake - attestations[j].stake :
                    attestations[j].stake - attestations[i].stake;
                sumOfAbsoluteDifferences += diff;
            }
        }
        
        // Gini coefficient approximation
        uint256 giniNumerator = sumOfAbsoluteDifferences;
        uint256 giniDenominator = attestations.length * attestations.length * totalStake / attestations.length;
        
        if (giniDenominator == 0) return 0;
        
        uint256 giniCoeff = (giniNumerator * BASIS_POINTS) / giniDenominator;
        
        // Lower Gini = more distributed = higher score
        distributionScore = giniCoeff >= BASIS_POINTS ? 0 : BASIS_POINTS - giniCoeff;
        
        return distributionScore;
    }
    
    /**
     * @notice Calculate score based on number of participating operators
     * @param operatorCount Number of operators
     * @return countScore Score from 0-10000
     */
    function calculateOperatorCountScore(uint256 operatorCount) internal pure returns (uint256 countScore) {
        // More operators = higher confidence, with diminishing returns
        if (operatorCount == 0) return 0;
        if (operatorCount == 1) return 2000;  // 20%
        if (operatorCount == 2) return 4000;  // 40%
        if (operatorCount == 3) return 6000;  // 60%
        if (operatorCount == 4) return 7500;  // 75%
        if (operatorCount >= 5) return 10000; // 100%
        
        return 0;
    }
    
    /**
     * @notice Calculate average reliability score of participating operators
     * @param attestations Array of attestations
     * @return avgReliability Average reliability score (0-10000)
     */
    function calculateAverageReliability(
        AttestationData[] memory attestations
    ) internal pure returns (uint256 avgReliability) {
        if (attestations.length == 0) return 0;
        
        uint256 totalReliability = 0;
        for (uint256 i = 0; i < attestations.length; i++) {
            totalReliability += attestations[i].reliability;
        }
        
        avgReliability = totalReliability / attestations.length;
        return avgReliability;
    }
    
    /**
     * @notice Filter attestations that deviate too much from median
     * @param attestations Array of attestations to filter
     * @param maxDeviationBps Maximum allowed deviation from median (in basis points)
     * @return filteredAttestations Array with outliers removed
     */
    function filterOutliers(
        AttestationData[] memory attestations,
        uint256 maxDeviationBps
    ) internal pure returns (AttestationData[] memory filteredAttestations) {
        if (attestations.length <= 2) return attestations; // Can't filter with too few data points
        
        // Calculate median price
        uint256[] memory prices = new uint256[](attestations.length);
        for (uint256 i = 0; i < attestations.length; i++) {
            prices[i] = attestations[i].price;
        }
        
        uint256 medianPrice = _calculateMedian(prices);
        
        // Count non-outliers first
        uint256 validCount = 0;
        for (uint256 i = 0; i < attestations.length; i++) {
            uint256 deviation = attestations[i].price > medianPrice ?
                ((attestations[i].price - medianPrice) * BASIS_POINTS) / medianPrice :
                ((medianPrice - attestations[i].price) * BASIS_POINTS) / medianPrice;
            
            if (deviation <= maxDeviationBps) {
                validCount++;
            }
        }
        
        // Create filtered array
        filteredAttestations = new AttestationData[](validCount);
        uint256 index = 0;
        
        for (uint256 i = 0; i < attestations.length; i++) {
            uint256 deviation = attestations[i].price > medianPrice ?
                ((attestations[i].price - medianPrice) * BASIS_POINTS) / medianPrice :
                ((medianPrice - attestations[i].price) * BASIS_POINTS) / medianPrice;
            
            if (deviation <= maxDeviationBps) {
                filteredAttestations[index] = attestations[i];
                index++;
            }
        }
        
        return filteredAttestations;
    }
    
    /**
     * @notice Calculate median of an array of prices
     * @param prices Array of prices
     * @return median The median price
     */
    function _calculateMedian(uint256[] memory prices) private pure returns (uint256 median) {
        // Simple bubble sort for small arrays
        for (uint256 i = 0; i < prices.length; i++) {
            for (uint256 j = 0; j < prices.length - 1 - i; j++) {
                if (prices[j] > prices[j + 1]) {
                    uint256 temp = prices[j];
                    prices[j] = prices[j + 1];
                    prices[j + 1] = temp;
                }
            }
        }
        
        if (prices.length % 2 == 0) {
            // Even number of elements - average of middle two
            median = (prices[prices.length / 2 - 1] + prices[prices.length / 2]) / 2;
        } else {
            // Odd number of elements - middle element
            median = prices[prices.length / 2];
        }
        
        return median;
    }
}