# Anvil Local Deployment Guide

This guide explains how to deploy and test the Oracle Hook system on a local Anvil network for development purposes.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation) installed
- Git repository cloned locally

## Quick Start

### 1. Start Anvil

```bash
# Start local Anvil network
anvil
```

Keep this terminal running. Anvil will show funded accounts and start listening on `http://127.0.0.1:8545`.

### 2. Deploy Oracle Hook System

In a new terminal:

```bash
# Deploy to local Anvil network
forge script script/DeployAnvil.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

## Deployment Overview

The deployment script creates a complete Oracle Hook system including:

### Core Contracts
- **MockPoolManager**: Simulates Uniswap V4 Pool Manager for testing
- **MockOracleAVS**: Mock oracle that provides price consensus data
- **AVSOracleHook**: Main hook contract that validates swaps against oracle prices

### Test Pools
- **ETH/USDC**: $2,105 per ETH (85% confidence)
- **WBTC/ETH**: 20.5 ETH per WBTC (82% confidence)  
- **DAI/USDC**: $1.001 per DAI (92% confidence)

### Test Accounts
- **Deployer**: Contract deployer (1000 ETH)
- **Operator1-3**: Mock oracle operators (100 ETH each)
- **User1-2**: Test users for swaps (10 ETH each)

## Testing the System

### Check Oracle Data

```bash
# Get current consensus for ETH/USDC pool
cast call <HOOK_ADDRESS> "getConsensusData(bytes32)" <ETH_USDC_POOL_ID>

# Check pool configuration
cast call <HOOK_ADDRESS> "poolConfigs(bytes32)" <ETH_USDC_POOL_ID>
```

### Update Mock Prices

```bash
# Update ETH price to $2,200 with 90% confidence
cast send <MOCK_AVS_ADDRESS> "setMockConsensus(bytes32,uint256,uint256,uint256,bool)" \
  <ETH_USDC_POOL_ID> \
  "2200000000000000000000" \
  "200000000000000000000" \
  "9000" \
  "true" \
  --private-key <OPERATOR_PRIVATE_KEY>
```

### Test Swap Validation

```bash
# Enable oracle for a pool (as hook owner)
cast send <HOOK_ADDRESS> "enableOracleForPool(bytes32,bool)" <POOL_ID> true \
  --private-key <DEPLOYER_PRIVATE_KEY>

# Update pool configuration
cast send <HOOK_ADDRESS> "updateOracleConfig(bytes32,uint256,uint256,uint256)" \
  <POOL_ID> \
  "500" \      # 5% max deviation
  "10000000000000000000" \ # 10 ETH min stake  
  "7500" \     # 75% confidence threshold
  --private-key <DEPLOYER_PRIVATE_KEY>
```

## Development Workflow

### 1. Local Testing Loop

```bash
# 1. Make changes to contracts
# 2. Redeploy
forge script script/DeployAnvil.s.sol --rpc-url http://127.0.0.1:8545 --broadcast

# 3. Run tests against deployed contracts
forge test --rpc-url http://127.0.0.1:8545

# 4. Test specific scenarios with cast commands
```

### 2. Debug with Console Logs

Add console logs to your contracts:

```solidity
import {console} from "forge-std/console.sol";

// In your contract
console.log("Price deviation:", deviation);
console.log("Consensus price:", consensusPrice);
```

Then view logs during deployment:

```bash
forge script script/DeployAnvil.s.sol --rpc-url http://127.0.0.1:8545 --broadcast -vvv
```

### 3. State Inspection

```bash
# Check contract storage
cast storage <CONTRACT_ADDRESS> <SLOT> --rpc-url http://127.0.0.1:8545

# Check balance
cast balance <ADDRESS> --rpc-url http://127.0.0.1:8545

# Get transaction receipt
cast receipt <TX_HASH> --rpc-url http://127.0.0.1:8545
```

## Common Use Cases

### Simulate Price Manipulation Attack

```bash
# 1. Set extreme price deviation
cast send <MOCK_AVS_ADDRESS> "setMockConsensus(bytes32,uint256,uint256,uint256,bool)" \
  <POOL_ID> "1000000000000000000000" "100000000000000000000" "9000" "true"

# 2. Try to swap - should be rejected
# Use your frontend or additional cast commands to test swap rejection
```

### Test Confidence Thresholds

```bash
# 1. Set low confidence consensus
cast send <MOCK_AVS_ADDRESS> "setMockConsensus(bytes32,uint256,uint256,uint256,bool)" \
  <POOL_ID> "2100000000000000000000" "50000000000000000000" "5000" "true"

# 2. Verify swaps are rejected due to low confidence
```

### Test Staleness Protection

```bash
# 1. Deploy system
# 2. Wait or manipulate block.timestamp
# 3. Verify old consensus data is rejected
```

## Troubleshooting

### Common Issues

1. **"Insufficient funds" errors**: Make sure you're using the right private key for funded accounts

2. **"Execution reverted" errors**: Check that:
   - Pool is initialized
   - Oracle is enabled for the pool  
   - Consensus data is valid and recent

3. **"No consensus available" errors**: Ensure mock consensus is set with `hasConsensus = true`

### Reset Environment

```bash
# Kill anvil and restart with fresh state
pkill anvil
anvil

# Redeploy contracts
forge script script/DeployAnvil.s.sol --rpc-url http://127.0.0.1:8545 --broadcast
```

## Advanced Testing

### Load Testing

```bash
# Run multiple swaps in sequence
for i in {1..10}; do
  cast send <HOOK_ADDRESS> "beforeSwap(...)" --private-key <USER_KEY>
done
```

### Gas Optimization Testing

```bash
# Test gas usage
forge test --gas-report --rpc-url http://127.0.0.1:8545
```

### Integration with Frontend

If you have a frontend application:

1. Point your frontend to `http://127.0.0.1:8545`
2. Use the deployed contract addresses from the deployment output
3. Test the complete user flow

## Contract Addresses

After deployment, the script will output contract addresses. Save these for testing:

```
Core Contracts:
  MockPoolManager: 0x...
  MockOracleAVS: 0x...
  AVSOracleHook: 0x...

Test Pools:
  ETH/USDC: 0x...
  WBTC/ETH: 0x...
  DAI/USDC: 0x...
```

## Next Steps

- Customize mock prices for your testing scenarios
- Add additional test pools
- Integrate with a frontend application
- Test integration with real Uniswap V4 when available
- Deploy to testnets for more realistic testing