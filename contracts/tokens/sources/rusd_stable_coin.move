module tokens::rusd_stable_coin {
    use std::option;

    use sui::object::{Self, UID, ID};
    use sui::tx_context::{TxContext};
    use sui::balance::{Self, Supply};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::package::{Publisher};
    use sui::tx_context;
    use sui::vec_set::{Self, VecSet};
    use sui::table::{Self, Table};

    // =================== Errors ===================

    const ERROR_UNAUTHORIZED: u64 = 1;

    // =================== Storage ===================

    /// OTW to create the stable coin
    struct RUSD_STABLE_COIN has drop {}

    /// Shared object
    struct RUSDStableCoinStorage has key {
        id: UID,
        supply: Supply<RUSD_STABLE_COIN>,
        balances: Table<address, u64>,
        managers: VecSet<ID> // List of minters for this stable coin
    }

    /// Admin capability object for the stable coin
    struct RUSDStableCoinAdminCap has key { id: UID }

    // =================== Initializer ===================

    fun init(witness: RUSD_STABLE_COIN, ctx: &mut TxContext) {
        // Create the stable coin
        let (treasury, metadata) = coin::create_currency<RUSD_STABLE_COIN>(
                witness, 
                9,
                b"rUSD",
                b"rUSD Stable Coin",
                b"Stable coin for the Embedr Protocol",
                option::none(),
                ctx
            );

        // Transform the treasury_cap into a supply struct to allow this contract to mint/burn tokens
        let supply = coin::treasury_into_supply(treasury);

        // Share the storage object with the network
        transfer::share_object(
            RUSDStableCoinStorage {
                id: object::new(ctx),
                supply,
                balances: table::new(ctx),
                managers: vec_set::empty()
            },
        );

        // Transfer the admin cap to the sender
        transfer::transfer(RUSDStableCoinAdminCap { id: object::new(ctx) }, tx_context::sender(ctx) );

        // Freeze the metadata object, since we cannot update without the TreasuryCap
        transfer::public_freeze_object(metadata);
    }

    // =================== Entries ===================

    /// Mints new stable coins and transfers them to the recipient
    /// 
    /// # Arguments
    /// 
    /// * `storage` - The storage object
    /// * `publisher` - The publisher object of the package that is calling this function
    /// * `recipient` - The recipient of the new coins
    /// * `amount` - The amount of coins to mint
    public fun mint(
        storage: &mut RUSDStableCoinStorage,
        publisher: &Publisher,
        recipient: address,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<RUSD_STABLE_COIN> {
        // Check if the publisher is allowed to mint
        assert!(is_authorized(storage, object::id(publisher)), ERROR_UNAUTHORIZED);

        // Increase user balance by the amount
        increase_account_balance(
            storage,
            recipient,
            amount
        );

        // Create the coin object and return it
        coin::from_balance(
            balance::increase_supply(
                &mut storage.supply,
                amount
            ),
            ctx
        )
    }

    /// Burns the given amount of stable coins
    /// 
    /// # Arguments
    /// 
    /// * `storage` - The storage object
    /// * `asset` - The asset to burn
    public fun burn(
        storage: &mut RUSDStableCoinStorage,
        publisher: &Publisher,
        recipient: address,
        asset: Coin<RUSD_STABLE_COIN>
    ) {
        // Check if the publisher is allowed to burn
        assert!(is_authorized(storage, object::id(publisher)), ERROR_UNAUTHORIZED);

        decrease_account_balance(
            storage,
            recipient,
            coin::value(&asset)
        );

        // Burn the asset
        balance::decrease_supply(
            &mut storage.supply,
            coin::into_balance(asset)
        );
    }

    /// Transfers the given amount of stable coins to the recipient
    /// 
    /// # Arguments
    entry public fun transfer(
        storage: &mut RUSDStableCoinStorage,
        asset: Coin<RUSD_STABLE_COIN>,
        recipient: address,
        ctx: &mut TxContext
    ) {
        decrease_account_balance(
            storage,
            tx_context::sender(ctx),
            coin::value(&asset)
        );
        increase_account_balance(
            storage,
            recipient,
            coin::value(&asset)
        );
        transfer::public_transfer(asset, recipient);
    }

    public fun update_account_balance(
        storage: &mut RUSDStableCoinStorage,
        publisher: &Publisher,
        recipient: address,
        amount: u64,
        is_increase: bool
    ) {
        assert!(is_authorized(storage, object::id(publisher)), ERROR_UNAUTHORIZED);

        if (is_increase) increase_account_balance(storage, recipient, amount)
        else decrease_account_balance(storage, recipient, amount)
    }

    /// Adds the given ID to the list of managers
    /// 
    /// # Arguments
    /// 
    /// * `storage` - The storage object
    /// * `id` - The ID to add
    entry public fun add_manager(_: &RUSDStableCoinAdminCap, storage: &mut RUSDStableCoinStorage, id: ID) {
        vec_set::insert(&mut storage.managers, id);
    }

    /// Removes the given ID from the list of managers
    /// 
    /// # Arguments
    /// 
    /// * `storage` - The storage object
    /// * `id` - The ID to remove
    entry public fun remove_manager(_: &RUSDStableCoinAdminCap, storage: &mut RUSDStableCoinStorage, id: ID) {
        vec_set::remove(&mut storage.managers, &id);
    }

    // =================== Queries ===================

    /// Returns the current supply of the stable coin
    /// 
    /// # Arguments
    /// 
    /// * `storage` - The storage object
    /// 
    /// # Returns
    /// 
    /// * `u64` - the current supply
    public fun get_supply(storage: &RUSDStableCoinStorage): u64 {
        balance::supply_value(&storage.supply)
    }

    /// Returns the balance of the given address
    /// 
    /// # Arguments
    /// 
    /// * `storage` - The storage object
    /// * `address` - The address to check
    /// 
    /// # Returns
    /// 
    /// * `u64` - the current balance
    public fun get_balance(storage: &RUSDStableCoinStorage, address: address): u64 {
        if (!table::contains(&storage.balances, address)) {
            return 0
        };
        *table::borrow(&storage.balances, address)
    }

    // =================== Helpers ===================

    /// Checks if the given ID is a manager for this stable coin
    /// 
    /// # Arguments
    /// 
    /// * `storage` - The storage object
    /// * `id` - The ID to check
    /// 
    /// # Returns
    /// 
    /// * `true` if the ID is a manager
    public fun is_authorized(storage: &RUSDStableCoinStorage, id: ID): bool {
        vec_set::contains(&storage.managers, &id)
    }

    /// Increases the balance of the given recipient by the given amount
    /// 
    /// # Arguments
    /// 
    /// * `storage` - The storage object
    /// * `recipient` - The address of the recipient
    /// * `amount` - The amount to increase the balance by
    fun increase_account_balance(storage: &mut RUSDStableCoinStorage, recipient: address, amount: u64) {
        if(table::contains(&storage.balances, recipient)) {
            let existing_balance = table::remove(&mut storage.balances, recipient);
            table::add(&mut storage.balances, recipient, existing_balance + amount);
        } else {
            table::add(&mut storage.balances, recipient, amount);
        };
    }

    /// Decreases the balance of the given recipient by the given amount
    /// 
    /// # Arguments
    /// 
    /// * `storage` - The storage object
    /// * `recipient` - The address of the recipient
    /// * `amount` - The amount to decrease the balance by
    fun decrease_account_balance(storage: &mut RUSDStableCoinStorage, recipient: address, amount: u64) {
        let existing_balance = table::remove(&mut storage.balances, recipient);
        table::add(&mut storage.balances, recipient, existing_balance - amount);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(RUSD_STABLE_COIN {}, ctx);
    }

    #[test_only]
    public fun mint_for_testing(
        storage: &mut RUSDStableCoinStorage,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<RUSD_STABLE_COIN> {
        coin::from_balance(balance::increase_supply(&mut storage.supply, amount), ctx)
    }
}
