module stable_coin_factory::kasa_manager_tests {
    use sui::test_scenario::{Self as test, next_tx};
    use sui::test_utils::{assert_eq};

    use stable_coin_factory::test_helpers::{init_stable_coin_factory, open_kasa, deposit_to_stability_pool};
    use stable_coin_factory::stability_pool::{Self, StabilityPoolStorage, StabilityPoolEpochScaleSum};
    use stable_coin_factory::kasa_manager::{Self, KasaManagerStorage};
    use tokens::rusd_stable_coin::RUSDStableCoinStorage;
    use library::test_utils::{people, scenario};
    // use library::utils::logger;

    #[test]
    fun test_liquidate_single_happy_path() {
        let scenario = scenario();
        let (admin, user) = people();
        let test = &mut scenario;

        init_stable_coin_factory(test);

        next_tx(test, user);
        {   
            open_kasa(test, user, 3_000000000, 4_500_000000000);
        };
        next_tx(test, @0x1234);
        {   
            open_kasa(test, @0x1234, 15_000000000, 20_000_000000000);
        };
        next_tx(test, @0x1234);
        {
            deposit_to_stability_pool(test, @0x1234, 10_000_000000000);
        };
        next_tx(test, admin);
        {
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let stability_pool_storage = test::take_shared<StabilityPoolStorage>(test);
            let stability_pool_epoch_scale_sum = test::take_shared<StabilityPoolEpochScaleSum>(test);
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);

            kasa_manager::liquidate_single(
                &mut kasa_manager_storage,
                &mut stability_pool_storage,
                &mut stability_pool_epoch_scale_sum,
                &mut rusd_stable_coin_storage,
                user,
                test::ctx(test)
            );

            assert_eq(kasa_manager::has_kasa(&kasa_manager_storage, user), false);
            assert_eq(kasa_manager::has_kasa(&kasa_manager_storage, @0x1234), true);

            let (total_collateral_amount, total_debt_amount) = kasa_manager::get_protocol_balances(&kasa_manager_storage);
            assert_eq(total_collateral_amount, 15_000000000);
            assert_eq(total_debt_amount, 20_000_000000000);

            let stability_pool_total_stake = stability_pool::get_total_stake_amount(&stability_pool_storage);
            assert_eq(stability_pool_total_stake, 5_500_000000000);

            let stake = stability_pool::get_stake_amount(&stability_pool_storage, @0x1234);
            assert_eq(stake, 5_500_000000000);

            test::return_shared(kasa_manager_storage);
            test::return_shared(stability_pool_storage);
            test::return_shared(stability_pool_epoch_scale_sum);
            test::return_shared(rusd_stable_coin_storage);
        };
        next_tx(test, @0x1234);
        {
            deposit_to_stability_pool(test, @0x1234, 800_000000000);
        };
        next_tx(test, @0x1234);
        {
            let stability_pool_storage = test::take_shared<StabilityPoolStorage>(test);
            let stake = stability_pool::get_stake_amount(&stability_pool_storage, @0x1234);
            assert_eq(stake, 6_300_000000000);
            test::return_shared(stability_pool_storage);
        };
        test::end(scenario);
    }

    #[test]
    fun test_liquidate_single_stability_pool_full_depletion() {
        let scenario = scenario();
        let (admin, user) = people();
        let test = &mut scenario;

        init_stable_coin_factory(test);

        next_tx(test, user);
        {   
            open_kasa(test, user, 3_000000000, 4_500_000000000);
        };
        next_tx(test, @0x1234);
        {   
            open_kasa(test, @0x1234, 15_000000000, 20_000_000000000);
        };
        next_tx(test, @0x1234);
        {
            deposit_to_stability_pool(test, @0x1234, 4_500_000000000);
        };
        next_tx(test, admin);
        {
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let stability_pool_storage = test::take_shared<StabilityPoolStorage>(test);
            let stability_pool_epoch_scale_sum = test::take_shared<StabilityPoolEpochScaleSum>(test);
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);

            kasa_manager::liquidate_single(
                &mut kasa_manager_storage,
                &mut stability_pool_storage,
                &mut stability_pool_epoch_scale_sum,
                &mut rusd_stable_coin_storage,
                user,
                test::ctx(test)
            );

            assert_eq(kasa_manager::has_kasa(&kasa_manager_storage, user), false);
            assert_eq(kasa_manager::has_kasa(&kasa_manager_storage, @0x1234), true);

            let (total_collateral_amount, total_debt_amount) = kasa_manager::get_protocol_balances(&kasa_manager_storage);
            assert_eq(total_collateral_amount, 15_000000000);
            assert_eq(total_debt_amount, 20_000_000000000);

            let stability_pool_total_stake = stability_pool::get_total_stake_amount(&stability_pool_storage);
            assert_eq(stability_pool_total_stake, 0);

            test::return_shared(kasa_manager_storage);
            test::return_shared(stability_pool_storage);
            test::return_shared(stability_pool_epoch_scale_sum);
            test::return_shared(rusd_stable_coin_storage);
        };
        test::end(scenario);
    }

    // #[test]
    // fun test_liquidate_batch_happy_path() {

    // }
}