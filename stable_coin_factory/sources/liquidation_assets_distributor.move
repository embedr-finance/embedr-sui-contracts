module stable_coin_factory::liquidation_assets_distributor {    
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};

    friend stable_coin_factory::stability_pool;

    /// CollateralGains represents the sum of collateral gains for each epoch and scale in Stability Pool
    /// These gains are distributed to Stability Pool stakers
    /// 
    /// # Fields
    /// 
    /// * `s` - sum of collateral gains for each epoch and scale
    struct CollateralGains has key, store {
        id: UID,
        sum_table: Table<u64, Table<u64, Balance<SUI>>>,
    }

    // =================== Initializer ===================

    fun init(ctx: &mut TxContext) {
        // Initialize the epoch to scale to sum table
        // Epoch is 0, scale is 0, sum is 0
        let sum_table = table::new(ctx);
        let inner = table::new(ctx);
        table::add(&mut inner, 0, balance::zero());
        table::add(&mut sum_table, 0, inner);
        transfer::share_object(CollateralGains {
            id: object::new(ctx),
            sum_table
        });
    }

    // =================== Entries ===================

    /// Initializes the epoch to scale to sum table for the given epoch.
    /// 
    /// # Arguments
    /// 
    /// * `collateral_gains` - the CollateralGains object to initialize
    /// * `epoch` - the epoch to initialize
    public(friend) fun initialize_collateral_gains(collateral_gains: &mut CollateralGains, epoch: u64, ctx: &mut TxContext) {
        let table = table::new(ctx);
        table::add(&mut table, 0, balance::zero());
        table::add(&mut collateral_gains.sum_table, epoch, table);
    }

    /// Updates the balance of collateral gains for the given epoch and scale.
    /// 
    /// # Arguments
    /// 
    /// * `collateral_gains` - the CollateralGains object to update
    /// * `epoch` - the epoch to update
    /// * `scale` - the scale to update
    /// * `value` - the value to update
    public(friend) fun update_collateral_gains_balance(
        collateral_gains: &mut CollateralGains,
        epoch: u64,
        scale: u64,
        collateral: Coin<SUI>
    ) {
        let balance = table::borrow_mut(
            table::borrow_mut(&mut collateral_gains.sum_table, epoch),
            scale
        );
        balance::join(balance, coin::into_balance(collateral));
    }

    // =================== Queries ===================

    /// Returns the sum of collateral gains for the given epoch and scale.
    /// 
    /// # Arguments
    /// 
    /// * `collateral_gains` - the CollateralGains object
    /// * `epoch` - the epoch to get the sum for
    /// * `scale` - the scale to get the sum for
    /// 
    /// # Returns
    /// 
    /// * `u64` - the sum of collateral gains for the given epoch and scale
    public fun get_collateral_gains_sum(collateral_gains: &mut CollateralGains, epoch: u64, scale: u64): u256 {
        // If the epoch does not exist, return 0
        if (!table::contains(&collateral_gains.sum_table, epoch)) return 0;
    
        let scale_sum = table::borrow(&collateral_gains.sum_table, epoch);

        // If the scale does not exist, return 0
        if (!table::contains(scale_sum, scale)) return 0;

        let balance = table::borrow(scale_sum, scale);
        (balance::value(balance) as u256)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}