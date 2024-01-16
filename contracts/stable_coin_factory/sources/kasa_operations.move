/// Kasa Operations module is responsible for all the operations related to kasas
/// This module can be used by users as a proxy to interact with the kasas
/// 
/// # Related Modules
/// 
/// * `Kasa Manager` - `Kasa Operations` calls `Kasa Manager` to perform Kasa operations
/// * `Sorted Kasas` - `Kasa Operations` calls `Sorted Kasas` to insert or reinsert a kasa to the sorted kasas list
/// 
/// There is a single responsibility for this module:
/// 
/// With each operation, `Kasa Operations` will check for the validity of the operation such as:
/// 
/// 1. Making sure the collateral ratio is valid
/// 2. Making sure the minimum debt amount is met for opening a Kasa
/// 3. Making sure Kasa exists for some operations
/// ...
/// 
/// After checking various conditions, `Kasa Operations` will call `Kasa Manager` to perform operations
module stable_coin_factory::kasa_operations {
    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;

    use stable_coin_factory::kasa_storage::{Self, KasaManagerStorage};
    use stable_coin_factory::kasa_manager::{Self, KasaManagerPublisher};
    use stable_coin_factory::sorted_kasas::{SortedKasasStorage};
    use tokens::rusd_stable_coin::{RUSDStableCoinStorage, RUSD_STABLE_COIN};
    use library::kasa::{is_icr_valid};
    use SupraOracle::SupraOracleValue::{ OracleHolder, Price,get_collateral_price}; 
    // use library::utils::logger;

    const COLLATERAL_PRICE: u64 = 1800_000000000;

    // =================== Errors ===================

    /// Collateral amount cannot be zero
    const ERROR_INVALID_COLLATERAL_AMOUNT: u64 = 1;
    /// Debt amount cannot be zero
    const ERROR_INVALID_DEBT_AMOUNT: u64 = 2;
    /// Collateral ratio is lower than 110% or 150%
    const ERROR_LOW_COLLATERAL_RATIO: u64 = 3;
    /// Error for existing kasa
    const ERROR_EXISTING_KASA: u64 = 4;
    /// Error for kasa not found
    const ERROR_KASA_NOT_FOUND: u64 = 5;

    // =================== Public Methods ===================

    /// Open a new kasa for an user
    /// 
    /// # Arguments
    /// 
    /// * `collateral` - the collateral coin object to be deposited
    /// * `debt_amount` - the amount of debt to be borrowed
    public fun open_kasa(
        km_publisher: &KasaManagerPublisher,
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        collateral: Coin<SUI>,
        debt_amount: u64,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);
        let collateral_amount = coin::value(&collateral);

        // TODO: Check for minumum debt amount

        // Check for existing kasa
        assert!(!kasa_storage::has_kasa(km_storage, account_address), ERROR_EXISTING_KASA);

        // Check for collateral and debt amount validity
        assert!(coin::value(&collateral) != 0, ERROR_INVALID_COLLATERAL_AMOUNT);
        assert!(debt_amount != 0, ERROR_INVALID_DEBT_AMOUNT);

        // Check for collateral ratio validity
        assert!(
            is_icr_valid(
                false, // FIXME: Normal mode for now
                collateral_amount,
                debt_amount,
                COLLATERAL_PRICE
            ),
            ERROR_LOW_COLLATERAL_RATIO
        );

        kasa_manager::create_kasa(
            km_publisher,
            km_storage,
            sk_storage,
            rsc_storage,
            account_address,
            collateral,
            debt_amount,
            ctx
        );
    }

    /// Deposit collateral to an existing kasa
    /// 
    /// # Arguments
    /// 
    /// * `collateral` - the collateral coin object to be deposited
    public fun deposit_collateral(
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        collateral: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        // Check for existing kasa
        assert!(kasa_storage::has_kasa(km_storage, account_address), ERROR_KASA_NOT_FOUND);

        // Check for collateral amount validity
        assert!(coin::value(&collateral) != 0, ERROR_INVALID_COLLATERAL_AMOUNT);

        kasa_manager::increase_collateral(
            km_storage,
            sk_storage,
            account_address,
            collateral
        );
    }

    /// Withdraw collateral from an existing kasa
    /// 
    /// # Arguments
    /// 
    /// * `amount` - the amount of collateral to be withdrawn
    public fun withdraw_collateral(
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        // Check for existing kasa
        assert!(kasa_storage::has_kasa(km_storage, account_address), ERROR_KASA_NOT_FOUND);

        // Check for collateral amount validity
        assert!(amount != 0, ERROR_INVALID_COLLATERAL_AMOUNT);

        // Check for collateral ratio validity
        let (kasa_collateral_amount, kasa_debt_amount) = kasa_storage::get_kasa_amounts(
            km_storage,
            account_address,
        );
        assert!(
            is_icr_valid(
                false, // FIXME: Normal mode for now
                kasa_collateral_amount - amount,
                kasa_debt_amount,
                COLLATERAL_PRICE
            ),
            ERROR_LOW_COLLATERAL_RATIO
        );

        kasa_manager::decrease_collateral(
            km_storage,
            sk_storage,
            account_address,
            amount,
            ctx
        );
    }

    /// Borrow debt from an existing kasa
    /// 
    /// # Arguments
    /// 
    /// * `amount` - the amount of debt to be borrowed
    public fun borrow_loan(
        km_publisher: &KasaManagerPublisher,
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        rusd_stable_coin_storage: &mut RUSDStableCoinStorage,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        // Check for existing kasa
        assert!(kasa_storage::has_kasa(km_storage, account_address), ERROR_KASA_NOT_FOUND);

        // Check for debt amount validity
        assert!(amount != 0, ERROR_INVALID_DEBT_AMOUNT);

        // Check for collateral ratio validity
        let (kasa_collateral_amount, kasa_debt_amount) = kasa_storage::get_kasa_amounts(
            km_storage,
            account_address,
        );
        assert!(
            is_icr_valid(
                false, // FIXME: Normal mode for now
                kasa_collateral_amount,
                kasa_debt_amount + amount,
                COLLATERAL_PRICE
            ),
            ERROR_LOW_COLLATERAL_RATIO
        );

        kasa_manager::increase_debt(
            km_publisher,
            km_storage,
            sk_storage,
            rusd_stable_coin_storage,
            account_address,
            amount,
            ctx
        );
    }

    /// Repay debt from an existing kasa
    /// 
    /// # Arguments
    /// 
    /// * `debt_coin` - the debt coin object to be repaid
    public fun repay_loan(
        km_publisher: &KasaManagerPublisher,
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        debt_coin: Coin<RUSD_STABLE_COIN>,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);
        let amount = coin::value(&debt_coin);

        // Check for existing kasa
        assert!(kasa_storage::has_kasa(km_storage, account_address), ERROR_KASA_NOT_FOUND);
        let (kasa_collateral_amount, kasa_debt_amount) = kasa_storage::get_kasa_amounts(km_storage, account_address);

        // Check for debt amount validity
        assert!(amount != 0, ERROR_INVALID_DEBT_AMOUNT);
        assert!(kasa_debt_amount - amount >= 0, ERROR_INVALID_DEBT_AMOUNT);

        // Check for collateral ratio validity
        // TODO: Check if we need this
        // let (kasa_collateral_amount, kasa_debt_amount) = kasa_manager::get_kasa_amounts(
        //     km_storage,
        //     account_address,
        // );
        // assert!(
        //     is_icr_valid(
        //         false, // FIXME: Normal mode for now
        //         kasa_collateral_amount,
        //         kasa_debt_amount - amount,
        //         COLLATERAL_PRICE
        //     ),
        //     ERROR_LOW_COLLATERAL_RATIO
        // );

        // Kasa will be deleted if debt amount is zero
        if (kasa_debt_amount - amount == 0) {
            kasa_manager::fully_repay_loan(
                km_publisher,
                km_storage,
                sk_storage,
                rsc_storage,
                account_address,
                debt_coin,
                ctx,
            );
        } else {
            kasa_manager::decrease_debt(
                km_publisher,
                km_storage,
                sk_storage,
                rsc_storage,
                account_address,
                debt_coin
            );
        }
    }
}
