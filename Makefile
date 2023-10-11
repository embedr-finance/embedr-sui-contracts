PACKAGES := library tokens stable_coin_factory 

# fund-active-wallet:
# 	curl --location --request POST 'https://faucet.devnet.sui.io/gas' --header 'Content-Type: application/json' --data-raw '{"FixedAmountRequest": {"recipient": "$(shell sui client active-address)"}}'

test:
	for package in $(PACKAGES); do \
		cd contracts/$$package && sui move test && cd ../..; \
	done

# build:
# 	for package in $(PACKAGES); do \
# 		cd contracts/$$package && sui move build && cd ../..; \
# 	done

# deploy:
# 	for package in $(PACKAGES); do \
# 		cd contracts/$$package && sui client publish --gas-budget 20000000 && cd ../..; \
# 	done