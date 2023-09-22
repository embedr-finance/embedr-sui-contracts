#[test_only]
module stable_coin_factory::test_helpers {
    use sui::test_scenario::{Self as test, next_tx, Scenario, ctx};
    use sui::coin::{mint_for_testing};
    use sui::sui::{SUI};

    use stable_coin_factory::kasa_manager::{Self, KasaManagerStorage};
    use stable_coin_factory::kasa_operations;
    use stable_coin_factory::stability_pool;
    use tokens::rusd_stable_coin::{Self, RUSDStableCoinStorage, RUSDStableCoinAdminCap};
    use library::test_utils::{people};

    public fun init_stable_coin_factory(test: &mut Scenario) {
        let (admin, _) = people();
        next_tx(test, admin);
        {
            kasa_manager::init_for_testing(ctx(test));
            stability_pool::init_for_testing(ctx(test));
            rusd_stable_coin::init_for_testing(ctx(test));
        };
    }

    public fun open_kasa(test: &mut Scenario, account_address: address, collateral_amount: u64, debt_amount: u64) {
        let (admin, _) = people();
        
        let kasa_manager_storage = test::take_shared<KasaManagerStorage>(test);
        let rusd_stable_coin_storage = test::take_shared<RUSDStableCoinStorage>(test);
        let rusd_stable_coin_admin_cap = test::take_from_address<RUSDStableCoinAdminCap>(test, admin);
        
        next_tx(test, admin);
        {
            let id = kasa_manager::get_publisher_id(&kasa_manager_storage);
            rusd_stable_coin::add_manager(
                &rusd_stable_coin_admin_cap,
                &mut rusd_stable_coin_storage,
                id
            );
        };

        next_tx(test, account_address);
        {
            let collateral = mint_for_testing<SUI>(collateral_amount, ctx(test));
            kasa_operations::open_kasa(
                &mut kasa_manager_storage,
                &mut rusd_stable_coin_storage,
                collateral,
                debt_amount,
                ctx(test)
            );
        };

        test::return_shared(kasa_manager_storage);
        test::return_shared(rusd_stable_coin_storage);
        test::return_to_address(admin, rusd_stable_coin_admin_cap);
    }
}