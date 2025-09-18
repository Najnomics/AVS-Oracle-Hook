// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IOracleAVS
 * @notice Interface for Oracle AVS Service Manager
 */
interface IOracleAVS {
    /**
     * @notice Get current consensus data for a pool
     * @param poolId Pool identifier
     * @return hasConsensus Whether consensus exists
     * @return consensusPrice Current consensus price
     * @return totalStake Total stake backing consensus
     * @return confidenceLevel Confidence level (0-10000 BPS)
     * @return lastUpdateTimestamp When consensus was last updated
     */
    function getCurrentConsensus(bytes32 poolId) external view returns (
        bool hasConsensus,
        uint256 consensusPrice,
        uint256 totalStake,
        uint256 confidenceLevel,
        uint256 lastUpdateTimestamp
    );
    
    /**
     * @notice Get operators participating in consensus for a pool
     * @param poolId Pool identifier
     * @return operators Array of operator addresses
     */
    function getConsensusOperators(bytes32 poolId) external view returns (address[] memory operators);
}