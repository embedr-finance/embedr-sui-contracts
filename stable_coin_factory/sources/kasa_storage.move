module stable_coin_factory::kasa_storage {
    use sui::object::{Self, UID};
    use sui::transfer;
    use sui::tx_context::TxContext;
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::balance::{Self, Balance};
    use sui::table::{Self, Table};

    use library::kasa::{calculate_nominal_collateral_ratio, calculate_collateral_ratio};

    // =================== Initialization ===================

    fun init(ctx: &mut TxContext) {
        transfer::share_object(KasaManagerStorage {
            id: object::new(ctx),
            kasa_table: table::new(ctx),
            collateral_balance: balance::zero(),
            debt_balance: 0
        });
    }

    // =================== Single Kasa Object ===================

    struct Kasa has store, drop {
        collateral_amount: u64,
        debt_amount: u64
    }

    public fun create_kasa(storage: &mut KasaManagerStorage, account_address: address, collateral_amount: u64, debt_amount: u64) {
        let kasa = Kasa { collateral_amount, debt_amount };
        table::add(&mut storage.kasa_table, account_address, kasa);
    }

    public fun borrow_kasa(storage: &mut KasaManagerStorage, account_address: address): &mut Kasa {
        table::borrow_mut(&mut storage.kasa_table, account_address)
    }

    public fun read_kasa(storage: &KasaManagerStorage, account_address: address): &Kasa {
        table::borrow(&storage.kasa_table, account_address)
    }

    public fun remove_kasa(storage: &mut KasaManagerStorage, account_address: address): Kasa {
        table::remove(&mut storage.kasa_table, account_address)
    }

    public fun has_kasa(storage: &KasaManagerStorage, account_address: address): bool {
        table::contains(&storage.kasa_table, account_address)
    }

    public fun increase_kasa_collateral_amount(storage: &mut KasaManagerStorage, account_address: address, amount: u64) {
        let kasa = borrow_kasa(storage, account_address);
        kasa.collateral_amount = kasa.collateral_amount + amount;
    }

    public fun decrease_kasa_collateral_amount(storage: &mut KasaManagerStorage, account_address: address, amount: u64) {
        let kasa = borrow_kasa(storage, account_address);
        kasa.collateral_amount = kasa.collateral_amount - amount;
    }

    public fun increase_kasa_debt_amount(storage: &mut KasaManagerStorage, account_address: address, amount: u64) {
        let kasa = borrow_kasa(storage, account_address);
        kasa.debt_amount = kasa.debt_amount + amount;
    }

    public fun decrease_kasa_debt_amount(storage: &mut KasaManagerStorage, account_address: address, amount: u64) {
        let kasa = borrow_kasa(storage, account_address);
        kasa.debt_amount = kasa.debt_amount - amount;
    }

    // TODO: This method can be in KasaManager module - look into it
    public fun get_kasa_amounts(storage: &mut KasaManagerStorage, account_address: address): (u64, u64) {
        // TODO: Check for pending rewards and add them to the amounts
        let kasa = borrow_kasa(storage, account_address);
        (kasa.collateral_amount, kasa.debt_amount)
    }

    // =================== Kasa Manager Object ===================

    struct KasaManagerStorage has key {
        id: UID,
        kasa_table: Table<address, Kasa>,
        collateral_balance: Balance<SUI>,
        debt_balance: u64
    }

    public fun increase_total_collateral_balance(storage: &mut KasaManagerStorage, balance: Balance<SUI>) {
        balance::join(&mut storage.collateral_balance, balance);
    }

    public fun decrease_total_collateral_balance(storage: &mut KasaManagerStorage, amount: u64, ctx: &mut TxContext): Coin<SUI> {
        coin::take(&mut storage.collateral_balance, amount, ctx)
    }

    public fun increase_total_debt_balance(storage: &mut KasaManagerStorage, amount: u64) {
        storage.debt_balance = storage.debt_balance + amount;
    }

    public fun decrease_total_debt_balance(storage: &mut KasaManagerStorage, amount: u64) {
        storage.debt_balance = storage.debt_balance - amount;
    }

    public fun get_total_balances(storage: &KasaManagerStorage): (u64, u64) {
        (balance::value(&storage.collateral_balance), storage.debt_balance)
    }
    
    // =================== Helpers ===================

    public fun get_nominal_collateral_ratio(
        storage: &mut KasaManagerStorage,
        account_address: address
    ): u256 {
        let (collateral_amount, debt_amount) = get_kasa_amounts(storage, account_address);
        calculate_nominal_collateral_ratio(collateral_amount, debt_amount)
    }

    public fun get_collateral_ratio(
        storage: &mut KasaManagerStorage,
        account_address: address,
        collateral_price: u64
    ): u256 {
        let (collateral_amount, debt_amount) = get_kasa_amounts(storage, account_address);
        calculate_collateral_ratio(collateral_amount, debt_amount, collateral_price)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}