// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IOracleAVS} from "../../src/interfaces/IOracleAVS.sol";

/**
 * @title MockOracleAVS
 * @notice Mock Oracle AVS for testing the Oracle Hook
 */
contract MockOracleAVS is IOracleAVS {
    
    struct ConsensusData {
        uint256 price;
        uint256 totalStake;
        uint256 confidenceLevel;
        uint256 timestamp;
        bool isValid;
    }
    
    mapping(bytes32 => ConsensusData) public poolConsensus;
    mapping(bytes32 => address[]) public consensusOperators;
    
    // Test control variables
    bool public shouldReturnValidConsensus = true;
    uint256 public mockPrice = 2105 * 1e18; // $2,105
    uint256 public mockStake = 100 ether;
    uint256 public mockConfidence = 8500; // 85%
    
    function setMockConsensus(
        bytes32 poolId,
        uint256 price,
        uint256 stake,
        uint256 confidence,
        bool isValid
    ) external {
        poolConsensus[poolId] = ConsensusData({
            price: price,
            totalStake: stake,
            confidenceLevel: confidence,
            timestamp: block.timestamp,
            isValid: isValid
        });
    }
    
    function setConsensusOperators(bytes32 poolId, address[] calldata operators) external {
        consensusOperators[poolId] = operators;
    }
    
    function setShouldReturnValidConsensus(bool valid) external {
        shouldReturnValidConsensus = valid;
    }
    
    function setMockPrice(uint256 price) external {
        mockPrice = price;
    }
    
    function setMockStake(uint256 stake) external {
        mockStake = stake;
    }
    
    function setMockConfidence(uint256 confidence) external {
        mockConfidence = confidence;
    }
    
    function getCurrentConsensus(bytes32 poolId) external view returns (
        bool hasConsensus,
        uint256 consensusPrice,
        uint256 totalStake,
        uint256 confidenceLevel,
        uint256 lastUpdateTimestamp
    ) {
        ConsensusData memory data = poolConsensus[poolId];
        
        if (data.timestamp == 0) {
            // Return mock data if no specific data set
            return (
                shouldReturnValidConsensus,
                mockPrice,
                mockStake,
                mockConfidence,
                block.timestamp
            );
        }
        
        return (
            data.isValid && shouldReturnValidConsensus,
            data.price,
            data.totalStake,
            data.confidenceLevel,
            data.timestamp
        );
    }
    
    function getConsensusOperators(bytes32 poolId) external view returns (address[] memory) {
        return consensusOperators[poolId];
    }
    
    // Helper function to simulate consensus failures
    function simulateConsensusFailure() external {
        shouldReturnValidConsensus = false;
    }
    
    function simulateStaleData(bytes32 poolId) external {
        // Use max(0, block.timestamp - 400) to avoid underflow
        // Make sure it's more than 300 seconds old (MAX_PRICE_STALENESS)
        uint256 staleTimestamp = block.timestamp > 400 ? block.timestamp - 400 : 1;
        poolConsensus[poolId] = ConsensusData({
            price: mockPrice,
            totalStake: mockStake,
            confidenceLevel: mockConfidence,
            timestamp: staleTimestamp, // 400 seconds ago (stale)
            isValid: true
        });
    }
    
    function simulateLowStake(bytes32 poolId) external {
        poolConsensus[poolId] = ConsensusData({
            price: mockPrice,
            totalStake: 1 ether, // Very low stake
            confidenceLevel: mockConfidence,
            timestamp: block.timestamp,
            isValid: true
        });
    }
    
    function simulateLowConfidence(bytes32 poolId) external {
        poolConsensus[poolId] = ConsensusData({
            price: mockPrice,
            totalStake: mockStake,
            confidenceLevel: 5000, // 50% confidence (below threshold)
            timestamp: block.timestamp,
            isValid: true
        });
    }
}