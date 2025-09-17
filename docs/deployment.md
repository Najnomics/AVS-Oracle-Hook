# Deployment Guide

## Prerequisites

### Development Environment
- **Node.js**: Version 16+ required
- **Forge/Foundry**: Latest version installed
- **Go**: Version 1.19+ for operator
- **Git**: For repository management

### Dependencies
```bash
# Install Foundry
curl -L https://foundry.paradigm.xyz | bash
foundryup

# Install Node.js dependencies (if any)
npm install

# Install Go dependencies
cd avs && go mod tidy
```

## Building the Project

### Smart Contracts
```bash
# Build all contracts
forge build

# Run tests
forge test

# Generate gas reports
forge test --gas-report

# Check coverage
forge coverage
```

### Go Operator
```bash
cd avs
go build -o bin/operator cmd/main.go
```

## Deployment Steps

### 1. Deploy AVS Infrastructure

#### Deploy Service Manager
```bash
# Deploy to testnet
forge script script/DeployOracleServiceManager.s.sol --rpc-url $TESTNET_RPC --private-key $PRIVATE_KEY --broadcast

# Deploy to mainnet
forge script script/DeployOracleServiceManager.s.sol --rpc-url $MAINNET_RPC --private-key $PRIVATE_KEY --broadcast --verify
```

#### Register with EigenLayer
```bash
# Register AVS with EigenLayer
cast send $SERVICE_MANAGER_ADDRESS "registerAVS()" --rpc-url $RPC_URL --private-key $PRIVATE_KEY
```

### 2. Deploy Hook Infrastructure

#### Deploy Oracle Hook
```bash
# Deploy main Oracle Hook
forge script script/DeployAVSOracleHook.s.sol --rpc-url $RPC_URL --private-key $PRIVATE_KEY --broadcast

# Verify contract
forge verify-contract $HOOK_ADDRESS src/AVSOracleHook.sol:AVSOracleHook --chain-id $CHAIN_ID
```

#### Deploy Task Hook (L2)
```bash
# Deploy L2 Task Hook
forge script script/DeployOracleTaskHook.s.sol --rpc-url $L2_RPC --private-key $PRIVATE_KEY --broadcast
```

### 3. Configure System

#### Set Oracle Parameters
```solidity
// Configure default oracle settings
hook.updateOracleConfig(
    poolId,
    500,        // 5% max deviation
    10 ether,   // 10 ETH min stake
    6600        // 66% consensus threshold
);
```

#### Enable Oracle for Pools
```solidity
// Enable oracle for major trading pairs
hook.enableOracleForPool(usdcWethPoolId, true);
hook.enableOracleForPool(wbtcWethPoolId, true);
```

### 4. Deploy Operators

#### Operator Configuration
Create `config.yaml`:
```yaml
operator:
  address: "0x..."
  private_key: "${OPERATOR_PRIVATE_KEY}"
  stake_amount: "100000000000000000000" # 100 ETH

networks:
  ethereum:
    rpc_url: "${ETH_RPC_URL}"
    service_manager: "0x..."
    task_hook: "0x..."

price_sources:
  binance:
    api_key: "${BINANCE_API_KEY}"
    secret_key: "${BINANCE_SECRET_KEY}"
  coinbase:
    api_key: "${COINBASE_API_KEY}"
    secret_key: "${COINBASE_SECRET_KEY}"
  kraken:
    api_key: "${KRAKEN_API_KEY}"
    secret_key: "${KRAKEN_SECRET_KEY}"

consensus:
  min_operators: 3
  consensus_threshold: 6600
  price_staleness: 300
```

#### Register Operators
```bash
# Register operator with AVS
./bin/operator register --config config.yaml

# Start operator service
./bin/operator start --config config.yaml
```

## Environment Variables

### Required Variables
```bash
# Network Configuration
export ETH_RPC_URL="https://..."
export SEPOLIA_RPC_URL="https://..."
export BASE_RPC_URL="https://..."

# Deployment Keys
export DEPLOYER_PRIVATE_KEY="0x..."
export OPERATOR_PRIVATE_KEY="0x..."

# API Keys
export ETHERSCAN_API_KEY="..."
export BINANCE_API_KEY="..."
export COINBASE_API_KEY="..."
export KRAKEN_API_KEY="..."

# Contract Addresses (after deployment)
export SERVICE_MANAGER_ADDRESS="0x..."
export ORACLE_HOOK_ADDRESS="0x..."
export TASK_HOOK_ADDRESS="0x..."
```

## Verification

### Contract Verification
```bash
# Verify on Etherscan
forge verify-contract $CONTRACT_ADDRESS src/AVSOracleHook.sol:AVSOracleHook \
  --chain-id 1 \
  --constructor-args $(cast abi-encode "constructor(address,address)" $POOL_MANAGER $ORACLE_AVS)

# Verify on Basescan
forge verify-contract $CONTRACT_ADDRESS src/AVSOracleHook.sol:AVSOracleHook \
  --chain-id 8453 \
  --verifier blockscout \
  --verifier-url https://base.blockscout.com/api
```

### System Health Checks
```bash
# Check operator status
./bin/operator status --config config.yaml

# Check consensus health
cast call $SERVICE_MANAGER_ADDRESS "getConsensusHealth(bytes32)" $POOL_ID --rpc-url $RPC_URL

# Check hook configuration
cast call $ORACLE_HOOK_ADDRESS "poolConfigs(bytes32)" $POOL_ID --rpc-url $RPC_URL
```

## Monitoring

### Operator Monitoring
```bash
# Monitor operator logs
tail -f logs/operator.log

# Monitor consensus participation
cast logs --address $SERVICE_MANAGER_ADDRESS --topic "ConsensusReached(bytes32,uint256,uint256,uint256,uint256)"

# Monitor price validations
cast logs --address $ORACLE_HOOK_ADDRESS --topic "PriceValidationRequested(bytes32,address,uint256,uint256)"
```

### Alerting Setup
```yaml
# Prometheus metrics
metrics:
  port: 8080
  path: /metrics

alerts:
  - name: operator_offline
    condition: operator_last_attestation > 300s
    action: slack_webhook
  
  - name: consensus_failure
    condition: consensus_failure_rate > 10%
    action: email_alert
  
  - name: high_deviation
    condition: price_deviation > 5%
    action: urgent_alert
```

## Security Considerations

### Key Management
- Use hardware wallets for mainnet deployments
- Implement key rotation for operators
- Use secure key storage (AWS KMS, HashiCorp Vault)

### Access Control
- Multi-sig for critical functions
- Time-locked governance changes
- Role-based access control

### Monitoring
- Real-time anomaly detection
- Consensus health monitoring
- Operator performance tracking

## Troubleshooting

### Common Issues

#### Build Failures
```bash
# Clear cache and rebuild
forge clean
forge build

# Update dependencies
forge update
```

#### Test Failures
```bash
# Run specific test
forge test --match-test testFunctionName -vvv

# Debug failing test
forge test --debug testFunctionName
```

#### Operator Issues
```bash
# Check operator registration
cast call $SERVICE_MANAGER_ADDRESS "operators(address)" $OPERATOR_ADDRESS

# Check stake amount
cast call $SERVICE_MANAGER_ADDRESS "operatorStakes(address)" $OPERATOR_ADDRESS

# Restart operator
./bin/operator stop
./bin/operator start --config config.yaml
```

## Mainnet Deployment Checklist

- [ ] All tests passing
- [ ] Security audit completed
- [ ] Testnet deployment successful
- [ ] Operator infrastructure tested
- [ ] Monitoring systems deployed
- [ ] Emergency procedures documented
- [ ] Multi-sig setup completed
- [ ] Insurance coverage arranged
- [ ] Community notification prepared
- [ ] Documentation updated

## Support

### Documentation
- [Architecture Documentation](./architecture.md)
- [API Reference](./api.md)
- [Testing Guide](./testing.md)

### Community
- Discord: #avs-oracle-hook
- Telegram: @AVSOracleHook
- Twitter: @AVSOracleHook

### Emergency Contacts
- Lead Developer: developer@project.com
- Security Team: security@project.com
- Operations: ops@project.com