/// Oracles module is responsible for fetching various token prices via multiple oracle services
/// 
/// There is one main operation in this module:
/// 
/// Implements two methods to fetch SUI price from Supra and Pyth oracles
/// Call either one of those methods in a single `get_sui_price` method
module oracles::oracle {
    use sui::object::{Self, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::clock::{Self, Clock};

    use SupraOracle::SupraSValueFeed::{Self, OracleHolder};

    use pyth::pyth:: {Self, get_price};
    use pyth::state:: {Self, State};
    use pyth::price_info:: {Self, PriceInfoObject};
    use pyth::price:: {Self, Price};
    use pyth::i64:: {Self, I64};

    // Supra_oracle sui pair code
    const SUPRA_SUI_USD_PAIR: u32 = 90;
    // Reduce to 9 decimal
    const SUI_FRACTION: u256 = 100_000_000;
    
    // share object for take live price of sui token
    struct Storage has key, store {
        id: UID,
        supra_price: u256,
        pyth_price:I64,
        pyth_price_u256:u256
    }

     // =================== Initializer ===================

    fun init(ctx:&mut TxContext) {
        transfer::share_object(
            Storage {
                id:object::new(ctx),
                supra_price:0,
                pyth_price:i64::new(0, false),
                pyth_price_u256:0
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

    /// Take a live price of sui token from Pyth
    /// 
    /// # Arguments
    /// 
    /// `oracle_holder` - the share object of SupraOracle
    /// `storage` - the share object for return the price of sui token
    public fun set_pyth_price(state:&State, price_info:&PriceInfoObject, clock:&Clock, storage: &mut Storage) {
        // Take Price object from pyth::get_price
        let pyth_sui_price = get_price(state, price_info, clock);
        // Get I64 object from price::get_price
        let price_I64 = price::get_price(&pyth_sui_price);
        // Return sui token as u256 from i64::get_magnitude_if_positive
        storage.pyth_price_u256 = (i64::get_magnitude_if_positive(&price_I64) as u256);
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
