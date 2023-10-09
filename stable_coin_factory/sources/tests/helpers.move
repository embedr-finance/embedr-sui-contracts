#[test_only]
module stable_coin_factory::test_helpers {
    use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
    use sui::coin::{Self, mint_for_testing, Coin};
    use sui::sui::{SUI};

    use stable_coin_factory::kasa_storage::{Self, KasaManagerStorage};
    use stable_coin_factory::kasa_manager::{Self, KasaManagerPublisher};
    use stable_coin_factory::kasa_operations;
    use stable_coin_factory::stability_pool::{Self, StabilityPoolStorage};
    use stable_coin_factory::liquidation_assets_distributor::{Self, CollateralGains};
    use stable_coin_factory::sorted_kasas::{Self, SortedKasasStorage};
    use tokens::rusd_stable_coin::{Self, RUSDStableCoinStorage, RUSDStableCoinAdminCap, RUSD_STABLE_COIN};
    use library::test_utils::people;

    public fun init_stable_coin_factory(test: &mut Scenario) {
        let (admin, _) = people();
        next_tx(test, admin);
        {
            kasa_storage::init_for_testing(ctx(test));
            kasa_manager::init_for_testing(ctx(test));
            stability_pool::init_for_testing(ctx(test));
            liquidation_assets_distributor::init_for_testing(ctx(test));
            rusd_stable_coin::init_for_testing(ctx(test));
            sorted_kasas::init_for_testing(ctx(test));
        };
        next_tx(test, admin);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let rsc_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);
            let id = kasa_manager::get_publisher_id(&km_publisher);
            rusd_stable_coin::add_manager(
                &rsc_admin_cap,
                &mut rsc_storage,
                id
            );
            test::return_shared(km_publisher);
            test::return_shared(km_storage);
            test::return_shared(rsc_storage);
            test::return_to_address(admin, rsc_admin_cap);
        };
    }

    public fun open_kasa(test: &mut Scenario, account_address: address, collateral_amount: u64, debt_amount: u64) {
        let km_publisher = test::take_shared<KasaManagerPublisher>(test);
        let km_storage = test::take_shared<KasaManagerStorage>(test);
        let sk_storage = test::take_shared<SortedKasasStorage>(test);
        let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);

        next_tx(test, account_address);
        {
            let collateral = mint_for_testing<SUI>(collateral_amount, ctx(test));
            kasa_operations::open_kasa(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                collateral,
                debt_amount,
                ctx(test)
            );
        };

        test::return_shared(km_publisher);
        test::return_shared(km_storage);
        test::return_shared(sk_storage);
        test::return_shared(rsc_storage);
    }

    public fun deposit_to_stability_pool(test: &mut Scenario, account_address: address, amount: u64) {
        next_tx(test, account_address);
        {
            let sp_storage = test::take_shared<StabilityPoolStorage>(test);
            let collateral_gains = test::take_shared<CollateralGains>(test);
            let stable_coin = test::take_from_sender<Coin<RUSD_STABLE_COIN>>(test);
            let coin_to_stake = coin::split(&mut stable_coin, amount, test::ctx(test));
            stability_pool::deposit(
                &mut sp_storage,
                &mut collateral_gains,
                coin_to_stake,
                test::ctx(test),
            );
            test::return_shared(sp_storage);
            test::return_shared(collateral_gains);
            test::return_to_sender(test, stable_coin);
        };
    }
}
