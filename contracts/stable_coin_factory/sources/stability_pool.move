/// Stability Pool is responsible for storing the stable coin tokens staked by users and
/// during liquidations covers the debt for liquidated Kasas
/// 
/// # Related Modules
/// 
/// * `Kasa Manager` - `Kasa Manager` reads the debt from the `Stability Pool` and sends collateral gains to this module
/// 
/// # Module Features
/// 
/// 1. Storing the stable coin tokens staked by users
/// 2. During liquidations, covering the debt for liquidated Kasas
/// 3. Distributing collateral gains to users automatically on deposit and withdrawal
module stable_coin_factory::stability_pool {
    use sui::object::{Self, UID, ID};
    use sui::table::{Self, Table};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::package::{Self, Publisher};

    use stable_coin_factory::liquidation_assets_distributor::{Self, CollateralGains};
    use tokens::rusd_stable_coin::{Self, RUSD_STABLE_COIN, RUSDStableCoinStorage};
    use library::math::{scalar, double_scalar, d_fdiv_u256, d_fmul_u256};
    // use library::utils::logger;

    friend stable_coin_factory::kasa_manager;

    /// OTW for Stability Pool
    struct STABILITY_POOL has drop {}

    /// Defines the data structure for saving the publisher
    struct StabilityPoolPublisher has key {
        id: UID,
        publisher: Publisher
    }

    /// Stake represents the amount of tokens staked by an account
    /// 
    /// # Fields
    /// 
    /// * `account_address` - the address of the account that staked the tokens
    /// * `amount` - the amount of tokens staked
    /// * `snapshot` - the snapshot of the stability pool
    struct Stake has store, drop {
        account_address: address,
        amount: u64,
        snapshot: StabilityPoolSnapshot
    }

    /// StabilityPoolStorage represents the storage for the stability pool
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

    /// StabilityPoolSnapshot represents the snapshot of the stability pool at various epochs
    /// 
    /// # Fields
    /// 
    /// * `p` - p value comes from the distribution formula
    /// * `s` - s value comes from the distribution formula
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

    fun init(witness: STABILITY_POOL, ctx: &mut TxContext) {
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
        transfer::share_object(StabilityPoolPublisher {
            id: object::new(ctx),
            publisher: package::claim<STABILITY_POOL>(witness, ctx)
        });
    }

    // =================== Public Methods ===================

    /// Deposits a given amount of stable coin into the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `stable_coin` - the stable coin object to be staked
    public fun deposit(
        sp_publisher: &StabilityPoolPublisher,
        sp_storage: &mut StabilityPoolStorage,
        collateral_gains: &mut CollateralGains,
        rsc_storage: &mut RUSDStableCoinStorage,
        stable_coin: Coin<RUSD_STABLE_COIN>,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);
        let amount = coin::value(&stable_coin);

        // Create a new stake for the account if it doesn't exist
        if (!check_stake_exists(sp_storage, account_address)) {
            let s = liquidation_assets_distributor::get_collateral_gains_sum(
                collateral_gains,
                sp_storage.snapshot.epoch,
                sp_storage.snapshot.scale
            );
            table::add(
                &mut sp_storage.stake_table,
                account_address, 
                Stake {
                    account_address: account_address,
                    amount: 0,
                    snapshot: StabilityPoolSnapshot {
                        p: sp_storage.snapshot.p,
                        s,
                        epoch: 0,
                        scale: 0
                    }
                }
            );
        };

        // Compounded stake amount for the account
        // Takes into account the change in global and snapshot p value
        let compounded_stake = get_stake_amount(sp_storage, account_address) + amount;

        // Borrow the stake for the account
        let stake = borrow_stake(sp_storage, account_address);

        // Send the collateral gains to the account
        liquidation_assets_distributor::send_collateral_gains(
            collateral_gains,
            account_address,
            stake.snapshot.epoch,
            stake.snapshot.scale,
            stake.snapshot.p,
            stake.snapshot.s,
            stake.amount,
            ctx
        );

        // Update the stake for the account
        stake.amount = compounded_stake;

        // Update user snapshots with protocol snapshots
        update_account_snapshots(sp_storage, collateral_gains, account_address);

        // Update the total stake balance
        coin::put(&mut sp_storage.stake_balance, stable_coin);

        // Decrease the stable coin balance for user
        rusd_stable_coin::update_account_balance(
            rsc_storage,
            get_publisher(sp_publisher),
            account_address,
            amount,
            false
        );
    }

    /// Withdraws a given amount of stable coin from the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `amount` - the amount of stable coin to be withdrawn
    public fun withdraw(
        sp_publisher: &StabilityPoolPublisher,
        sp_storage: &mut StabilityPoolStorage,
        collateral_gains: &mut CollateralGains,
        rsc_storage: &mut RUSDStableCoinStorage,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        // Compounded stake amount for the account
        // Takes into account the change in global and snapshot p value
        let compounded_stake = get_stake_amount(sp_storage, account_address) - amount;

        // Borrow and update the stake for the account
        let stake = borrow_stake(sp_storage, account_address);
        
        // Send the collateral gains to the account
        liquidation_assets_distributor::send_collateral_gains(
            collateral_gains,
            account_address,
            stake.snapshot.epoch,
            stake.snapshot.scale,
            stake.snapshot.p,
            stake.snapshot.s,
            stake.amount,
            ctx
        );
        
        // Update the stake for the account
        stake.amount = compounded_stake;

        // Remove the stake for the account if the stake amount is 0
        // Else update the snapshots for the account
        if (stake.amount == 0) remove_stake(sp_storage, account_address)
        else update_account_snapshots(sp_storage, collateral_gains, account_address);

        // Update the total stake balance
        let stable_coin = coin::take(
            &mut sp_storage.stake_balance,
            amount,
            ctx
        );

        // Transfer the stable coin back to the user
        transfer::public_transfer(stable_coin, account_address);

        // Increase the stable coin balance for user
        rusd_stable_coin::update_account_balance(
            rsc_storage,
            get_publisher(sp_publisher),
            account_address,
            amount,
            true
        );
    }  

    // =================== Friend Methods ===================

    /// Decreases the total balance of the stability pool by a given amount of stable coin.
    /// Only callable by the KasaManager module.
    /// 
    /// # Arguments
    /// 
    /// * `collateral` - collateral gained from the liquidation
    /// * `stake_offset_amount` - debt to offset from the stability pool
    /// 
    /// # Returns
    /// 
    /// * `Coin<RUSD_STABLE_COIN> - the stable coin object taken from the stability pool
    public(friend) fun liquidation(
        sp_storage: &mut StabilityPoolStorage,
        collateral_gains: &mut CollateralGains,
        collateral: Coin<SUI>,
        stake_offset_amount: u64,
        ctx: &mut TxContext
    ): Coin<RUSD_STABLE_COIN> {
        // Get the total stake balance
        let total_stake_amount = get_total_stake_amount(sp_storage);

        // TODO: Check if we need to uncomment these lines?
        // if (total_stake_amount == 0) return coin::zero<RUSD_STABLE_COIN>(ctx);
        // if (stake_offset_amount == 0) return coin::zero<RUSD_STABLE_COIN>(ctx);

        // TODO: Return error if stake_offset_amount is higher than total_stake_amount

        let (collateral_gain_per_stake, stake_offset_per_stake) = calculate_rewards_per_stake(
            sp_storage,
            &collateral,
            (stake_offset_amount as u256),
            (total_stake_amount as u256),
        );

        update_storage_snapshot(
            sp_storage,
            collateral_gains,
            collateral_gain_per_stake,
            stake_offset_per_stake,
            collateral,
            ctx
        );

        // Take the stable coin from the total balance
        coin::take(&mut sp_storage.stake_balance, stake_offset_amount, ctx)
    }

    // =================== Queries ===================
    
    /// Returns the amount of tokens staked by an account in the stability pool
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the address of the account
    /// 
    /// # Returns
    /// 
    /// * `u64` - the amount of tokens staked by the account
    public fun get_stake_amount(sp_storage: &StabilityPoolStorage, account_address: address): u64 {
        if (!check_stake_exists(sp_storage, account_address)) return 0;        
        let stake = table::borrow(&sp_storage.stake_table, account_address);
        
        // Pool is emptied and epoch is increased in previous liquidation call
        if (stake.snapshot.epoch < sp_storage.snapshot.epoch) return 0;

        let compounded_stake = 0;
        let scale_difference
            = sp_storage.snapshot.scale - stake.snapshot.scale;

        if (scale_difference == 0) {
            compounded_stake =
                d_fdiv_u256(
                    d_fmul_u256(
                        (stake.amount as u256),
                        sp_storage.snapshot.p
                    ),
                    stake.snapshot.p
                );
        } else if (scale_difference == 1) {
            compounded_stake = 
            d_fdiv_u256(
                d_fdiv_u256(
                    d_fmul_u256(
                        (stake.amount as u256),
                        sp_storage.snapshot.p
                    ),
                    stake.snapshot.p
                ),
                scalar()
            );
        };

        (compounded_stake as u64)
    }

    /// Returns the total amount of tokens staked in the stability pool
    /// 
    /// # Returns
    /// 
    /// * `u64` - the total amount of tokens staked in the stability pool
    public fun get_total_stake_amount(sp_storage: &StabilityPoolStorage): u64 {
        balance::value(&sp_storage.stake_balance)
    }

    // =================== Helpers ===================

    /// Calculates the rewards per stake and the stake offset per stake
    /// 
    /// # Arguments
    /// 
    /// * `collateral` - the collateral gained from the liquidation
    /// * `stake_offset_amount` - the debt to offset from the stability pool
    /// * `total_stake_amount` - the total amount of tokens staked in the stability pool
    /// 
    /// # Returns
    /// 
    /// * `(u256, u256)` - the rewards per stake and the stake offset per stake
    fun calculate_rewards_per_stake(
        sp_storage: &mut StabilityPoolStorage,
        collateral: &Coin<SUI>,
        stake_offset_amount: u256,
        total_stake_amount: u256
    ): (u256, u256) {
        let collateral_gain_amount = (coin::value(collateral) as u256);

        let collateral_gain_per_stake;
        let stake_offset_per_stake;

        let collateral_numerator =
            d_fmul_u256(collateral_gain_amount, double_scalar()) + sp_storage.last_error_offsets.collateral;
        collateral_gain_per_stake = d_fdiv_u256(collateral_numerator, total_stake_amount);
        sp_storage.last_error_offsets.collateral =
            collateral_numerator - d_fmul_u256(collateral_gain_per_stake, total_stake_amount);

        if (stake_offset_amount == total_stake_amount) {
            stake_offset_per_stake = double_scalar();
            sp_storage.last_error_offsets.stake = 0;
        } else {
            let stake_numerator =
                d_fmul_u256(stake_offset_amount, double_scalar()) - sp_storage.last_error_offsets.stake;
            stake_offset_per_stake = d_fdiv_u256(stake_numerator, total_stake_amount);
            sp_storage.last_error_offsets.stake =
                d_fmul_u256(stake_offset_per_stake, total_stake_amount) - stake_numerator;
        };

        (collateral_gain_per_stake, stake_offset_per_stake)
    }

    /// Updates the snapshot of the stability pool
    /// 
    /// # Arguments
    /// 
    /// * `collateral_gain_per_stake` - the collateral gain per stake
    /// * `stake_offset_per_stake` - the stake offset per stake
    /// * `collateral` - the collateral gained from the liquidation
    fun update_storage_snapshot(
        sp_storage: &mut StabilityPoolStorage,
        collateral_gains: &mut CollateralGains,
        collateral_gain_per_stake: u256,
        stake_offset_per_stake: u256,
        collateral: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let product_factor = double_scalar() - stake_offset_per_stake;

        let marginal_collateral_gain=
            d_fmul_u256(
                collateral_gain_per_stake,
                (sp_storage.snapshot.p as u256)
            );
        liquidation_assets_distributor::update_collateral_gains_balance(
            collateral_gains,
            sp_storage.snapshot.epoch,
            sp_storage.snapshot.scale,
            marginal_collateral_gain,
            collateral
        );

        // Stability pool was emptied
        // Increment the epoch and reset the p value and scale
        if (product_factor == 0) {
            sp_storage.snapshot.epoch = sp_storage.snapshot.epoch + 1;
            sp_storage.snapshot.p = double_scalar();
            sp_storage.snapshot.scale = 0;
            
            // Initialize the table for sum
            liquidation_assets_distributor::initialize_collateral_gains(
                collateral_gains,
                sp_storage.snapshot.epoch,
                ctx
            );


        // If product factor reduces P below the scale boundary
        // Increment the scale
        } else if (
            d_fdiv_u256(
                d_fmul_u256(
                    sp_storage.snapshot.p,
                    product_factor
                ),
                double_scalar()
            ) < scalar()
        ) {
            sp_storage.snapshot.p = d_fdiv_u256(
                d_fmul_u256(
                    d_fmul_u256(
                        sp_storage.snapshot.p,
                        product_factor
                    ),
                    scalar()
                ),
                double_scalar()
            );
            sp_storage.snapshot.scale = sp_storage.snapshot.scale + 1;
        } else {
            sp_storage.snapshot.p = d_fdiv_u256(
                d_fmul_u256(
                    sp_storage.snapshot.p,
                    product_factor
                ),
                double_scalar()
            );
        };
    }

    /// Updates the snapshots of an account's stake
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the address of the account
    fun update_account_snapshots(
        sp_storage: &mut StabilityPoolStorage,
        collateral_gains: &mut CollateralGains,
        account_address: address,
    ) {
        let protocol_p_value = sp_storage.snapshot.p;
        let protocol_scale = sp_storage.snapshot.scale;
        let protocol_epoch = sp_storage.snapshot.epoch;

        let stake = borrow_stake(sp_storage, account_address);

        stake.snapshot.p = protocol_p_value;
        stake.snapshot.s = liquidation_assets_distributor::get_collateral_gains_sum(
            collateral_gains,
            protocol_epoch,
            protocol_scale
        );
        stake.snapshot.epoch = protocol_epoch;
        stake.snapshot.scale = protocol_scale;
    }

    /// Check if a stake exists for a given account address in the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the address of the account
    /// 
    /// # Returns
    /// 
    /// * `bool` - true if a stake exists for the account, false otherwise
    fun check_stake_exists(sp_storage: &StabilityPoolStorage, account_address: address): bool {
        table::contains(&sp_storage.stake_table, account_address)
    }
    
    /// Borrow stake from the StabilityPoolStorage for a given account address.
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the address of the account
    /// 
    /// # Returns
    /// 
    /// * `Stake` - A mutable reference to the stake for the account
    fun borrow_stake(sp_storage: &mut StabilityPoolStorage, account_address: address): &mut Stake {
        table::borrow_mut(&mut sp_storage.stake_table, account_address)
    }

    /// Removes the stake for a given account address from the stability pool
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the address of the account
    fun remove_stake(sp_storage: &mut StabilityPoolStorage, account_address: address) {
        table::remove(&mut sp_storage.stake_table, account_address);
    }

    public fun get_publisher(storage: &StabilityPoolPublisher): &Publisher {
        &storage.publisher
    }

    public fun get_publisher_id(publisher: &StabilityPoolPublisher): ID {
        object::id(&publisher.publisher)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(STABILITY_POOL {}, ctx);
    }
}