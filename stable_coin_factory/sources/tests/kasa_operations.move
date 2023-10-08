#[test_only]
module stable_coin_factory::kasa_operations_tests {
    use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
    use sui::test_utils::{assert_eq};
    use sui::coin::{mint_for_testing};
    use sui::sui::{SUI};

    use stable_coin_factory::kasa_manager::{Self, KasaManagerStorage};
    use stable_coin_factory::kasa_operations;
    use stable_coin_factory::sorted_kasas::{Self, SortedKasasStorage};
    use tokens::rusd_stable_coin::{Self, RUSDStableCoinStorage, RUSDStableCoinAdminCap, RUSD_STABLE_COIN};
    use library::test_utils::{people, scenario};

    fun start_kasa_manager(test: &mut Scenario) {
        let (admin, _) = people();
        next_tx(test, admin);
        {
            kasa_manager::init_for_testing(ctx(test));
            rusd_stable_coin::init_for_testing(ctx(test));
            sorted_kasas::init_for_testing(ctx(test));
        };
    }

    fun setup_open_kasa(test: &mut Scenario, collateral_amount: u64, debt_amount: u64) {
        let (admin, _) = people();
        let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
        let sorted_kasas_storage = test::take_shared<SortedKasasStorage>(test);
        let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);
        let rusd_stable_coin_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);

        let collateral = mint_for_testing<SUI>(collateral_amount, ctx(test));

        let id = kasa_manager::get_publisher_id(&kasa_manager_storage);
        rusd_stable_coin::add_manager(
            &rusd_stable_coin_admin_cap,
            &mut rusd_stable_coin_storage,
            id
        );

        kasa_operations::open_kasa(
            &mut kasa_manager_storage,
            &mut sorted_kasas_storage,
            &mut rusd_stable_coin_storage,
            collateral,
            debt_amount,
            ctx(test)
        );

        test::return_shared(kasa_manager_storage);
        test::return_shared(sorted_kasas_storage);
        test::return_shared(rusd_stable_coin_storage);
        test::return_to_address(admin, rusd_stable_coin_admin_cap);
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
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let sorted_kasas_storage = test::take_shared<SortedKasasStorage>(test);
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let rusd_stable_coin_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);

            let collateral = mint_for_testing<SUI>(1000_000000000, ctx(test));

            let id = kasa_manager::get_publisher_id(&kasa_manager_storage);
            rusd_stable_coin::add_manager(
                &rusd_stable_coin_admin_cap,
                &mut rusd_stable_coin_storage,
                id
            );

            kasa_operations::open_kasa(
                &mut kasa_manager_storage,
                &mut sorted_kasas_storage,
                &mut rusd_stable_coin_storage,
                collateral,
                5000_000000000,
                ctx(test)
            );

            let (kasa_collateral_amount, kasa_debt_amount) = kasa_operations::display_kasa(&mut kasa_manager_storage, ctx(test));
            assert_eq(kasa_collateral_amount, 1000_000000000);
            assert_eq(kasa_debt_amount, 5000_000000000);

            let (collateral_balance, debt_balance) = kasa_manager::get_protocol_balances(&kasa_manager_storage);
            assert_eq(collateral_balance, 1000_000000000);
            assert_eq(debt_balance, 5000_000000000);

            test::return_shared(kasa_manager_storage);
            test::return_shared(sorted_kasas_storage);
            test::return_shared(rusd_stable_coin_storage);
            test::return_to_address(admin, rusd_stable_coin_admin_cap);
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
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let sorted_kasas_storage = test::take_shared<SortedKasasStorage>(test);
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let rusd_stable_coin_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);

            let collateral = mint_for_testing<SUI>(1000_000000000, ctx(test));
            kasa_operations::open_kasa(
                &mut kasa_manager_storage,
                &mut sorted_kasas_storage,
                &mut rusd_stable_coin_storage,
                collateral,
                5000_000000000,
                ctx(test)
            );

            test::return_shared(kasa_manager_storage);
            test::return_shared(sorted_kasas_storage);
            test::return_shared(rusd_stable_coin_storage);
            test::return_to_address(admin, rusd_stable_coin_admin_cap);
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
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let rusd_stable_coin_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);

            let collateral = mint_for_testing<SUI>(800_000000000, ctx(test));
            kasa_operations::deposit_collateral(
                &mut kasa_manager_storage,
                collateral,
                ctx(test)
            );

            let (kasa_collateral_amount, kasa_debt_amount) = kasa_operations::display_kasa(&mut kasa_manager_storage, ctx(test));
            assert_eq(kasa_collateral_amount, 1800_000000000);
            assert_eq(kasa_debt_amount, 5000_000000000);

            let (collateral_balance, debt_balance) = kasa_manager::get_protocol_balances(&kasa_manager_storage);
            assert_eq(collateral_balance, 1800_000000000);
            assert_eq(debt_balance, 5000_000000000);

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
            test::return_to_address(admin, rusd_stable_coin_admin_cap);
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
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let collateral = mint_for_testing<SUI>(800_000000000, ctx(test));
            kasa_operations::deposit_collateral(
                &mut kasa_manager_storage,
                collateral,
                ctx(test)
            );
            test::return_shared(kasa_manager_storage);
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
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let rusd_stable_coin_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);

            let collateral = mint_for_testing<SUI>(0, ctx(test));
            kasa_operations::deposit_collateral(
                &mut kasa_manager_storage,
                collateral,
                ctx(test)
            );

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
            test::return_to_address(admin, rusd_stable_coin_admin_cap);
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
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            kasa_operations::withdraw_collateral(
                &mut kasa_manager_storage,
                500,
                ctx(test)
            );
            test::return_shared(kasa_manager_storage);
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
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);

            kasa_operations::withdraw_collateral(
                &mut kasa_manager_storage,
                0,
                ctx(test)
            );

            test::return_shared(kasa_manager_storage);
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
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);

            kasa_operations::withdraw_collateral(
                &mut kasa_manager_storage,
                999_000000000,
                ctx(test)
            );

            test::return_shared(kasa_manager_storage);
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
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);
            kasa_operations::borrow_loan(
                &mut kasa_manager_storage,
                &mut rusd_stable_coin_storage,
                500,
                ctx(test)
            );
            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
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
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);

            kasa_operations::borrow_loan(
                &mut kasa_manager_storage,
                &mut rusd_stable_coin_storage,
                0,
                ctx(test)
            );

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
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
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);

            kasa_operations::borrow_loan(
                &mut kasa_manager_storage,
                &mut rusd_stable_coin_storage,
                2000000_000000000,
                ctx(test)
            );

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
        };
        test::end(scenario);
    }

    // =================== Repay Loan ===================

    // TODO: Add happy path test

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
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let coin = mint_for_testing<RUSD_STABLE_COIN>(500_000000000, ctx(test));
            kasa_operations::repay_loan(
                &mut kasa_manager_storage,
                &mut rusd_stable_coin_storage,
                coin,
                ctx(test)
            );
            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
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
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);

            let coin = mint_for_testing<RUSD_STABLE_COIN>(0, ctx(test));
            kasa_operations::repay_loan(
                &mut kasa_manager_storage,
                &mut rusd_stable_coin_storage,
                coin,
                ctx(test)
            );

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
        };
        test::end(scenario);
    }
}
