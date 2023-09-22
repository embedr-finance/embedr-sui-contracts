module stable_coin_factory::stability_pool {
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};

    use tokens::rusd_stable_coin::{RUSD_STABLE_COIN};

    /// Stake represents the amount of tokens staked by an account.
    /// 
    /// # Fields
    /// 
    /// * `account_address` - the address of the account that staked the tokens
    /// * `amount` - the amount of tokens staked
    struct Stake has store, drop {
        account_address: address,
        amount: u64
    }

    /// StabilityPoolStorage represents the storage for the stability pool.
    /// 
    /// # Fields
    /// 
    /// * `stake_table` - the table that stores the staked amounts for each account
    /// * `stake_balance` - the balance of the stable coin in the stability pool
    struct StabilityPoolStorage has key {
        id: UID,
        stake_table: Table<address, Stake>,
        stake_balance: Balance<RUSD_STABLE_COIN>
    }

    // =================== Initializer ===================

    fun init(ctx: &mut TxContext) {
        transfer::share_object(StabilityPoolStorage {
            id: object::new(ctx),
            stake_table: table::new(ctx),
            stake_balance: balance::zero()
        });
    }

    // =================== Entries ===================

    /// Deposits a given amount of stable coin into the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// * `stable_coin` - the stable coin to be staked
    entry public fun deposit(
        stability_pool_storage: &mut StabilityPoolStorage,
        stable_coin: Coin<RUSD_STABLE_COIN>,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);
        let amount = coin::value(&stable_coin);

        // Create a new stake for the account if it doesn't exist
        if (!check_stake_exists(stability_pool_storage, account_address)) {
            table::add(
                &mut stability_pool_storage.stake_table,
                account_address, 
                Stake {
                    account_address: account_address,
                    amount: 0
                }
            );
        };

        // Borrow the stake for the account
        let stake = borrow_stake(stability_pool_storage, account_address);

        // Update stake amount for the account
        stake.amount = stake.amount + amount;

        // Update the total stake balance
        coin::put(&mut stability_pool_storage.stake_balance, stable_coin);
    }

    /// Withdraws a given amount of stable coin from the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// * `amount` - the amount of stable coin to be withdrawn
    entry public fun withdraw(
        stability_pool_storage: &mut StabilityPoolStorage,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        // Borrow and update the stake for the account
        let stake = borrow_stake(stability_pool_storage, account_address);
        stake.amount = stake.amount - amount;

        // Remove the stake for the account if the stake amount is 0
        if (stake.amount == 0) remove_stake(stability_pool_storage, account_address);

        // Update the total stake balance
        let stable_coin = coin::take(&mut stability_pool_storage.stake_balance, amount, ctx);
        
        // Transfer the stable coin back to the user
        transfer::public_transfer(stable_coin, account_address);
    }  

    // =================== Queries ===================
    
    /// Returns the amount of tokens staked by an account in the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// * `account_address` - the address of the account
    /// 
    /// # Returns
    /// 
    /// The amount of tokens staked by the account
    public fun get_stake_amount(stability_pool_storage: &StabilityPoolStorage, account_address: address): u64 {
        if (!check_stake_exists(stability_pool_storage, account_address)) return 0;
        let stake = table::borrow(&stability_pool_storage.stake_table, account_address);
        stake.amount
    }

    /// Returns the total amount of tokens staked in the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// 
    /// # Returns
    /// 
    /// The total amount of tokens staked in the stability pool
    public fun get_total_stake_amount(stability_pool_storage: &StabilityPoolStorage): u64 {
        balance::value(&stability_pool_storage.stake_balance)
    }

    // =================== Helpers ===================

    /// Check if a stake exists for a given account address in the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// * `account_address` - the address of the account
    /// 
    /// # Returns
    /// 
    /// `true` if a stake exists for the account, `false` otherwise
    fun check_stake_exists(stability_pool_storage: &StabilityPoolStorage, account_address: address): bool {
        table::contains(&stability_pool_storage.stake_table, account_address)
    }
    
    /// Borrow stake from the StabilityPoolStorage for a given account address.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// * `account_address` - the address of the account
    /// 
    /// # Returns
    /// 
    /// A mutable reference to the stake for the account
    fun borrow_stake(stability_pool_storage: &mut StabilityPoolStorage, account_address: address): &mut Stake {
        table::borrow_mut(&mut stability_pool_storage.stake_table, account_address)
    }

    /// Removes the stake for a given account address from the stability pool.
    /// 
    /// # Arguments
    /// 
    /// * `stability_pool_storage` - the storage for the stability pool
    /// * `account_address` - the address of the account
    fun remove_stake(stability_pool_storage: &mut StabilityPoolStorage, account_address: address) {
        table::remove(&mut stability_pool_storage.stake_table, account_address);
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}