#[test_only]
module stable_coin_factory::sorted_kasas_tests {
    use std::option::{Self, Option};
    
    use sui::test_scenario::{Self as test, next_tx};
    use sui::test_utils::{assert_eq};

    use stable_coin_factory::test_helpers::{init_stable_coin_factory, open_kasa};
    use stable_coin_factory::sorted_kasas::{Self, SortedKasasStorage};
    use library::test_utils::{people, scenario};
    use supra_holder:: SupraSValueFeed :: {Self, OracleHolder};
    // use library::utils::logger;

    #[test]
    fun test_open_multiple_kasas() {
        let scenario = scenario();
        let (admin, user) = people();
        let user_2 = @0x2222;
        let user_3 = @0x3333;
        let user_4 = @0x4444;
        let user_5 = @0x5555;
        let test = &mut scenario;

        init_stable_coin_factory(test);

        next_tx(test, admin);
        {
            SupraSValueFeed::create_oracle_holder_for_test(test::ctx(test));
        };

        next_tx(test, admin);
        {   
            open_kasa(test, user, 3_000000000, 1000_000000000);
        };
        next_tx(test, admin);
        {   
            open_kasa(test, user_2, 4_000000000, 1000_000000000);
        };
        next_tx(test, admin);
        {   
            open_kasa(test, user_3, 2_000000000, 1000_000000000);
        };
        next_tx(test, admin);
        {   
            open_kasa(test, user_4, 3_500000000, 1000_000000000);
        };
        next_tx(test, admin);
        {   
            open_kasa(test, user_5, 2_500000000, 1000_000000000);
        };
        next_tx(test, admin);
        {
            let sorted_kasas_storage = test::take_shared<SortedKasasStorage>(test);

            let list_size = sorted_kasas::get_size(&sorted_kasas_storage);
            assert_eq(list_size, 5);

            let first_kasa: Option<address> = sorted_kasas::get_first(&sorted_kasas_storage);
            assert_eq(option::is_some(&first_kasa), true);
            assert_eq(option::destroy_some(first_kasa), user_2);

            let second_kasa = sorted_kasas::get_next(&sorted_kasas_storage, option::destroy_some(first_kasa));
            assert_eq(option::is_some(&second_kasa), true);
            assert_eq(option::destroy_some(second_kasa), user_4);

            let third_kasa = sorted_kasas::get_next(&sorted_kasas_storage, option::destroy_some(second_kasa));
            assert_eq(option::is_some(&third_kasa), true);
            assert_eq(option::destroy_some(third_kasa), user);

            let fifth_kasa = sorted_kasas::get_last(&sorted_kasas_storage);
            assert_eq(option::is_some(&fifth_kasa), true);
            assert_eq(option::destroy_some(fifth_kasa), user_3);

            let fourth_kasa: Option<address> = sorted_kasas::get_prev(&sorted_kasas_storage, option::destroy_some(fifth_kasa));
            assert_eq(option::is_some(&fourth_kasa), true);
            assert_eq(option::destroy_some(fourth_kasa), user_5);

            test::return_shared(sorted_kasas_storage);
        };
        test::end(scenario);
    }
}
