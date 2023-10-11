module library::kasa {
    use library::math::{d_fdiv_u256, d_fmul_u256, mul_div, double_scalar, scalar};
    use library::utils::logger;

    const NOMINAL_PRECISION: u256 = 100000000000000000000; // 1e20

    /// Minimum collateral ratio for a single Kasa
    const MINIMUM_COLLATERAL_RATIO: u256 = 1100000000;

    /// Critical system collateral ratio
    /// If the system collateral ratio falls below this value, the system enters recovery mode
    const CRITICAL_SYSTEM_COLLATERAL_RATIO: u256 = 1500000000;

    /// Calculates the collateral ratio for a given collateral amount, debt amount and collateral price.
    /// 
    /// # Arguments
    /// 
    /// * `collateral_amount` - The amount of collateral tokens.
    /// * `debt_amount` - The amount of debt tokens.
    /// * `collateral_price` - The price of the collateral token in USD.
    /// 
    /// # Returns
    /// 
    /// The collateral ratio as a percentage.
    public fun calculate_collateral_ratio(
        collateral_amount: u64,
        debt_amount: u64,
        collateral_price: u64,
    ): u256 {
        d_fdiv_u256(
            d_fmul_u256(
                (collateral_amount as u256),
                (collateral_price as u256),
            ),
            (debt_amount as u256),
        )
    }

    /// Calculates the nominal collateral ratio for a given collateral amount and debt amount.
    /// 
    /// # Arguments
    /// 
    /// * `collateral_amount` - The amount of collateral tokens.
    /// * `debt_amount` - The amount of debt tokens.
    /// 
    /// # Returns
    /// 
    /// The nominal collateral ratio as a percentage.
    public fun calculate_nominal_collateral_ratio(
        collateral_amount: u64,
        debt_amount: u64,
    ): u256 {
        d_fdiv_u256(
            d_fmul_u256((collateral_amount as u256), NOMINAL_PRECISION),
            (debt_amount as u256),
        )
    }

    /// Checks if the collateral ratio is valid for given parameters.
    /// Also accounts for recovery mode.
    /// 
    /// # Arguments
    /// 
    /// * `is_recovery_mode` - Whether the system is in recovery mode.
    /// * `collateral_amount` - The amount of collateral tokens.
    /// * `debt_amount` - The amount of debt tokens.
    /// * `collateral_price` - The price of the collateral token in USD.
    public fun is_icr_valid(
        is_recovery_mode: bool,
        collateral_amount: u64,
        debt_amount: u64,
        collateral_price: u64,
    ): bool {
        let ratio = calculate_collateral_ratio(collateral_amount, debt_amount, collateral_price);
        if (is_recovery_mode) ratio >= CRITICAL_SYSTEM_COLLATERAL_RATIO else ratio >= MINIMUM_COLLATERAL_RATIO
    }

    public fun get_minimum_collateral_ratio(): u256 {
        MINIMUM_COLLATERAL_RATIO
    }

    public fun get_critical_system_collateral_ratio(): u256 {
        CRITICAL_SYSTEM_COLLATERAL_RATIO
    }
}
