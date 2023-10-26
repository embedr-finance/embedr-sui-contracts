module stable_coin_factory::kasa_storage {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};

    use library::kasa::{
        calculate_nominal_collateral_ratio, calculate_collateral_ratio,
        get_critical_system_collateral_ratio, is_icr_valid
    };
    // use library::utils::logger;

    friend stable_coin_factory::kasa_manager;

    // =================== Initialization ===================

    fun init(ctx: &mut TxContext) {
        transfer::share_object(KasaManagerStorage {
            id: object::new(ctx),
            kasa_table: table::new(ctx),
            collateral_balance: balance::zero(),
            debt_balance: 0,
            total_stakes: 0
        });
        transfer::share_object(LiquidationSnapshots {
            id: object::new(ctx),
            total_collateral: 0,
            total_stakes: 0
        });
    }

    // =================== Single Kasa Object ===================

    // TODO: What does this stake variable do?
    /// Represents a Kasa object
    /// 
    /// # Fields
    /// 
    /// * `collateral_amount` - amount of collateral available in the Kasa
    /// * `debt_amount` - amount of debt available in the Kasa
    struct Kasa has store, drop {
        collateral_amount: u64,
        debt_amount: u64,
        stake_amount: u64
    }

    /// Creates a new Kasa object and adds it to the storage
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - address of the account
    /// * `collateral_amount` - amount of collateral
    /// * `debt_amount` - amount of debt
    public(friend) fun create_kasa(storage: &mut KasaManagerStorage, account_address: address, collateral_amount: u64, debt_amount: u64) {
        // TODO: Stake amount will be different than zero
        let kasa = Kasa { collateral_amount, debt_amount, stake_amount: 0 };
        table::add(&mut storage.kasa_table, account_address, kasa);
    }

    /// Borrows a Kasa object from the storage
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - address of the account
    /// 
    /// # Returns
    /// 
    /// * `Kasa` - a mutable reference to the Kasa object
    public(friend) fun borrow_kasa(storage: &mut KasaManagerStorage, account_address: address): &mut Kasa {
        table::borrow_mut(&mut storage.kasa_table, account_address)
    }

    /// Reads a Kasa reference from the storage
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - address of the account
    /// 
    /// # Returns
    /// 
    /// * `Kasa` - a reference to the Kasa object
    public fun read_kasa(storage: &KasaManagerStorage, account_address: address): &Kasa {
        table::borrow(&storage.kasa_table, account_address)
    }

    /// Removes a Kasa object from the storage
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - address of the account
    /// 
    /// # Returns
    /// 
    /// * `Kasa` - the removed Kasa object
    public(friend) fun remove_kasa(storage: &mut KasaManagerStorage, account_address: address): Kasa {
        table::remove(&mut storage.kasa_table, account_address)
    }

    /// Checks if a Kasa object exists in the storage
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - address of the account
    /// 
    /// # Returns
    /// 
    /// * `bool` - true if the Kasa object exists, false otherwise
    public fun has_kasa(storage: &KasaManagerStorage, account_address: address): bool {
        table::contains(&storage.kasa_table, account_address)
    }

    /// Increases the collateral amount of a Kasa object
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - address of the account
    /// * `amount` - amount of collateral
    public(friend) fun increase_kasa_collateral_amount(storage: &mut KasaManagerStorage, account_address: address, amount: u64) {
        let kasa = borrow_kasa(storage, account_address);
        kasa.collateral_amount = kasa.collateral_amount + amount;
    }

    /// Decreases the collateral amount of a Kasa object
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - address of the account
    /// * `amount` - amount of collateral
    public(friend) fun decrease_kasa_collateral_amount(storage: &mut KasaManagerStorage, account_address: address, amount: u64) {
        let kasa = borrow_kasa(storage, account_address);
        kasa.collateral_amount = kasa.collateral_amount - amount;
    }

    /// Increases the debt amount of a Kasa object
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - address of the account
    /// * `amount` - amount of debt
    public(friend) fun increase_kasa_debt_amount(storage: &mut KasaManagerStorage, account_address: address, amount: u64) {
        let kasa = borrow_kasa(storage, account_address);
        kasa.debt_amount = kasa.debt_amount + amount;
    }

    /// Decreases the debt amount of a Kasa object
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - address of the account
    /// * `amount` - amount of debt
    public(friend) fun decrease_kasa_debt_amount(storage: &mut KasaManagerStorage, account_address: address, amount: u64) {
        let kasa = borrow_kasa(storage, account_address);
        kasa.debt_amount = kasa.debt_amount - amount;
    }

    /// Removes the stake amount of a Kasa object and decreases the total stake amount
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - address of the account
    public(friend) fun remove_kasa_stake(storage: &mut KasaManagerStorage, account_address: address) {
        let kasa = read_kasa(storage, account_address);
        storage.total_stakes = storage.total_stakes - kasa.stake_amount;
        let kasa = borrow_kasa(storage, account_address);
        kasa.stake_amount = 0;
    }

    /// Returns the collateral and debt amounts of a Kasa object
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - address of the account
    // TODO: This method can be in KasaManager module - look into it
    public fun get_kasa_amounts(storage: &mut KasaManagerStorage, account_address: address): (u64, u64) {
        // TODO: Check for pending rewards and add them to the amounts
        let kasa = read_kasa(storage, account_address);
        (kasa.collateral_amount, kasa.debt_amount)
    }

    // =================== Kasa Manager Object ===================

    /// Represents the Kasa Manager object
    /// 
    /// # Fields
    /// 
    /// * `kasa_table` - Table of Kasa objects mapped to account addresses
    /// * `collateral_balance` - Total collateral balance of the protocol
    /// * `debt_balance` - Total debt balance of the protocol
    struct KasaManagerStorage has key {
        id: UID,
        kasa_table: Table<address, Kasa>,
        collateral_balance: Balance<SUI>,
        debt_balance: u64,
        total_stakes: u64
    }

    /// Keeps track of collateral and stake amounts after each liquidation
    /// 
    /// # Fields
    /// 
    /// * `total_collateral` - Snapshot of the value of total collateral, taken right after the lastest liquidation
    /// * `total_stakes` - Snapshot of the value of total stakes, taken right after the lastest liquidation
    struct LiquidationSnapshots has key {
        id: UID,
        total_collateral: u64,
        total_stakes: u64,
    }

    /// Increases the total collateral balance of the protocol
    /// 
    /// # Arguments
    /// 
    /// * `balance` - amount of balance to be added
    public(friend) fun increase_total_collateral_balance(storage: &mut KasaManagerStorage, balance: Balance<SUI>) {
        balance::join(&mut storage.collateral_balance, balance);
    }

    /// Decreases the total collateral balance of the protocol
    /// 
    /// # Arguments
    /// 
    /// * `amount` - amount of balance to be taken
    /// 
    /// # Returns
    /// 
    /// * `Coin<SUI>` - the collateral coin object that was taken
    public(friend) fun decrease_total_collateral_balance(storage: &mut KasaManagerStorage, amount: u64, ctx: &mut TxContext): Coin<SUI> {
        coin::take(&mut storage.collateral_balance, amount, ctx)
    }

    /// Increases the total debt balance of the protocol
    /// 
    /// # Arguments
    /// 
    /// * `amount` - amount of debt to be added
    public(friend) fun increase_total_debt_balance(storage: &mut KasaManagerStorage, amount: u64) {
        storage.debt_balance = storage.debt_balance + amount;
    }

    /// Decreases the total debt balance of the protocol
    /// 
    /// # Arguments
    ///
    /// * `amount` - amount of debt to be taken
    public(friend) fun decrease_total_debt_balance(storage: &mut KasaManagerStorage, amount: u64) {
        storage.debt_balance = storage.debt_balance - amount;
    }

    /// Returns the total collateral and debt balances of the protocol
    /// 
    /// # Returns
    /// 
    /// * `(u64, u64)` - total collateral and debt balances
    public fun get_total_balances(storage: &KasaManagerStorage): (u64, u64) {
        (balance::value(&storage.collateral_balance), storage.debt_balance)
    }

    /// Returns the kasa count of the protocol
    /// 
    /// # Returns
    /// 
    /// * `u64` - kasa count
    public fun get_kasa_count(storage: &KasaManagerStorage): u64 {
        table::length(&storage.kasa_table)
    }

    /// Updates the total collateral and stake amounts after each liquidation
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - address of the account
    /// 
    /// # Returns
    /// 
    /// * `u64` - new stake amount
    public(friend) fun update_stake_and_total_stakes(
        storage: &mut KasaManagerStorage,
        snapshots: &LiquidationSnapshots,
        account_address: address,
    ): u64 {
        let kasa = borrow_kasa(storage, account_address);
        
        // Save the new and old stake amounts
        let new_stake = get_new_stake(snapshots, kasa.collateral_amount);
        let old_stake = kasa.stake_amount;

        // Update kasa stake amount
        kasa.stake_amount = new_stake;

        // Update total stakes
        storage.total_stakes = storage.total_stakes - old_stake + new_stake;

        new_stake
    }

    // =================== Helpers ===================

    /// Returns the new stake amount of a Kasa object
    /// 
    /// # Arguments
    /// 
    /// * `collateral_amount` - amount of collateral
    /// 
    /// # Returns
    /// 
    /// * `u64` - new stake amount
    fun get_new_stake(snapshots: &LiquidationSnapshots, collateral_amount: u64): u64 {
        let stake;
        if (snapshots.total_collateral == 0) {
            stake = collateral_amount;
        } else {
            // assert!(snapshots.total_stakes > 0, "Total stakes should be greater than zero");
            // TODO: Might have to use math library for this
            stake = collateral_amount * snapshots.total_stakes / snapshots.total_collateral;
        };
        stake
    }

    /// Returns the nominal collateral ratio of a Kasa object
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - address of the account
    /// 
    /// # Returns
    /// 
    /// * `u256` - nominal collateral ratio
    public fun get_nominal_collateral_ratio(
        storage: &mut KasaManagerStorage,
        account_address: address
    ): u256 {
        let (collateral_amount, debt_amount) = get_kasa_amounts(storage, account_address);
        calculate_nominal_collateral_ratio(collateral_amount, debt_amount)
    }

    /// Returns the collateral ratio of a Kasa object
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - address of the account
    /// * `collateral_price` - price of the collateral
    /// 
    /// # Returns
    /// 
    /// * `u256` - collateral ratio percentage
    public fun get_collateral_ratio(
        storage: &mut KasaManagerStorage,
        account_address: address,
        collateral_price: u64
    ): u256 {
        let (collateral_amount, debt_amount) = get_kasa_amounts(storage, account_address);
        calculate_collateral_ratio(collateral_amount, debt_amount, collateral_price)
    }

    /// Returns the total collateral ratio of the protocol
    /// 
    /// # Arguments
    /// 
    /// * `collateral_price` - price of the collateral
    /// 
    /// # Returns
    /// 
    /// * `u256` - total collateral ratio percentage
    public fun get_total_collateral_ratio(
        storage: &mut KasaManagerStorage,
        collateral_price: u64
    ): u256 {
        let (collateral_amount, debt_amount) = get_total_balances(storage);
        calculate_collateral_ratio(collateral_amount, debt_amount, collateral_price)
    }

    /// Checks if the protocol is in recovery mode
    /// 
    /// # Arguments
    /// 
    /// * `collateral_price` - price of the collateral
    /// 
    /// # Returns
    /// 
    /// * `bool` - true if the protocol is in recovery mode, false otherwise
    public fun check_recovery_mode(km_storage: &mut KasaManagerStorage, collateral_price: u64): bool {
        let total_collateral_ratio = get_total_collateral_ratio(km_storage, collateral_price);
        total_collateral_ratio < get_critical_system_collateral_ratio()
    }

    /// Checks if the total collateral ratio is over the minimum collateral ratio
    /// 
    /// # Arguments
    /// 
    /// * `collateral_price` - price of the collateral
    /// 
    /// # Returns
    /// 
    /// * `bool` - true if the total collateral ratio is over the minimum collateral ratio (110%), false otherwise
    public fun is_tcr_over_threshold(storage: &mut KasaManagerStorage, collateral_price: u64): bool {
        let (collateral_amount, debt_amount) = get_total_balances(storage);
        is_icr_valid(
            false,
            collateral_amount,
            debt_amount,
            collateral_price
        )
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}