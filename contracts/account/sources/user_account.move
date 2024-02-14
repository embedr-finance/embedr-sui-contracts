module account::user_account {
    use std::ascii::String;
    use std::option::Option;

    use sui::coin::{Self, Coin};

    use registry::registry::{Self, RegistryStorage};
    // use stable_coin_factory::kasa_operations;
    use participation_bank_factory::pool_manager;

    entry fun call_function(
        // Registry object that has information about protocol objects
        registry: &mut RegistryStorage,
        // Name of the function to call
        function_name: String,
        // BCS bytes that will be sent to the function
        input_bytes: Option<vector<u8>>
    ) {
        // TODO: Check if user has an account
        // TODO: Check if target package is authorized
        // TODO: Check if target function is authorized

        // let (
        //     OPEN_KASA,
        //     DEPOSIT_COLLATERAL,
        //     WITHDRAW_COLLATERAL,
        //     BORROW_LOAN,
        //     REPAY_LOAN,
        //     REDEEM
        // ) = registry::get_user_functions();

        // if function_name == OPEN_KASA {

    }

    fun call_deposit_to_pool<T>(
        registry: &mut RegistryStorage,
        input_bytes: vector<u8>,
        // oracle object here
        coin: Coin<T>
    ) {
    //    pool_manager::deposi 
    }

}