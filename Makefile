PACKAGES := library tokens stable_coin_factory 

test:
ifdef module
	cd contracts/$(module) && sui move test && cd ../..
else
	for package in $(PACKAGES); do \
		cd contracts/$$package && sui move test && cd ../..; \
	done
endif

deploy:
	@echo "Deploying Embedr Protocol Contracts"
	@echo ""

	@bash scripts/request_test_tokens.sh
	@echo ""

	@bash scripts/deploy_modules.sh
	@echo ""

	@bash scripts/km_mint_permission.sh
	@echo ""
