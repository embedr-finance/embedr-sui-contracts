module stable_coin_factory::kasa_operations {
    use std::option::{Self, Option};

    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;

    use stable_coin_factory::kasa_storage::{Self, KasaManagerStorage};
    use stable_coin_factory::kasa_manager::{Self, KasaManagerPublisher};
    use stable_coin_factory::sorted_kasas::{Self, SortedKasasStorage};
    use tokens::rusd_stable_coin::{RUSDStableCoinStorage, RUSD_STABLE_COIN};
    use library::kasa::{is_icr_valid, calculate_nominal_collateral_ratio};
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
            rsc_storage,
            account_address,
            collateral,
            debt_amount,
            ctx
        );

        // TODO: Get prev_id and next_id as a parameter
        sorted_kasas::insert(
            km_storage,
            sk_storage,
            account_address,
            calculate_nominal_collateral_ratio(collateral_amount, debt_amount),
            option::none(),
            option::none(),
            ctx
        )
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
            account_address,
            collateral
        );

        reinsert_kasa_to_list(
            km_storage,
            sk_storage,
            account_address,
            option::none(),
            option::none()
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
            account_address,
            amount,
            ctx
        );

        reinsert_kasa_to_list(
            km_storage,
            sk_storage,
            account_address,
            option::none(),
            option::none()
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
            rusd_stable_coin_storage,
            account_address,
            amount,
            ctx
        );

        reinsert_kasa_to_list(
            km_storage,
            sk_storage,
            account_address,
            option::none(),
            option::none()
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
        rusd_stable_coin_storage: &mut RUSDStableCoinStorage,
        debt_coin: Coin<RUSD_STABLE_COIN>,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);
        let amount = coin::value(&debt_coin);

        // Check for existing kasa
        assert!(kasa_storage::has_kasa(km_storage, account_address), ERROR_KASA_NOT_FOUND);

        // Check for debt amount validity
        assert!(amount != 0, ERROR_INVALID_DEBT_AMOUNT);

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

        kasa_manager::decrease_debt(
            km_publisher,
            km_storage,
            rusd_stable_coin_storage,
            account_address,
            debt_coin
        );

        reinsert_kasa_to_list(
            km_storage,
            sk_storage,
            account_address,
            option::none(),
            option::none()
        )
    }

    // =================== Helpers ===================

    /// Reinsert a kasa to the sorted kasas list
    /// After updating the collateral ratio of a kasa, we need to reinsert it to the sorted kasas list
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the account address of the kasa
    /// * `prev_id` - the previous kasa id in the sorted kasas list
    /// * `next_id` - the next kasa id in the sorted kasas list
    fun reinsert_kasa_to_list(
        km_storage: &mut KasaManagerStorage,
        sk_storage: &mut SortedKasasStorage,
        account_address: address,
        prev_id: Option<address>,
        next_id: Option<address>
    ) {
        let (current_collateral_amount, current_debt_amount) = kasa_storage::get_kasa_amounts(
            km_storage,
            account_address,
        );
        sorted_kasas::reinsert(
            km_storage,
            sk_storage,
            account_address,
            calculate_nominal_collateral_ratio(
                current_collateral_amount,
                current_debt_amount
            ),
            prev_id,
            next_id
        )
    }
}
