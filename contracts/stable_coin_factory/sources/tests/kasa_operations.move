#[test_only]
module stable_coin_factory::kasa_operations_tests {
    use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
    use sui::test_utils::{assert_eq};
    use sui::coin::{Self, mint_for_testing, burn_for_testing, Coin};
    use sui::sui::{SUI};

    use stable_coin_factory::kasa_storage::{Self, KasaManagerStorage};
    use stable_coin_factory::kasa_manager::{Self, KasaManagerPublisher};
    use stable_coin_factory::kasa_operations;
    use stable_coin_factory::sorted_kasas::{Self, SortedKasasStorage};
    use tokens::rusd_stable_coin::{Self, RUSDStableCoinStorage, RUSDStableCoinAdminCap, RUSD_STABLE_COIN};
    use library::test_utils::{people, scenario};
    use supra_holder:: SupraSValueFeed::{Self, OracleHolder};
 
    fun start_kasa_manager(test: &mut Scenario) {
        let (admin, _) = people();
        next_tx(test, admin);
        {
            kasa_storage::init_for_testing(ctx(test));
            kasa_manager::init_for_testing(ctx(test));
            rusd_stable_coin::init_for_testing(ctx(test));
            sorted_kasas::init_for_testing(ctx(test));
        };
        next_tx(test, admin);
        {
        SupraSValueFeed::create_oracle_holder_for_test(test::ctx(test));
        };
        next_tx(test, admin);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let rsc_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);
            let id = kasa_manager::get_publisher_id(&km_publisher);
            rusd_stable_coin::add_manager(
                &rsc_admin_cap,
                &mut rsc_storage,
                id
            );
            test::return_shared(km_publisher);
            test::return_shared(rsc_storage);
            test::return_to_address(admin, rsc_admin_cap);
        };
    }

    fun setup_open_kasa(test: &mut Scenario, collateral_amount: u64, debt_amount: u64) {
        let (admin, _) = people();
        let km_publisher = test::take_shared<KasaManagerPublisher>(test);
        let km_storage = test::take_shared<KasaManagerStorage>(test);
        let sk_storage = test::take_shared<SortedKasasStorage>(test);
        let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
        let rsc_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);
        let oracle_holder = test::take_shared<OracleHolder>(test);
        SupraSValueFeed::add_pair_data(
            &mut oracle_holder, 90, 1800_000000000000000000, 18, 1704693072240, 6489821);

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

        test::return_shared(km_publisher);
        test::return_shared(km_storage);
        test::return_shared(sk_storage);
        test::return_shared(rsc_storage);
        test::return_to_address(admin, rsc_admin_cap);
        test::return_shared(oracle_holder);
    }

    // =================== Open Kasa ===================

    #[test]
    fun test_open_kasa_happy_path() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let rsc_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);
            let oracle_holder = test::take_shared<OracleHolder>(test);
                SupraSValueFeed::add_pair_data(
            &mut oracle_holder, 90, 1800_000000000000000000, 18, 1704693072240, 6489821);

            let collateral = mint_for_testing<SUI>(1000_000000000, ctx(test));

            kasa_operations::open_kasa(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                &oracle_holder,
                collateral,
                5000_000000000,
                ctx(test)
            );

            let (kasa_collateral_amount, kasa_debt_amount) = kasa_storage::get_kasa_amounts(&mut km_storage, admin);
            assert_eq(kasa_collateral_amount, 1000_000000000);
            assert_eq(kasa_debt_amount, 5000_000000000);

            let (collateral_balance, debt_balance) = kasa_storage::get_total_balances(&km_storage);
            assert_eq(collateral_balance, 1000_000000000);
            assert_eq(debt_balance, 5000_000000000);

            test::return_shared(km_publisher);
            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(rsc_storage);
            test::return_to_address(admin, rsc_admin_cap);
            test::return_shared(oracle_holder);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_EXISTING_KASA)]
    fun test_open_kasa_existing_kasa() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 1000_000000000, 5000_000000000);
        };
        next_tx(test, admin);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let rsc_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);
            let oracle_holder = test::take_shared<OracleHolder>(test);
             SupraSValueFeed::add_pair_data(
                &mut oracle_holder, 90, 1800_000000000000000000, 18, 1704693072240, 6489821);

            let collateral = mint_for_testing<SUI>(1000_000000000, ctx(test));
            kasa_operations::open_kasa(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                &oracle_holder,
                collateral,
                5000_000000000,
                ctx(test)
            );

            test::return_shared(km_publisher);
            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(rsc_storage);
            test::return_to_address(admin, rsc_admin_cap);
            test::return_shared(oracle_holder);
            
        };
        test::end(scenario);
    }
    
    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_INVALID_COLLATERAL_AMOUNT)]
    fun test_open_kasa_zero_collateral() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 0, 5000_000000000);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_INVALID_DEBT_AMOUNT)]
    fun test_open_kasa_zero_debt_amount() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 1000_000000000, 0);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_LOW_COLLATERAL_RATIO)]
    fun test_open_kasa_low_collateral_ratio() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 1_000000000, 5000_000000000);
        };
        test::end(scenario);
    }

    // =================== Deposit Collateral ===================

    #[test]
    fun test_deposit_collateral_happy_path() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 1000_000000000, 5000_000000000);
        };
        next_tx(test, admin);
        {
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let rsc_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);

            let collateral = mint_for_testing<SUI>(800_000000000, ctx(test));
            kasa_operations::deposit_collateral(
                &mut km_storage,
                &mut sk_storage,
                collateral,
                ctx(test)
            );

            let (kasa_collateral_amount, kasa_debt_amount) = kasa_storage::get_kasa_amounts(&mut km_storage, admin);
            assert_eq(kasa_collateral_amount, 1800_000000000);
            assert_eq(kasa_debt_amount, 5000_000000000);

            let (collateral_balance, debt_balance) = kasa_storage::get_total_balances(&km_storage);
            assert_eq(collateral_balance, 1800_000000000);
            assert_eq(debt_balance, 5000_000000000);

            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(rsc_storage);
            test::return_to_address(admin, rsc_admin_cap);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_KASA_NOT_FOUND)]
    fun test_deposit_collateral_kasa_not_found() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 1000_000000000, 5000_000000000);
        };
        next_tx(test, @0x1234);
        {
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sorted_kasa_storage = test::take_shared<SortedKasasStorage>(test);
            let collateral = mint_for_testing<SUI>(800_000000000, ctx(test));
            kasa_operations::deposit_collateral(
                &mut km_storage,
                &mut sorted_kasa_storage,
                collateral,
                ctx(test)
            );
            test::return_shared(km_storage);
            test::return_shared(sorted_kasa_storage);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_INVALID_COLLATERAL_AMOUNT)]
    fun test_deposit_collateral_invalid_collateral_amount() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 1000_000000000, 5000_000000000);
        };
        next_tx(test, admin);
        {
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let rsc_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);

            let collateral = mint_for_testing<SUI>(0, ctx(test));
            kasa_operations::deposit_collateral(
                &mut km_storage,
                &mut sk_storage,
                collateral,
                ctx(test)
            );

            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(rsc_storage);
            test::return_to_address(admin, rsc_admin_cap);
        };
        test::end(scenario);
    }

    // =================== Withdraw Collateral ===================

    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_KASA_NOT_FOUND)]
    fun test_withdraw_collateral_kasa_not_found() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 1000_000000000, 5000_000000000);
        };
        next_tx(test, @0x1234);
        {
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let oracle_holder = test::take_shared<OracleHolder>(test);
                SupraSValueFeed::add_pair_data(
            &mut oracle_holder, 90, 1800_000000000000000000, 18, 1704693072240, 6489821);

            kasa_operations::withdraw_collateral(
                &mut km_storage,
                &mut sk_storage,
                &oracle_holder,
                500,
                ctx(test)
            );
            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(oracle_holder);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_INVALID_COLLATERAL_AMOUNT)]
    fun test_withdraw_collateral_invalid_collateral_amount() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 1000_000000000, 5000_000000000);
        };
        next_tx(test, admin);
        {
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let oracle_holder = test::take_shared<OracleHolder>(test);
                SupraSValueFeed::add_pair_data(
            &mut oracle_holder, 90, 1800_000000000000000000, 18, 1704693072240, 6489821);

            kasa_operations::withdraw_collateral(
                &mut km_storage,
                &mut sk_storage,
                &oracle_holder,
                0,
                ctx(test)
            );

            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(oracle_holder);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_LOW_COLLATERAL_RATIO)]
    fun test_withdraw_collateral_low_collateral_ratio() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 1000_000000000, 5000_000000000);
        };
        next_tx(test, admin);
        {
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let oracle_holder = test::take_shared<OracleHolder>(test);
                SupraSValueFeed::add_pair_data(
            &mut oracle_holder, 90, 1800_000000000000000000, 18, 1704693072240, 6489821);

            kasa_operations::withdraw_collateral(
                &mut km_storage,
                &mut sk_storage,
                &oracle_holder,
                999_000000000,
                ctx(test)
            );

            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(oracle_holder);
        };
        test::end(scenario);
    }

    // =================== Borrow Loan ===================

    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_KASA_NOT_FOUND)]
    fun test_borrow_loan_kasa_not_found() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 1000_000000000, 5000_000000000);
        };
        next_tx(test, @0x1234);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let oracle_holder = test::take_shared<OracleHolder>(test);
                SupraSValueFeed::add_pair_data(
            &mut oracle_holder, 90, 1800_000000000000000000, 18, 1704693072240, 6489821);

            kasa_operations::borrow_loan(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                &oracle_holder,
                500,
                ctx(test)
            );
            test::return_shared(km_publisher);
            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(rsc_storage);
            test::return_shared(oracle_holder);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_INVALID_DEBT_AMOUNT)]
    fun test_borrow_loan_invalid_debt_amount() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 1000_000000000, 5000_000000000);
        };
        next_tx(test, admin);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let oracle_holder = test::take_shared<OracleHolder>(test);
                SupraSValueFeed::add_pair_data(
            &mut oracle_holder, 90, 1800_000000000000000000, 18, 1704693072240, 6489821);

            kasa_operations::borrow_loan(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                &oracle_holder,
                0,
                ctx(test)
            );
            test::return_shared(km_publisher);
            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(rsc_storage);
            test::return_shared(oracle_holder);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_LOW_COLLATERAL_RATIO)]
    fun test_borrow_loan_low_collateral_ratio() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 1000_000000000, 5000_000000000);
        };
        next_tx(test, admin);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let oracle_holder = test::take_shared<OracleHolder>(test);
                SupraSValueFeed::add_pair_data(
            &mut oracle_holder, 90, 1800_000000000000000000, 18, 1704693072240, 6489821);

            kasa_operations::borrow_loan(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                &oracle_holder,
                2000000_000000000,
                ctx(test)
            );
            test::return_shared(km_publisher);
            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(rsc_storage);
            test::return_shared(oracle_holder);
        };
        test::end(scenario);
    }

    // =================== Repay Loan ===================

    #[test]
    fun test_repay_loan_happy_path() {
        let scenario = scenario();
        let (admin, user) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, user);
        {
            setup_open_kasa(test, 1000_000000000, 5000_000000000);
        };
        next_tx(test, @0x1234);
        {
            setup_open_kasa(test, 1000_000000000, 5000_000000000);
        };
        next_tx(test, user);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let stable_coin = test::take_from_sender<Coin<RUSD_STABLE_COIN>>(test);
            kasa_operations::repay_loan(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                stable_coin,
                ctx(test)
            );
            test::return_shared(km_publisher);
            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(rsc_storage);

        };
        next_tx(test, user);
        {
            let collateral = test::take_from_sender<Coin<SUI>>(test);
            assert_eq(coin::value(&collateral), 1000_000000000);
            test::return_to_sender(test, collateral);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_KASA_NOT_FOUND)]
    fun test_repay_loan_kasa_not_found() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 1000_000000000, 5000_000000000);
        };
        next_tx(test, @0x1234);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let coin = mint_for_testing<RUSD_STABLE_COIN>(500_000000000, ctx(test));
            kasa_operations::repay_loan(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                coin,
                ctx(test)
            );
            test::return_shared(km_publisher);
            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(rsc_storage);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_INVALID_DEBT_AMOUNT)]
    fun test_repay_loan_invalid_debt_amount() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            setup_open_kasa(test, 1000_000000000, 5000_000000000);
        };
        next_tx(test, admin);
        {
            let km_publisher = test::take_shared<KasaManagerPublisher>(test);
            let km_storage = test::take_shared<KasaManagerStorage>(test);
            let sk_storage = test::take_shared<SortedKasasStorage>(test);
            let rsc_storage = test::take_shared<RUSDStableCoinStorage>(test);

            let coin = mint_for_testing<RUSD_STABLE_COIN>(0, ctx(test));
            kasa_operations::repay_loan(
                &km_publisher,
                &mut km_storage,
                &mut sk_storage,
                &mut rsc_storage,
                coin,
                ctx(test)
            );

            test::return_shared(km_publisher);
            test::return_shared(km_storage);
            test::return_shared(sk_storage);
            test::return_shared(rsc_storage);
        };
        test::end(scenario);
    }
}
