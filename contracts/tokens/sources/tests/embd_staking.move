#[test_only]
module tokens::embd_staking_tests {
    use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
    use sui::test_utils::{assert_eq};
    
    use tokens::embd_staking::{Self, EMBD_STAKING, EMBDStakingPublisher, EMBDStakingStorage};
    use tokens::embd_incentive_token::{
        Self, EMBD_INCENTIVE_TOKEN,
        EMBDIncentiveTokenAdminCap, EMBDIncentiveTokenStorage
    };
    use library::test_utils::{people, scenario};

    fun setup_embd_token_module(test: &mut Scenario) {
        let (admin, _) = people();
        next_tx(test, admin);
        {
            embd_incentive_token::init_for_testing(test::ctx(test));
        };
    }

    fun setup_staking_module(test: &mut Scenario) {
        let (admin, _) = people();
        next_tx(test, admin);
        {
            embd_staking::init_for_testing(test::ctx(test));
        };
        next_tx(test, admin);
        {
            let es_publisher = test::take_shared<EMBDStakingPublisher>(test);
            let eit_storage = test::take_shared<EMBDIncentiveTokenStorage>(test);
            let eit_admin_cap = test::take_from_sender<EMBDIncentiveTokenAdminCap>(test);
            embd_incentive_token::add_manager(
                &eit_admin_cap,
                &mut eit_storage,
                embd_staking::get_publisher_id(&es_publisher)
            );
            test::return_shared(es_publisher);
            test::return_shared(eit_storage);
            test::return_to_sender(test, eit_admin_cap);
        };
    }

    fun setup_test(test: &mut Scenario) {
        setup_embd_token_module(test);
        setup_staking_module(test);
    }

    fun mint_and_stake(test: &mut Scenario, sender: address, amount: u64) {
        next_tx(test, sender);
        {
            let es_publisher = test::take_shared<EMBDStakingPublisher>(test);
            let es_storage = test::take_shared<EMBDStakingStorage>(test);
            let eit_storage = test::take_shared<EMBDIncentiveTokenStorage>(test);
            let embd_token = embd_incentive_token::mint(
                embd_staking::get_publisher(&es_publisher),
                &mut eit_storage,
                sender,
                amount,
                test::ctx(test)
            );
            embd_staking::deposit_for_testing(
                &es_publisher,
                &mut es_storage,
                &mut eit_storage,
                embd_token,
                test::ctx(test)
            );
            test::return_shared(es_publisher);
            test::return_shared(es_storage);
            test::return_shared(eit_storage);
        };
    }

    #[test]
    fun test_deposit_happy_path() {
        let scenario = scenario();
        let test = &mut scenario;
        let (admin, user) = people();
        let user2 = @0x2222;
        
        setup_test(test);

        next_tx(test, user);
        {
            let es_publisher = test::take_shared<EMBDStakingPublisher>(test);
            let es_storage = test::take_shared<EMBDStakingStorage>(test);
            let eit_storage = test::take_shared<EMBDIncentiveTokenStorage>(test);
            
            let embd_token = embd_incentive_token::mint(
                embd_staking::get_publisher(&es_publisher),
                &mut eit_storage,
                user,
                1000,
                test::ctx(test)
            );
            embd_staking::deposit_for_testing(
                &es_publisher,
                &mut es_storage,
                &mut eit_storage,
                embd_token,
                test::ctx(test)
            );

            let stake_amount = embd_staking::get_stake_amount(&es_storage, user);
            assert_eq(stake_amount, 1000);

            let total_stake_amount = embd_staking::get_total_stake_amount(&es_storage);
            assert_eq(total_stake_amount, 1000);

            test::return_shared(es_publisher);
            test::return_shared(es_storage);
            test::return_shared(eit_storage);
        };

        mint_and_stake(test, user2, 500);

        next_tx(test, user2);
        {
            let es_storage = test::take_shared<EMBDStakingStorage>(test);

            let stake_amount = embd_staking::get_stake_amount(&es_storage, user2);
            assert_eq(stake_amount, 500);

            let total_stake_amount = embd_staking::get_total_stake_amount(&es_storage);
            assert_eq(total_stake_amount, 1500);

            test::return_shared(es_storage);
        };
        test::end(scenario);
    }

    #[test]
    fun test_withdraw_happy_path() {
        let scenario = scenario();
        let test = &mut scenario;
        let (admin, user) = people();
        
        setup_test(test);

        mint_and_stake(test, user, 1500);

        next_tx(test, user);
        {
            let es_publisher = test::take_shared<EMBDStakingPublisher>(test);
            let es_storage = test::take_shared<EMBDStakingStorage>(test);
            let eit_storage = test::take_shared<EMBDIncentiveTokenStorage>(test);

            embd_staking::withdraw_for_testing(
                &es_publisher,
                &mut es_storage,
                &mut eit_storage,
                1000,
                test::ctx(test)
            );

            let stake_amount = embd_staking::get_stake_amount(&es_storage, user);
            assert_eq(stake_amount, 500);

            let total_stake_amount = embd_staking::get_total_stake_amount(&es_storage);
            assert_eq(total_stake_amount, 500);

            embd_staking::withdraw_for_testing(
                &es_publisher,
                &mut es_storage,
                &mut eit_storage,
                500,
                test::ctx(test)
            );

            let stake_amount = embd_staking::get_stake_amount(&es_storage, user);
            assert_eq(stake_amount, 0);

            let total_stake_amount = embd_staking::get_total_stake_amount(&es_storage);
            assert_eq(total_stake_amount, 0);

            test::return_shared(es_publisher);
            test::return_shared(es_storage);
            test::return_shared(eit_storage);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = embd_staking::ERROR_STAKE_NOT_FOUND)]
    fun test_withdraw_stake_not_found() {
        let scenario = scenario();
        let test = &mut scenario;
        let (admin, user) = people();
        
        setup_test(test);

        next_tx(test, user);
        {
            let es_publisher = test::take_shared<EMBDStakingPublisher>(test);
            let es_storage = test::take_shared<EMBDStakingStorage>(test);
            let eit_storage = test::take_shared<EMBDIncentiveTokenStorage>(test);
            embd_staking::withdraw_for_testing(
                &es_publisher,
                &mut es_storage,
                &mut eit_storage,
                1000,
                test::ctx(test)
            );
            test::return_shared(es_publisher);
            test::return_shared(es_storage);
            test::return_shared(eit_storage);
        };
        test::end(scenario);
    }
}