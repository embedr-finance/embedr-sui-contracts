module stable_coin_factory::kasa_manager {
    use std::vector;

    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{TxContext};
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};
    use sui::package::{Self, Publisher};

    use stable_coin_factory::stability_pool::{Self, StabilityPoolStorage};
    use stable_coin_factory::liquidation_assets_distributor::CollateralGains;
    use tokens::rusd_stable_coin::{Self, RUSD_STABLE_COIN, RUSDStableCoinStorage};
    use library::kasa::is_icr_valid;
    // use library::utils::logger;

    friend stable_coin_factory::kasa_operations;

    /// OTW for Kasa Manager
    struct KASA_MANAGER has drop {}

    /// Defines the data structure for a Kasa
    /// 
    /// Kasa is user's position in the Stable Coin Factory
    /// 
    /// # Fields
    /// 
    /// * `collateral_amount` - the amount of collateral the user has deposited
    /// * `debt_amount` - the amount of debt the user has borrowed
    struct Kasa has store, drop {
        collateral_amount: u64,
        debt_amount: u64
    }

    /// Storage for the KasaManager module
    /// 
    /// # Fields
    /// 
    /// * `collateral_balance` - total collateral balance of the protocol
    /// * `debt_balance` - total debt balance of the protocol
    struct KasaManagerStorage has key {
        id: UID,
        kasa_table: Table<address, Kasa>,
        collateral_balance: Balance<SUI>,
        debt_balance: u64,
        publisher: Publisher
    }

    // =================== Events ===================

    /// Defines the event for when a Kasa is created
    struct KasaCreated has copy, drop {
        account_address: address,
        collateral_amount: u64,
        debt_amount: u64
    }

    // =================== Initializer ===================

    /// Initializes the module
    fun init(witness: KASA_MANAGER, ctx: &mut TxContext) {
        transfer::share_object(KasaManagerStorage {
            id: object::new(ctx),
            kasa_table: table::new(ctx),
            collateral_balance: balance::zero(),
            debt_balance: 0,
            publisher: package::claim<KASA_MANAGER>(witness, ctx)
        });
    }

    // =================== Entries ===================

    /// Creates a new Kasa for the user
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the address of the Account module
    /// * `collateral_amount` - the amount of collateral the user has deposited
    /// * `loan_amount` - the amount of debt the user has borrowed
    public(friend) fun create_kasa(
        kasa_manager_storage: &mut KasaManagerStorage,
        rusd_stable_coin_storage: &mut RUSDStableCoinStorage,
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
            rusd_stable_coin_storage,
            &kasa_manager_storage.publisher,
            debt_amount,
            ctx
        );
        let stable_coin_amount = coin::value(&stable_coin);

        // Create a new Kasa object
        let kasa = Kasa {
            collateral_amount,
            debt_amount
        };

        // Add the Kasa object to the kasa_table
        table::add(&mut kasa_manager_storage.kasa_table, account_address, kasa);

        // Update the total collateral balance of the protocol
        balance::join(&mut kasa_manager_storage.collateral_balance, collateral_balance);
        // Update the total debt balance of the protocol
        kasa_manager_storage.debt_balance = kasa_manager_storage.debt_balance + stable_coin_amount;

        transfer::public_transfer(stable_coin, account_address);

        // Emit event
        event::emit(KasaCreated {
            account_address,
            collateral_amount,
            debt_amount
        })
    }

    /// Increases the collateral amount of the user
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `account_address` - the address of the Account module
    /// * `amount` - the amount to increase the collateral by
    public(friend) fun increase_collateral(kasa_manager_storage: &mut KasaManagerStorage, account_address: address, collateral: Coin<SUI>) {
        // TODO: Where do we transfer the collateral to?
        let amount = coin::value<SUI>(&collateral);

        // Update Kasa object
        let kasa = borrow_kasa(kasa_manager_storage, account_address);
        kasa.collateral_amount = kasa.collateral_amount + amount;

        // Update total collateral balance of the protocol
        coin::put(&mut kasa_manager_storage.collateral_balance, collateral);
    }
    
    /// Decreases the collateral amount of the user
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `account_address` - the address of the Account module
    /// * `amount` - the amount to decrease the collateral by
    public(friend) fun decrease_collateral(kasa_manager_storage: &mut KasaManagerStorage, account_address: address, amount: u64, ctx: &mut TxContext) {
        let kasa = borrow_kasa(kasa_manager_storage, account_address);
        kasa.collateral_amount = kasa.collateral_amount - amount;

        // Update total collateral balance of the protocol
        let collateral = coin::take(&mut kasa_manager_storage.collateral_balance, amount, ctx);

        // Transfer the collateral back to the user
        transfer::public_transfer(collateral, account_address);
    }
    
    /// Increases the debt amount of the user
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `account_address` - the address of the Account module
    /// * `amount` - the amount to increase the debt by
    public(friend) fun increase_debt(
        kasa_manager_storage: &mut KasaManagerStorage,
        rusd_stable_coin_storage: &mut RUSDStableCoinStorage,
        account_address: address,
        amount: u64,
        ctx: &mut TxContext
    ) {
        // Mint the rUSD to the user
        let rusd = rusd_stable_coin::mint(
            rusd_stable_coin_storage,
            &kasa_manager_storage.publisher,
            amount,
            ctx
        );
        transfer::public_transfer(rusd, account_address);

        // Update the Kasa object
        let kasa = borrow_kasa(kasa_manager_storage, account_address);
        kasa.debt_amount = kasa.debt_amount + amount;

        // Update the total debt balance of the protocol
        kasa_manager_storage.debt_balance = kasa_manager_storage.debt_balance + amount;
    }

    /// Decreases the debt amount of the user
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `account_address` - the address of the Account module
    /// * `amount` - the amount to decrease the debt by
    public(friend) fun decrease_debt(
        kasa_manager_storage: &mut KasaManagerStorage,
        rusd_stable_coin_storage: &mut RUSDStableCoinStorage,
        account_address: address,
        debt_coin: Coin<RUSD_STABLE_COIN>
    ) {
        let amount = coin::value(&debt_coin);

        let kasa = borrow_kasa(kasa_manager_storage, account_address);
        kasa.debt_amount = kasa.debt_amount - amount;

        // // Update the total debt balance of the protocol
        kasa_manager_storage.debt_balance = kasa_manager_storage.debt_balance - amount;

        // Burn the rUSD from the user
        rusd_stable_coin::burn(
            rusd_stable_coin_storage,
            &kasa_manager_storage.publisher,
            debt_coin
        );
    }
    
    /// Liquidates a single Kasa, processing rewards and burning the debt
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `stability_pool_storage` - the StabilityPoolStorage object
    /// * `collateral_gains` - the CollateralGains object
    /// * `rusd_stable_coin_storage` - the RUSDStableCoinStorage object
    /// * `account_address` - the address of the Account module
    entry public fun liquidate_single(
        kasa_manager_storage: &mut KasaManagerStorage,
        stability_pool_storage: &mut StabilityPoolStorage,
        collateral_gains: &mut CollateralGains,
        rusd_stable_coin_storage: &mut RUSDStableCoinStorage,
        account_address: address,
        ctx: &mut TxContext
    ) {
        let account_addresses = vector::empty<address>();
        vector::push_back(&mut account_addresses, account_address);

        liquidate_kasas(
            kasa_manager_storage,
            stability_pool_storage,
            collateral_gains,
            rusd_stable_coin_storage,
            account_addresses,
            ctx
        );
    }

    /// Same as `liquidate_single` but for multiple kasas
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `stability_pool_storage` - the StabilityPoolStorage object
    /// * `collateral_gains` - the CollateralGains object
    /// * `rusd_stable_coin_storage` - the RUSDStableCoinStorage object
    /// * `account_addresses` - the vector of account addresses
    entry public fun liquidate_batch(
        kasa_manager_storage: &mut KasaManagerStorage,
        stability_pool_storage: &mut StabilityPoolStorage,
        collateral_gains: &mut CollateralGains,
        rusd_stable_coin_storage: &mut RUSDStableCoinStorage,
        account_addresses: vector<address>,
        ctx: &mut TxContext
    ) {
        liquidate_kasas(
            kasa_manager_storage,
            stability_pool_storage,
            collateral_gains,
            rusd_stable_coin_storage,
            account_addresses,
            ctx
        );
    }

    // =================== Queries ===================

    /// Checks if there is a kasa with a specific account address
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `account_address` - the address of the Account module
    ///
    /// # Returns
    ///
    /// * `bool` - `true` if a kasa exists with the given account address, `false` otherwise
    public fun has_kasa(kasa_manager_storage: &KasaManagerStorage, account_address: address): bool {
        table::contains(&kasa_manager_storage.kasa_table, account_address)
    }

    /// Gets the collateral and debt amount for a Kasa
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `account_address` - the address of the Account module
    public fun get_kasa_amounts(kasa_manager_storage: &mut KasaManagerStorage, account_address: address): (u64, u64) {
        let kasa = borrow_kasa(kasa_manager_storage, account_address);
        (kasa.collateral_amount, kasa.debt_amount)
    }
    
    /// Gets the protocol balances from the KasaManagerStorage object.
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    ///
    /// # Returns
    ///
    /// * `(u64, u64)` - A tuple containing the collateral balance and debt balance of the protocol
    public fun get_protocol_balances(kasa_manager_storage: &KasaManagerStorage): (u64, u64) {
        (balance::value(&kasa_manager_storage.collateral_balance), kasa_manager_storage.debt_balance)
    }

    /// Gets the publisher ID from the KasaManagerStorage object.
    /// 
    /// # Arguments
    /// 
    /// * `storage` - the KasaManagerStorage object
    ///
    /// # Returns
    ///
    /// The ID of the publisher
    public fun get_publisher_id(storage: &KasaManagerStorage): ID {
        object::id(&storage.publisher)
    }

    // =================== Helpers ===================

    /// Liquidates all the kasas in the given vector
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `stability_pool_storage` - the StabilityPoolStorage object
    /// * `collateral_gains` - the CollateralGains object
    /// * `rusd_stable_coin_storage` - the RUSDStableCoinStorage object
    /// * `account_addresses` - the vector of account addresses
    fun liquidate_kasas(
        kasa_manager_storage: &mut KasaManagerStorage,
        stability_pool_storage: &mut StabilityPoolStorage,
        collateral_gains: &mut CollateralGains,
        rusd_stable_coin_storage: &mut RUSDStableCoinStorage,
        account_addresses: vector<address>,
        ctx: &mut TxContext
    ) {
        while (!vector::is_empty(&account_addresses)) {
            let account_address = vector::pop_back(&mut account_addresses);

            let kasa = read_kasa(kasa_manager_storage, account_address);

            // If the ICR is valid, return
            if (is_icr_valid(false, kasa.collateral_amount, kasa.debt_amount, 1600)) return;

            // Kasa to be liquidated
            let kasa = remove_kasa(kasa_manager_storage, account_address);

            // Get the total stake amount from the stability pool
            let stability_pool_stake_amount = stability_pool::get_total_stake_amount(stability_pool_storage);

            // If the stability pool has enough stake amount to cover the debt amount
            if (stability_pool_stake_amount >= kasa.debt_amount) {
                // Remove collateral from the collateral balance
                let collateral = coin::take(&mut kasa_manager_storage.collateral_balance, kasa.collateral_amount, ctx);

                // Decrease the stability pool balance
                let stable_coin = stability_pool::liquidation(
                    stability_pool_storage,
                    collateral_gains,
                    coin::value(&collateral),
                    kasa.debt_amount,
                    ctx
                );
                // Burn the stable coin
                tokens::rusd_stable_coin::burn(
                    rusd_stable_coin_storage,
                    &kasa_manager_storage.publisher,
                    stable_coin
                );

                // Decrease the debt balance of the protocol
                kasa_manager_storage.debt_balance = kasa_manager_storage.debt_balance - kasa.debt_amount;

                // TODO: Transfer the collateral to the liquidation assets distributor
                transfer::public_transfer(collateral, account_address); // FIXME: This is just for testing
            };
        };

        vector::destroy_empty(account_addresses);
    }

    /// Borrows the Kasa from the KasaManagerStorage
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `account_address` - the address of the Account module
    fun borrow_kasa(kasa_manager_store: &mut KasaManagerStorage, account_address: address): &mut Kasa {
        table::borrow_mut(&mut kasa_manager_store.kasa_table, account_address)
    }

    /// Reads the Kasa from the KasaManagerStorage
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `account_address` - the address of the Account module
    fun read_kasa(kasa_manager_store: &KasaManagerStorage, account_address: address): &Kasa {
        table::borrow(&kasa_manager_store.kasa_table, account_address)
    }

    fun remove_kasa(kasa_manager_store: &mut KasaManagerStorage, account_address: address): Kasa {
        table::remove(&mut kasa_manager_store.kasa_table, account_address)
    }
    
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(KASA_MANAGER {}, ctx);
    }
}