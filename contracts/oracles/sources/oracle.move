/// Oracles package is responsible for live price of sui token
/// 
///  # Related Modules
/// 
/// `kasa.manager` - `kasa.operations` - `kasa.storage` modules calls the method in this module for taking live price of sui token.
/// 
/// 
/// There are one main operation in this module:
/// 
/// Creates two functions for take sui token price from supra oracle and pyth oracle.
/// Call that two functions in one method. 
module oracles::oracle {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    use SupraOracle::SupraSValueFeed::{Self, OracleHolder};

    // Supra_oracle sui pair code
    const SUPRA_SUI_USD_PAIR: u32 = 90;
    // Reduce to 9 decimal
    const SUI_FRACTION: u256 = 100_000_000;
    
    // share object for take live price of sui token
    struct Storage has key, store {
        id: UID,
        supra_price: u256,
    }

     // =================== Initializer ===================

    fun init(ctx:&mut TxContext) {
        transfer::share_object(
            Storage {
                id:object::new(ctx),
                supra_price:0,
            }
        );
    }

    /// Take a live price of sui token from SupraOracle
    /// 
    /// # Arguments
    /// 
    /// `oracle_holder` - the share object of SupraOracle
    /// `storage` - the share object for return the price of sui token
    public fun set_supra_price(oracle_holder: &OracleHolder, storage: &mut Storage) {
        // Take sui token price
        let (sui_usd_price, _, _, _) 
            = SupraSValueFeed::get_price(oracle_holder, SUPRA_SUI_USD_PAIR);
        // Assign the sui live price into our share object as u256 and 9 decimal
        storage.supra_price = (sui_usd_price as u256) / SUI_FRACTION;   
    }

    /// Get sui token live price from SupraOracle and pyth
    /// 
    /// # Arguments 
    ///
    /// `oracle_holder` - the share object of SupraOracle
    /// `storage` - the share object for return the price of sui token
    public fun get_sui_price(oracle_holder: &OracleHolder, storage: &mut Storage) : u256 {
        set_supra_price(oracle_holder, storage);
        storage.supra_price
    }
}