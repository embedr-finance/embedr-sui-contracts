PACKAGES := library tokens stable_coin_factory 

test:
ifdef module
	cd contracts/$(module) && sui move test && cd ../..
else
	for package in $(PACKAGES); do \
		cd contracts/$$package && sui move test && cd ../..; \
	done
endif

# build:
# 	for package in $(PACKAGES); do \
# 		cd contracts/$$package && sui move build && cd ../..; \
# 	done

# deploy:
# 	for package in $(PACKAGES); do \
# 		cd contracts/$$package && sui client publish --gas-budget 20000000 && cd ../..; \
# 	done