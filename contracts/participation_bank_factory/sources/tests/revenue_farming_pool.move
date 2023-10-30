#[test_only]
module participation_bank_factory::revenue_farming_pool_tests {
    use std::string;

    use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
    use sui::test_utils::{assert_eq};
    use sui::vec_map;
    use sui::coin::{Self, Coin};
    
    use participation_bank_factory::revenue_farming_pool::{
        Self, RevenueFarmingPoolAdminCap, RevenueFarmingPoolStorage,
        FarmingPoolStorage, RevenueFarmingPoolPublisher
    };
    use stable_coin_factory::test_helpers::{init_stable_coin_factory, open_kasa};
    use tokens::rusd_stable_coin::{Self, RUSDStableCoinStorage, RUSDStableCoinAdminCap, RUSD_STABLE_COIN};
    use library::test_utils::{people, scenario};

    fun setup_modules(test: &mut Scenario) {
        let (admin, _) = people();
        init_stable_coin_factory(test);
        next_tx(test, admin);
        {
            revenue_farming_pool::init_for_testing(test::ctx(test));
        };
        next_tx(test, admin);
        {
            let rfp_publisher = test::take_shared<RevenueFarmingPoolPublisher>(test);
            let rfp_publisher_id = revenue_farming_pool::get_publisher_id(&rfp_publisher);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let rsc_admin_cap = test::take_from_sender<RUSDStableCoinAdminCap>(test);
            rusd_stable_coin::add_manager(
                &rsc_admin_cap,
                &mut rsc_storage,
                rfp_publisher_id,
            );
            test::return_shared(rfp_publisher);
            test::return_shared(rsc_storage);
            test::return_to_sender(test, rsc_admin_cap);
        };
    }

    fun setup_farming_pool(test: &mut Scenario, account_address: address) {
        let (admin, _) = people();
        next_tx(test, admin);
        {
            let rfp_storage = test::take_shared<RevenueFarmingPoolStorage>(test);
            revenue_farming_pool::add_farming_pool_for_testing(
                &mut rfp_storage,
                account_address,
                test::ctx(test)
            );
            test::return_shared(rfp_storage);
        };
    }

    fun setup_pool_request(test: &mut Scenario, sender: address) {
        let (admin, _) = people();
        next_tx(test, sender);
        {
            let rfp_storage = test::take_shared<RevenueFarmingPoolStorage>(test);
            revenue_farming_pool::request_pool_for_testing(
                &mut rfp_storage,
                string::utf8(b"SME Name"),
                string::utf8(b"SME Description"),
                test::ctx(test)
            );
            test::return_shared(rfp_storage);
        };
    }

    fun setup_pool_approval(test: &mut Scenario, account_address: address, pool_id: u64) {
        let (admin, _) = people();
        next_tx(test, admin);
        {
            let rfp_storage = test::take_shared<RevenueFarmingPoolStorage>(test);
            revenue_farming_pool::approve_pool_request_for_testing(
                &mut rfp_storage,
                account_address,
                pool_id,
            );
            test::return_shared(rfp_storage);
        };
    }

    fun setup_deposit(test: &mut Scenario, pool_address: address, sender: address, amount: u64) {
        next_tx(test, sender);
        {
            let rfp_publisher = test::take_shared<RevenueFarmingPoolPublisher>(test);
            let rfp_storage = test::take_shared<RevenueFarmingPoolStorage>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let stable_coin = test::take_from_sender<Coin<RUSD_STABLE_COIN>>(test);
            let deposit_coin = coin::split(&mut stable_coin, amount, test::ctx(test));
            revenue_farming_pool::deposit_for_testing(
                &rfp_publisher,
                &mut rfp_storage,
                &mut rsc_storage,
                pool_address,
                1,
                deposit_coin,
                test::ctx(test)
            );
            test::return_shared(rfp_publisher);
            test::return_shared(rfp_storage);
            test::return_shared(rsc_storage);
            test::return_to_sender(test, stable_coin);
        };
    }

    #[test]
    fun test_add_farming_pool_happy_path() {
        let scenario = scenario();
        let test = &mut scenario;
        let (admin, user) = people();

        setup_modules(test);

        next_tx(test, admin);
        {
            let rfp_storage = test::take_shared<RevenueFarmingPoolStorage>(test);

            revenue_farming_pool::add_farming_pool_for_testing(
                &mut rfp_storage,
                user,
                test::ctx(test)
            );
            revenue_farming_pool::get_farming_pool(&rfp_storage, user);

            test::return_shared(rfp_storage);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = revenue_farming_pool::ERROR_FARMING_POOL_ALREADY_EXISTS)]
    fun test_add_farming_pool_farming_pool_already_exists() {
        let scenario = scenario();
        let test = &mut scenario;
        let (admin, user) = people();

        setup_modules(test);

        next_tx(test, admin);
        {
            let rfp_storage = test::take_shared<RevenueFarmingPoolStorage>(test);

            revenue_farming_pool::add_farming_pool_for_testing(
                &mut rfp_storage,
                user,
                test::ctx(test)
            );
            revenue_farming_pool::add_farming_pool_for_testing(
                &mut rfp_storage,
                user,
                test::ctx(test)
            );

            test::return_shared(rfp_storage);
        };
        test::end(scenario);
    }

    #[test]
    fun test_request_pool_happy_path() {
        let scenario = scenario();
        let test = &mut scenario;
        let (_, user) = people();

        setup_modules(test);

        setup_farming_pool(test, user);

        next_tx(test, user);
        {
            let rfp_storage = test::take_shared<RevenueFarmingPoolStorage>(test);

            let farming_pool = revenue_farming_pool::get_farming_pool(&rfp_storage, user);
            let pool_requests_size = revenue_farming_pool::get_pool_requests_size_for_testing(farming_pool);
            assert_eq(pool_requests_size, 0);

            revenue_farming_pool::request_pool_for_testing(
                &mut rfp_storage,
                string::utf8(b"SME Name"),
                string::utf8(b"SME Description"),
                test::ctx(test)
            );

            let farming_pool = revenue_farming_pool::get_farming_pool(&rfp_storage, user);
            let pool_requests_size = revenue_farming_pool::get_pool_requests_size_for_testing(farming_pool);
            assert_eq(pool_requests_size, 1);

            test::return_shared(rfp_storage);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = revenue_farming_pool::ERROR_FARMING_POOL_NOT_FOUND)]
    fun test_request_pool_farming_pool_not_found() {
        let scenario = scenario();
        let test = &mut scenario;
        let (_, user) = people();

        setup_modules(test);

        next_tx(test, user);
        {
            let rfp_storage = test::take_shared<RevenueFarmingPoolStorage>(test);
            revenue_farming_pool::request_pool_for_testing(
                &mut rfp_storage,
                string::utf8(b"SME Name"),
                string::utf8(b"SME Description"),
                test::ctx(test)
            );
            test::return_shared(rfp_storage);
        };
        test::end(scenario);
    }

    #[test]
    fun test_approve_pool_request_happy_path() {
        let scenario = scenario();
        let test = &mut scenario;
        let (admin, user) = people();

        setup_modules(test);

        setup_farming_pool(test, user);
        setup_pool_request(test, user);

        next_tx(test, admin);
        {
            let rfp_storage = test::take_shared<RevenueFarmingPoolStorage>(test);
            
            revenue_farming_pool::approve_pool_request_for_testing(
                &mut rfp_storage,
                user,
                1,
            );

            let farming_pool = revenue_farming_pool::get_farming_pool(&rfp_storage, user);
            let pool_requests_size = revenue_farming_pool::get_pool_requests_size_for_testing(farming_pool);
            assert_eq(pool_requests_size, 0);

            let active_pools_size = revenue_farming_pool::get_active_pools_size_for_testing(farming_pool);
            assert_eq(active_pools_size, 1);

            let (single_pool_name, single_pool_description) = revenue_farming_pool::get_single_pool_for_testing(farming_pool, 1);
            assert_eq(single_pool_name, string::utf8(b"SME Name"));
            assert_eq(single_pool_description, string::utf8(b"SME Description"));

            test::return_shared(rfp_storage);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = revenue_farming_pool::ERROR_FARMING_POOL_NOT_FOUND)]
    fun test_approve_pool_request_farming_pool_not_found() {
        let scenario = scenario();
        let test = &mut scenario;
        let (_, user) = people();

        setup_modules(test);

        next_tx(test, user);
        {
            let rfp_storage = test::take_shared<RevenueFarmingPoolStorage>(test);
            revenue_farming_pool::approve_pool_request_for_testing(
                &mut rfp_storage,
                user,
                1,
            );
            test::return_shared(rfp_storage);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = revenue_farming_pool::ERROR_POOL_REQUEST_NOT_FOUND)]
    fun test_approve_pool_request_pool_request_not_found() {
        let scenario = scenario();
        let test = &mut scenario;
        let (_, user) = people();

        setup_modules(test);
        
        setup_farming_pool(test, user);

        next_tx(test, user);
        {
            let rfp_storage = test::take_shared<RevenueFarmingPoolStorage>(test);
            revenue_farming_pool::approve_pool_request_for_testing(
                &mut rfp_storage,
                user,
                1,
            );
            test::return_shared(rfp_storage);
        };
        test::end(scenario);
    }

    #[test]
    fun test_deposit_happy_path() {
        let scenario = scenario();
        let test = &mut scenario;
        let (_, user) = people();
        let user2 = @0x2222;

        setup_modules(test);

        setup_farming_pool(test, user);
        setup_pool_request(test, user);
        setup_pool_approval(test, user, 1);

        next_tx(test, user2);
        {
            open_kasa(test, user2, 3_000000000, 1000_000000000);
        };
        next_tx(test, user2);
        {
            let rfp_publisher = test::take_shared<RevenueFarmingPoolPublisher>(test);
            let rfp_storage = test::take_shared<RevenueFarmingPoolStorage>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            
            let stable_coin = test::take_from_sender<Coin<RUSD_STABLE_COIN>>(test);
            let deposit_coin = coin::split(&mut stable_coin, 600_000000000, test::ctx(test));

            let coin_balance = rusd_stable_coin::get_balance(&rsc_storage, user2);
            assert_eq(coin_balance, 1000_000000000);

            revenue_farming_pool::deposit_for_testing(
                &rfp_publisher,
                &mut rfp_storage,
                &mut rsc_storage,
                user,
                1,
                deposit_coin,
                test::ctx(test)
            );

            let stake_amount = revenue_farming_pool::get_stake_amount(
                &rfp_storage,
                user,
                1,
                user2,
            );
            assert_eq(stake_amount, 600_000000000);

            let pool_balance = revenue_farming_pool::get_pool_stake_amount(
                &rfp_storage,
                user,
                1,
            );
            assert_eq(pool_balance, 600_000000000);

            let coin_balance = rusd_stable_coin::get_balance(&rsc_storage, user2);
            assert_eq(coin_balance, 400_000000000);

            test::return_shared(rfp_publisher);
            test::return_shared(rfp_storage);
            test::return_shared(rsc_storage);
            test::return_to_sender(test, stable_coin);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = revenue_farming_pool::ERROR_FARMING_POOL_NOT_FOUND)]
    fun test_deposit_farming_pool_not_found() {
        let scenario = scenario();
        let test = &mut scenario;
        let (_, user) = people();
        let user2 = @0x2222;

        setup_modules(test);

        next_tx(test, user2);
        {
            open_kasa(test, user2, 3_000000000, 1000_000000000);
        };
        next_tx(test, user2);
        {
            let rfp_publisher = test::take_shared<RevenueFarmingPoolPublisher>(test);
            let rfp_storage = test::take_shared<RevenueFarmingPoolStorage>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let stable_coin = test::take_from_sender<Coin<RUSD_STABLE_COIN>>(test);
            revenue_farming_pool::deposit_for_testing(
                &rfp_publisher,
                &mut rfp_storage,
                &mut rsc_storage,
                user,
                1,
                stable_coin,
                test::ctx(test)
            );
            test::return_shared(rfp_publisher);
            test::return_shared(rfp_storage);
            test::return_shared(rsc_storage);
        };
        test::end(scenario);
    }
}
