module SupraOracleTest::SupraSValueFeed2 {

    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    

    struct OracleHolder has key, store { id: UID }

    struct Price has drop {
        pair: u32,
        value: u128,
        decimal: u16,
        timestamp: u128,
        round: u64
    }

    /// It will return the priceFeedData value for that particular tradingPair
    public fun get_price(oracle_holder: &OracleHolder, pair: u32): (u128, u16, u128, u64) {
        (1800_000000000, 0, 0, 0) 
    }

     #[test_only]
    public fun return_oracleholder(ctx:&mut TxContext) : OracleHolder {
        let supra_oracle = OracleHolder {
           id: object::new(ctx)
        };
        supra_oracle
    }

    public fun delete_oracleholder(oracleholder: OracleHolder) {
        let OracleHolder {id} = oracleholder;
        object::delete(id);
    }

}
