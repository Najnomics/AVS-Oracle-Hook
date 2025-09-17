# Testing Guide

## Overview

The AVS Oracle Hook project includes comprehensive testing suites covering smart contracts, operator functionality, and integration scenarios. This guide covers how to run tests, interpret results, and extend the test suite.

## Test Structure

### Smart Contract Tests
- **Location**: `test/`
- **Framework**: Foundry Test Framework
- **Coverage**: Unit tests, integration tests, fuzz tests

### Test Organization
```
test/
├── unit/                      # Unit tests for individual contracts
│   ├── AVSOracleHook.t.sol   # Main hook functionality
│   ├── PriceValidation.t.sol # Price validation library
│   └── ConsensusCalculation.t.sol # Consensus calculation library
├── mocks/                     # Mock contracts for testing
│   ├── MockPoolManager.sol   # Mock Uniswap V4 pool manager
│   └── MockOracleAVS.sol     # Mock Oracle AVS
├── utils/                     # Testing utilities
│   └── TestUtils.sol         # Common test helper functions
└── integration/              # Integration tests (planned)
    └── FullFlow.t.sol        # End-to-end scenarios
```

## Running Tests

### All Tests
```bash
# Run all tests
forge test

# Run with verbose output
forge test -vv

# Run with maximum verbosity (includes traces)
forge test -vvvv
```

### Specific Test Files
```bash
# Run specific test file
forge test --match-path test/unit/AVSOracleHook.t.sol

# Run specific test function
forge test --match-test test_BeforeSwap_ValidConsensus

# Run tests matching pattern
forge test --match-test "test_BeforeSwap_*"
```

### Test Categories

#### Unit Tests
```bash
# Hook functionality
forge test --match-path test/unit/AVSOracleHook.t.sol

# Price validation
forge test --match-path test/unit/PriceValidation.t.sol

# Consensus calculation
forge test --match-path test/unit/ConsensusCalculation.t.sol
```

#### Fuzz Tests
```bash
# Run only fuzz tests
forge test --match-test "testFuzz_*"

# Increase fuzz runs for thorough testing
forge test --fuzz-runs 1000 --match-test "testFuzz_*"
```

## Test Coverage

### Generate Coverage Report
```bash
# Generate coverage report
forge coverage

# Generate detailed HTML report
forge coverage --report lcov
genhtml lcov.info -o coverage-report
open coverage-report/index.html
```

### Coverage Targets
- **Smart Contracts**: 100% line coverage goal
- **Critical Functions**: 100% branch coverage required
- **Edge Cases**: Comprehensive fuzz testing

### Current Coverage Status
```
┌─────────────────────────────────────┬─────────────────┬─────────────────┬─────────────────┬─────────────────┐
│ File                                │ % Lines         │ % Statements    │ % Branches      │ % Funcs         │
├─────────────────────────────────────┼─────────────────┼─────────────────┼─────────────────┼─────────────────┤
│ src/AVSOracleHook.sol              │ 95.00% (57/60)  │ 95.00% (57/60)  │ 87.50% (14/16)  │ 100.00% (8/8)   │
│ src/hooks/libraries/PriceValidation.sol │ 90.00% (45/50)  │ 90.00% (45/50)  │ 85.00% (17/20)  │ 100.00% (6/6)   │
│ src/hooks/libraries/ConsensusCalculation.sol │ 92.00% (46/50)  │ 92.00% (46/50)  │ 88.00% (22/25)  │ 100.00% (8/8)   │
│ Total                               │ 92.50% (148/160)│ 92.50% (148/160)│ 86.89% (53/61)  │ 100.00% (22/22) │
└─────────────────────────────────────┴─────────────────┴─────────────────┴─────────────────┴─────────────────┘
```

## Test Scenarios

### AVSOracleHook Tests

#### Deployment Tests
- ✅ Constructor parameters validation
- ✅ Hook permissions configuration
- ✅ Initial state verification

#### Pool Initialization Tests
- ✅ Major token pair oracle enablement
- ✅ Non-major token pair handling
- ✅ Oracle configuration setup
- ✅ Consensus data initialization

#### Swap Validation Tests
- ✅ Oracle disabled scenarios
- ✅ Valid consensus handling
- ⚠️ Insufficient stake detection (failing)
- ⚠️ Low confidence handling (failing)
- ⚠️ Stale data detection (failing)
- ⚠️ Consensus failure handling (failing)

#### Configuration Tests
- ✅ Oracle enable/disable functionality
- ✅ Configuration parameter updates
- ✅ Consensus data retrieval

#### Edge Case Tests
- ✅ Multiple sequential swaps
- ✅ Different swap amounts
- ✅ Zero amount swaps
- ✅ Fuzz testing with random parameters

### PriceValidation Tests

#### Basic Validation Tests
- ✅ Successful price validation
- ✅ Low confidence detection
- ✅ Stale data detection
- ⚠️ High deviation detection (failing)

#### Deviation Calculation Tests
- ✅ Exact price matches
- ✅ Positive price differences
- ✅ Negative price differences
- ✅ Zero reference handling

#### Manipulation Detection Tests
- ⚠️ Normal price patterns (failing - implementation needed)
- ⚠️ High volatility detection (failing - implementation needed)
- ⚠️ Extreme deviation detection (failing - implementation needed)
- ⚠️ Insufficient data handling (failing - implementation needed)

#### Multi-Source Validation Tests
- ✅ Equal weight scenarios
- ✅ Different weight scenarios
- ✅ High variance detection
- ⚠️ Empty array handling (failing - implementation needed)

#### Fuzz Tests
- ⚠️ Deviation calculation (failing - edge case issue)
- ✅ Price validation parameters
- ✅ Price movement validation

### ConsensusCalculation Tests

#### Basic Consensus Tests
- ✅ Single attestation handling
- ✅ Multiple convergent attestations
- ⚠️ Divergent attestation handling (failing)
- ⚠️ No attestations error handling (failing)
- ✅ Zero stake scenarios

#### Convergence Tests
- ✅ Perfect convergence calculation
- ✅ Partial convergence scenarios
- ⚠️ Poor convergence detection (failing - threshold issue)
- ✅ Empty attestation handling
- ✅ Zero consensus price handling

#### Confidence Level Tests
- ✅ High confidence scenarios
- ✅ Low confidence scenarios
- ✅ Stake distribution scoring
- ✅ Operator count scoring
- ✅ Average reliability calculation

#### Outlier Filtering Tests
- ✅ No outlier scenarios
- ✅ Outlier detection and removal
- ✅ Insufficient data point handling

#### Fuzz Tests
- ⚠️ Consensus calculation (failing - input validation needed)
- ✅ Operator count scoring

## Known Test Issues

### Critical Issues (Must Fix)
1. **Oracle Validation Logic**: Mock AVS not properly simulating failure conditions
2. **Manipulation Detection**: Missing implementation in PriceValidation library
3. **Consensus Calculation**: Edge cases not handled properly

### Implementation Gaps
1. **Price Validation Library**: Several functions need actual implementation
2. **Consensus Calculation**: Some validation logic missing
3. **Error Handling**: Proper revert messages needed

### Test Infrastructure Improvements Needed
1. **Mock AVS**: More sophisticated failure simulation
2. **Integration Tests**: End-to-end testing scenarios
3. **Gas Optimization**: Performance testing suite

## Test Data Patterns

### Price Data
```solidity
uint256 constant BASE_PRICE = 2000 * 1e18; // $2,000
uint256 constant BASIS_POINTS = 10000;

// Small variation (+0.5%)
uint256 smallIncrease = BASE_PRICE + (BASE_PRICE * 50) / BASIS_POINTS;

// Large deviation (+20%)
uint256 largeIncrease = BASE_PRICE * 120 / 100;
```

### Consensus Data
```solidity
// High reliability operator
attestations[0] = ConsensusCalculation.AttestationData({
    operator: operators[0],
    price: BASE_PRICE,
    stake: 100 ether,
    timestamp: block.timestamp,
    reliability: 9000 // 90%
});
```

### Pool Configuration
```solidity
// Typical configuration
poolConfigs[poolId] = PoolOracleConfig({
    oracleEnabled: true,
    maxPriceDeviation: 500,     // 5%
    minStakeRequired: 10 ether,
    consensusThreshold: 6600,   // 66%
    maxStaleness: 300          // 5 minutes
});
```

## Debugging Tests

### Verbose Output
```bash
# Show test execution details
forge test --match-test test_BeforeSwap_ValidConsensus -vv

# Show complete traces
forge test --match-test test_BeforeSwap_ValidConsensus -vvvv
```

### Gas Profiling
```bash
# Generate gas report
forge test --gas-report

# Profile specific test
forge test --match-test test_BeforeSwap_ValidConsensus --gas-report
```

### Debug Mode
```bash
# Interactive debugging
forge test --debug test_BeforeSwap_ValidConsensus
```

## Writing New Tests

### Test Function Naming
```solidity
// Positive test case
function test_FunctionName_SuccessCondition() public {
    // Test successful execution
}

// Negative test case  
function test_FunctionName_FailureCondition() public {
    // Test failure scenarios
    vm.expectRevert("Expected error message");
    // Function call that should revert
}

// Fuzz test
function testFuzz_FunctionName(uint256 parameter) public {
    vm.assume(parameter > 0 && parameter < type(uint128).max);
    // Test with random inputs
}
```

### Test Structure Pattern
```solidity
function test_Description() public {
    // 1. Setup
    // Arrange test data and state
    
    // 2. Execution
    // Call the function being tested
    
    // 3. Verification
    // Assert expected outcomes
    
    // 4. Additional Checks
    // Verify side effects, events, etc.
}
```

### Mock Usage
```solidity
function test_WithMockAVS() public {
    // Setup mock response
    mockAVS.setMockConsensus(poolId, price, stake, confidence, true);
    
    // Test interaction
    hook.beforeSwap(sender, poolKey, swapParams, "");
    
    // Verify mock was called correctly
    // (implement call tracking in mock if needed)
}
```

## Continuous Integration

### GitHub Actions
```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Install Foundry
        uses: foundry-rs/foundry-toolchain@v1
      - name: Run tests
        run: forge test
      - name: Check coverage
        run: forge coverage --report lcov
      - name: Upload coverage
        uses: codecov/codecov-action@v3
```

### Quality Gates
- All tests must pass
- Coverage threshold: 90%
- No high-severity linting issues
- Gas usage within limits

## Performance Testing

### Gas Benchmarks
```bash
# Benchmark gas usage
forge test --gas-report > gas-report.txt

# Compare gas usage between versions
forge snapshot
forge snapshot --diff
```

### Load Testing
```solidity
function test_HighVolumeSwaps() public {
    // Test with high frequency swaps
    for (uint256 i = 0; i < 1000; i++) {
        hook.beforeSwap(alice, poolKey, swapParams, "");
    }
}
```

## Test Maintenance

### Regular Tasks
1. **Update test data**: Keep price data realistic
2. **Review coverage**: Identify uncovered branches
3. **Performance monitoring**: Track gas usage trends
4. **Dependency updates**: Keep test frameworks current

### Test Review Checklist
- [ ] All critical paths covered
- [ ] Edge cases identified and tested
- [ ] Error conditions properly tested
- [ ] Gas usage reasonable
- [ ] Mock behaviors realistic
- [ ] Test names descriptive
- [ ] Documentation updated

## Troubleshooting

### Common Test Failures

#### "Call didn't revert as expected"
- Check that the function actually reverts
- Verify the exact revert message
- Ensure test setup creates the expected failure condition

#### "Arithmetic underflow/overflow"
- Check for integer overflow in calculations
- Verify input bounds in fuzz tests
- Add proper bounds checking

#### "vm.assume rejected too many inputs"
- Relax assumption constraints
- Use more reasonable input ranges
- Consider splitting complex fuzz tests

### Getting Help
- Check test output carefully for clues
- Review similar working tests
- Use verbose mode for detailed execution trace
- Ask in project Discord for complex issues