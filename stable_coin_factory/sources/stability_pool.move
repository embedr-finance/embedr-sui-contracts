module stable_coin_factory::stability_pool {
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};

    use stable_coin_factory::liquidation_assets_distributor::{Self, CollateralGains};
    use tokens::rusd_stable_coin::{RUSD_STABLE_COIN};
    use library::math::{scalar, double_scalar, d_fdiv_u256, d_fmul_u256};
    // use library::utils::logger;

    friend stable_coin_factory::kasa_manager;

    /// Stake represents the amount of tokens staked by an account.
    /// 
    /// # Fields
    /// 
    /// * `account_address` - the address of the account that staked the tokens
    /// * `amount` - the amount of tokens staked
    struct Stake has store, drop {
        account_address: address,
        amount: u64,
        snapshot: StabilityPoolSnapshot
    }

    /// StabilityPoolStorage represents the storage for the stability pool.
    /// 
    /// # Fields
    /// 
    /// * `stake_table` - the table that stores the staked amounts for each account
    /// * `stake_balance` - the balance of the stable coin in the stability pool
    /// * `snapshot` - the snapshot of the stability pool
    /// * `last_error_offsets` - the errors in the collateral gain and stake offset
    struct StabilityPoolStorage has key {
        id: UID,
        stake_table: Table<address, Stake>,
        stake_balance: Balance<RUSD_STABLE_COIN>,
        snapshot: StabilityPoolSnapshot,
        last_error_offsets: OffsetErrors
    }

    /// LiquidationSnapshot represents the snapshot of the stability pool at var
    /// 
    /// # Fields
    /// 
    /// * `p` - value to calculate the compounded stake amount
    /// * `epoch` - stability pool depletion epoch
    /// * `scale` - decimal shift of the p value
    struct StabilityPoolSnapshot has store, drop {
        p: u256,
        s: u256,
        epoch: u64,
        scale: u64
    }

    /// OffsetErrors represents the errors in the collateral gain and stake offset
    /// 
    /// # Fields
    /// 
    /// * `collateral` - error in the collateral gain
    /// * `stake` - error in the stake offset
    struct OffsetErrors has store {
        collateral: u256,
        stake: u256
    }

    // =================== Initializer ===================

    fun init(ctx: &mut TxContext) {
        // Initialize the storage for the stability pool
        transfer::share_object(StabilityPoolStorage {
            id: object::new(ctx),
            stake_table: table::new(ctx),
            stake_balance: balance::zero(),
            snapshot: StabilityPoolSnapshot {
                p: double_scalar(),
                s: 0, // Unused variable
                epoch: 0,
                scale: 0
            },
            last_error_offsets: OffsetErrors {
                collateral: 0,
                stake: 0
            }
        });
    }

    // =================== Entries ===================

    /// Deposits a given amount of stable coin into the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// * `stable_coin` - the stable coin to be staked
    entry public fun deposit(
        stability_pool_storage: &mut StabilityPoolStorage,
        collateral_gains: &mut CollateralGains,
        stable_coin: Coin<RUSD_STABLE_COIN>,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);
        let amount = coin::value(&stable_coin);

        // Create a new stake for the account if it doesn't exist
        if (!check_stake_exists(stability_pool_storage, account_address)) {
            let s = liquidation_assets_distributor::get_collateral_gains_sum(
                collateral_gains,
                stability_pool_storage.snapshot.epoch,
                stability_pool_storage.snapshot.scale
            );
            table::add(
                &mut stability_pool_storage.stake_table,
                account_address, 
                Stake {
                    account_address: account_address,
                    amount: 0,
                    snapshot: StabilityPoolSnapshot {
                        p: stability_pool_storage.snapshot.p,
                        s,
                        epoch: 0,
                        scale: 0
                    }
                }
            );
        };

        // Compounded stake amount for the account
        // Takes into account the change in global and snapshot p value
        let compounded_stake = get_stake_amount(stability_pool_storage, account_address) + amount;
        let protocol_p_value = stability_pool_storage.snapshot.p;

        // Borrow and update the stake for the account
        let stake = borrow_stake(stability_pool_storage, account_address);
        stake.amount = compounded_stake;

        // Update the snapshot p value
        stake.snapshot.p = protocol_p_value;

        // Update the total stake balance
        coin::put(&mut stability_pool_storage.stake_balance, stable_coin);
    }

    /// Withdraws a given amount of stable coin from the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// * `amount` - the amount of stable coin to be withdrawn
    entry public fun withdraw(
        stability_pool_storage: &mut StabilityPoolStorage,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        // Compounded stake amount for the account
        // Takes into account the change in global and snapshot p value
        let compounded_stake = get_stake_amount(stability_pool_storage, account_address) - amount;

        // Borrow and update the stake for the account
        let stake = borrow_stake(stability_pool_storage, account_address);
        stake.amount = compounded_stake;

        // Remove the stake for the account if the stake amount is 0
        if (stake.amount == 0) remove_stake(stability_pool_storage, account_address);

        // Update the total stake balance
        let stable_coin = coin::take(
            &mut stability_pool_storage.stake_balance,
            amount,
            ctx
        );
        
        // Transfer the stable coin back to the user
        transfer::public_transfer(stable_coin, account_address);
    }  

    /// Decreases the total balance of the stability pool by a given amount of stable coin.
    /// Only callable by the KasaManager module.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// * `amount` - the amount of stable coin to be taken from the total balance
    /// * `ctx` - the transaction context
    /// 
    /// # Returns
    /// 
    /// The stable coin that was taken from the total balance
    public(friend) fun liquidation(
        stability_pool_storage: &mut StabilityPoolStorage,
        collateral_gains: &mut CollateralGains,
        collateral_gain_amount: u64,
        stake_offset_amount: u64,
        ctx: &mut TxContext
    ): Coin<RUSD_STABLE_COIN> {
        // Get the total stake balance
        let total_stake_amount = get_total_stake_amount(stability_pool_storage);

        // TODO: Return if total_stake_amount is 0
        // TODO: Return if amount is 0
        if (total_stake_amount == 0) return coin::zero(ctx);
        if (stake_offset_amount == 0) return coin::zero(ctx);

        // TODO: Return error if stake_offset_amount is higher than total_stake_amount

        let (collateral_gain_per_stake, stake_offset_per_stake) = calculate_rewards_per_stake(
            stability_pool_storage,
            (collateral_gain_amount as u256),
            (stake_offset_amount as u256),
            (total_stake_amount as u256),
        );

        update_storage_snapshot(
            stability_pool_storage,
            collateral_gains,
            collateral_gain_per_stake,
            stake_offset_per_stake,
            ctx
        );

        // Take the stable coin from the total balance
        coin::take(&mut stability_pool_storage.stake_balance, stake_offset_amount, ctx)
    }

    // =================== Queries ===================
    
    /// Returns the amount of tokens staked by an account in the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// * `account_address` - the address of the account
    /// 
    /// # Returns
    /// 
    /// The amount of tokens staked by the account
    public fun get_stake_amount(stability_pool_storage: &StabilityPoolStorage, account_address: address): u64 {
        if (!check_stake_exists(stability_pool_storage, account_address)) return 0;        
        let stake = table::borrow(&stability_pool_storage.stake_table, account_address);
        
        // Pool is emptied and epoch is increased in previous liquidation call
        if (stake.snapshot.epoch < stability_pool_storage.snapshot.epoch) return 0;

        let compounded_stake = 0;
        let scale_difference
            = stability_pool_storage.snapshot.scale - stake.snapshot.scale;

        if (scale_difference == 0) {
            compounded_stake =
                d_fdiv_u256(
                    d_fmul_u256(
                        (stake.amount as u256),
                        stability_pool_storage.snapshot.p
                    ),
                    stake.snapshot.p
                );
        } else if (scale_difference == 1) {
            compounded_stake = 
            d_fdiv_u256(
                d_fdiv_u256(
                    d_fmul_u256(
                        (stake.amount as u256),
                        stability_pool_storage.snapshot.p
                    ),
                    stake.snapshot.p
                ),
                scalar()
            );
        };

        (compounded_stake as u64)
    }

    // public fun get_collateral_gain(
    //     stability_pool_storage: &mut StabilityPoolStorage,
    //     account_address: address
    // ): u64 {
    //     let first_portion = 
    // }

    /// Returns the total amount of tokens staked in the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// 
    /// # Returns
    /// 
    /// The total amount of tokens staked in the stability pool
    public fun get_total_stake_amount(stability_pool_storage: &StabilityPoolStorage): u64 {
        balance::value(&stability_pool_storage.stake_balance)
    }

    // =================== Helpers ===================

    /// Calculates the rewards per stake and the stake offset per stake.
    /// 
    /// # Arguments
    /// 
    /// * `collateral_amount` - the amount of collateral gained from the liquidation
    /// * `debt_amount` - the amount of debt offset from the stability pool
    /// * `total_stake_amount` - the total amount of tokens staked in the stability pool
    /// 
    /// # Returns
    /// 
    /// The rewards per stake and the stake offset per stake
    fun calculate_rewards_per_stake(
        stability_pool_storage: &mut StabilityPoolStorage,
        collateral_gain_amount: u256,
        stake_offset_amount: u256,
        total_stake_amount: u256
    ): (u256, u256) {
        let collateral_gain_per_stake;
        let stake_offset_per_stake;

        let collateral_numerator = d_fmul_u256(collateral_gain_amount, double_scalar()) + stability_pool_storage.last_error_offsets.collateral;
        collateral_gain_per_stake = d_fdiv_u256(collateral_numerator, total_stake_amount);
        stability_pool_storage.last_error_offsets.collateral = collateral_numerator - d_fmul_u256(collateral_gain_per_stake, total_stake_amount);

        if (stake_offset_amount == total_stake_amount) {
            stake_offset_per_stake = double_scalar();
            stability_pool_storage.last_error_offsets.stake = 0;
        } else {
            let stake_numerator = d_fmul_u256(stake_offset_amount, double_scalar()) - stability_pool_storage.last_error_offsets.stake;
            stake_offset_per_stake = d_fdiv_u256(stake_numerator, total_stake_amount);
            stability_pool_storage.last_error_offsets.stake = d_fmul_u256(stake_offset_per_stake, total_stake_amount) - stake_numerator;
        };

        (collateral_gain_per_stake, stake_offset_per_stake)
    }

    // Updates the snapshot of the stability pool
    fun update_storage_snapshot(
        stability_pool_storage: &mut StabilityPoolStorage,
        collateral_gains: &mut CollateralGains,
        collateral_gain_per_stake: u256,
        stake_offset_per_stake: u256,
        ctx: &mut TxContext
    ) {
        let product_factor = double_scalar() - stake_offset_per_stake;

        let marginal_collateral_gain = d_fmul_u256(collateral_gain_per_stake, (stability_pool_storage.snapshot.p as u256));
        let s = liquidation_assets_distributor::get_collateral_gains_sum(
            collateral_gains,
            stability_pool_storage.snapshot.epoch,
            stability_pool_storage.snapshot.scale
        );
        liquidation_assets_distributor::update_collateral_gains_sum(
            collateral_gains,
            stability_pool_storage.snapshot.epoch,
            stability_pool_storage.snapshot.scale,
            s + marginal_collateral_gain
        );

        // Stability pool was emptied
        // Increment the epoch and reset the p value and scale
        if (product_factor == 0) {
            stability_pool_storage.snapshot.epoch = stability_pool_storage.snapshot.epoch + 1;
            stability_pool_storage.snapshot.p = double_scalar();
            stability_pool_storage.snapshot.scale = 0;
            
            // Initialize the table for sum
            liquidation_assets_distributor::initialize_collateral_gains(
                collateral_gains,
                stability_pool_storage.snapshot.epoch,
                ctx
            );


        // If product factor reduces P below the scale boundary
        // Increment the scale
        } else if (
            d_fdiv_u256(
                d_fmul_u256(
                    stability_pool_storage.snapshot.p,
                    product_factor
                ),
                double_scalar()
            ) < scalar()
        ) {
            stability_pool_storage.snapshot.p = d_fdiv_u256(
                d_fmul_u256(
                    d_fmul_u256(
                        stability_pool_storage.snapshot.p,
                        product_factor
                    ),
                    scalar()
                ),
                double_scalar()
            );
            stability_pool_storage.snapshot.scale = stability_pool_storage.snapshot.scale + 1;
        } else {
            stability_pool_storage.snapshot.p = d_fdiv_u256(
                d_fmul_u256(
                    stability_pool_storage.snapshot.p,
                    product_factor
                ),
                double_scalar()
            );
        };
    }

    /// Check if a stake exists for a given account address in the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// * `account_address` - the address of the account
    /// 
    /// # Returns
    /// 
    /// `true` if a stake exists for the account, `false` otherwise
    fun check_stake_exists(stability_pool_storage: &StabilityPoolStorage, account_address: address): bool {
        table::contains(&stability_pool_storage.stake_table, account_address)
    }
    
    /// Borrow stake from the StabilityPoolStorage for a given account address.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// * `account_address` - the address of the account
    /// 
    /// # Returns
    /// 
    /// A mutable reference to the stake for the account
    fun borrow_stake(stability_pool_storage: &mut StabilityPoolStorage, account_address: address): &mut Stake {
        table::borrow_mut(&mut stability_pool_storage.stake_table, account_address)
    }

    /// Removes the stake for a given account address from the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// * `account_address` - the address of the account
    fun remove_stake(stability_pool_storage: &mut StabilityPoolStorage, account_address: address) {
        table::remove(&mut stability_pool_storage.stake_table, account_address);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}