// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title MockOracleAVS
 * @notice Mock Oracle AVS for testing the Oracle Hook
 */
contract MockOracleAVS {
    
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
        uint256 confidenceLevel
    ) {
        ConsensusData memory data = poolConsensus[poolId];
        
        if (data.timestamp == 0) {
            // Return mock data if no specific data set
            return (
                shouldReturnValidConsensus,
                mockPrice,
                mockStake,
                mockConfidence
            );
        }
        
        return (
            data.isValid && shouldReturnValidConsensus,
            data.price,
            data.totalStake,
            data.confidenceLevel
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
        ConsensusData storage data = poolConsensus[poolId];
        data.timestamp = block.timestamp - 400; // 400 seconds ago (stale)
    }
    
    function simulateLowStake(bytes32 poolId) external {
        ConsensusData storage data = poolConsensus[poolId];
        data.totalStake = 1 ether; // Very low stake
    }
    
    function simulateLowConfidence(bytes32 poolId) external {
        ConsensusData storage data = poolConsensus[poolId];
        data.confidenceLevel = 5000; // 50% confidence (below threshold)
    }
}