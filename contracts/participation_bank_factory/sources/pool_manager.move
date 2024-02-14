module participation_bank_factory::pool_manager {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::SUI;

    use participation_bank_factory::participation_bank_factory::ParticipationBankFactoryStorage;

    // This is some object that will be sent to the admin
    // to be used as shared storage
    // This object will be tied to the main package object
    struct PoolManagerStorage has key, store {
        id: UID,
        balance: Balance<SUI>
    }
    
    fun init(ctx: &mut TxContext) {
        let pool_manager_storage = PoolManagerStorage {
            id: object::new(ctx),
            balance: balance::zero()
        };
        transfer::public_transfer(pool_manager_storage, tx_context::sender(ctx))
    }

    fun deposit_to_pool(pbf_storage: &mut ParticipationBankFactoryStorage, coin: Coin<SUI>) {
        
    }

}