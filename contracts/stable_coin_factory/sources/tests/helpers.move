#[test_only]
module stable_coin_factory::test_helpers {
    use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
    use sui::coin::{Self, mint_for_testing, Coin};
    use sui::sui::{SUI};

    use stable_coin_factory::kasa_storage::{Self, KasaManagerStorage};
    use stable_coin_factory::kasa_manager::{Self, KasaManagerPublisher};
    use stable_coin_factory::kasa_operations;
    use stable_coin_factory::stability_pool::{Self, StabilityPoolStorage, StabilityPoolPublisher};
    use stable_coin_factory::liquidation_assets_distributor::{Self, CollateralGains};
    use stable_coin_factory::sorted_kasas::{Self, SortedKasasStorage};
    use tokens::rusd_stable_coin::{Self, RUSDStableCoinStorage, RUSDStableCoinAdminCap, RUSD_STABLE_COIN};
    use library::test_utils::people;
    use supra_holder:: SupraSValueFeed::{Self, OracleHolder};

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
            SupraSValueFeed::create_oracle_holder_for_test(test::ctx(test));
        };
        next_tx(test, admin);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sp_publisher = test::take_shared<StabilityPoolPublisher>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let rsc_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);
            let km_id = kasa_manager::get_publisher_id(&km_publisher);
            let sp_id = stability_pool::get_publisher_id(&sp_publisher);
            rusd_stable_coin::add_manager(
                &rsc_admin_cap,
                &mut rsc_storage,
                km_id
            );
            rusd_stable_coin::add_manager(
                &rsc_admin_cap,
                &mut rsc_storage,
                sp_id
            );
            test::return_shared(km_publisher);
            test::return_shared(km_storage);
            test::return_shared(sp_publisher);
            test::return_shared(rsc_storage);
            test::return_to_address(admin, rsc_admin_cap);
        };
        next_tx(test, admin);
        {
            let oracle_holder = test::take_shared<OracleHolder>(test);
            SupraSValueFeed::add_pair_data(
                &mut oracle_holder, 90, 1800_000000000000000000, 18, 1704693072240, 6489821);
            test::return_shared(oracle_holder);
        };
    }

    public fun open_kasa(test: &mut Scenario, account_address: address, collateral_amount: u64, debt_amount: u64) {
        let km_publisher = test::take_shared<KasaManagerPublisher>(test);
        let km_storage = test::take_shared<KasaManagerStorage>(test);
        let sk_storage = test::take_shared<SortedKasasStorage>(test);
        let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
        let oracle_holder = test::take_shared<OracleHolder>(test);
        
        next_tx(test, account_address);
        {
            let collateral = mint_for_testing<SUI>(collateral_amount, ctx(test));
            kasa_operations::open_kasa(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                &oracle_holder,
                collateral,
                debt_amount,
                ctx(test)
            );
        };

        test::return_shared(km_publisher);
        test::return_shared(km_storage);
        test::return_shared(sk_storage);
        test::return_shared(rsc_storage);
        test::return_shared(oracle_holder);
    }

    public fun deposit_to_stability_pool(test: &mut Scenario, account_address: address, amount: u64) {
        next_tx(test, account_address);
        {
            let sp_publisher = test::take_shared<StabilityPoolPublisher>(test);
            let sp_storage = test::take_shared<StabilityPoolStorage>(test);
            let collateral_gains = test::take_shared<CollateralGains>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let stable_coin = test::take_from_sender<Coin<RUSD_STABLE_COIN>>(test);
            let coin_to_stake = coin::split(&mut stable_coin, amount, test::ctx(test));
            stability_pool::deposit(
                &sp_publisher,
                &mut sp_storage,
                &mut collateral_gains,
                &mut rsc_storage,
                coin_to_stake,
                test::ctx(test),
            );
            test::return_shared(sp_publisher);
            test::return_shared(sp_storage);
            test::return_shared(collateral_gains);
            test::return_shared(rsc_storage);
            test::return_to_sender(test, stable_coin);
        };
    }

    public fun update_oracle_price(test: &mut Scenario, sui_price: u128, time: u128) : OracleHolder {
        let live_price = (sui_price * 1_000_000_000_000_000_000);
        let oracle_holder = test::take_shared<OracleHolder>(test);
            SupraSValueFeed::add_pair_data(
            &mut oracle_holder, 90, live_price, 18, time, 6489821);
            oracle_holder
    }
}
