#[test_only]
module stable_coin_factory::kasa_manager_liquidation_tests {
    use sui::test_scenario::{Self as test, next_tx, ctx};
    use sui::test_utils::{assert_eq};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;

    use stable_coin_factory::test_helpers::{init_stable_coin_factory, open_kasa, deposit_to_stability_pool};
    use stable_coin_factory::kasa_storage::{Self, KasaManagerStorage};
    use stable_coin_factory::kasa_manager::{Self, KasaManagerPublisher};
    use stable_coin_factory::sorted_kasas::{SortedKasasStorage};
    use stable_coin_factory::stability_pool::{Self, StabilityPoolStorage};
    use stable_coin_factory::liquidation_assets_distributor::CollateralGains;
    use tokens::rusd_stable_coin::{Self, RUSDStableCoinStorage};
    use library::test_utils::{people, scenario};
    use SupraOracle::SupraSValueFeed::{Self, OracleHolder, return_oracleholder, delete_oracleholder};
   
    // use library::utils::logger;

    #[test]
    fun test_liquidate_stability_pool_partial_depletion() {
        let scenario = scenario();
        let (admin, user) = people();
        let test = &mut scenario;

        init_stable_coin_factory(test);

        next_tx(test, user);
        {   
            open_kasa(test, user, 3_000000000, 4500_000000000);
        };
        next_tx(test, @0x2222);
        {   
            open_kasa(test, @0x2222, 15_000000000, 20000_000000000);
        };
        next_tx(test, @0x2222);
        {
            deposit_to_stability_pool(test, @0x2222, 10000_000000000);
        };
        next_tx(test, admin);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let sp_storage = test::take_shared<StabilityPoolStorage>(test);
            let collateral_gains = test::take_shared<CollateralGains>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let oracle_holder = return_oracleholder(ctx(test));
            

            let balance = rusd_stable_coin::get_balance(&rsc_storage, user);
            assert_eq(balance, 4500_000000000);

            kasa_manager::liquidate(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut sp_storage,
                &mut collateral_gains,
                &mut rsc_storage,
                &oracle_holder,
                test::ctx(test)
            );

            assert_eq(kasa_storage::has_kasa(&km_storage, user), false);
            assert_eq(kasa_storage::has_kasa(&km_storage, @0x2222), true);

            let (total_collateral_amount, total_debt_amount) = kasa_storage::get_total_balances(&km_storage);
            assert_eq(total_collateral_amount, 15_000000000);
            assert_eq(total_debt_amount, 20000_000000000);

            let stability_pool_total_stake = stability_pool::get_total_stake_amount(&sp_storage);
            assert_eq(stability_pool_total_stake, 5500_000000000);

            let stake = stability_pool::get_stake_amount(&sp_storage, @0x2222);
            assert_eq(stake, 5500_000000000);

            let balance = rusd_stable_coin::get_balance(&rsc_storage, user);
            assert_eq(balance, 0);

            test::return_shared(km_publisher);
            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(sp_storage);
            test::return_shared(collateral_gains);
            test::return_shared(rsc_storage);
            delete_oracleholder(oracle_holder);
        };
        next_tx(test, @0x2222);
        {
            deposit_to_stability_pool(test, @0x2222, 800_000000000);
        };
        next_tx(test, @0x2222);
        {
            let collateral = test::take_from_sender<Coin<SUI>>(test);
            assert_eq(coin::value(&collateral), 3_000000000);

            let sp_storage = test::take_shared<StabilityPoolStorage>(test);   
            let stake = stability_pool::get_stake_amount(&sp_storage, @0x2222);
            assert_eq(stake, 6300_000000000);
            
            test::return_shared(sp_storage);
            test::return_to_sender(test, collateral);
        };
        test::end(scenario);
    }

    #[test]
    fun test_liquidate_stability_pool_full_depletion() {
        let scenario = scenario();
        let (admin, user) = people();
        let test = &mut scenario;

        init_stable_coin_factory(test);

        next_tx(test, user);
        {   
            open_kasa(test, user, 3_000000000, 4500_000000000);
        };
        next_tx(test, @0x2222);
        {   
            open_kasa(test, @0x2222, 15_000000000, 20000_000000000);
        };
        next_tx(test, @0x2222);
        {
            deposit_to_stability_pool(test, @0x2222, 4500_000000000);
        };
        next_tx(test, admin);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let sp_storage = test::take_shared<StabilityPoolStorage>(test);
            let collateral_gains = test::take_shared<CollateralGains>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let oracle_holder = return_oracleholder(ctx(test));

            kasa_manager::liquidate(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut sp_storage,
                &mut collateral_gains,
                &mut rsc_storage,
                &oracle_holder,
                test::ctx(test)
            );

            assert_eq(kasa_storage::has_kasa(&km_storage, user), false);
            assert_eq(kasa_storage::has_kasa(&km_storage, @0x2222), true);

            let (total_collateral_amount, total_debt_amount) = kasa_storage::get_total_balances(&km_storage);
            assert_eq(total_collateral_amount, 15_000000000);
            assert_eq(total_debt_amount, 20000_000000000);

            let stability_pool_total_stake = stability_pool::get_total_stake_amount(&sp_storage);
            assert_eq(stability_pool_total_stake, 0);

            test::return_shared(km_publisher);
            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(sp_storage);
            test::return_shared(collateral_gains);
            test::return_shared(rsc_storage);
            delete_oracleholder(oracle_holder);
        };
        test::end(scenario);
    }
}
