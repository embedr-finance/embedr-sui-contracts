module registry::registry {
    use std::vector;
    
    use sui::object::{Self, UID, ID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::table::{Self, Table};

    // =================== @Errors ===================

    const ERROR_INVALID_KEY_VALUE_LENGTH: u64 = 1;

    // =================== @Storage ===================

    struct RegistryAdminCap has key { id: UID }

    struct RegistryStorage has key {
        id: UID,
        // stable_coin_factory: StableCoinFactory,
        // participation_bank_factory: ParticipationBankFactory,
        // tokens: Tokens,
        registry_table: Table<vector<u8>, ID>
    }
    
    // =================== @Initializer ===================

    fun init(ctx: &mut TxContext) {
        // let stable_coin_factory = get_stable_coin_factory_objects();
        // let participation_bank_factory = get_participation_bank_factory_objects();
        // let tokens = get_tokens_objects();
        transfer::share_object(RegistryStorage {
            id: object::new(ctx),
            // stable_coin_factory: stable_coin_factory,
            // participation_bank_factory: participation_bank_factory,
            // tokens: tokens,
            registry_table: table::new(ctx),
        });
        transfer::transfer(
            RegistryAdminCap { id: object::new(ctx) },
            tx_context::sender(ctx)
        )
    }

    // =================== @Entry Methods ===================

    entry fun register(
        _: &RegistryAdminCap,
        storage: &mut RegistryStorage,
        keys: vector<vector<u8>>,
        values: vector<ID>,
    ) {
        register_(storage, keys, values)
    }

    // =================== @Helpers  ===================

    fun register_(
        storage: &mut RegistryStorage,
        keys: vector<vector<u8>>,
        values: vector<ID>,
    ) {
        assert!(vector::length(&keys) == vector::length(&values), ERROR_INVALID_KEY_VALUE_LENGTH);
        while (!vector::is_empty(&keys)) {
            let key = vector::pop_back(&mut keys);
            let value = vector::pop_back(&mut values);
            table::add(&mut storage.registry_table, key, value);
        }
    }

    #[test_only]
    public fun register_for_testing(
        storage: &mut RegistryStorage,
        keys: vector<vector<u8>>,
        values: vector<ID>,
    ) {
        register_(storage, keys, values)
    }

    #[test_only]
    public fun read_registry_table(storage: &RegistryStorage, key: vector<u8>): &ID {
        table::borrow(&storage.registry_table, key)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}
