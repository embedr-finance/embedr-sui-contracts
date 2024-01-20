module oracles::oracle {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    use SupraOracle::SupraSValueFeed::{Self, OracleHolder};
    
    struct Storage has key, store {
        id: sui::object::UID,
        supra_price: u256,
    }

    fun init(ctx:&mut TxContext) {
        transfer::share_object(
            Storage {
                id:object::new(ctx),
                supra_price:0,
            }
        );
    }

    public fun set_supra_price(oracle_holder: &OracleHolder, storage: &mut Storage) {
        let (sui_usd_price, _, _, _) = SupraSValueFeed::get_price(oracle_holder, 90);
        storage.supra_price = (sui_usd_price as u256) / 1000000000;   
    }

    public fun get_sui_price(oracle_holder: &OracleHolder, storage: &mut Storage) : u256 {
        set_supra_price(oracle_holder, storage);
        storage.supra_price
    }
}