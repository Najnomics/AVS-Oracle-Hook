# AVS Oracle Hook Architecture

## Overview

The AVS Oracle Hook is a sophisticated price validation system that integrates EigenLayer's Actively Validated Services (AVS) with Uniswap V4's hook mechanism to provide real-time manipulation detection and consensus-based price validation.

## System Components

### 1. Core Components

#### AVSOracleHook (Main Hook)
- **Location**: `src/AVSOracleHook.sol`
- **Purpose**: Main Uniswap V4 hook that validates prices before swaps
- **Key Features**:
  - Real-time price validation via AVS consensus
  - Configurable oracle settings per pool
  - Manipulation detection and blocking
  - Support for major trading pairs

#### Oracle Service Manager
- **Location**: `avs/contracts/src/l1-contracts/OracleServiceManager.sol`
- **Purpose**: EigenLayer AVS service manager for price consensus
- **Key Features**:
  - Stake-weighted consensus calculation
  - Operator coordination
  - Slashing mechanism for malicious behavior
  - BLS signature aggregation

#### Oracle Task Hook
- **Location**: `avs/contracts/src/l2-contracts/OracleTaskHook.sol`
- **Purpose**: L2 connector between AVS and main hook
- **Key Features**:
  - Task validation and fee calculation
  - Bridge between EigenLayer tasks and Oracle validation

### 2. Supporting Libraries

#### PriceValidation Library
- **Location**: `src/hooks/libraries/PriceValidation.sol`
- **Purpose**: Core price validation algorithms
- **Functions**:
  - `validatePrice()`: Main validation logic
  - `detectManipulation()`: Manipulation detection
  - `validateMultipleSources()`: Multi-source validation
  - `calculateDeviation()`: Price deviation calculation

#### ConsensusCalculation Library
- **Location**: `src/hooks/libraries/ConsensusCalculation.sol`
- **Purpose**: Consensus calculation and confidence scoring
- **Functions**:
  - `calculateConsensus()`: Main consensus calculation
  - `calculateConvergence()`: Price convergence analysis
  - `calculateConfidenceLevel()`: Confidence scoring
  - `filterOutliers()`: Outlier detection and removal

### 3. Operator Infrastructure

#### Go Operator
- **Location**: `avs/cmd/main.go`
- **Purpose**: AVS operator implementation
- **Key Features**:
  - Price attestation generation
  - Multiple data source integration (Binance, Coinbase, Kraken)
  - BLS signature generation
  - Real-time consensus participation

## Architecture Flow

### 1. Pool Initialization
1. Pool creator deploys pool with AVSOracleHook
2. Hook determines if oracle validation should be enabled based on token pair
3. Oracle configuration is set for the pool
4. AVS operators begin monitoring the pool

### 2. Price Validation Flow
1. **Swap Initiation**: User initiates swap
2. **beforeSwap Hook**: Hook intercepts swap request
3. **Consensus Request**: Hook requests current price consensus from AVS
4. **Operator Attestations**: AVS operators provide price attestations
5. **Consensus Calculation**: Stake-weighted consensus is calculated
6. **Validation**: Hook validates swap price against consensus
7. **Decision**: Swap is either allowed or blocked
8. **afterSwap Hook**: Post-swap validation and logging

### 3. Consensus Mechanism
1. **Price Collection**: Operators fetch prices from multiple sources
2. **Attestation Creation**: Each operator creates signed price attestation
3. **Stake Weighting**: Attestations are weighted by operator stake
4. **Outlier Filtering**: Extreme price deviations are filtered out
5. **Confidence Calculation**: Overall confidence level is computed
6. **Consensus Determination**: Final consensus price and validity

## Security Features

### 1. Economic Security
- **Stake Requirements**: Minimum stake thresholds for participation
- **Slashing Conditions**: Penalties for malicious behavior
- **Reward Distribution**: Incentives for accurate price reporting

### 2. Manipulation Detection
- **Statistical Analysis**: Real-time price pattern analysis
- **Multi-Source Validation**: Cross-validation across price sources
- **Temporal Analysis**: Price movement pattern detection
- **Operator Reputation**: Historical accuracy tracking

### 3. Consensus Validation
- **Minimum Operator Count**: Requires multiple independent attestations
- **Convergence Thresholds**: Minimum agreement levels
- **Confidence Scoring**: Multi-factor confidence calculation
- **Staleness Checks**: Time-based data validity

## Configuration

### Pool-Level Settings
- **Oracle Enabled**: Whether validation is active
- **Max Price Deviation**: Maximum allowed price variance (BPS)
- **Min Stake Required**: Minimum total stake for consensus
- **Consensus Threshold**: Required agreement percentage
- **Max Staleness**: Maximum age of price data

### Global Constants
- **Default Consensus Threshold**: 66% (6600 BPS)
- **Max Price Staleness**: 300 seconds
- **Min Attestations**: 3 operators minimum
- **Max Price Deviation**: 5% (500 BPS)

## Integration Points

### Uniswap V4 Integration
- **Hook Permissions**: beforeInitialize, beforeSwap, afterSwap
- **Pool Configuration**: Automatic oracle enablement for major pairs
- **Gas Optimization**: Minimal overhead for price validation

### EigenLayer Integration
- **AVS Registration**: Service manager registration with EigenLayer
- **Operator Management**: Stake tracking and slashing
- **Task Coordination**: Price validation task distribution

### External Price Sources
- **Binance API**: Real-time spot prices
- **Coinbase Pro API**: Institutional price feeds
- **Kraken API**: Additional price validation
- **Uniswap TWAP**: On-chain price reference

## Performance Considerations

### Gas Optimization
- **Minimal State Changes**: Efficient storage updates
- **Batched Operations**: Group multiple validations
- **Cached Consensus**: Reuse recent consensus data

### Scalability
- **Parallel Processing**: Concurrent operator attestations
- **Selective Validation**: Only major trading pairs
- **Configurable Thresholds**: Adjustable based on network conditions

## Future Enhancements

### Planned Features
- **Dynamic Thresholds**: Adaptive consensus requirements
- **Advanced ML Detection**: Machine learning manipulation detection
- **Cross-Chain Support**: Multi-chain price validation
- **Governance Integration**: DAO-controlled parameters

### Research Areas
- **Zero-Knowledge Proofs**: Privacy-preserving validation
- **Optimistic Validation**: Challenge-based consensus
- **MEV Protection**: Front-running detection and prevention