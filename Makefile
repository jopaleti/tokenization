-include .env

.PHONY: deploy

deploy :; forge script script/DeployDTsla.s.sol:DeployDTsla \
 --sender 0x7B85A65ae33da5436e6950dF506D51C1729e7878 \
 --private-key 53f79ba46063a9ceef03f510f9f9e3832269cdd46f7774a10ad0eb79b46f26c5 \
 --account defaultKey --rpc-url ${SEPOLIA_RPC_URL} --etherscan-api-key ${ETHERSCAN_API_KEY} \
 --priority-gas-price 1 --verify --broadcast

# --verify --broadcast 