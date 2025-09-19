#!/bin/bash

# Anvil Utilities Script
# Helper script for common Oracle Hook operations on Anvil

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default values
RPC_URL="http://127.0.0.1:8545"
PRIVATE_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80" # Default anvil account 0

# Contract addresses (will be set after deployment)
HOOK_ADDRESS=""
MOCK_AVS_ADDRESS=""
POOL_MANAGER_ADDRESS=""

echo_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

echo_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

echo_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

echo_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if anvil is running
check_anvil() {
    if ! curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' $RPC_URL > /dev/null; then
        echo_error "Anvil is not running. Please start anvil first with: anvil"
        exit 1
    fi
    echo_success "Anvil is running"
}

# Deploy the Oracle Hook system
deploy() {
    echo_info "Deploying Oracle Hook system to Anvil..."
    
    if forge script script/DeployAnvil.s.sol --rpc-url $RPC_URL --broadcast; then
        echo_success "Deployment completed successfully"
        echo_warning "Please update contract addresses in this script from the deployment output"
    else
        echo_error "Deployment failed"
        exit 1
    fi
}

# Run tests
test() {
    echo_info "Running tests..."
    if forge test; then
        echo_success "All tests passed"
    else
        echo_warning "Some tests failed - check output above"
    fi
}

# Update mock consensus price
update_price() {
    local pool_id=$1
    local price=$2
    local stake=$3
    local confidence=$4
    
    if [[ -z "$MOCK_AVS_ADDRESS" ]]; then
        echo_error "MOCK_AVS_ADDRESS not set. Please update this script with deployed addresses."
        exit 1
    fi
    
    echo_info "Updating price for pool $pool_id to $price"
    
    cast send $MOCK_AVS_ADDRESS "setMockConsensus(bytes32,uint256,uint256,uint256,bool)" \
        $pool_id $price $stake $confidence true \
        --private-key $PRIVATE_KEY \
        --rpc-url $RPC_URL
        
    echo_success "Price updated successfully"
}

# Get consensus data for a pool
get_consensus() {
    local pool_id=$1
    
    if [[ -z "$HOOK_ADDRESS" ]]; then
        echo_error "HOOK_ADDRESS not set. Please update this script with deployed addresses."
        exit 1
    fi
    
    echo_info "Getting consensus data for pool $pool_id"
    
    cast call $HOOK_ADDRESS "getConsensusData(bytes32)" $pool_id --rpc-url $RPC_URL
}

# Enable/disable oracle for a pool
toggle_oracle() {
    local pool_id=$1
    local enabled=$2
    
    if [[ -z "$HOOK_ADDRESS" ]]; then
        echo_error "HOOK_ADDRESS not set. Please update this script with deployed addresses."
        exit 1
    fi
    
    echo_info "Setting oracle enabled=$enabled for pool $pool_id"
    
    cast send $HOOK_ADDRESS "enableOracleForPool(bytes32,bool)" \
        $pool_id $enabled \
        --private-key $PRIVATE_KEY \
        --rpc-url $RPC_URL
        
    echo_success "Oracle setting updated"
}

# Show help
show_help() {
    echo "Oracle Hook Anvil Utilities"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  deploy                     Deploy the Oracle Hook system"
    echo "  test                       Run all tests"
    echo "  check                      Check if Anvil is running"
    echo "  update-price <pool> <price> <stake> <confidence>"
    echo "                            Update mock consensus price"
    echo "  get-consensus <pool>       Get consensus data for a pool"
    echo "  enable-oracle <pool>       Enable oracle for a pool"
    echo "  disable-oracle <pool>      Disable oracle for a pool"
    echo "  help                       Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 deploy"
    echo "  $0 update-price 0x123... 2200000000000000000000 200000000000000000000 9000"
    echo "  $0 get-consensus 0x123..."
    echo "  $0 enable-oracle 0x123..."
    echo ""
    echo "Note: Update contract addresses in this script after deployment"
}

# Main command handler
case "$1" in
    "deploy")
        check_anvil
        deploy
        ;;
    "test")
        test
        ;;
    "check")
        check_anvil
        ;;
    "update-price")
        if [[ $# -ne 5 ]]; then
            echo_error "Usage: $0 update-price <pool_id> <price> <stake> <confidence>"
            exit 1
        fi
        check_anvil
        update_price "$2" "$3" "$4" "$5"
        ;;
    "get-consensus")
        if [[ $# -ne 2 ]]; then
            echo_error "Usage: $0 get-consensus <pool_id>"
            exit 1
        fi
        check_anvil
        get_consensus "$2"
        ;;
    "enable-oracle")
        if [[ $# -ne 2 ]]; then
            echo_error "Usage: $0 enable-oracle <pool_id>"
            exit 1
        fi
        check_anvil
        toggle_oracle "$2" true
        ;;
    "disable-oracle")
        if [[ $# -ne 2 ]]; then
            echo_error "Usage: $0 disable-oracle <pool_id>"
            exit 1
        fi
        check_anvil
        toggle_oracle "$2" false
        ;;
    "help"|"--help"|"-h"|"")
        show_help
        ;;
    *)
        echo_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac