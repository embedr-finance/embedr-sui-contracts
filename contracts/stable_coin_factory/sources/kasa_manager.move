/// Kasa Manager module is responsible for managing the Kasas and their operations
/// 
/// # Related Modules
/// 
/// * `Kasa Storage` - `Kasa Manager` calls `Kasa Storage` to manipulate the Kasas and protocol balances
/// * `Kasa Operations` - `Kasa Operations` module calls the methods in this module for executing Kasa operations
/// * `Sorted Kasas` - `Kasa Manager` calls `Sorted Kasas` to manipulate and get the Kasas in order
/// * `Stability Pool` - `Kasa Manager` calls `Stability Pool` during liquidations
/// * `RUSD Stable Coin` - `Kasa Manager` calls `RUSD Stable Coin` to mint and burn stable coins
///
/// 
/// There are three main operations in this module:
/// 
/// 1. Creates and manipulates the Kasa objects
/// 2. Liquidates Kasas that are below the minimum collateral ratio
/// 3. Redeems stable coins for collateral from Kasas
module stable_coin_factory::kasa_manager {
    use std::option::{Self, Option};

    #[test_only]
    use sui::object::{ID};

    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::package::{Self, Publisher};

    use stable_coin_factory::kasa_storage::{Self, KasaManagerStorage, get_collateral_ratio, LiquidationSnapshots};
    use stable_coin_factory::stability_pool::{Self, StabilityPoolStorage};
    use stable_coin_factory::liquidation_assets_distributor::CollateralGains;
    use stable_coin_factory::sorted_kasas::{Self, SortedKasasStorage};
    use tokens::rusd_stable_coin::{Self, RUSD_STABLE_COIN, RUSDStableCoinStorage};
    use library::kasa::{get_minimum_collateral_ratio, calculate_nominal_collateral_ratio, get_minimum_net_debt};
    use library::math::{min, mul_div, scalar};
    // use library::utils::logger;

    friend stable_coin_factory::kasa_operations;

    // =================== Errors ===================

    // const ERROR_LIST_FULL: u64 = 1;
    // const ERROR_EXISTING_ITEM: u64 = 2;
    const ERROR_UNABLE_TO_REDEEM: u64 = 3;
    const ERROR_UNABLE_TO_LIQUIDATE: u64 = 4;
    const ERROR_SINGLE_KASA_LEFT: u64 = 5;

    // =================== Storage ===================

    /// OTW for Kasa Manager
    struct KASA_MANAGER has drop {}

    /// Defines the data structure for saving the publisher
    struct KasaManagerPublisher has key {
        id: UID,
        publisher: Publisher
    }

    /// LiquidationTotals is used to keep track of the liquidation totals
    /// across multiple Kasas in the liquidation loop
    struct LiquidationTotals has drop {
        collateral_in_sequence: u64,
        debt_in_sequence: u64,
        collateral_to_send_to_stability_pool: u64,
        debt_to_offset: u64,
        collateral_to_redistribute: u64,
        debt_to_redistribute: u64,
        collateral_surplus: u64,
    }

    /// LiquidationValues is used to keep track of the liquidation values
    /// for a single Kasa in the liquidation loop
    struct LiquidationValues has drop {
        kasa_collateral_amount: u64,
        kasa_debt_amount: u64,
        collateral_to_send_to_stability_pool: u64,
        debt_to_offset: u64,
        collateral_to_redistribute: u64,
        debt_to_redistribute: u64,
        collateral_surplus: u64,
    }

    /// RedemptionValues is used to keep track of the redemption values
    /// for a single Kasa in the redemption loop
    struct RedemptionValues has drop {
        collateral_amount: u64,
        debt_amount: u64,
        cancelled_partial: bool,
    }

    // =================== Events ===================

    struct KasaCreated has copy, drop {
        account_address: address,
        collateral_amount: u64,
        debt_amount: u64
    }

    struct LiquidationEvent has copy, drop {
        collateral_reward: u64,
        debt_offset: u64,
        collateral_redistributed: u64,
        debt_redistributed: u64,
    }

    // =================== Initializer ===================

    fun init(witness: KASA_MANAGER, ctx: &mut TxContext) {
        transfer::share_object(KasaManagerPublisher {
            id: object::new(ctx),
            publisher: package::claim<KASA_MANAGER>(witness, ctx)
        });
    }

    // =================== Friend Methods ===================

    /// Creates a new Kasa for a user
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the address of the user
    /// * `collateral` - the collateral coin object
    /// * `debt_amount` - the amount of debt to mint
    public(friend) fun create_kasa(
        km_publisher: &KasaManagerPublisher,
        km_storage: &mut KasaManagerStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        account_address: address,
        collateral: Coin<SUI>,
        debt_amount: u64,
        ctx: &mut TxContext
    ) { 
        // Get the collateral amount and balance from the coin object
        let collateral_amount = coin::value<SUI>(&collateral);
        let collateral_balance = coin::into_balance<SUI>(collateral);

        // Mint the rUSD to the user
        let stable_coin = rusd_stable_coin::mint(
            rsc_storage,
            get_publisher(km_publisher),
            account_address,
            debt_amount,
            ctx
        );
        let stable_coin_amount = coin::value(&stable_coin);

        // Create Kasa object
        kasa_storage::create_kasa(
            km_storage,
            account_address,
            collateral_amount,
            debt_amount
        );

        // Update the total collateral balance of the protocol
        kasa_storage::increase_total_collateral_balance(km_storage, collateral_balance);
        // Update the total debt balance of the protocol
        kasa_storage::increase_total_debt_balance(km_storage, stable_coin_amount);

        // Transfer the stable coin to the user
        transfer::public_transfer(stable_coin, account_address);

        // Emit event
        event::emit(KasaCreated {
            account_address,
            collateral_amount,
            debt_amount
        })
    }

    /// Increases the collateral amount of a Kasa
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the address of the user
    /// * `collateral` - the collateral coin object
    public(friend) fun increase_collateral(
        km_storage: &mut KasaManagerStorage,
        account_address: address,
        collateral: Coin<SUI>
    ) {
        // TODO: Where do we transfer the collateral to?
        let amount = coin::value<SUI>(&collateral);

        // Update Kasa object
        kasa_storage::increase_kasa_collateral_amount(km_storage, account_address, amount);

        // Update total collateral balance of the protocol
        kasa_storage::increase_total_collateral_balance(km_storage, coin::into_balance<SUI>(collateral));
    }
    
    /// Decreases the collateral amount of a Kasa
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the address of the user
    /// * `amount` - the amount of collateral to decrease
    public(friend) fun decrease_collateral(
        km_storage: &mut KasaManagerStorage,
        account_address: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        // Update Kasa object
        kasa_storage::decrease_kasa_collateral_amount(km_storage, account_address, amount);

        // Update total collateral balance of the protocol
        let collateral = kasa_storage::decrease_total_collateral_balance(km_storage, amount, ctx);

        // Transfer the collateral back to the user
        transfer::public_transfer(collateral, account_address);
    }

    /// Increases the debt amount of a Kasa
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the address of the user
    /// * `amount` - the amount of debt to increase
    public(friend) fun increase_debt(
        km_publisher: &KasaManagerPublisher,
        km_storage: &mut KasaManagerStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        account_address: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        // Mint the rUSD to the user
        let rusd = rusd_stable_coin::mint(
            rsc_storage,
            get_publisher(km_publisher),
            account_address,
            amount,
            ctx
        );
        transfer::public_transfer(rusd, account_address);

        // Update the Kasa object
        kasa_storage::increase_kasa_debt_amount(km_storage, account_address, amount);

        // Update the total debt balance of the protocol
        kasa_storage::increase_total_debt_balance(km_storage, amount);
    }

    /// Decreases the debt amount of a Kasa
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the address of the user
    /// * `stable_coin` - the stable coin object
    public(friend) fun decrease_debt(
        km_publisher: &KasaManagerPublisher,
        km_storage: &mut KasaManagerStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        account_address: address,
        stable_coin: Coin<RUSD_STABLE_COIN>
    ) {
        let amount = coin::value(&stable_coin);

        // Update the Kasa object
        kasa_storage::decrease_kasa_debt_amount(km_storage, account_address, amount);

        // Update the total debt balance of the protocol
        kasa_storage::decrease_total_debt_balance(km_storage, amount);

        // Burn the rUSD from the user
        rusd_stable_coin::burn(
            rsc_storage,
            get_publisher(km_publisher),
            account_address,
            stable_coin
        );
    }
    
    // =================== Public Methods ===================

    /// Liquidates a list of Kasas that are below the minimum collateral ratio
    /// 
    /// # Arguments
    /// 
    /// All of the arguments are storage objects
    public fun liquidate(
        km_publisher: &KasaManagerPublisher,
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        sp_storage: &mut StabilityPoolStorage,
        collateral_gains: &mut CollateralGains,
        rsc_storage: &mut RUSDStableCoinStorage,
        ctx: &mut TxContext
    ) {
        // TODO: Take a look at the stake logic - what does it do?

        let collateral_price = 1600_000000000; // FIXME: Change this to the actual price

        let stability_pool_stake_amount = stability_pool::get_total_stake_amount(sp_storage);
        // TODO: Uncomment this later
        // let recovery_mode_at_start = check_recovery_mode(km_storage, collateral_price);
        let recovery_mode_at_start = false;

        // Initializing the liquidation totals for the loop
        let liquidation_totals = LiquidationTotals {
            collateral_in_sequence: 0,
            debt_in_sequence: 0,
            debt_to_offset: 0,
            collateral_to_send_to_stability_pool: 0,
            collateral_to_redistribute: 0,
            debt_to_redistribute: 0,
            collateral_surplus: 0,
        };

        // Recovery mode and normal mode are different in terms of liquidation
        if (recovery_mode_at_start) {
            // TODO: Need to implement this
        } else process_liquidations_normal_mode(
            km_publisher,
            km_storage,
            sk_storage,
            sp_storage,
            collateral_gains,
            rsc_storage,
            &mut liquidation_totals,
            stability_pool_stake_amount,
            collateral_price,
            ctx
        );

        assert!(liquidation_totals.debt_in_sequence > 0, ERROR_UNABLE_TO_LIQUIDATE);

        // TODO: call this method if needed - need to be implemented
        // redistribute_collateral_and_debt()

        if (liquidation_totals.collateral_surplus > 0) {
            // TODO: Write this logic later on
            // Send the surplus collateral to asset distributor
        };

        // Send the liquidation event
        event::emit(LiquidationEvent {
            collateral_reward: liquidation_totals.collateral_to_send_to_stability_pool,
            debt_offset: liquidation_totals.debt_to_offset,
            collateral_redistributed: liquidation_totals.collateral_to_redistribute,
            debt_redistributed: liquidation_totals.debt_to_redistribute,
        })
    }

    /// Redeems RUSD stable coins for collateral from Kasas
    /// Kasas can be partially or fully redeemed based on the stable coin amount
    /// 
    /// # Arguments
    /// 
    /// * `stable_coin` - the stable coin object to redeem
    /// * `first_redemption_hint` - the address of the first Kasa to redeem from
    /// * `upper_partial_redemption_hint` - the hint for Kasa reinsertion to sorted kasas
    /// * `lower_partial_redemption_hint` - the hint for Kasa reinsertion to sorted kasas
    /// * `partial_redemption_hint_nicr` - the nominal collateral ratio of the Kasa to reinsert
    public fun redeem(
        km_publisher: &KasaManagerPublisher,
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        liquidation_snapshots: &LiquidationSnapshots,
        stable_coin: Coin<RUSD_STABLE_COIN>,
        first_redemption_hint: Option<address>,
        upper_partial_redemption_hint: Option<address>,
        lower_partial_redemption_hint: Option<address>,
        partial_redemption_hint_nicr: u256,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);
        let stable_coin_amount = coin::value(&stable_coin);

        // TODO: Require max valid fee percentage -> IMPLEMENT FEES
        // TODO: Disable this method for 14 days after release

        let collateral_price = 1800_000000000; // FIXME: Change this to the actual price

        let user_stable_coin_balance = rusd_stable_coin::get_balance(rsc_storage, account_address);

        // Total collateral ratio must be over minimum collateral ratio
        assert!(kasa_storage::is_tcr_over_threshold(km_storage, collateral_price), ERROR_UNABLE_TO_REDEEM);
        // Stable coin amount must be over 0
        assert!(stable_coin_amount > 0, ERROR_UNABLE_TO_REDEEM);
        // User's stable coin balance must be over the redeemed stable coin amount
        assert!(
            user_stable_coin_balance >= stable_coin_amount,
            ERROR_UNABLE_TO_REDEEM
        );

        let (_, total_debt_amount) = kasa_storage::get_total_balances(km_storage);
        // User's stable coin balance must be less than the total debt amount
        assert!(user_stable_coin_balance <= total_debt_amount, ERROR_UNABLE_TO_REDEEM); // FIXME: Find a better error code

        let remaining_stable_coin_amount = stable_coin_amount;
        let total_redeemed_collateral = coin::zero<SUI>(ctx);
        let current_kasa_owner: Option<address>;

        // Check if the first redemption hint is valid
        // Meaning we do not need to iterate through all Kasas to find the first one
        if (
            check_first_redemption_hint(
                km_storage,
                sk_storage,
                first_redemption_hint,
                collateral_price
            )
        ) {
            current_kasa_owner = first_redemption_hint;
        } else {
            current_kasa_owner = sorted_kasas::get_last(sk_storage);
            // Find the first trove with ICR >= MCR
            while (
                option::is_some(&current_kasa_owner) &&
                kasa_storage::get_collateral_ratio(
                    km_storage,
                    option::destroy_some(current_kasa_owner),
                    collateral_price
                ) < get_minimum_collateral_ratio()
            ) {
                current_kasa_owner = sorted_kasas::get_prev(
                    sk_storage,
                    option::destroy_some(current_kasa_owner)
                );
            };
        };

        // TODO: Implement max iterations?
        while (option::is_some(&current_kasa_owner) && remaining_stable_coin_amount > 0) {
            // max_iterations = max_iterations - 1;
            let next_kasa_owner = sorted_kasas::get_prev(
                sk_storage,
                option::destroy_some(current_kasa_owner)
            );

            // TODO: Apply pending rewards here
            // Rewards include the redistribution of kasas

            // Process the redemption for the current Kasa
            // This method will return the collateral and debt amounts to redeem
            // If the redemption is partial and cannot continue it will break the loop
            let redemption_values = redeem_collateral_from_kasa(
                km_storage,
                sk_storage,
                liquidation_snapshots,
                option::destroy_some(current_kasa_owner),
                remaining_stable_coin_amount,
                collateral_price,
                upper_partial_redemption_hint,
                lower_partial_redemption_hint,
                partial_redemption_hint_nicr,
            );
            if (redemption_values.cancelled_partial) break;            

            // Decrease the total collateral balance of the protocol
            let kasa_collateral 
                = kasa_storage::decrease_total_collateral_balance(km_storage, redemption_values.collateral_amount, ctx);

            // Add the redeemed collateral to the total redeemed collateral
            coin::join(&mut total_redeemed_collateral, kasa_collateral);

            remaining_stable_coin_amount = remaining_stable_coin_amount - redemption_values.debt_amount;
            current_kasa_owner = next_kasa_owner;
        };

        // If there is not enough collateral to redeem the stable coins
        assert!(coin::value(&total_redeemed_collateral) > 0, ERROR_UNABLE_TO_REDEEM);

        // Calculate the fee - %0.05 -> 5 / 1000
        // Extract it from the total collateral amount
        let redeem_fee_amount = mul_div(coin::value(&total_redeemed_collateral), 5, 1000);

        // Burn the redeemed stable coin
        rusd_stable_coin::burn(
            rsc_storage,
            get_publisher(km_publisher),
            account_address,
            stable_coin
        );

        // Remove the redeem fee from total redeemed collateral
        // This coin will have the redeem fee amount
        let redeem_fee_coin = coin::split(&mut total_redeemed_collateral, redeem_fee_amount, ctx);
        // Send the redeem fee to EMBD staking contract
        transfer::public_transfer(
            redeem_fee_coin,
            @0xbee // FIXME: This will be the EMBD staking contract
        );
        // Send the collateral to the sender
        // total_redeemed_collateral will have the remaining collateral amount after the fee deduction
        transfer::public_transfer(
            total_redeemed_collateral,
            account_address
        );
    }

    // =================== Helpers ===================

    /// Processes the liquidations in normal mode
    /// Loops through the Kasas and liquidates them
    /// Decreases the total debt and collateral balances of the protocol
    /// Sends the collateral to the stability pool if needed
    /// Burns the stable coin if needed
    fun process_liquidations_normal_mode(
        km_publisher: &KasaManagerPublisher,
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        sp_storage: &mut StabilityPoolStorage,
        collateral_gains: &mut CollateralGains,
        rsc_storage: &mut RUSDStableCoinStorage,
        liquidation_totals: &mut LiquidationTotals,
        stability_pool_stake_amount: u64,
        collateral_price: u64,
        ctx: &mut TxContext
    ) {
        // Saving the remaining amount for decreasing with each liquidation
        let remaining_stability_pool_stake = stability_pool_stake_amount;

        loop {
            // Get the account address from the sorted kasas storage
            let account_address = sorted_kasas::get_last(sk_storage);
            // Make the account address is not none
            // TODO: Check if this is correct - if the code breaks that means there is no more Kasas
            // TODO: Should we liquidate ALL of them??
            if (option::is_none(&account_address)) break;
            let account_address = option::destroy_some(account_address);

            let collateral_ratio = get_collateral_ratio(km_storage, account_address, collateral_price);

            if (collateral_ratio < get_minimum_collateral_ratio()) {
                // Initializing the liquidation values for the single liquidation
                // This will be used to keep track of the liquidation values for a single Kasa
                let single_liquidation = LiquidationValues {
                    kasa_collateral_amount: 0,
                    kasa_debt_amount: 0,
                    collateral_to_send_to_stability_pool: 0,
                    debt_to_offset: 0,
                    collateral_to_redistribute: 0,
                    debt_to_redistribute: 0,
                    collateral_surplus: 0,
                };

                // Updates the liquidation values
                liquidate_normal_mode(
                    km_storage,
                    sk_storage,
                    &mut single_liquidation,
                    account_address,
                    remaining_stability_pool_stake
                );

                // Kasa is liquidated - decrease the remaining stability pool stake
                remaining_stability_pool_stake = remaining_stability_pool_stake - single_liquidation.debt_to_offset;

                // Stability pool will be able to cover the debt
                if (single_liquidation.collateral_to_send_to_stability_pool > 0) {
                    // Decrease the total debt balance of the protocol
                    kasa_storage::decrease_total_debt_balance(
                        km_storage,
                        single_liquidation.debt_to_offset,
                    );
                    // Decrease the collateral balance of the protocol
                    let collateral_coin = kasa_storage::decrease_total_collateral_balance(
                        km_storage,
                        single_liquidation.collateral_to_send_to_stability_pool,
                        ctx
                    );
                    // Decrease the stability pool balance
                    let stable_coin = stability_pool::liquidation(
                        sp_storage,
                        collateral_gains,
                        collateral_coin,
                        single_liquidation.debt_to_offset,
                        ctx
                    );
                    // Burn the stable coin
                    rusd_stable_coin::burn(
                        rsc_storage,
                        get_publisher(km_publisher),
                        account_address,
                        stable_coin
                    );
                };

                // Update the liquidation totals
                update_liquidation_totals(
                    liquidation_totals,
                    single_liquidation,
                );
            } else break;
        }
    }

    /// Liquidates a single Kasa in normal mode
    /// Populates the liquidation values and closes the Kasa
    fun liquidate_normal_mode(
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        liquidation_values: &mut LiquidationValues,
        account_address: address,
        stability_pool_stake_amount: u64
    ) {
        // TODO: We need to add pending rewards to the calculation
        let (
            kasa_collateral_amount,
            kasa_debt_amount
        ) = kasa_storage::get_kasa_amounts(km_storage, account_address);

        // TODO: We can call this method to apply pending rewards
        // apply_pending_rewards()

        kasa_storage::remove_kasa_stake(km_storage, account_address);

        let (
            collateral_to_send_to_stability_pool,
            debt_to_offset,
            collateral_to_redistribute,
            debt_to_redistribute
        ) = get_offset_and_redistribution_values(
            kasa_collateral_amount,
            kasa_debt_amount,
            stability_pool_stake_amount,
        );

        // Remove the Kasa from storages
        close_kasa(km_storage, sk_storage, account_address);
        
        liquidation_values.kasa_collateral_amount = kasa_collateral_amount;
        liquidation_values.kasa_debt_amount = kasa_debt_amount;
        liquidation_values.collateral_to_send_to_stability_pool = collateral_to_send_to_stability_pool;
        liquidation_values.debt_to_offset = debt_to_offset;
        liquidation_values.collateral_to_redistribute = collateral_to_redistribute;
        liquidation_values.debt_to_redistribute = debt_to_redistribute;
        liquidation_values.collateral_surplus = 0; // TODO: What do we put in here?
    }

    /// Returns the offset and redistribution values during liquidation
    /// 
    /// # Arguments
    /// 
    /// * `collateral_amount` - the amount of collateral in the Kasa
    /// * `debt_amount` - the amount of debt in the Kasa
    /// * `stability_pool_stake_amount` - the amount of debt in the stability pool
    /// 
    /// # Returns
    /// 
    /// * `collateral_to_send_to_stability_pool` - the amount of collateral to send to the stability pool
    /// * `debt_to_offset` - the amount of debt to offset from the stability pool
    /// * `collateral_to_redistribute` - the amount of collateral to redistribute to the Kasas
    /// * `debt_to_redistribute` - the amount of debt to redistribute to the Kasas
    fun get_offset_and_redistribution_values(
        collateral_amount: u64,
        debt_amount: u64,
        stability_pool_stake_amount: u64,
    ): (u64, u64, u64, u64) {
        if (stability_pool_stake_amount > 0) {
            let debt_to_offset = min(debt_amount, stability_pool_stake_amount);
            let collateral_to_send_to_stability_pool = mul_div(collateral_amount, debt_to_offset, debt_amount);
            let debt_to_redistribute = debt_amount - debt_to_offset;
            let collateral_to_redistribute = collateral_amount - collateral_to_send_to_stability_pool;
            (
                collateral_to_send_to_stability_pool,
                debt_to_offset,
                collateral_to_redistribute,
                debt_to_redistribute
            )
        } else (0, 0, collateral_amount, debt_amount)
    }

    /// Updates the liquidation totals with the values from a single liquidation
    fun update_liquidation_totals(
        liquidation_totals: &mut LiquidationTotals,
        single_liquidation: LiquidationValues
    ) {
        liquidation_totals.collateral_in_sequence =
            liquidation_totals.collateral_in_sequence + single_liquidation.kasa_collateral_amount;
        liquidation_totals.debt_in_sequence =
            liquidation_totals.debt_in_sequence + single_liquidation.kasa_debt_amount;
        liquidation_totals.collateral_to_send_to_stability_pool =
            liquidation_totals.collateral_to_send_to_stability_pool + single_liquidation.collateral_to_send_to_stability_pool;
        liquidation_totals.debt_to_offset =
            liquidation_totals.debt_to_offset + single_liquidation.debt_to_offset;
        liquidation_totals.collateral_to_redistribute =
            liquidation_totals.collateral_to_redistribute + single_liquidation.collateral_to_redistribute;
        liquidation_totals.debt_to_redistribute =
            liquidation_totals.debt_to_redistribute + single_liquidation.debt_to_redistribute;
        liquidation_totals.collateral_surplus =
            liquidation_totals.collateral_surplus + single_liquidation.collateral_surplus;
    }

    /// Checks if the first redemption hint is valid or not
    /// 
    /// # Arguments
    /// 
    /// * `hint` - the address of the first Kasa to redeem from
    /// * `collateral_price` - the price of the collateral
    /// 
    /// # Returns
    /// 
    /// * `bool` true if the hint is valid
    fun check_first_redemption_hint(
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        hint: Option<address>,
        collateral_price: u64,
    ): bool {
        if (
            option::is_none(&hint) ||
            !sorted_kasas::contains(sk_storage, option::destroy_some(hint)) ||
            kasa_storage::get_collateral_ratio(
                km_storage,
                option::destroy_some(hint),
                collateral_price
            ) < get_minimum_collateral_ratio()
        ) {
            return false
        };
        
        let next_kasa = sorted_kasas::get_next(sk_storage, option::destroy_some(hint));
        return option::is_none(&next_kasa) || kasa_storage::get_collateral_ratio(
            km_storage,
            option::destroy_some(next_kasa),
            collateral_price
        ) < get_minimum_collateral_ratio()
    }

    /// Redeems as much collateral as possible from the Kasa in exchange for
    /// stable coin up to max stable coin amount
    /// 
    /// # Arguments
    /// 
    /// * `current_kasa_owner` - the address of the Kasa owner
    /// * `max_stable_coin_amount` - the maximum amount of stable coin to redeem
    /// * `collateral_price` - the price of the collateral
    /// * `upper_partial_redemption_hint` - the hint for Kasa reinsertion to sorted kasas
    /// * `lower_partial_redemption_hint` - the hint for Kasa reinsertion to sorted kasas
    /// * `partial_redemption_hint_nicr` - the nominal collateral ratio of the Kasa to reinsert
    fun redeem_collateral_from_kasa(
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        liquidation_snapshots: &LiquidationSnapshots,
        current_kasa_owner: address,
        max_stable_coin_amount: u64,
        collateral_price: u64,
        upper_partial_redemption_hint: Option<address>,
        lower_partial_redemption_hint: Option<address>,
        partial_redemption_hint_nicr: u256,
    ): RedemptionValues {
        let redemption_values = RedemptionValues {
            collateral_amount: 0,
            debt_amount: 0,
            cancelled_partial: false,
        };

        let (kasa_collateral_amount, kasa_debt_amount) = kasa_storage::get_kasa_amounts(km_storage, current_kasa_owner);

        // Stable coin amount to redeem from Kasa
        redemption_values.debt_amount = min(max_stable_coin_amount, kasa_debt_amount);
        // Collateral amount to redeem from Kasa
        redemption_values.collateral_amount = mul_div(redemption_values.debt_amount, (scalar() as u64), collateral_price);

        let new_collateral = kasa_collateral_amount - redemption_values.collateral_amount;
        let new_debt = kasa_debt_amount - redemption_values.debt_amount;

        // All the debt in the Kasa is redeemed
        // Kasa will be closed and removed from the sorted kasas
        if (new_debt == 0) {
            // Decrease the total debt balance of the protocol
            kasa_storage::decrease_total_debt_balance(km_storage, kasa_debt_amount);
            // TODO: Send the surplus collateral to asset distributor
            // new_collateral will be passed
            kasa_storage::remove_kasa_stake(km_storage, current_kasa_owner);
            close_kasa(km_storage, sk_storage, current_kasa_owner);
        } else {
            let new_nicr = calculate_nominal_collateral_ratio(new_collateral, new_debt);

            // If the provided hint is out of date, we bail since trying to reinsert without a good hint will almost
            // certainly result in running out of gas
            // If the resultant net debt of the partial is less than the minimum net debt we bail
            if (
                new_nicr != partial_redemption_hint_nicr ||
                (new_debt as u256) < get_minimum_net_debt()
            ) {
                redemption_values.cancelled_partial = true;
                return redemption_values
            };

            sorted_kasas::reinsert(
                km_storage,
                sk_storage,
                current_kasa_owner,
                new_nicr,
                upper_partial_redemption_hint,
                lower_partial_redemption_hint
            );

            kasa_storage::decrease_kasa_collateral_amount(
                km_storage,
                current_kasa_owner,
                redemption_values.collateral_amount
            );
            kasa_storage::decrease_kasa_debt_amount(km_storage, current_kasa_owner, redemption_values.debt_amount);
            kasa_storage::update_stake_and_total_stakes(km_storage, liquidation_snapshots,current_kasa_owner);
        };

        redemption_values
    }

    /// Removes the Kasa from manager and sorted kasas storages
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the address of the user
    fun close_kasa(
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        account_address: address
    ) {
        assert!(kasa_storage::get_kasa_count(km_storage) > 1, ERROR_SINGLE_KASA_LEFT);
        kasa_storage::remove_kasa(km_storage, account_address);
        sorted_kasas::remove(sk_storage, account_address);
    }

    fun get_publisher(storage: &KasaManagerPublisher): &Publisher {
        &storage.publisher
    }

    #[test_only]
    public fun get_publisher_id(publisher: &KasaManagerPublisher): ID {
        object::id(&publisher.publisher)
    }

    #[test_only]
    #[allow(unused_assignment)]
    public fun get_redemption_hints(
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        amount: u64,
        price: u64,
        _max_iterations: u64
    ): (Option<address>, u256, u64) {
        let first_redemption_hint: Option<address>;
        let partial_redemption_hint_nicr: u256 = 0;
        let truncated_stable_coin_amount: u64 = 0;

        let remaining_stable_coin_amount = amount;
        let current_kasa_owner = sorted_kasas::get_last(sk_storage);

        while (
            option::is_some(&current_kasa_owner) &&
            kasa_storage::get_collateral_ratio(
                km_storage,
                option::destroy_some(current_kasa_owner),
                price
            ) < get_minimum_collateral_ratio()
        ) {
            current_kasa_owner = sorted_kasas::get_prev(sk_storage, option::destroy_some(current_kasa_owner));
        };

        first_redemption_hint = current_kasa_owner;

        while (
            option::is_some(&current_kasa_owner) &&
            remaining_stable_coin_amount > 0
        ) {
            let (kasa_collateral_amount, kasa_debt_amount) = kasa_storage::get_kasa_amounts(
                km_storage,
                option::destroy_some(current_kasa_owner)
            );
            let net_debt = kasa_debt_amount;

            if (net_debt > remaining_stable_coin_amount) {
                if ((net_debt as u256) > get_minimum_net_debt()) {
                    let max_redeemedable_stable_coin = min(
                        remaining_stable_coin_amount,
                        ((net_debt as u256) - get_minimum_net_debt() as u64)
                    );

                    let new_collateral = kasa_collateral_amount - mul_div(
                        max_redeemedable_stable_coin, (scalar() as u64), price
                    );
                    let new_debt = net_debt - max_redeemedable_stable_coin;

                    partial_redemption_hint_nicr = calculate_nominal_collateral_ratio(
                        new_collateral,
                        new_debt
                    );

                    remaining_stable_coin_amount = remaining_stable_coin_amount - max_redeemedable_stable_coin;
                };
                break
            } else {
                remaining_stable_coin_amount = remaining_stable_coin_amount - net_debt;
            };

            current_kasa_owner = sorted_kasas::get_prev(sk_storage, option::destroy_some(current_kasa_owner));
        };

        truncated_stable_coin_amount = amount - remaining_stable_coin_amount;

        (first_redemption_hint, partial_redemption_hint_nicr, truncated_stable_coin_amount)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(KASA_MANAGER {}, ctx);
    }
}