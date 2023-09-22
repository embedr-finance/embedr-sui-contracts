#[test_only]
module stable_coin_factory::kasa_operations_tests {
    use std::debug;

    use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
    use sui::test_utils::{assert_eq};
    use sui::coin::{burn_for_testing, mint_for_testing, Coin};
    use sui::sui::{SUI};
    use sui::balance;

    use stable_coin_factory::kasa_manager::{Self, KasaManagerStorage};
    use stable_coin_factory::kasa_operations;
    use tokens::rusd_stable_coin::{Self, RUSDStableCoinStorage, RUSDStableCoinAdminCap, RUSD_STABLE_COIN};
    use library::test_utils::{people, scenario};
    use library::foo::{Self, FooStorage};

    fun start_kasa_manager(test: &mut Scenario) {
        let (admin, _) = people();
        next_tx(test, admin);
        {
            kasa_manager::init_for_testing(ctx(test));
            rusd_stable_coin::init_for_testing(ctx(test));
        };

        next_tx(test, admin);
        {
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let rusd_stable_coin_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);

            let id = kasa_manager::get_publisher_id(&kasa_manager_storage);
            rusd_stable_coin::add_manager(
                &rusd_stable_coin_admin_cap,
                &mut rusd_stable_coin_storage,
                id
            );

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
            test::return_to_address(admin, rusd_stable_coin_admin_cap);
        };
    }

    fun setup_open_kasa(test: &mut Scenario, collateral_amount: u64, debt_amount: u64): (KasaManagerStorage, RUSDStableCoinStorage) {
        let (admin, _) = people();
        let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
        let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);

        let collateral = mint_for_testing<SUI>(collateral_amount, ctx(test));

        kasa_operations::open_kasa(
            &mut kasa_manager_storage,
            &mut rusd_stable_coin_storage,
            collateral,
            debt_amount,
            ctx(test)
        );

        (kasa_manager_storage, rusd_stable_coin_storage)
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
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);

            let collateral = mint_for_testing<SUI>(1000, ctx(test));

            kasa_operations::open_kasa(
                &mut kasa_manager_storage,
                &mut rusd_stable_coin_storage,
                collateral,
                5000,
                ctx(test)
            );

            let (kasa_collateral_amount, kasa_debt_amount) = kasa_operations::display_kasa(&mut kasa_manager_storage, ctx(test));
            assert_eq(kasa_collateral_amount, 1000);
            assert_eq(kasa_debt_amount, 5000);

            let (collateral_balance, debt_balance) = kasa_manager::get_protocol_balances(&kasa_manager_storage);
            assert_eq(collateral_balance, 1000);
            assert_eq(debt_balance, 5000);

            let (collateral_percentage, debt_percentage) = kasa_manager::get_kasa_asset_percentages(&mut kasa_manager_storage, admin);
            assert_eq(collateral_percentage, 100000000000000000000);
            assert_eq(debt_percentage, 100000000000000000000);

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
        };
        test::end(scenario);
    }

    #[test]
    fun test_open_multiple_kasa_happy_path() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 5000);

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
        };
        
        next_tx(test, @0x1234);
        {
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 5000);

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
        };

        next_tx(test, @0x2345);
        {
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);

            let (collateral_percentage, debt_percentage) = kasa_manager::get_kasa_asset_percentages(&mut kasa_manager_storage, admin);
            assert_eq(collateral_percentage, 50000000000000000000);
            assert_eq(debt_percentage, 50000000000000000000);

            let (collateral_percentage, debt_percentage) = kasa_manager::get_kasa_asset_percentages(&mut kasa_manager_storage, @0x1234);
            assert_eq(collateral_percentage, 50000000000000000000);
            assert_eq(debt_percentage, 50000000000000000000);

            test::return_shared(kasa_manager_storage);
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
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 5000);

            let collateral = mint_for_testing<SUI>(1000, ctx(test));
            kasa_operations::open_kasa(
                &mut kasa_manager_storage,
                &mut rusd_stable_coin_storage,
                collateral,
                5000,
                ctx(test)
            );

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
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
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 0, 5000);

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
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
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 0);

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
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
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1, 5000);

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
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
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 5000);

            let collateral = mint_for_testing<SUI>(800, ctx(test));
            kasa_operations::deposit_collateral(
                &mut kasa_manager_storage,
                collateral,
                ctx(test)
            );

            let (kasa_collateral_amount, kasa_debt_amount) = kasa_operations::display_kasa(&mut kasa_manager_storage, ctx(test));
            assert_eq(kasa_collateral_amount, 1800);
            assert_eq(kasa_debt_amount, 5000);

            let (collateral_balance, debt_balance) = kasa_manager::get_protocol_balances(&kasa_manager_storage);
            assert_eq(collateral_balance, 1800);
            assert_eq(debt_balance, 5000);

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
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
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 5000);

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
        };

        next_tx(test, @0x1234);
        {
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let collateral = mint_for_testing<SUI>(800, ctx(test));
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
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 5000);

            let collateral = mint_for_testing<SUI>(0, ctx(test));
            kasa_operations::deposit_collateral(
                &mut kasa_manager_storage,
                collateral,
                ctx(test)
            );

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
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
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 5000);

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
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
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 5000);

            kasa_operations::withdraw_collateral(
                &mut kasa_manager_storage,
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
    fun test_withdraw_collateral_low_collateral_ratio() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 5000);

            kasa_operations::withdraw_collateral(
                &mut kasa_manager_storage,
                999,
                ctx(test)
            );

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
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
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 5000);

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
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
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 5000);

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
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 5000);

            kasa_operations::borrow_loan(
                &mut kasa_manager_storage,
                &mut rusd_stable_coin_storage,
                2000000,
                ctx(test)
            );

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
        };
        test::end(scenario);
    }

    // =================== Repay Loan ===================

    #[test]
    #[expected_failure(abort_code = kasa_operations::ERROR_KASA_NOT_FOUND)]
    fun test_repay_loan_kasa_not_found() {
        let scenario = scenario();
        let (admin, _) = people();
        let test = &mut scenario;

        start_kasa_manager(test);

        next_tx(test, admin);
        {
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 5000);

            test::return_shared(kasa_manager_storage);
            test::return_shared(rusd_stable_coin_storage);
        };

        next_tx(test, @0x1234);
        {
            let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
            let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);
            let coin = mint_for_testing<RUSD_STABLE_COIN>(500, ctx(test));
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
            let (
                kasa_manager_storage,
                rusd_stable_coin_storage
            ) = setup_open_kasa(test, 1000, 5000);

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
