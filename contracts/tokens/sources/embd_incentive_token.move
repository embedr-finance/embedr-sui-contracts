/// EMBD Incentive Token is responsible for the issuance of EMBD tokens for the Embedr Protocol
module tokens::embd_incentive_token {
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

    /// OTW to create the token
    struct EMBD_INCENTIVE_TOKEN has drop {}

    /// Shared object
    struct EMBDIncentiveTokenStorage has key {
        id: UID,
        supply: Supply<EMBD_INCENTIVE_TOKEN>,
        balances: Table<address, u64>,
        managers: VecSet<ID> // List of minters for this token
    }

    /// Admin capability object for the stable coin
    struct EMBDIncentiveTokenAdminCap has key { id: UID }

    // =================== Initializer ===================

    fun init(witness: EMBD_INCENTIVE_TOKEN, ctx: &mut TxContext) {
        // Create the stable coin
        let (treasury, metadata)
            = coin::create_currency<EMBD_INCENTIVE_TOKEN>(
                witness, 
                9,
                b"EMBD",
                b"EMBD Incentive Token",
                b"Incentive token for the Embedr Protocol",
                option::none(),
                ctx
            );

        // Transform the treasury_cap into a supply struct to allow this contract to mint/burn tokens
        let supply = coin::treasury_into_supply(treasury);

        // Share the storage object with the network
        transfer::share_object(
            EMBDIncentiveTokenStorage {
                id: object::new(ctx),
                supply,
                balances: table::new(ctx),
                managers: vec_set::empty()
            },
        );

        // Transfer the admin cap to the sender
        transfer::transfer(EMBDIncentiveTokenAdminCap { id: object::new(ctx) }, tx_context::sender(ctx) );

        // Freeze the metadata object, since we cannot update without the TreasuryCap
        transfer::public_freeze_object(metadata);
    }

    // =================== Entries ===================

    /// Mints new tokens and transfers them to the recipient
    /// 
    /// # Arguments
    /// 
    /// * `recipient` - recipient of the new coins
    /// * `amount` - amount of tokens to mint
    public fun mint(
        publisher: &Publisher,
        storage: &mut EMBDIncentiveTokenStorage,
        recipient: address,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<EMBD_INCENTIVE_TOKEN> {
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

    /// Burns the given amount of tokens
    /// 
    /// # Arguments
    /// 
    /// * `recipient` - recipient of the new tokens
    /// * `asset` - asset to burn
    public fun burn(
        publisher: &Publisher,
        storage: &mut EMBDIncentiveTokenStorage,
        recipient: address,
        asset: Coin<EMBD_INCENTIVE_TOKEN>
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

    /// Transfers the given amount of tokens to the recipient
    /// 
    /// # Arguments
    /// 
    /// * `recipient` - recipient of the new tokens
    entry public fun transfer(
        storage: &mut EMBDIncentiveTokenStorage,
        asset: Coin<EMBD_INCENTIVE_TOKEN>,
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

    /// Updates the balance of the given account
    /// 
    /// # Arguments
    /// 
    /// * `recipient` - address of the recipient
    /// * `amount` - amount to update the balance by
    /// * `is_increase` - whether to increase or decrease the balance
    public fun update_account_balance(
        publisher: &Publisher,
        storage: &mut EMBDIncentiveTokenStorage,
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
    /// * `id` - The ID to add
    entry public fun add_manager(_: &EMBDIncentiveTokenAdminCap, storage: &mut EMBDIncentiveTokenStorage, id: ID) {
        vec_set::insert(&mut storage.managers, id);
    }

    /// Removes the given ID from the list of managers
    /// 
    /// # Arguments
    /// 
    /// * `id` - The ID to remove
    entry public fun remove_manager(_: &EMBDIncentiveTokenAdminCap, storage: &mut EMBDIncentiveTokenStorage, id: ID) {
        vec_set::remove(&mut storage.managers, &id);
    }

    // =================== Queries ===================

    /// Returns the current supply of the tokens
    /// 
    /// # Arguments
    /// 
    /// * `storage` - The storage object
    /// 
    /// # Returns
    /// 
    /// * `u64` - the current supply
    public fun get_supply(storage: &EMBDIncentiveTokenStorage): u64 {
        balance::supply_value(&storage.supply)
    }

    /// Returns the balance of the given address
    /// 
    /// # Arguments
    /// 
    /// * `address` - address to check
    /// 
    /// # Returns
    /// 
    /// * `u64` - the current balance
    public fun get_balance(storage: &EMBDIncentiveTokenStorage, recipient: address): u64 {
        if (!table::contains(&storage.balances, recipient)) {
            return 0
        };
        *table::borrow(&storage.balances, recipient)
    }

    // =================== Helpers ===================

    /// Checks if the given ID is a manager for this module
    /// 
    /// # Arguments
    /// 
    /// * `storage` - The storage object
    /// * `id` - The ID to check
    /// 
    /// # Returns
    /// 
    /// * `true` if the ID is a manager
    public fun is_authorized(storage: &EMBDIncentiveTokenStorage, id: ID): bool {
        vec_set::contains(&storage.managers, &id)
    }

    /// Increases the balance of the given recipient by the given amount
    /// 
    /// # Arguments
    /// 
    /// * `recipient` - address of the recipient
    /// * `amount` - amount to increase the balance by
    fun increase_account_balance(storage: &mut EMBDIncentiveTokenStorage, recipient: address, amount: u64) {
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
    /// * `recipient` - address of the recipient
    /// * `amount` - amount to decrease the balance by
    fun decrease_account_balance(storage: &mut EMBDIncentiveTokenStorage, recipient: address, amount: u64) {
        let existing_balance = table::remove(&mut storage.balances, recipient);
        table::add(&mut storage.balances, recipient, existing_balance - amount);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(EMBD_INCENTIVE_TOKEN {}, ctx);
    }

    #[test_only]
    public fun mint_for_testing(
        storage: &mut EMBDIncentiveTokenStorage,
        amount: u64,
        ctx: &mut TxContext
    ): Coin<EMBD_INCENTIVE_TOKEN> {
        coin::from_balance(balance::increase_supply(&mut storage.supply, amount), ctx)
    }
}
