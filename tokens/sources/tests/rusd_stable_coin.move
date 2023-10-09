#[test_only]
module tokens::rusd_stable_coin_tests {
    use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
    use sui::test_utils::{assert_eq};
    use sui::coin::{burn_for_testing as burn};

    use tokens::rusd_stable_coin::{Self, RUSDStableCoinStorage, RUSDStableCoinAdminCap, RUSD_STABLE_COIN};
    use library::test_utils::{people, scenario};
    use library::foo::{Self, FooStorage};

    fun start_rusd_stable_coin(test: &mut Scenario) {
        let (alice, _) = people();
        next_tx(test, alice);
        {
            rusd_stable_coin::init_for_testing(ctx(test));
            foo::init_for_testing(ctx(test));
        };
    }

    #[test]
    fun test_mint_happy_path() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_rusd_stable_coin(test);

        next_tx(test, admin);
        {
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let foo_storage = test::take_shared<FooStorage>(test);
            let admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);

            let publisher = foo::get_publisher(&foo_storage);
            let id = foo::get_publisher_id(&foo_storage);

            rusd_stable_coin::add_manager(&admin_cap, &mut rusd_stable_coin_storage, id);

            let coin = rusd_stable_coin::mint(
                &mut rusd_stable_coin_storage,
                publisher,
                admin,
                100,
                ctx(test)
            );
            assert_eq(burn<RUSD_STABLE_COIN>(coin), 100);

            let balance = rusd_stable_coin::get_balance(&rusd_stable_coin_storage, admin);
            assert_eq(balance, 100);

            test::return_shared(rusd_stable_coin_storage);
            test::return_shared(foo_storage);
            test::return_to_address(admin, admin_cap);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = rusd_stable_coin::ERROR_UNAUTHORIZED)]
    fun test_mint_unauthorized_module() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_rusd_stable_coin(test);

        next_tx(test, admin);
        {
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let foo_storage = test::take_shared<FooStorage>(test);

            let publisher = foo::get_publisher(&foo_storage);

            let coin = rusd_stable_coin::mint(
                &mut rusd_stable_coin_storage,
                publisher,
                admin,
                100,
                ctx(test)
            );
            assert_eq(burn<RUSD_STABLE_COIN>(coin), 100);

            test::return_shared(rusd_stable_coin_storage);
            test::return_shared(foo_storage);
        };
        test::end(scenario);
    }

    #[test]
    fun test_burn_happy_path() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_rusd_stable_coin(test);

        next_tx(test, admin);
        {
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let foo_storage = test::take_shared<FooStorage>(test);
            let admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);

            let publisher = foo::get_publisher(&foo_storage);
            let id = foo::get_publisher_id(&foo_storage);

            rusd_stable_coin::add_manager(&admin_cap, &mut rusd_stable_coin_storage, id);

            let coin = rusd_stable_coin::mint(
                &mut rusd_stable_coin_storage,
                publisher,
                admin,
                100,
                ctx(test)
            );
            assert_eq(rusd_stable_coin::get_supply(&rusd_stable_coin_storage), 100);

            rusd_stable_coin::burn(&mut rusd_stable_coin_storage, publisher, admin, coin);

            assert_eq(rusd_stable_coin::get_supply(&rusd_stable_coin_storage), 0);

            let balance = rusd_stable_coin::get_balance(&rusd_stable_coin_storage, admin);
            assert_eq(balance, 0);

            test::return_shared(rusd_stable_coin_storage);
            test::return_shared(foo_storage);
            test::return_to_address(admin, admin_cap);
        };
        test::end(scenario);
    }
}
