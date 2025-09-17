// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {ConsensusCalculation} from "../../src/hooks/libraries/ConsensusCalculation.sol";
import {TestUtils} from "../utils/TestUtils.sol";

contract ConsensusCalculationTest is Test {
    using ConsensusCalculation for *;
    
    uint256 constant BASIS_POINTS = 10000;
    uint256 constant BASE_PRICE = 2000 * 1e18;
    
    address[] operators;
    
    function setUp() public {
        operators = TestUtils.createTestOperators();
    }
    
    /*//////////////////////////////////////////////////////////////
                         BASIC CONSENSUS TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_CalculateConsensus_SingleAttestation() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](1);
        attestations[0] = ConsensusCalculation.AttestationData({
            operator: operators[0],
            price: BASE_PRICE,
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000 // 80%
        });
        
        ConsensusCalculation.ConsensusResult memory result = ConsensusCalculation.calculateConsensus(
            attestations,
            ConsensusCalculation.DEFAULT_CONSENSUS_THRESHOLD
        );
        
        assertEq(result.consensusPrice, BASE_PRICE);
        assertEq(result.totalStake, 100 ether);
        assertEq(result.participatingStake, 100 ether);
        // Single attestation should have low confidence due to operator count
        assertLt(result.confidenceLevel, ConsensusCalculation.DEFAULT_CONSENSUS_THRESHOLD);
        assertFalse(result.hasConsensus);
    }
    
    function test_CalculateConsensus_MultipleAttestations_Convergent() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](3);
        
        // Create convergent prices (within 1% of each other)
        attestations[0] = ConsensusCalculation.AttestationData({
            operator: operators[0],
            price: BASE_PRICE,
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        attestations[1] = ConsensusCalculation.AttestationData({
            operator: operators[1],
            price: BASE_PRICE + (BASE_PRICE * 50) / BASIS_POINTS, // +0.5%
            stake: 150 ether,
            timestamp: block.timestamp,
            reliability: 9000
        });
        
        attestations[2] = ConsensusCalculation.AttestationData({
            operator: operators[2],
            price: BASE_PRICE - (BASE_PRICE * 30) / BASIS_POINTS, // -0.3%
            stake: 120 ether,
            timestamp: block.timestamp,
            reliability: 7500
        });
        
        ConsensusCalculation.ConsensusResult memory result = ConsensusCalculation.calculateConsensus(
            attestations,
            ConsensusCalculation.DEFAULT_CONSENSUS_THRESHOLD
        );
        
        // Should reach consensus with convergent prices
        assertTrue(result.hasConsensus);
        assertGt(result.confidenceLevel, ConsensusCalculation.DEFAULT_CONSENSUS_THRESHOLD);
        assertEq(result.totalStake, 370 ether);
        
        // Consensus price should be weighted by stake and reliability
        assertGt(result.consensusPrice, BASE_PRICE - (BASE_PRICE * 100) / BASIS_POINTS); // Within reasonable range
        assertLt(result.consensusPrice, BASE_PRICE + (BASE_PRICE * 100) / BASIS_POINTS);
    }
    
    function test_CalculateConsensus_MultipleAttestations_Divergent() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](3);
        
        // Create divergent prices
        attestations[0] = ConsensusCalculation.AttestationData({
            operator: operators[0],
            price: BASE_PRICE,
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        attestations[1] = ConsensusCalculation.AttestationData({
            operator: operators[1],
            price: BASE_PRICE * 120 / 100, // +20%
            stake: 50 ether,
            timestamp: block.timestamp,
            reliability: 6000
        });
        
        attestations[2] = ConsensusCalculation.AttestationData({
            operator: operators[2],
            price: BASE_PRICE * 80 / 100, // -20%
            stake: 75 ether,
            timestamp: block.timestamp,
            reliability: 7000
        });
        
        ConsensusCalculation.ConsensusResult memory result = ConsensusCalculation.calculateConsensus(
            attestations,
            ConsensusCalculation.DEFAULT_CONSENSUS_THRESHOLD
        );
        
        // Should not reach consensus due to divergent prices
        assertFalse(result.hasConsensus);
        assertLt(result.confidenceLevel, ConsensusCalculation.DEFAULT_CONSENSUS_THRESHOLD);
        assertLt(result.convergenceScore, 8000); // Low convergence
    }
    
    function test_CalculateConsensus_NoAttestations() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](0);
        
        vm.expectRevert("No attestations provided");
        ConsensusCalculation.calculateConsensus(attestations, ConsensusCalculation.DEFAULT_CONSENSUS_THRESHOLD);
    }
    
    function test_CalculateConsensus_ZeroStake() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](2);
        
        attestations[0] = ConsensusCalculation.AttestationData({
            operator: operators[0],
            price: BASE_PRICE,
            stake: 0, // Zero stake
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        attestations[1] = ConsensusCalculation.AttestationData({
            operator: operators[1],
            price: BASE_PRICE,
            stake: 0, // Zero stake
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        ConsensusCalculation.ConsensusResult memory result = ConsensusCalculation.calculateConsensus(
            attestations,
            ConsensusCalculation.DEFAULT_CONSENSUS_THRESHOLD
        );
        
        assertFalse(result.hasConsensus);
        assertEq(result.totalStake, 0);
        assertEq(result.consensusPrice, 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                       CONVERGENCE CALCULATION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_CalculateConvergence_PerfectConvergence() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](3);
        
        // All same price = perfect convergence
        for (uint256 i = 0; i < 3; i++) {
            attestations[i] = ConsensusCalculation.AttestationData({
                operator: operators[i],
                price: BASE_PRICE,
                stake: 100 ether,
                timestamp: block.timestamp,
                reliability: 8000
            });
        }
        
        uint256 convergence = ConsensusCalculation.calculateConvergence(attestations, BASE_PRICE);
        assertEq(convergence, BASIS_POINTS); // Perfect 100% convergence
    }
    
    function test_CalculateConvergence_PartialConvergence() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](3);
        
        attestations[0] = ConsensusCalculation.AttestationData({
            operator: operators[0],
            price: BASE_PRICE,
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        attestations[1] = ConsensusCalculation.AttestationData({
            operator: operators[1],
            price: BASE_PRICE + (BASE_PRICE * 200) / BASIS_POINTS, // +2%
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        attestations[2] = ConsensusCalculation.AttestationData({
            operator: operators[2],
            price: BASE_PRICE - (BASE_PRICE * 100) / BASIS_POINTS, // -1%
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        uint256 convergence = ConsensusCalculation.calculateConvergence(attestations, BASE_PRICE);
        
        // Should be good but not perfect convergence
        assertGt(convergence, 8000); // > 80%
        assertLt(convergence, BASIS_POINTS); // < 100%
    }
    
    function test_CalculateConvergence_PoorConvergence() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](3);
        
        attestations[0] = ConsensusCalculation.AttestationData({
            operator: operators[0],
            price: BASE_PRICE,
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        attestations[1] = ConsensusCalculation.AttestationData({
            operator: operators[1],
            price: BASE_PRICE * 150 / 100, // +50%
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        attestations[2] = ConsensusCalculation.AttestationData({
            operator: operators[2],
            price: BASE_PRICE * 50 / 100, // -50%
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        uint256 convergence = ConsensusCalculation.calculateConvergence(attestations, BASE_PRICE);
        
        // Should have poor convergence
        assertLt(convergence, 5000); // < 50%
    }
    
    function test_CalculateConvergence_EmptyAttestations() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](0);
        
        uint256 convergence = ConsensusCalculation.calculateConvergence(attestations, BASE_PRICE);
        assertEq(convergence, 0);
    }
    
    function test_CalculateConvergence_ZeroConsensusPrice() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](1);
        attestations[0] = ConsensusCalculation.AttestationData({
            operator: operators[0],
            price: BASE_PRICE,
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        uint256 convergence = ConsensusCalculation.calculateConvergence(attestations, 0);
        assertEq(convergence, 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                      CONFIDENCE LEVEL TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_CalculateConfidenceLevel_HighConfidence() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](5);
        
        // Create scenario for high confidence: many operators, convergent prices, good reliability
        for (uint256 i = 0; i < 5; i++) {
            attestations[i] = ConsensusCalculation.AttestationData({
                operator: operators[i],
                price: i >= 2 ? BASE_PRICE + (BASE_PRICE * (i - 2) * 10) / BASIS_POINTS : BASE_PRICE - (BASE_PRICE * (2 - i) * 10) / BASIS_POINTS, // Small variations
                stake: 100 ether,
                timestamp: block.timestamp,
                reliability: 9000 // High reliability
            });
        }
        
        uint256 confidence = ConsensusCalculation.calculateConfidenceLevel(
            attestations,
            BASE_PRICE,
            500 ether,
            9500 // High convergence
        );
        
        assertGt(confidence, 8000); // Should be high confidence
    }
    
    function test_CalculateConfidenceLevel_LowConfidence() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](2);
        
        // Scenario for low confidence: few operators, poor reliability
        attestations[0] = ConsensusCalculation.AttestationData({
            operator: operators[0],
            price: BASE_PRICE,
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 3000 // Low reliability
        });
        
        attestations[1] = ConsensusCalculation.AttestationData({
            operator: operators[1],
            price: BASE_PRICE * 110 / 100, // 10% off
            stake: 50 ether,
            timestamp: block.timestamp,
            reliability: 4000 // Low reliability
        });
        
        uint256 confidence = ConsensusCalculation.calculateConfidenceLevel(
            attestations,
            BASE_PRICE,
            150 ether,
            3000 // Low convergence
        );
        
        assertLt(confidence, 5000); // Should be low confidence
    }
    
    /*//////////////////////////////////////////////////////////////
                    STAKE DISTRIBUTION TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_CalculateStakeDistributionScore_EqualDistribution() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](3);
        
        // Equal stake distribution
        for (uint256 i = 0; i < 3; i++) {
            attestations[i] = ConsensusCalculation.AttestationData({
                operator: operators[i],
                price: BASE_PRICE,
                stake: 100 ether, // Equal stakes
                timestamp: block.timestamp,
                reliability: 8000
            });
        }
        
        uint256 score = ConsensusCalculation.calculateStakeDistributionScore(attestations, 300 ether);
        
        // Equal distribution should get high score
        assertGt(score, 8000);
    }
    
    function test_CalculateStakeDistributionScore_UnequalDistribution() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](3);
        
        // Unequal stake distribution
        attestations[0] = ConsensusCalculation.AttestationData({
            operator: operators[0],
            price: BASE_PRICE,
            stake: 1000 ether, // Dominant stake
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        attestations[1] = ConsensusCalculation.AttestationData({
            operator: operators[1],
            price: BASE_PRICE,
            stake: 10 ether, // Small stake
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        attestations[2] = ConsensusCalculation.AttestationData({
            operator: operators[2],
            price: BASE_PRICE,
            stake: 10 ether, // Small stake
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        uint256 score = ConsensusCalculation.calculateStakeDistributionScore(attestations, 1020 ether);
        
        // Unequal distribution should get lower score
        assertLt(score, 5000);
    }
    
    /*//////////////////////////////////////////////////////////////
                      OPERATOR COUNT TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_CalculateOperatorCountScore() public {
        assertEq(ConsensusCalculation.calculateOperatorCountScore(0), 0);
        assertEq(ConsensusCalculation.calculateOperatorCountScore(1), 2000);
        assertEq(ConsensusCalculation.calculateOperatorCountScore(2), 4000);
        assertEq(ConsensusCalculation.calculateOperatorCountScore(3), 6000);
        assertEq(ConsensusCalculation.calculateOperatorCountScore(4), 7500);
        assertEq(ConsensusCalculation.calculateOperatorCountScore(5), 10000);
        assertEq(ConsensusCalculation.calculateOperatorCountScore(10), 10000); // Capped at 100%
    }
    
    /*//////////////////////////////////////////////////////////////
                      AVERAGE RELIABILITY TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_CalculateAverageReliability() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](3);
        
        attestations[0] = ConsensusCalculation.AttestationData({
            operator: operators[0],
            price: BASE_PRICE,
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        attestations[1] = ConsensusCalculation.AttestationData({
            operator: operators[1],
            price: BASE_PRICE,
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 9000
        });
        
        attestations[2] = ConsensusCalculation.AttestationData({
            operator: operators[2],
            price: BASE_PRICE,
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 7000
        });
        
        uint256 avgReliability = ConsensusCalculation.calculateAverageReliability(attestations);
        assertEq(avgReliability, 8000); // (8000 + 9000 + 7000) / 3 = 8000
    }
    
    function test_CalculateAverageReliability_EmptyArray() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](0);
        uint256 avgReliability = ConsensusCalculation.calculateAverageReliability(attestations);
        assertEq(avgReliability, 0);
    }
    
    /*//////////////////////////////////////////////////////////////
                        OUTLIER FILTERING TESTS
    //////////////////////////////////////////////////////////////*/
    
    function test_FilterOutliers_NoOutliers() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](4);
        
        // Create prices within 2% of each other
        for (uint256 i = 0; i < 4; i++) {
            attestations[i] = ConsensusCalculation.AttestationData({
                operator: operators[i],
                price: BASE_PRICE + (BASE_PRICE * i * 50) / BASIS_POINTS, // 0%, 0.5%, 1%, 1.5%
                stake: 100 ether,
                timestamp: block.timestamp,
                reliability: 8000
            });
        }
        
        ConsensusCalculation.AttestationData[] memory filtered = ConsensusCalculation.filterOutliers(
            attestations,
            500 // 5% max deviation
        );
        
        // All should remain (no outliers)
        assertEq(filtered.length, 4);
    }
    
    function test_FilterOutliers_WithOutliers() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](4);
        
        // Create one outlier
        attestations[0] = ConsensusCalculation.AttestationData({
            operator: operators[0],
            price: BASE_PRICE,
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        attestations[1] = ConsensusCalculation.AttestationData({
            operator: operators[1],
            price: BASE_PRICE + (BASE_PRICE * 50) / BASIS_POINTS, // +0.5%
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        attestations[2] = ConsensusCalculation.AttestationData({
            operator: operators[2],
            price: BASE_PRICE - (BASE_PRICE * 30) / BASIS_POINTS, // -0.3%
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        attestations[3] = ConsensusCalculation.AttestationData({
            operator: operators[3],
            price: BASE_PRICE * 130 / 100, // +30% - outlier
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        ConsensusCalculation.AttestationData[] memory filtered = ConsensusCalculation.filterOutliers(
            attestations,
            500 // 5% max deviation
        );
        
        // Outlier should be removed
        assertEq(filtered.length, 3);
        
        // Verify the outlier was removed
        for (uint256 i = 0; i < filtered.length; i++) {
            assertLt(filtered[i].price, BASE_PRICE * 110 / 100); // All should be < +10%
        }
    }
    
    function test_FilterOutliers_TooFewDataPoints() public {
        ConsensusCalculation.AttestationData[] memory attestations = new ConsensusCalculation.AttestationData[](2);
        
        attestations[0] = ConsensusCalculation.AttestationData({
            operator: operators[0],
            price: BASE_PRICE,
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        attestations[1] = ConsensusCalculation.AttestationData({
            operator: operators[1],
            price: BASE_PRICE * 200 / 100, // Even if outlier, shouldn't filter
            stake: 100 ether,
            timestamp: block.timestamp,
            reliability: 8000
        });
        
        ConsensusCalculation.AttestationData[] memory filtered = ConsensusCalculation.filterOutliers(
            attestations,
            500
        );
        
        // Should return original array (too few data points to filter)
        assertEq(filtered.length, 2);
    }
    
    /*//////////////////////////////////////////////////////////////
                           FUZZ TESTS
    //////////////////////////////////////////////////////////////*/
    
    function testFuzz_CalculateConsensus(
        uint256 numAttestations,
        uint256 baseStake,
        uint256 priceVariation
    ) public {
        vm.assume(numAttestations >= 1 && numAttestations <= 10);
        vm.assume(baseStake >= 1 ether && baseStake <= 1000 ether);
        vm.assume(priceVariation <= 5000); // Max 50% variation
        
        ConsensusCalculation.AttestationData[] memory attestations = 
            new ConsensusCalculation.AttestationData[](numAttestations);
        
        for (uint256 i = 0; i < numAttestations; i++) {
            uint256 priceVar = (BASE_PRICE * priceVariation * (i + 1)) / (BASIS_POINTS * numAttestations);
            uint256 price = i % 2 == 0 ? BASE_PRICE + priceVar : BASE_PRICE - priceVar;
            
            attestations[i] = ConsensusCalculation.AttestationData({
                operator: address(uint160(0x1000 + i)),
                price: price,
                stake: baseStake + (baseStake * i) / 10, // Varying stakes
                timestamp: block.timestamp,
                reliability: 7000 + (i * 500) % 3000 // 70% to 100% reliability
            });
        }
        
        ConsensusCalculation.ConsensusResult memory result = ConsensusCalculation.calculateConsensus(
            attestations,
            ConsensusCalculation.DEFAULT_CONSENSUS_THRESHOLD
        );
        
        // Basic sanity checks
        assertGt(result.totalStake, 0);
        assertGt(result.consensusPrice, 0);
        assertLe(result.confidenceLevel, BASIS_POINTS);
        assertLe(result.convergenceScore, BASIS_POINTS);
    }
    
    function testFuzz_OperatorCountScore(uint256 count) public {
        vm.assume(count <= 1000); // Reasonable upper bound
        
        uint256 score = ConsensusCalculation.calculateOperatorCountScore(count);
        
        // Score should be capped at 100%
        assertLe(score, BASIS_POINTS);
        
        // Score should be monotonically increasing (or staying at max)
        if (count > 0) {
            uint256 prevScore = ConsensusCalculation.calculateOperatorCountScore(count - 1);
            assertGe(score, prevScore);
        }
    }
}