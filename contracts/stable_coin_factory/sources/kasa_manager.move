module stable_coin_factory::kasa_manager {
    use std::option::{Self, Option};

    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::package::{Self, Publisher};

    use stable_coin_factory::kasa_storage::{Self, KasaManagerStorage, get_collateral_ratio};
    use stable_coin_factory::stability_pool::{Self, StabilityPoolStorage};
    use stable_coin_factory::liquidation_assets_distributor::CollateralGains;
    use stable_coin_factory::sorted_kasas::{Self, SortedKasasStorage};
    use tokens::rusd_stable_coin::{Self, RUSD_STABLE_COIN, RUSDStableCoinStorage};
    use library::kasa::get_minimum_collateral_ratio;
    use library::math::{min, mul_div};
    // use library::utils::logger;

    friend stable_coin_factory::kasa_operations;

    const COLLATERAL_PRICE: u64 = 1800_000000000;

    // =================== Errors ===================

    const ERROR_LIST_FULL: u64 = 1;
    const ERROR_EXISTING_ITEM: u64 = 2;
    const ERROR_: u64 = 3;
    const ERROR_UNABLE_TO_REDEEM: u64 = 4;
    const ERROR_UNABLE_TO_LIQUIDATE: u64 = 5;

    // =================== Storage ===================

    /// OTW for Kasa Manager
    struct KASA_MANAGER has drop {}

    /// Defines the data structure for saving the publisher
    struct KasaManagerPublisher has key {
        id: UID,
        publisher: Publisher
    }

    struct LiquidationTotals has drop {
        collateral_in_sequence: u64,
        debt_in_sequence: u64,
        collateral_to_send_to_stability_pool: u64,
        debt_to_offset: u64,
        collateral_to_redistribute: u64,
        debt_to_redistribute: u64,
        collateral_surplus: u64,
    }

    struct LiquidationValues has drop {
        kasa_collateral_amount: u64,
        kasa_debt_amount: u64,
        collateral_to_send_to_stability_pool: u64,
        debt_to_offset: u64,
        collateral_to_redistribute: u64,
        debt_to_redistribute: u64,
        collateral_surplus: u64,
    }

    // =================== Events ===================

    /// Defines the event for when a Kasa is created
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

    // =================== Entries ===================

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

    public(friend) fun decrease_debt(
        km_publisher: &KasaManagerPublisher,
        km_storage: &mut KasaManagerStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        account_address: address,
        debt_coin: Coin<RUSD_STABLE_COIN>
    ) {
        let amount = coin::value(&debt_coin);

        // Update the Kasa object
        kasa_storage::decrease_kasa_debt_amount(km_storage, account_address, amount);

        // Update the total debt balance of the protocol
        kasa_storage::decrease_total_debt_balance(km_storage, amount);

        // Burn the rUSD from the user
        rusd_stable_coin::burn(
            rsc_storage,
            get_publisher(km_publisher),
            account_address,
            debt_coin
        );
    }
    
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

    /// Redeems RUSD stable coins for collateral
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `rusd_stable_coin_storage` - the RUSDStableCoinStorage object
    /// * `amount` - the amount of RUSD stable coins to redeem
    public fun redeem(
        km_publisher: &KasaManagerPublisher,
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        stable_coin: Coin<RUSD_STABLE_COIN>,
        first_redemption_hint: Option<address>,
        _upper_partial_redemption_hint: Option<address>,
        _lower_partial_redemption_hint: Option<address>,
        _partial_redemption_hint_nicr: u256,
        ctx: &mut TxContext
    ) {
        let stable_coin_amount = coin::value(&stable_coin);

        // TODO: Disable this method for 14 days after release
        // TODO: IF TCR < 110% throw error
        // TODO: Do not redeem Kasas with ICR < MCR => ICR must be >= to 110%
        // TODO: Check the actual code and fork the assert statements

        let (_, _total_debt_amount) = kasa_storage::get_total_balances(km_storage);

        let (_, _sender_debt_amount) = kasa_storage::get_kasa_amounts(
            km_storage,
            tx_context::sender(ctx)
        );
        let user_stable_coin_balance = rusd_stable_coin::get_balance(rsc_storage, tx_context::sender(ctx));
        assert!(user_stable_coin_balance <= stable_coin_amount, ERROR_); // FIXME: Find a better error code

        let remaining_stable_coin_amount = coin::value(&stable_coin);
        let total_debt_to_decrease = coin::zero<RUSD_STABLE_COIN>(ctx);
        let total_collateral_to_send = coin::zero<SUI>(ctx);
        let current_kasa_owner: Option<address>;

        if (check_first_redemption_hint(sk_storage, first_redemption_hint, 0)) { // FIXME: Change the collateral price
            current_kasa_owner = first_redemption_hint;
        } else {
            current_kasa_owner = sorted_kasas::get_last(sk_storage);
            // Find the first trove with ICR >= MCR
            while (
                option::is_some(&current_kasa_owner) &&
                kasa_storage::get_collateral_ratio(
                    km_storage,
                    option::destroy_some(current_kasa_owner),
                    COLLATERAL_PRICE
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

            // TODO: Remove collateral from kasa method
            // We will get the amount of collateral and debt to decrease
            let redemption_collateral_amount = coin::zero<SUI>(ctx); // FIXME: This will come from the redemption method
            let redemption_debt_amount = coin::zero<RUSD_STABLE_COIN>(ctx); // FIXME: Same as above

            remaining_stable_coin_amount = remaining_stable_coin_amount - coin::value(&redemption_debt_amount);
            current_kasa_owner = next_kasa_owner;

            coin::join(&mut total_collateral_to_send, redemption_collateral_amount);
            coin::join(&mut total_debt_to_decrease, redemption_debt_amount);
        };

        assert!(coin::value(&total_collateral_to_send) > 0, ERROR_UNABLE_TO_REDEEM);

        // TODO: Calculate the fee
        // Extract it from the total collateral amount

        // Decrease the total debt balance of the protocol
        kasa_storage::decrease_total_debt_balance(km_storage, coin::value(&total_debt_to_decrease));
        // Burn the rUSD tokens
        rusd_stable_coin::burn(
            rsc_storage,
            get_publisher(km_publisher),
            tx_context::sender(ctx), // FIXME: This is incorrect
            stable_coin
        );
        rusd_stable_coin::burn(
            rsc_storage,
            get_publisher(km_publisher),
            tx_context::sender(ctx), // FIXME: This is incorrect
            total_debt_to_decrease
        );
        // Send the collateral to the sender
        transfer::public_transfer(
            total_collateral_to_send,
            tx_context::sender(ctx)
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
                let single_liquidation = LiquidationValues {
                    kasa_collateral_amount: 0,
                    kasa_debt_amount: 0,
                    collateral_to_send_to_stability_pool: 0,
                    debt_to_offset: 0,
                    collateral_to_redistribute: 0,
                    debt_to_redistribute: 0,
                    collateral_surplus: 0,
                };

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

        // TODO: Call close_kasa method in here
        kasa_storage::remove_kasa(km_storage, account_address);
        sorted_kasas::remove(sk_storage, account_address);
        
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

    fun check_first_redemption_hint(
        _sorted_kasas_storage: &mut SortedKasasStorage,
        _hint: Option<address>,
        _collateral_price: u64,
    ): bool {
        // TODO: Implement this method
        false
    }
    
    fun get_publisher(storage: &KasaManagerPublisher): &Publisher {
        &storage.publisher
    }

    #[test_only]
    public fun get_publisher_id(publisher: &KasaManagerPublisher): ID {
        object::id(&publisher.publisher)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(KASA_MANAGER {}, ctx);
    }
}