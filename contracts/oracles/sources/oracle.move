module oracles::oracle {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    use SupraOracle::SupraSValueFeed::{Self, OracleHolder};

    const SUPRA_SUI_USD_PAIR: u32 = 90;
    const SUI_FRACTION: u256 = 100_000_000;
    
    struct Storage has key, store {
        id: UID,
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
        let (sui_usd_price, _, _, _) 
            = SupraSValueFeed::get_price(oracle_holder, SUPRA_SUI_USD_PAIR);
        storage.supra_price = (sui_usd_price as u256) / SUI_FRACTION;   
    }

    public fun get_sui_price(oracle_holder: &OracleHolder, storage: &mut Storage) : u256 {
        set_supra_price(oracle_holder, storage);
        storage.supra_price
    }
}