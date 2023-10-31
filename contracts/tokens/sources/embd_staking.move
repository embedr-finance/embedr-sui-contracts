/// EMBD Staking is responsible for managing the staking of EMBD tokens
module tokens::embd_staking {
    #[test_only]
    use sui::object::{ID};

    use sui::package::{Self, Publisher};
    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::coin::{Self, Coin};
    use sui::balance::{Self, Balance};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    use tokens::embd_incentive_token::{Self, EMBD_INCENTIVE_TOKEN, EMBDIncentiveTokenStorage};

    const ERROR_STAKE_NOT_FOUND: u64 = 1;

    /// OTW for EMBD Staking
    struct EMBD_STAKING has drop {}

    /// Defines the data structure for saving the publisher
    struct EMBDStakingPublisher has key {
        id: UID,
        publisher: Publisher
    }

    /// Stake represents the amount of tokens staked by an account
    /// 
    /// # Fields
    /// 
    /// * `account_address` - the address of the account that staked the tokens
    /// * `amount` - the amount of tokens staked
    struct Stake has store, drop {
        account_address: address,
        amount: u64
    }

    /// StakingStorage is the storage for the staking module
    /// 
    /// # Fields
    /// 
    /// * `stake_table` - the table of stakes
    /// * `stake_balance` - the total amount of tokens staked
    struct EMBDStakingStorage has key, store {
        id: UID,
        stake_table: Table<address, Stake>,
        stake_balance: Balance<EMBD_INCENTIVE_TOKEN>
    }

    // =================== Initializer ===================

    fun init(witness: EMBD_STAKING, ctx: &mut TxContext) {
        transfer::share_object(EMBDStakingStorage {
            id: object::new(ctx),
            stake_table: table::new(ctx),
            stake_balance: balance::zero()
        });
        transfer::share_object(EMBDStakingPublisher {
            id: object::new(ctx),
            publisher: package::claim<EMBD_STAKING>(witness, ctx)
        });
    }

    // =================== Entry Methods ===================

    /// Deposit allows an account to stake EMBD tokens
    /// 
    /// # Arguments
    /// 
    /// * `token` - the coin object containing the amount of tokens to stake
    entry fun deposit(
        es_publisher: &EMBDStakingPublisher,
        es_storage: &mut EMBDStakingStorage,
        eit_storage: &mut EMBDIncentiveTokenStorage,
        token: Coin<EMBD_INCENTIVE_TOKEN>,
        ctx: &mut TxContext
    ) {
        deposit_(
            es_publisher,
            es_storage,
            eit_storage,
            token,
            ctx
        )
    }

    /// Withdraw allows an account to withdraw EMBD tokens from their stake
    /// 
    /// # Arguments
    /// 
    /// * `amount` - the amount of tokens to withdraw
    entry fun withdraw(
        es_publisher: &EMBDStakingPublisher,
        es_storage: &mut EMBDStakingStorage,
        eit_storage: &mut EMBDIncentiveTokenStorage,
        amount: u64,
        ctx: &mut TxContext
    ) {
        withdraw_(
            es_publisher,
            es_storage,
            eit_storage,
            amount,
            ctx
        )
    }

    // =================== Query Methods ===================

    /// Get the total amount of tokens staked in the staking module
    /// 
    /// # Returns
    /// 
    /// * `u64` - the total amount of tokens staked
    public fun get_total_stake_amount(storage: &EMBDStakingStorage): u64 {
        balance::value(&storage.stake_balance)
    }

    /// Get the amount of tokens staked by an account
    /// 
    /// # Arguments
    /// 
    /// * `account_address` - the address of the account to get the stake amount for
    /// 
    /// # Returns
    /// 
    /// * `u64` - the amount of tokens staked by the account
    public fun get_stake_amount(storage: &EMBDStakingStorage, account_address: address): u64 {
        let stake: u64;
        if (check_stake_exists(storage, account_address)) {
            stake = read_stake(storage, account_address).amount
        }
        else stake = 0;
        stake
    }

    // =================== Helpers ===================

    /// deposit_ is the internal implementation of the deposit entry method
    fun deposit_(
        es_publisher: &EMBDStakingPublisher,
        es_storage: &mut EMBDStakingStorage,
        eit_storage: &mut EMBDIncentiveTokenStorage,
        token: Coin<EMBD_INCENTIVE_TOKEN>,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);
        let amount = coin::value(&token);

        // Check if the account has a stake before depositing
        // Create a stake if the account does not have one
        if (!check_stake_exists(es_storage, account_address)) {
            table::add(
                &mut es_storage.stake_table,
                account_address, 
                Stake {
                    account_address: account_address,
                    amount: 0
                }
            );
        };

        // Update the user stake amount
        let stake = borrow_stake(es_storage, account_address);
        stake.amount = stake.amount + amount;

        // Update the total stake amount
        coin::put(&mut es_storage.stake_balance, token);

        // Decrease the account balance by the amount being staked
        embd_incentive_token::update_account_balance(
            get_publisher(es_publisher),
            eit_storage,
            account_address,
            amount,
            false
        );
    }

    /// withdraw_ is the internal implementation of the withdraw entry method
    fun withdraw_(
        es_publisher: &EMBDStakingPublisher,
        es_storage: &mut EMBDStakingStorage,
        eit_storage: &mut EMBDIncentiveTokenStorage,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        // Check if the account has a stake before withdrawing
        assert!(check_stake_exists(es_storage, account_address), ERROR_STAKE_NOT_FOUND);

        // Update the user stake amount
        let stake = borrow_stake(es_storage, account_address);
        stake.amount = stake.amount - amount;

        // If the stake amount is equal to the amount being withdrawn, remove the stake
        if (stake.amount == 0) {
            remove_stake(es_storage, account_address);
        };

        // Transfer the tokens to the account
        let token = coin::take(
            &mut es_storage.stake_balance,
            amount,
            ctx
        );
        transfer::public_transfer(token, account_address);

        // Increase the account balance by the amount being withdrawn
        embd_incentive_token::update_account_balance(
            get_publisher(es_publisher),
            eit_storage,
            account_address,
            amount,
            true
        );
    }

    fun check_stake_exists(storage: &EMBDStakingStorage, account_address: address): bool {
        table::contains(&storage.stake_table, account_address)
    }

    fun borrow_stake(storage: &mut EMBDStakingStorage, account_address: address): &mut Stake {
        table::borrow_mut(&mut storage.stake_table, account_address)
    }

    fun read_stake(storage: &EMBDStakingStorage, account_address: address): &Stake {
        table::borrow(&storage.stake_table, account_address)
    }

    fun remove_stake(storage: &mut EMBDStakingStorage, account_address: address) {
        table::remove(&mut storage.stake_table, account_address);
    }

    public fun get_publisher(storage: &EMBDStakingPublisher): &Publisher {
        &storage.publisher
    }

    #[test_only]
    public fun get_publisher_id(publisher: &EMBDStakingPublisher): ID {
        object::id(&publisher.publisher)
    }

    #[test_only]
    public fun deposit_for_testing(
        es_publisher: &EMBDStakingPublisher,
        es_storage: &mut EMBDStakingStorage,
        eit_storage: &mut EMBDIncentiveTokenStorage,
        token: Coin<EMBD_INCENTIVE_TOKEN>,
        ctx: &mut TxContext
    ) {
        deposit_(
            es_publisher,
            es_storage,
            eit_storage,
            token,
            ctx
        );
    }

    #[test_only]
    public fun withdraw_for_testing(
        es_publisher: &EMBDStakingPublisher,
        es_storage: &mut EMBDStakingStorage,
        eit_storage: &mut EMBDIncentiveTokenStorage,
        amount: u64,
        ctx: &mut TxContext
    ) {
        withdraw_(
            es_publisher,
            es_storage,
            eit_storage,
            amount,
            ctx
        );
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(EMBD_STAKING {}, ctx);
    }
}
