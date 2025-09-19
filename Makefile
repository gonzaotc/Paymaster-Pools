# Decentralized Paymasters - Makefile
# Commands for deploying and testing the Uniswap v4 + Account Abstraction system

# Load environment variables from config.env if it exists
-include config.env

# Default Anvil configuration
ANVIL_HOST := 0.0.0.0
ANVIL_PORT := 8545
ANVIL_RPC_URL := http://localhost:$(ANVIL_PORT)

# Default private key (Anvil's first account)
PRIVATE_KEY := 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80

# Forge script configuration
SCRIPT_CONTRACT := script/Deploy.s.sol:Deploy

# Default values for environment variables
BROADCAST ?= true
BUNDLER_ETH ?= 1000000000000000000
DEPOSITOR_ETH ?= 1000000000000000000
LP_ETH ?= 100000000000000000000000000
TOKEN_AMOUNT ?= 100000000000000000000000000
LIQUIDITY_AMOUNT ?= 10000000000000000000000

.PHONY: help anvil deploy test clean compile setup-env mint-tokens add-liquidity

# Default target
help:
	@echo "Decentralized Paymasters - Available Commands:"
	@echo ""
	@echo "  make anvil     - Start Anvil local blockchain"
	@echo "  make help      - Show this help message"
	@echo ""
	@echo "Environment variables:"
	@echo "  ANVIL_PORT     - Anvil port (default: 8545)"
	@echo "  PRIVATE_KEY    - Private key for deployment"
	@echo "  FORK_URL       - RPC URL for forking (e.g., https://eth-mainnet.alchemyapi.io/v2/YOUR_KEY)"

# Start Anvil blockchain
anvil:
	@echo "Starting Anvil blockchain on $(ANVIL_HOST):$(ANVIL_PORT)..."
	@echo "Press Ctrl+C to stop"
	anvil --host $(ANVIL_HOST) --port $(ANVIL_PORT)

# Deploy contracts to Anvil
deploy: compile
	@echo "deploy"
	forge script script/Deploy.s.sol:Deploy \
		--rpc-url $(ANVIL_RPC_URL) \
		--broadcast \
		--private-key $(PRIVATE_KEY)

# Deploy without broadcasting (dry run)
deploy-dry:
	BROADCAST=false make deploy

# Mint tokens (deploys new token and mints)
mint:
	@echo "mint-tokens"
	forge script script/MintTokens.sol:MintTokens \
		--rpc-url $(ANVIL_RPC_URL) \
		--broadcast \
		--private-key $(PRIVATE_KEY)
