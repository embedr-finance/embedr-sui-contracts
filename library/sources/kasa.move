module library::kasa {


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
    ): u64 {
        let collateral_value = collateral_amount * collateral_price;
        let collateral_ratio = collateral_value / debt_amount;
        collateral_ratio * 100
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

        if (is_recovery_mode) ratio >= 150 else ratio >= 110
    }
}