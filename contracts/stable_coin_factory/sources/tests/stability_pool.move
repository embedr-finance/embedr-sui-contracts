#[test_only]
module stable_coin_factory::stability_pool_tests {
    use sui::test_scenario::{Self as test, next_tx};
    use sui::test_utils::{assert_eq};
    use sui::coin::{Self, Coin};

    use stable_coin_factory::test_helpers::{init_stable_coin_factory, open_kasa};
    use stable_coin_factory::stability_pool::{Self, StabilityPoolStorage, StabilityPoolPublisher};
    use stable_coin_factory::liquidation_assets_distributor::CollateralGains;
    use tokens::rusd_stable_coin::{Self, RUSD_STABLE_COIN, RUSDStableCoinStorage};
    use supra_holder:: svalue_feed_holder :: {Self, OracleHolder};
    use library::test_utils::{people, scenario};

    #[test]
    fun test_deposit_happy_path() {
        let scenario = scenario();
        let (_, user) = people();
        let test = &mut scenario;

        init_stable_coin_factory(test);

        next_tx(test, user);
        {
            svalue_feed_holder::create_oracle_holder_for_test(test::ctx(test));
        };

        next_tx(test, user);
        {   
            open_kasa(test, user, 1000_000000000, 5000_000000000);
        };
        next_tx(test, user);
        {
            let sp_publisher = test::take_shared<StabilityPoolPublisher>(test);
            let sp_storage = test::take_shared<StabilityPoolStorage>(test);
            let collateral_gains = test::take_shared<CollateralGains>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let stable_coin = test::take_from_sender<Coin<RUSD_STABLE_COIN>>(test);
            let coin_to_stake = coin::split(&mut stable_coin, 3400_000000000, test::ctx(test));

            stability_pool::deposit(
                &sp_publisher,
                &mut sp_storage,
                &mut collateral_gains,
                &mut rsc_storage,
                coin_to_stake,
                test::ctx(test),
            );
            assert_eq(stability_pool::get_stake_amount(&sp_storage, user), 3400_000000000);
            assert_eq(stability_pool::get_total_stake_amount(&sp_storage), 3400_000000000);

            let balance = rusd_stable_coin::get_balance(&rsc_storage, user);
            assert_eq(balance, 1600_000000000);

            test::return_shared(sp_publisher);
            test::return_shared(sp_storage);
            test::return_shared(collateral_gains);
            test::return_shared(rsc_storage);
            test::return_to_sender(test, stable_coin);
        };
        test::end(scenario);
    }

    #[test]
    fun test_withdraw_happy_path() {
        let scenario = scenario();
        let (_, user) = people();
        let test = &mut scenario;

        init_stable_coin_factory(test);

        next_tx(test, user);
        {
            svalue_feed_holder::create_oracle_holder_for_test(test::ctx(test));
        };

        next_tx(test, user);
        {   
            open_kasa(test, user, 1000_000000000, 5000_000000000);
        };
        next_tx(test, user);
        {   
            let sp_publisher = test::take_shared<StabilityPoolPublisher>(test);
            let sp_storage = test::take_shared<StabilityPoolStorage>(test);
            let collateral_gains = test::take_shared<CollateralGains>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let stable_coin = test::take_from_sender<Coin<RUSD_STABLE_COIN>>(test);
            let coin_to_stake = coin::split(&mut stable_coin, 5000_000000000, test::ctx(test));
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
        next_tx(test, user);
        {
            let sp_publisher = test::take_shared<StabilityPoolPublisher>(test);
            let sp_storage = test::take_shared<StabilityPoolStorage>(test);
            let collateral_gains = test::take_shared<CollateralGains>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);

            stability_pool::withdraw(
                &sp_publisher,
                &mut sp_storage,
                &mut collateral_gains,
                &mut rsc_storage,
                3400_000000000,
                test::ctx(test),
            );
            assert_eq(stability_pool::get_stake_amount(&sp_storage, user), 1600_000000000);
            assert_eq(stability_pool::get_total_stake_amount(&sp_storage), 1600_000000000);

            let balance = rusd_stable_coin::get_balance(&rsc_storage, user);
            assert_eq(balance, 3400_000000000);

            stability_pool::withdraw(
                &sp_publisher,
                &mut sp_storage,
                &mut collateral_gains,
                &mut rsc_storage,
                1600_000000000,
                test::ctx(test),
            );
            assert_eq(stability_pool::get_stake_amount(&sp_storage, user), 0);
            assert_eq(stability_pool::get_total_stake_amount(&sp_storage), 0);

            let balance = rusd_stable_coin::get_balance(&rsc_storage, user);
            assert_eq(balance, 5000_000000000);

            test::return_shared(sp_publisher);
            test::return_shared(sp_storage);
            test::return_shared(collateral_gains);
            test::return_shared(rsc_storage);
        };
        next_tx(test, user);
        {
            let stable_coin1 = test::take_from_sender<Coin<RUSD_STABLE_COIN>>(test);
            let stable_coin2 = test::take_from_sender<Coin<RUSD_STABLE_COIN>>(test);
            assert_eq(coin::value(&stable_coin1), 1600_000000000);
            assert_eq(coin::value(&stable_coin2), 3400_000000000);
            test::return_to_sender(test, stable_coin1);
            test::return_to_sender(test, stable_coin2);
        };
        test::end(scenario);
    }
}