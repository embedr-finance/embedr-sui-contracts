#[test_only]
module stable_coin_factory::kasa_manager_redemption_tests {
    use std::option;

    use sui::test_scenario::{Self as test, next_tx, Scenario};
    use sui::test_utils::{assert_eq};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;

    use stable_coin_factory::test_helpers::{init_stable_coin_factory, open_kasa};
    use stable_coin_factory::kasa_storage::{Self, KasaManagerStorage, LiquidationSnapshots};
    use stable_coin_factory::kasa_manager::{Self, KasaManagerPublisher};
    use stable_coin_factory::sorted_kasas::{Self, SortedKasasStorage};
    use stable_coin_factory::liquidation_assets_distributor::CollateralGains;
    use tokens::rusd_stable_coin::{Self, RUSDStableCoinStorage, RUSD_STABLE_COIN};
    use library::test_utils::{people, scenario};
    use library::utils::logger;

    const COLLATERAL_PRICE: u64 = 1800_000000000;

    fun setup_kasas(test: &mut Scenario) {
        let (admin, user) = people();
        let user2 = @0x2222;
        let user3 = @0x3333;
        let user4 = @0x4444;
        next_tx(test, admin);
        {
            open_kasa(test, admin, 100000_000000000, 100000_000000000);
        };
        next_tx(test, admin);
        {
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let stable_coin = test::take_from_sender<Coin<RUSD_STABLE_COIN>>(test);
            rusd_stable_coin::transfer(&mut rsc_storage, stable_coin, user4, test::ctx(test));
            test::return_shared(rsc_storage);
        };
        next_tx(test, user);
        {   
            // ICR = 3 * 1800 / 4500 = 1.2
            open_kasa(test, user, 3_000000000, 4500_000000000);
        };
        next_tx(test, user2);
        {
            // ICR = 15 * 1800 / 20000 = 1.35  
            open_kasa(test, user2, 15_000000000, 20000_000000000);
        };
        next_tx(test, user3);
        {
            // ICR = 10 * 1800 / 10000 = 1.8
            open_kasa(test, user3, 10_000000000, 10000_000000000);
        };
    }

    // #[test]
    fun test_full_redemption() {
        let scenario = scenario();
        let (admin, user) = people();
        let test = &mut scenario;

        let user2 = @0x2222;
        let user3 = @0x3333;
        let user4 = @0x4444;

        init_stable_coin_factory(test);
        setup_kasas(test);

        next_tx(test, user4);
        {
            let collateral = test::take_from_sender<Coin<SUI>>(test);
            assert_eq(coin::value(&collateral), 0);
            test::return_to_sender(test, collateral);
        };
        next_tx(test, user4);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let collateral_gains = test::take_shared<CollateralGains>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let liquidation_snapshots = test::take_shared<LiquidationSnapshots>(test);

            let stable_coin = test::take_from_sender<Coin<RUSD_STABLE_COIN>>(test);

            let kasa_count = kasa_storage::get_kasa_count(&km_storage);
            assert_eq(kasa_count, 4);
            let sorted_kasas_size = sorted_kasas::get_size(&sk_storage);
            assert_eq(sorted_kasas_size, 4);

            kasa_manager::redeem(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                &liquidation_snapshots,
                coin::split(&mut stable_coin, 4500_000000000, test::ctx(test)),
                option::none(),
                option::none(),
                option::none(),
                0,
                test::ctx(test)
            );

            let kasa_count = kasa_storage::get_kasa_count(&km_storage);
            assert_eq(kasa_count, 3);
            let sorted_kasas_size = sorted_kasas::get_size(&sk_storage);
            assert_eq(sorted_kasas_size, 3);
            assert_eq(kasa_storage::has_kasa(&km_storage, user), false);

            let balance = rusd_stable_coin::get_balance(&rsc_storage, user);
            assert_eq(balance, 4500_000000000);

            let balance = rusd_stable_coin::get_balance(&rsc_storage, user4);
            assert_eq(balance, 95500_000000000);

            kasa_manager::redeem(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                &liquidation_snapshots,
                coin::split(&mut stable_coin, 20000_000000000, test::ctx(test)),
                option::none(),
                option::none(),
                option::none(),
                0,
                test::ctx(test)
            );

            let kasa_count = kasa_storage::get_kasa_count(&km_storage);
            assert_eq(kasa_count, 2);
            let sorted_kasas_size = sorted_kasas::get_size(&sk_storage);
            assert_eq(sorted_kasas_size, 2);
            assert_eq(kasa_storage::has_kasa(&km_storage, user2), false);

            let balance = rusd_stable_coin::get_balance(&rsc_storage, user2);
            assert_eq(balance, 20000_000000000);

            let balance = rusd_stable_coin::get_balance(&rsc_storage, user4);
            assert_eq(balance, 75500_000000000);

            kasa_manager::redeem(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                &liquidation_snapshots,
                coin::split(&mut stable_coin, 10000_000000000, test::ctx(test)),
                option::none(),
                option::none(),
                option::none(),
                0,
                test::ctx(test)
            );

            let kasa_count = kasa_storage::get_kasa_count(&km_storage);
            assert_eq(kasa_count, 1);
            let sorted_kasas_size = sorted_kasas::get_size(&sk_storage);
            assert_eq(sorted_kasas_size, 1);
            assert_eq(kasa_storage::has_kasa(&km_storage, user3), false);

            let balance = rusd_stable_coin::get_balance(&rsc_storage, user3);
            assert_eq(balance, 10000_000000000);

            let balance = rusd_stable_coin::get_balance(&rsc_storage, user4);
            assert_eq(balance, 65500_000000000);

            test::return_shared(km_publisher);
            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(collateral_gains);
            test::return_shared(rsc_storage);
            test::return_shared(liquidation_snapshots);
            test::return_to_sender(test, stable_coin);
        };
        test::end(scenario);
    }

    #[test]
    fun test_partial_redemption() {
        let scenario = scenario();
        let (admin, user) = people();
        let test = &mut scenario;

        let user2 = @0x2222;
        let user3 = @0x3333;
        let user4 = @0x4444;

        init_stable_coin_factory(test);
        setup_kasas(test);
        
        next_tx(test, user4);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let collateral_gains = test::take_shared<CollateralGains>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let liquidation_snapshots = test::take_shared<LiquidationSnapshots>(test);

            let stable_coin = test::take_from_sender<Coin<RUSD_STABLE_COIN>>(test);

            let kasa_count = kasa_storage::get_kasa_count(&km_storage);
            assert_eq(kasa_count, 4);
            let sorted_kasas_size = sorted_kasas::get_size(&sk_storage);
            assert_eq(sorted_kasas_size, 4);

            // ============== FIRST REDEMPTION ==============
    
            let (
                first_redemption_hint,
                partial_redemption_hint_nicr,
                truncated_stable_coin_amount
            ) = kasa_manager::get_redemption_hints(
                &mut km_storage,
                &mut sk_storage,
                1000_000000000,
                COLLATERAL_PRICE,
                10,
            );

            kasa_manager::redeem(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                &liquidation_snapshots,
                coin::split(&mut stable_coin, truncated_stable_coin_amount, test::ctx(test)),
                first_redemption_hint,
                option::none(),
                option::none(),
                partial_redemption_hint_nicr,
                test::ctx(test)
            );

            let kasa_count = kasa_storage::get_kasa_count(&km_storage);
            assert_eq(kasa_count, 4);
            let sorted_kasas_size = sorted_kasas::get_size(&sk_storage);
            assert_eq(sorted_kasas_size, 4);

            let (kasa_collateral_amount, kasa_debt_amount) =
                kasa_storage::get_kasa_amounts(&mut km_storage, user);
            assert_eq(kasa_collateral_amount, 2_444444445);
            assert_eq(kasa_debt_amount, 3500_000000000);

            let balance = rusd_stable_coin::get_balance(&rsc_storage, user4);
            assert_eq(balance, 99000_000000000);

            // ============== SECOND REDEMPTION ==============

            let (
                first_redemption_hint,
                partial_redemption_hint_nicr,
                truncated_stable_coin_amount
            ) = kasa_manager::get_redemption_hints(
                &mut km_storage,
                &mut sk_storage,
                6000_000000000,
                COLLATERAL_PRICE,
                10,
            );

            kasa_manager::redeem(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                &liquidation_snapshots,
                coin::split(&mut stable_coin, truncated_stable_coin_amount, test::ctx(test)),
                first_redemption_hint,
                option::none(),
                option::none(),
                partial_redemption_hint_nicr,
                test::ctx(test)
            );

            let kasa_count = kasa_storage::get_kasa_count(&km_storage);
            assert_eq(kasa_count, 3);
            let sorted_kasas_size = sorted_kasas::get_size(&sk_storage);
            assert_eq(sorted_kasas_size, 3);

            let (kasa_collateral_amount, kasa_debt_amount) =
                kasa_storage::get_kasa_amounts(&mut km_storage, user2);
            assert_eq(kasa_collateral_amount, 13_611111112);
            assert_eq(kasa_debt_amount, 17500_000000000);

            let balance = rusd_stable_coin::get_balance(&rsc_storage, user4);
            assert_eq(balance, 93000_000000000);

            // ============== THIRD REDEMPTION ==============

            let (
                first_redemption_hint,
                partial_redemption_hint_nicr,
                truncated_stable_coin_amount
            ) = kasa_manager::get_redemption_hints(
                &mut km_storage,
                &mut sk_storage,
                26500_000000000,
                COLLATERAL_PRICE,
                10,
            );

            kasa_manager::redeem(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                &liquidation_snapshots,
                coin::split(&mut stable_coin, truncated_stable_coin_amount, test::ctx(test)),
                first_redemption_hint,
                option::none(),
                option::none(),
                partial_redemption_hint_nicr,
                test::ctx(test)
            );

            let kasa_count = kasa_storage::get_kasa_count(&km_storage);
            assert_eq(kasa_count, 2);
            let sorted_kasas_size = sorted_kasas::get_size(&sk_storage);
            assert_eq(sorted_kasas_size, 2);

            let (kasa_collateral_amount, kasa_debt_amount) =
                kasa_storage::get_kasa_amounts(&mut km_storage, user3);
            assert_eq(kasa_collateral_amount, 5_444444445);
            assert_eq(kasa_debt_amount, 1800_000000000);

            let balance = rusd_stable_coin::get_balance(&rsc_storage, user4);
            assert_eq(balance, 67300_000000000);

            test::return_shared(km_publisher);
            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(collateral_gains);
            test::return_shared(rsc_storage);
            test::return_shared(liquidation_snapshots);
            test::return_to_sender(test, stable_coin);
        };
        next_tx(test, user4);
        {
            // At the end of each calculation we have 1 denom leftover SUI

            // Last redemption
            let collateral = test::take_from_sender<Coin<SUI>>(test);
            assert_eq(coin::value(&collateral), 14_206388889);
            coin::burn_for_testing(collateral);

            // Middle redemption
            let collateral = test::take_from_sender<Coin<SUI>>(test);
            assert_eq(coin::value(&collateral), 3_316666666);
            coin::burn_for_testing(collateral);

            // First redemption
            let collateral = test::take_from_sender<Coin<SUI>>(test);
            assert_eq(coin::value(&collateral), 552777778);
            coin::burn_for_testing(collateral);
        };
        test::end(scenario);
    }
}
