test:
	cd stable_coin_factory && sui move test && cd ..
	cd tokens && sui move test && cd ..