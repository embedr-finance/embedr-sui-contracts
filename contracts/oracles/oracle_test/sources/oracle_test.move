// module oracle_test::oracle_test {

//     use sui::object::{Self, UID};
//     use sui::tx_context::{Self,TxContext};
//     use sui::transfer;
//     use SupraOracle::SupraSValueFeed::{Self, OracleHolder};

//     struct Storage has key, store {
//         id: sui::object::UID,
//         price: u128
//     }

//     fun init(ctx:&mut TxContext) {
//         transfer::share_object(
//             Storage {
//                 id:object::new(ctx),
//                 price:0
//             }
//         );
//     }

//     public fun set_price(oracle_holder:&OracleHolder, storage: &mut Storage) : u128 {
//         let (sui_usd_price,_,_,_) = SupraSValueFeed::get_price(oracle_holder, 90);
//         storage.price = sui_usd_price;
//         storage.price
//     }

//       fun convert_to_9_decimal_places(value: u128): u128 {
//        value / 1000000000
//     } 
    
// }