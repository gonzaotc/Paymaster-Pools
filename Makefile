# Decentralized Paymasters - Makefile
# Commands for deploying and testing the Uniswap v4 + Account Abstraction system

# Load environment variables from config.env if it exists
-include config.env

# Default Anvil configuration
ANVIL_HOST := 0.0.0.0 
ANVIL_RPC_URL := http://localhost:8545

# Default addresses
PRIVATE_KEY := 0x1e5091fe2d2997d2a7121bf052a974fa66af92da69890a2e738d4e7c39faede2
EOA_ADDRESS := 0x8CF2e7649D788f83Fa32EfFa0386724f6fD78BD5
TOKEN_ADDRESS := 0x07088757F513C5E48aeBb66f0a67F76260A737B4
RECEIVER_ADDRESS := 0xB6D4805bf6943c5875C0C7b67EDa24b2bDACBF6e
PERMIT2_ADDRESS := 0x000000000022D473030F116dDEE9F6B43aC78BA3

.PHONY: help anvil deploy test clean compile setup-env mint-tokens add-liquidity

fork:
	anvil --fork-url https://eth-sepolia.g.alchemy.com/v2/qnebjCbC6nk-NLXELGEZ4 --fork-block-number 9232749

# Deploy contracts to Anvil
deploy: compile
	@echo "deploy"
	forge script script/Deploy.s.sol:Deploy \
		--rpc-url $(ANVIL_RPC_URL) \
		--broadcast \
		--private-key $(PRIVATE_KEY)

add-liquidity:
	@echo "add-liquidity"
	forge script script/AddLiquidity.s.sol:AddLiquidity \
		--rpc-url $(ANVIL_RPC_URL) \
		--broadcast \
		--private-key $(PRIVATE_KEY)

code:
	cast code --rpc-url $(ANVIL_RPC_URL) $(EOA_ADDRESS)

delegate:
	forge script script/EIP7702Delegation.s.sol:EIP7702Delegation \
		--rpc-url $(ANVIL_RPC_URL) \
		--broadcast \
		--private-key $(PRIVATE_KEY)

approve-permit:
	forge script script/ApprovePermit.s.sol:ApprovePermit \
		--rpc-url $(ANVIL_RPC_URL) \
		--broadcast \
		--private-key $(PRIVATE_KEY)

deposit:
	forge script script/Deposit.s.sol:Deposit \
		--rpc-url $(ANVIL_RPC_URL) \
		--broadcast \
		--private-key $(PRIVATE_KEY)

sponsorship:
	forge script script/Sponsorship.s.sol:Sponsorship \
		--rpc-url $(ANVIL_RPC_URL) \
		--broadcast \
		--private-key $(PRIVATE_KEY)












balance:
	cast balance --rpc-url $(ANVIL_RPC_URL) $(EOA_ADDRESS) | cast to-dec

balance-of-eoa:
	cast call $(TOKEN_ADDRESS) "balanceOf(address)" $(EOA_ADDRESS) --rpc-url $(ANVIL_RPC_URL) | cast to-dec

balance-of-receiver:
	cast call $(TOKEN_ADDRESS) "balanceOf(address)" $(RECEIVER_ADDRESS) --rpc-url $(ANVIL_RPC_URL) | cast to-dec
	
permit-allowance:
	cast call $(TOKEN_ADDRESS) "allowance(address,address)" $(EOA_ADDRESS) $(PERMIT2_ADDRESS) --rpc-url $(ANVIL_RPC_URL) | cast to-dec
