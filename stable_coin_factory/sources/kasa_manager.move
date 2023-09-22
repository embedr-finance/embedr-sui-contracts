module stable_coin_factory::kasa_manager {
    use std::ascii::String;
    use std::debug;
    
    use sui::object::{Self, UID, ID};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::event;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::object_table::{Self, ObjectTable};
    use sui::package::{Self, Publisher};

    use tokens::rusd_stable_coin::{Self, RUSD_STABLE_COIN, RUSDStableCoinStorage};
    use library::kasa::{calculate_asset_percentage};
    use library::math::d_fdiv;

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
        debt_amount: u64,
        percentages: KasaPercentages
    }

    /// Keeps track of the collateral and debt percentages of a Kasa
    /// 
    /// # Fields
    /// 
    /// * `collateral_percentage` - the percentage of collateral the user has deposited
    /// * `debt_percentage` - the percentage of debt the user has borrowed
    struct KasaPercentages has store {
        id: UID,
        collateral_percentage: u256,
        debt_percentage: u256
    }

    /// Keeps track of the riskiest Kasa based on collateral ratio
    /// 
    /// # Fields
    /// 
    /// * `account_address` - the address of the Account module
    /// * `collateral_ratio` - the collateral ratio of the Kasa
    struct RiskiestKasa has key {
        id: UID,
        account_address: address,
        collateral_ratio: u64
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

        // Update the total collateral balance of the protocol
        balance::join(&mut kasa_manager_storage.collateral_balance, collateral_balance);
        // Update the total debt balance of the protocol
        kasa_manager_storage.debt_balance = kasa_manager_storage.debt_balance + stable_coin_amount;

        // Get the total collateral and debt balances of the protocol
        let (total_collateral_amount, total_debt_amount) = get_protocol_balances(kasa_manager_storage);

        // Calculate the collateral and debt percentages for the Kasa
        let kasa_percentages = KasaPercentages {
            id: object::new(ctx),
            collateral_percentage: calculate_asset_percentage(collateral_amount, total_collateral_amount),
            debt_percentage: calculate_asset_percentage(stable_coin_amount, total_debt_amount)
        };

        // Create a new Kasa object
        let kasa_uid = object::new(ctx);
        let kasa_id = object::uid_to_inner(&kasa_uid);
        let kasa = Kasa {
            id: kasa_uid,
            collateral_amount,
            debt_amount,
            percentages: kasa_percentages
        };

        // Add the Kasa object to the kasa_table
        object_table::add(&mut kasa_manager_storage.kasa_table, account_address, kasa);

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
        let amount = coin::value<SUI>(&collateral);

        // Update total collateral balance of the protocol
        coin::put(&mut kasa_manager_storage.collateral_balance, collateral);

        // Calculate the collateral percentage for the Kasa
        let kasa = get_kasa(kasa_manager_storage, account_address);
        let (total_collateral_amount, _) = get_protocol_balances(kasa_manager_storage);
        let kasa_collateral_percentage = calculate_asset_percentage(kasa.collateral_amount + amount, total_collateral_amount);

        // Update Kasa object - collateral amount and collateral percentage
        let kasa = borrow_kasa(kasa_manager_storage, account_address);
        kasa.collateral_amount = kasa.collateral_amount + amount;
        kasa.percentages.collateral_percentage = kasa_collateral_percentage;
    }
    
    /// Decreases the collateral amount of the user
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `account_address` - the address of the Account module
    /// * `amount` - the amount to decrease the collateral by
    public(friend) fun decrease_collateral(kasa_manager_storage: &mut KasaManagerStorage, account_address: address, amount: u64, ctx: &mut TxContext) {
        // Update total collateral balance of the protocol
        let collateral = coin::take(&mut kasa_manager_storage.collateral_balance, amount, ctx);
        
        // Calculate the collateral percentage for the Kasa
        let kasa = get_kasa(kasa_manager_storage, account_address);
        let (total_collateral_amount, _) = get_protocol_balances(kasa_manager_storage);
        let kasa_collateral_percentage = calculate_asset_percentage(kasa.collateral_amount - amount, total_collateral_amount);
        
        // Update Kasa object - collateral amount and collateral percentage
        let kasa = borrow_kasa(kasa_manager_storage, account_address);
        kasa.collateral_amount = kasa.collateral_amount + amount;
        kasa.percentages.collateral_percentage = kasa_collateral_percentage;

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
        // Update the total debt balance of the protocol
        kasa_manager_storage.debt_balance = kasa_manager_storage.debt_balance + amount;

        // Calculate the debt percentage for the Kasa
        let kasa = get_kasa(kasa_manager_storage, account_address);
        let (_, total_debt_amount) = get_protocol_balances(kasa_manager_storage);
        let kasa_debt_percentage = calculate_asset_percentage(kasa.debt_amount + amount, total_debt_amount);

        // Update Kasa object - debt amount and debt percentage
        let kasa = borrow_kasa(kasa_manager_storage, account_address);
        kasa.debt_amount = kasa.debt_amount + amount;
        kasa.percentages.debt_percentage = kasa_debt_percentage;

        // Mint the rUSD to the user
        let rusd = rusd_stable_coin::mint(
            rusd_stable_coin_storage,
            &kasa_manager_storage.publisher,
            amount,
            ctx
        );
        transfer::public_transfer(rusd, account_address);
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
        debt_coin: Coin<RUSD_STABLE_COIN>,
        ctx: &mut TxContext
    ) {
        let amount = coin::value(&debt_coin);

        // // Update the total debt balance of the protocol
        kasa_manager_storage.debt_balance = kasa_manager_storage.debt_balance - amount;

        // Calculate the debt percentage for the Kasa
        let kasa = get_kasa(kasa_manager_storage, account_address);
        let (_, total_debt_amount) = get_protocol_balances(kasa_manager_storage);
        let kasa_debt_percentage = calculate_asset_percentage(kasa.debt_amount - amount, total_debt_amount);

        // Update Kasa object - debt amount and debt percentage
        let kasa = borrow_kasa(kasa_manager_storage, account_address);
        kasa.debt_amount = kasa.debt_amount - amount;
        kasa.percentages.debt_percentage = kasa_debt_percentage;

        // Burn the rUSD from the user
        rusd_stable_coin::burn(
            rusd_stable_coin_storage,
            &kasa_manager_storage.publisher,
            debt_coin
        );
    }

    /// Redeems stable coin for collateral from the protocol
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `rusd_stable_coin_storage` - the RUSDStableCoinStorage object
    /// * `account_address` - the address of the Account module
    /// * `stable_coin` - the amount of stable coin to redeem
    // entry public fun redeem_stable_coin(
    //     kasa_manager_storage: &mut KasaManagerStorage,
    //     rusd_stable_coin_storage: &mut RUSDStableCoinStorage,
    //     account_address: address,
    //     stable_coin: Coin<RUSD_STABLE_COIN>,
    //     ctx: &mut TxContext
    // ) {
    //     // TODO: Check out linked table

    //     // TODO: We need a way to find the riskiest Kasa and write it down
    // }

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
    public fun get_kasa_asset_amounts(kasa_manager_storage: &mut KasaManagerStorage, account_address: address): (u64, u64) {
        let kasa = borrow_kasa(kasa_manager_storage, account_address);
        (kasa.collateral_amount, kasa.debt_amount)
    }

    /// Gets the percentages for a Kasa
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `account_address` - the address of the Account module
    public fun get_kasa_asset_percentages(kasa_manager_storage: &mut KasaManagerStorage, account_address: address): (u256, u256) {
        let kasa = borrow_kasa(kasa_manager_storage, account_address);
        (kasa.percentages.collateral_percentage, kasa.percentages.debt_percentage)
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

    /// Gets the Kasa from the KasaManagerStorage
    ///
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - the KasaManagerStorage object
    /// * `account_address` - the address of the Account module
    fun get_kasa(kasa_manager_store: &mut KasaManagerStorage, account_address: address): &Kasa {
        object_table::borrow(&mut kasa_manager_store.kasa_table, account_address)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(KASA_MANAGER {}, ctx);
    }
}