module participation_bank_factory::participation_bank_factory {
    // ========== IMPORTS ==========
    use std::ascii::{Self, String};

    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::dynamic_object_field as dof;

    use registry::registry;

    // ========== CONSTANTS ==========

    const PARTICIPATION_BANK_FACTORY_STORAGE_KEY: vector<u8> = b"participation_bank_factory";

    // ========== STRUCTS ==========

    struct ParticipationBankFactoryStorage has key, store {
        id: UID
    }

    // ========== FUNCTIONS ==========

    fun init(ctx: &mut TxContext) {
        let pbf_storage = ParticipationBankFactoryStorage {
            id: object::new(ctx)
        };
        let wrapper = registry::create_storage_wrapper<ParticipationBankFactoryStorage>(
            ascii::string(PARTICIPATION_BANK_FACTORY_STORAGE_KEY),
            pbf_storage,
            ctx
        );
        transfer::public_transfer(wrapper, tx_context::sender(ctx));
    }

    fun register_storage_object<T: key + store>(
        pbf_storage: &mut ParticipationBankFactoryStorage,
        name: String,
        object: T
    ) {
        dof::add<String, T>(&mut pbf_storage.id, name, object);
    }

    fun borrow_storage_object<T: key + store>(
        pbf_storage: &mut ParticipationBankFactoryStorage,
        name: String
    ): &mut T {
        dof::borrow_mut<String, T>(&mut pbf_storage.id, name)
    }

}