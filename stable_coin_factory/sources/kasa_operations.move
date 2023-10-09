module stable_coin_factory::kasa_operations {
    use std::option::{Self, Option};

    use sui::tx_context::{Self, TxContext};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;

    use stable_coin_factory::kasa_manager::{Self, KasaManagerStorage};
    use stable_coin_factory::sorted_kasas::{Self, SortedKasasStorage};
    use tokens::rusd_stable_coin::{RUSDStableCoinStorage, RUSD_STABLE_COIN};
    use library::kasa::{is_icr_valid, calculate_collateral_ratio, calculate_nominal_collateral_ratio};
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

    // =================== Entries ===================

    /// Opens a new Kasa for Account
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - Kasa Manager storage object
    /// * `rusd_stable_coin_storage` - RUSD Stable Coin storage object
    /// * `collateral` - collateral to be deposited
    /// * `debt_amount` - debt amount to be borrowed
    entry public fun open_kasa(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasa_storage: &mut SortedKasasStorage,
        rusd_stable_coin_storage: &mut RUSDStableCoinStorage,
        collateral: Coin<SUI>,
        debt_amount: u64,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);
        let collateral_amount = coin::value(&collateral);

        // Check for existing kasa
        assert!(!kasa_manager::has_kasa(kasa_manager_storage, account_address), ERROR_EXISTING_KASA);

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
            kasa_manager_storage,
            rusd_stable_coin_storage,
            account_address,
            collateral,
            debt_amount,
            ctx
        );

        // TODO: Get prev_id and next_id as a parameter
        sorted_kasas::insert(
            kasa_manager_storage,
            sorted_kasa_storage,
            account_address,
            calculate_nominal_collateral_ratio(collateral_amount, debt_amount),
            option::none(),
            option::none(),
            ctx
        )
    }

    /// Deposits collateral into the Kasa.
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - Kasa Manager storage object
    /// * `collateral` - collateral to be deposited
    /// * `ctx` - transaction context
    entry public fun deposit_collateral(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasa_storage: &mut SortedKasasStorage,
        collateral: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        // Check for existing kasa
        assert!(kasa_manager::has_kasa(kasa_manager_storage, account_address), ERROR_KASA_NOT_FOUND);

        // Check for collateral amount validity
        assert!(coin::value(&collateral) != 0, ERROR_INVALID_COLLATERAL_AMOUNT);

        kasa_manager::increase_collateral(
            kasa_manager_storage,
            account_address,
            collateral
        );

        reinsert_kasa_to_list(
            kasa_manager_storage,
            sorted_kasa_storage,
            account_address,
            option::none(),
            option::none(),
            ctx
        );
    }

    /// Withdraws collateral from the Kasa.
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - Kasa Manager storage object
    /// * `collateral` - collateral to be withdrawn
    /// * `ctx` - transaction context
    entry public fun withdraw_collateral(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasa_storage: &mut SortedKasasStorage,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        // Check for existing kasa
        assert!(kasa_manager::has_kasa(kasa_manager_storage, account_address), ERROR_KASA_NOT_FOUND);

        // Check for collateral amount validity
        assert!(amount != 0, ERROR_INVALID_COLLATERAL_AMOUNT);

        // Check for collateral ratio validity
        let (kasa_collateral_amount, kasa_debt_amount) = kasa_manager::get_kasa_amounts(
            kasa_manager_storage,
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
            kasa_manager_storage,
            account_address,
            amount,
            ctx
        );

        reinsert_kasa_to_list(
            kasa_manager_storage,
            sorted_kasa_storage,
            account_address,
            option::none(),
            option::none(),
            ctx
        );
    }

    /// Borrows rUSD from the protocol.
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - Kasa Manager storage object
    /// * `rusd_stable_coin_storage` - RUSD Stable Coin storage object
    /// * `amount` - debt amount to be borrowed
    /// * `ctx` - transaction context
    entry public fun borrow_loan(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasa_storage: &mut SortedKasasStorage,
        rusd_stable_coin_storage: &mut RUSDStableCoinStorage,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        // Check for existing kasa
        assert!(kasa_manager::has_kasa(kasa_manager_storage, account_address), ERROR_KASA_NOT_FOUND);

        // Check for debt amount validity
        assert!(amount != 0, ERROR_INVALID_DEBT_AMOUNT);

        // Check for collateral ratio validity
        let (kasa_collateral_amount, kasa_debt_amount) = kasa_manager::get_kasa_amounts(
            kasa_manager_storage,
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
            kasa_manager_storage,
            rusd_stable_coin_storage,
            account_address,
            amount,
            ctx
        );

        reinsert_kasa_to_list(
            kasa_manager_storage,
            sorted_kasa_storage,
            account_address,
            option::none(),
            option::none(),
            ctx
        );
    }

    /// Repays the loan to the protocol.
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - Kasa Manager storage object
    /// * `rusd_stable_coin_storage` - RUSD Stable Coin storage object
    /// * `amount` - amount of rUSD to be repaid
    /// * `ctx` - transaction context
    entry public fun repay_loan(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasa_storage: &mut SortedKasasStorage,
        rusd_stable_coin_storage: &mut RUSDStableCoinStorage,
        debt_coin: Coin<RUSD_STABLE_COIN>,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);
        let amount = coin::value(&debt_coin);

        // Check for existing kasa
        assert!(kasa_manager::has_kasa(kasa_manager_storage, account_address), ERROR_KASA_NOT_FOUND);

        // Check for debt amount validity
        assert!(amount != 0, ERROR_INVALID_DEBT_AMOUNT);

        // Check for collateral ratio validity
        // TODO: Check if we need this
        // let (kasa_collateral_amount, kasa_debt_amount) = kasa_manager::get_kasa_amounts(
        //     kasa_manager_storage,
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
            kasa_manager_storage,
            rusd_stable_coin_storage,
            account_address,
            debt_coin
        );

        reinsert_kasa_to_list(
            kasa_manager_storage,
            sorted_kasa_storage,
            account_address,
            option::none(),
            option::none(),
            ctx
        )
    }

    // =================== Queries ===================

    /// Display the collateral and debt amount of the Kasa
    /// 
    /// # Arguments
    /// 
    /// * `kasa_manager_storage` - Kasa Manager storage object
    public fun display_kasa(
        kasa_manager_storage: &mut KasaManagerStorage,
        ctx: &TxContext
    ): (u64, u64) {
        let account_address = tx_context::sender(ctx);
        kasa_manager::get_kasa_amounts(
            kasa_manager_storage,
            account_address,
        )
    }

    // =================== Helpers ===================

    fun reinsert_kasa_to_list(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasa_storage: &mut SortedKasasStorage,
        account_address: address,
        prev_id: Option<address>,
        next_id: Option<address>,
        ctx: &mut TxContext
    ) {
        let (current_collateral_amount, current_debt_amount) = kasa_manager::get_kasa_amounts(
            kasa_manager_storage,
            account_address,
        );
        sorted_kasas::reinsert(
            kasa_manager_storage,
            sorted_kasa_storage,
            account_address,
            calculate_nominal_collateral_ratio(
                current_collateral_amount,
                current_debt_amount
            ),
            prev_id,
            next_id,
            ctx
        )
    }
}
