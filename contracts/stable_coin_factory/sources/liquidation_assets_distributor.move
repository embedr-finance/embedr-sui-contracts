/// Liquidation Assets Distributor is responsible for distributing collateral gains to Stability Pool stakers
/// With each liquidation of Kasa, this module is executed to save the reward state of the liquidation
/// 
/// # Related Modules
/// 
/// * `Stability Pool` - `Stability Pool` calls methods from this module to save and distribute collateral gains to stakers
/// 
/// There is a single responsibility for this module:
/// 
/// During liquidations, this module is called to save the collateral gains for each epoch and scale
/// After saving the collateral gains, with each deposit and withdraw from Stability Pool
/// this module is called to distribute the collateral gains to stakers automatically
module stable_coin_factory::liquidation_assets_distributor {    
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext};
    use sui::transfer;
    use sui::table::{Self, Table};
    use sui::sui::SUI;
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};

    use library::math::{d_fdiv_u256, d_fmul_u256, scalar, double_scalar};
    // use library::utils::logger;

    friend stable_coin_factory::stability_pool;

    /// CollateralGains represents the sum of collateral gains for each epoch and scale in Stability Pool
    /// These gains are distributed to Stability Pool stakers
    /// 
    /// # Fields
    /// 
    /// * `sum_table` - the sum of collateral gains for each epoch and scale
    /// * `balance` - the total balance of collateral gains
    struct CollateralGains has key, store {
        id: UID,
        sum_table: Table<u64, Table<u64, u256>>,
        balance: Balance<SUI>
    }

    // =================== Initializer ===================

    fun init(ctx: &mut TxContext) {
        // Initialize the epoch to scale to sum table
        // Epoch is 0, scale is 0, sum is 0
        let sum_table = table::new(ctx);
        let inner = table::new(ctx);
        table::add(&mut inner, 0, 0);
        table::add(&mut sum_table, 0, inner);
        transfer::share_object(CollateralGains {
            id: object::new(ctx),
            sum_table,
            balance: balance::zero()
        });
    }

    // =================== Friend Methods ===================

    /// Initializes the epoch to scale to sum table for the given epoch.
    /// 
    /// # Arguments
    /// 
    /// * `epoch` - the epoch to initialize
    public(friend) fun initialize_collateral_gains(collateral_gains: &mut CollateralGains, epoch: u64, ctx: &mut TxContext) {
        let table = table::new(ctx);
        table::add(&mut table, 0, 0);
        table::add(&mut collateral_gains.sum_table, epoch, table);
    }

    /// Updates the balance of collateral gains for the given epoch and scale.
    /// 
    /// # Arguments
    /// 
    /// * `epoch` - the epoch to update
    /// * `scale` - the scale to update
    /// * `gain` - the amount of collateral gains to add
    /// * `value` - the value to update
    public(friend) fun update_collateral_gains_balance(
        collateral_gains: &mut CollateralGains,
        epoch: u64,
        scale: u64,
        gain: u256,
        collateral: Coin<SUI>
    ) {
        let sum = table::remove(
            table::borrow_mut(&mut collateral_gains.sum_table, epoch),
            scale
        );
        table::add(
            table::borrow_mut(&mut collateral_gains.sum_table, epoch),
            scale,
            sum + gain
        );
        coin::put(&mut collateral_gains.balance, collateral);
    }

    /// Sends collateral gains to the given account address for the given epoch and scale
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the account address to send the collateral gains to
    /// * `epoch` - the epoch to send the collateral gains for
    /// * `scale` - the scale to send the collateral gains for
    /// * `p` - p value that is used to calculate the collateral gains in distribution formula
    /// * `s` - p value that is used to calculate the collateral gains in distribution formula
    /// * `stake` - the stability pool stake of the account address
    public(friend) fun send_collateral_gains(
        collateral_gains: &mut CollateralGains,
        account_address: address,
        epoch: u64,
        scale: u64,
        p: u256,
        s: u256,
        stake: u64,
        ctx: &mut TxContext
    ) {
        let first_portion = get_collateral_gains_sum(collateral_gains, epoch, scale) - s;
        let second_portion = d_fdiv_u256(get_collateral_gains_sum(collateral_gains, epoch, scale + 1), scalar());

        if (stake == 0) return;
        if (first_portion + second_portion == 0) return;

        let collateral_gain = d_fdiv_u256(
            d_fdiv_u256(
                d_fmul_u256(
                    (stake as u256),
                    first_portion + second_portion
                ),
                p
            ),
            double_scalar()
        );

        let collateral = coin::from_balance(
            balance::split(&mut collateral_gains.balance, (collateral_gain as u64)),
            ctx
        );
        transfer::public_transfer(collateral, account_address);
    }

    // =================== Public Methods ===================

    /// Returns the sum of collateral gains for the given epoch and scale.
    /// 
    /// # Arguments
    /// 
    /// * `epoch` - the epoch to get the sum for
    /// * `scale` - the scale to get the sum for
    /// 
    /// # Returns
    /// 
    /// * `u256` - the sum of collateral gains for the given epoch and scale
    public fun get_collateral_gains_sum(collateral_gains: &mut CollateralGains, epoch: u64, scale: u64): u256 {
        // If the epoch does not exist, return 0
        if (!table::contains(&collateral_gains.sum_table, epoch)) return 0;
    
        let scale_sum = table::borrow(&collateral_gains.sum_table, epoch);

        // If the scale does not exist, return 0
        if (!table::contains(scale_sum, scale)) return 0;

        let sum = table::borrow(scale_sum, scale);
        *sum
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}
