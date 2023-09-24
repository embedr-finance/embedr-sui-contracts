module stable_coin_factory::kasa_manager {
    // use std::ascii::String;
    // use std::vector;
    
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{TxContext};
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::object_table::{Self, ObjectTable};
    use sui::package::{Self, Publisher};

    use tokens::rusd_stable_coin::{Self, RUSD_STABLE_COIN, RUSDStableCoinStorage};

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
    struct Kasa has key, store {
        id: UID,
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
        kasa_table: ObjectTable<address, Kasa>,
        collateral_balance: Balance<SUI>,
        debt_balance: u64,
        publisher: Publisher
    }

    // =================== Events ===================

    /// Defines the event for when a Kasa is created
    struct KasaCreated has copy, drop {
        kasa_id: ID,
        account_address: address,
        collateral_amount: u64,
        debt_amount: u64
    }

    // =================== Initializer ===================

    /// Initializes the module
    fun init(witness: KASA_MANAGER, ctx: &mut TxContext) {
        transfer::share_object(KasaManagerStorage {
            id: object::new(ctx),
            kasa_table: object_table::new(ctx),
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
        let kasa_uid = object::new(ctx);
        let kasa_id = object::uid_to_inner(&kasa_uid);
        let kasa = Kasa {
            id: kasa_uid,
            collateral_amount,
            debt_amount
        };

        // Add the Kasa object to the kasa_table
        object_table::add(&mut kasa_manager_storage.kasa_table, account_address, kasa);

        // Update the total collateral balance of the protocol
        balance::join(&mut kasa_manager_storage.collateral_balance, collateral_balance);
        // Update the total debt balance of the protocol
        kasa_manager_storage.debt_balance = kasa_manager_storage.debt_balance + stable_coin_amount;

        transfer::public_transfer(stable_coin, account_address);

        // Emit the KasaOpened event
        event::emit(KasaCreated {
            kasa_id,
            account_address,
            collateral_amount,
            debt_amount
        });
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
    public fun has_kasa(kasa_manager_storage: &mut KasaManagerStorage, account_address: address): bool {
        object_table::contains(&kasa_manager_storage.kasa_table, account_address)
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

    /// Borrows the Kasa from the KasaManagerStorage
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `account_address` - the address of the Account module
    fun borrow_kasa(kasa_manager_store: &mut KasaManagerStorage, account_address: address): &mut Kasa {
        object_table::borrow_mut(&mut kasa_manager_store.kasa_table, account_address)
    }
    
    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(KASA_MANAGER {}, ctx);
    }
}