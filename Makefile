-include .env

.PHONY: all test clean install snapshot format anvil 


all: remove install build

# Clean the repo
clean  :; forge clean


remove :; rm -rf .gitmodules && rm -rf .git/modules/* && rm -rf lib && touch .gitmodules && git add . && git commit -m "modules"

install :; forge install foundry-rs/forge-std --no-commit && forge install openzeppelin/openzeppelin-contracts --no-commit 

# Update Dependencies
update:; forge update

build:; forge build

test :; forge test 

snapshot :; forge snapshot

format :; forge fmt

deploy:
	forge script script/Deploy.s.sol:Deploy --rpc-url $(SEPOLIA_RPC_URL) --account dev --broadcast --verify --etherscan-api-key $(ETHERSCAN_API_KEY)
