PACKAGES := library tokens stable_coin_factory participation_bank_factory

test:
ifdef package
	cd contracts/$(package) && sui move test && cd ../..
else
	for package in $(PACKAGES); do \
		cd contracts/$$package && sui move test && cd ../..; \
	done
endif

deploy:
	@bash scripts/request_test_tokens.sh

	@bash scripts/deploy_modules.sh

	@bash scripts/add_manager_rusd_stable_coin.sh

	@bash scripts/add_manager_embd_incentive_token.sh
