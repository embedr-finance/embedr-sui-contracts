module stable_coin_factory::liquidation_assets_distributor {
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::sui::{SUI};
    use sui::tx_context::{Self, TxContext};
    use sui::object_table::{Self, ObjectTable};

    use stable_coin_factory::kasa_manager::{Kasa};
    use tokens::rusd_stable_coin::{RUSD_STABLE_COIN};

    struct LiquidationAssetsDistributorStorage {
        // liquidation_rewards: 
    }

    struct LiquidationReward {
        epoch: u64,
        kasa_table: ObjectTable<address, Kasa>,
        collateral_balance: Balance<SUI>,
        debt_balance: Balance<RUSD_STABLE_COIN>
    }

}