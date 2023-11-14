#[test_only]
module registry::registry_tests {
    use std::vector;
    use std::string::{Self, String};

    use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
    use sui::test_utils::{assert_eq};
    use sui::object::{Self, ID};
    use sui::address;

    use registry::registry::{Self, RegistryAdminCap, RegistryStorage};

    public fun scenario(): Scenario { test::begin(@0x1) }

    fun setup_module(test: &mut Scenario) {
        let admin = @0xbeef;
        next_tx(test, admin);
        {
            registry::init_for_testing(ctx(test));
        };
    }

    #[test]
    fun test_registry_happy_path() {
        let scenario = scenario();
        let test = &mut scenario;
        let admin = @0xbeef;
        
        setup_module(test);

        let keys = vector::empty<String>();
        let values = vector::empty<ID>();

        let (key_1, value_1) = (
            string::utf8(b"some_package_id:some_module_id:key_1"),
            object::id_from_address(address::from_u256(10))
        );
        let (key_2, value_2) = (
            string::utf8(b"some_package_id:some_module_id:key_2"),
            object::id_from_address(address::from_u256(20))
        );
        let (key_3, value_3) = (
            string::utf8(b"some_package_id:some_module_id:key_3"),
            object::id_from_address(address::from_u256(30))
        );

        vector::push_back(&mut keys, key_1);
        vector::push_back(&mut values, value_1);

        vector::push_back(&mut keys, key_2);
        vector::push_back(&mut values, value_2);

        vector::push_back(&mut keys, key_3);
        vector::push_back(&mut values, value_3);

        next_tx(test, admin);
        {
            let registry_storage = test::take_shared<RegistryStorage>(test);
            let registry_admin_cap = test::take_from_sender<RegistryAdminCap>(test);

            registry::register_for_testing(
                &mut registry_storage,
                keys,
                values
            );

            let res = registry::read_registry_table(&registry_storage, key_1);
            assert_eq(*res, value_1);

            let res = registry::read_registry_table(&registry_storage, key_2);
            assert_eq(*res, value_2);

            let res = registry::read_registry_table(&registry_storage, key_3);
            assert_eq(*res, value_3);

            test::return_shared(registry_storage);
            test::return_to_sender(test, registry_admin_cap);
        };
        test::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = registry::registry::ERROR_INVALID_KEY_VALUE_LENGTH)]
    fun test_registry_invalid_key_value_length() {
        let scenario = scenario();
        let test = &mut scenario;
        let admin = @0xbeef;
        
        setup_module(test);

        let keys = vector::empty<String>();
        let values = vector::empty<ID>();

        let (key_1, value_1) = (
            string::utf8(b"some_package_id:some_module_id:key_1"),
            object::id_from_address(address::from_u256(10))
        );
        vector::push_back(&mut keys, key_1);
        vector::push_back(&mut keys, key_1);
        vector::push_back(&mut values, value_1);

        next_tx(test, admin);
        {
            let registry_storage = test::take_shared<RegistryStorage>(test);
            let registry_admin_cap = test::take_from_sender<RegistryAdminCap>(test);
            registry::register_for_testing(
                &mut registry_storage,
                keys,
                values
            );
            test::return_shared(registry_storage);
            test::return_to_sender(test, registry_admin_cap);
        };
        test::end(scenario);
    }
}
