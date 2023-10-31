module participation_bank_factory::revenue_farming_pool {
    use std::string;
    use std::option::{Self, Option};

    use sui::object::{Self, UID, ID};
    use sui::table::{Self, Table};
    use sui::balance::{Self, Balance};
    use sui::vec_set::{Self, VecSet};
    use sui::vec_map::{Self, VecMap};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::coin::{Self, Coin};
    use sui::package::{Self, Publisher};

    use tokens::rusd_stable_coin::{Self, RUSD_STABLE_COIN, RUSDStableCoinStorage};

    // =================== @Errors ===================

    const ERROR_FARMING_POOL_ALREADY_EXISTS: u64 = 1;
    const ERROR_FARMING_POOL_NOT_FOUND: u64 = 2;
    const ERROR_POOL_REQUEST_NOT_FOUND: u64 = 3;
    const ERROR_POOL_NOT_FOUND: u64 = 4;
    const ERROR_STAKE_NOT_FOUND: u64 = 5;
    const ERROR_LIQUIDITY_REQUEST_NOT_FOUND: u64 = 6;
    const ERROR_LIQUIDITY_REQUEST_ALREADY_EXISTS: u64 = 7;
    const ERROR_POOL_INSUFFICIENT_BALANCE: u64 = 8;

    // =================== @Storage ===================

    /// FarmingPoolStake is the stake of a user in a given pool
    /// 
    /// # Fields
    /// 
    /// - `account_address`: The address of the user
    /// - `amount`: The amount of stable coin staked by the user
    struct FarmingPoolStake has store, drop {
        account_address: address,
        amount: u64,
    }

    /// SinglePoolStorage is the storage for a single business pool
    /// 
    /// # Fields
    /// 
    /// - `stake_table`: The table of all stakes in this pool
    /// - `balance`: The balance of the total stable coin in this pool
    struct SinglePoolStorage has store {
        name: string::String,
        description: string::String,
        stake_table: Table<address, FarmingPoolStake>,
        balance: Balance<RUSD_STABLE_COIN>,
        liquidity_request: Option<u64>,
    }

    /// FarmingPoolStorage is the storage for a single business pool storage
    /// 
    /// # Fields
    /// 
    /// - `pool_id`: Incremental ID for the single pools
    /// - `active_pools`: The list of active pools for this revenue farming pool
    /// - `pool_table`: The table of all pools
    struct FarmingPoolStorage has store {
        pool_id: u64,
        active_pools: VecSet<u64>,
        pool_table: Table<u64, SinglePoolStorage>,
        pool_requests: VecMap<u64, SinglePoolStorage>,
    }

    /// RevenueFarmingPoolStorage is the storage for this module
    /// 
    /// # Fields
    /// 
    /// - `pool_table`: The table of all business pool storages
    struct RevenueFarmingPoolStorage has key {
        id: UID,
        pool_table: Table<address, FarmingPoolStorage>,
    }

    /// Admin capability object
    struct RevenueFarmingPoolAdminCap has key { id: UID }

    /// Publisher capability object
    struct RevenueFarmingPoolPublisher has key { id: UID, publisher: Publisher }

    /// OTW
    struct REVENUE_FARMING_POOL has drop {}

    // =================== @Initializer ===================

    fun init(witness: REVENUE_FARMING_POOL, ctx: &mut TxContext) {
        transfer::share_object(RevenueFarmingPoolStorage {
            id: object::new(ctx),
            pool_table: table::new(ctx),
        });
        transfer::transfer(
            RevenueFarmingPoolAdminCap { id: object::new(ctx) },
            tx_context::sender(ctx)
        );
        transfer::share_object(RevenueFarmingPoolPublisher {
            id: object::new(ctx),
            publisher: package::claim<REVENUE_FARMING_POOL>(witness, ctx)
        });
    }

    // =================== @Entry Methods ===================

    /// Adds a new farming pool to the protocol for a given business
    /// 
    /// # Arguments
    /// 
    /// * `name` - The name of the farming pool
    /// * `description` - The description of the farming pool
    entry fun add_farming_pool(
        _: &RevenueFarmingPoolAdminCap,
        rfp_storage: &mut RevenueFarmingPoolStorage,
        account_address: address,
        ctx: &mut TxContext
    ) {
        add_farming_pool_(
            rfp_storage,
            account_address,
            ctx
        );
    }

    /// Requests a new pool to be created
    /// TODO: Add NFT here for the KYB information
    entry fun request_pool(
        rfp_storage: &mut RevenueFarmingPoolStorage,
        name: string::String,
        description: string::String,
        ctx: &mut TxContext
    ) {
        request_pool_(
            rfp_storage,
            name,
            description,
            ctx
        )
    }

    /// Approves a pool request
    entry fun approve_pool_request(
        _: &RevenueFarmingPoolAdminCap,
        rfp_storage: &mut RevenueFarmingPoolStorage,
        account_address: address,
        pool_id: u64,
    ) {
        approve_pool_request_(
            rfp_storage,
            account_address,
            pool_id,
        )
    }

    /// Deposits stable coin to a given pool
    /// 
    /// # Arguments
    /// 
    /// * `pool_address` - The address of pool
    /// * `pool_id` - The ID of the pool
    /// * `stable_coin` - The amount of stable coin to deposit
    entry fun deposit(
        rfp_publisher: &RevenueFarmingPoolPublisher,
        rfp_storage: &mut RevenueFarmingPoolStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        pool_address: address,
        pool_id: u64,
        stable_coin: Coin<RUSD_STABLE_COIN>,
        ctx: &mut TxContext
    ) {
        deposit_(
            rfp_publisher,
            rfp_storage,
            rsc_storage,
            pool_address,
            pool_id,
            stable_coin,
            ctx
        )
    }

    /// Withdraws stable coin from a given pool
    /// 
    /// # Arguments
    /// 
    /// * `pool_address` - The address of pool
    /// * `pool_id` - The ID of the pool
    /// * `amount` - The amount of stable coin to withdraw
    entry fun withdraw(
        rfp_publisher: &RevenueFarmingPoolPublisher,
        rfp_storage: &mut RevenueFarmingPoolStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        pool_address: address,
        pool_id: u64,
        amount: u64,
        ctx: &mut TxContext
    ) {
        withdraw_(
            rfp_publisher,
            rfp_storage,
            rsc_storage,
            pool_address,
            pool_id,
            amount,
            ctx
        )
    }

    /// Requests liquidity from a given pool
    /// 
    /// # Arguments
    /// 
    /// * `pool_id` - The ID of the pool
    /// * `amount` - The amount of stable coin to request
    entry fun request_liquidity(
        rfp_storage: &mut RevenueFarmingPoolStorage,
        pool_id: u64,
        amount: u64,
        ctx: &mut TxContext
    ) {
        request_liquidity_(
            rfp_storage,
            pool_id,
            amount,
            ctx
        );
    }

    /// Approves a liquidity request 
    /// 
    /// # Arguments
    /// 
    /// * `pool_address` - The address of pool
    /// * `pool_id` - The ID of the pool
    entry fun approve_liquidity_request(
        _: &RevenueFarmingPoolAdminCap,
        rfp_publisher: &RevenueFarmingPoolPublisher,
        rfp_storage: &mut RevenueFarmingPoolStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        pool_address: address,
        pool_id: u64,
        ctx: &mut TxContext
    ) {
        approve_liquidity_request_(
            rfp_publisher,
            rfp_storage,
            rsc_storage,
            pool_address,
            pool_id,
            ctx
        )
    }

    // =================== @Query Methods ===================

    // TODO: Do we need this?
    public fun get_farming_pool(
        rfp_storage: &RevenueFarmingPoolStorage,
        account_address: address,
    ): &FarmingPoolStorage {
        // Make sure farming pool for this account exists
        assert!(table::contains(&rfp_storage.pool_table, account_address), ERROR_FARMING_POOL_NOT_FOUND);

        // Borrow the farming pool
        table::borrow(&rfp_storage.pool_table, account_address)
    }

    public fun get_stake_amount(
        rfp_storage: &RevenueFarmingPoolStorage,
        pool_address: address,
        pool_id: u64,
        account_address: address
    ): u64 {
        // Make sure farming pool for this account exists
        assert!(table::contains(&rfp_storage.pool_table, pool_address), ERROR_FARMING_POOL_NOT_FOUND);

        let farming_pool = table::borrow(&rfp_storage.pool_table, pool_address);

        // Make sure the pool exists
        assert!(table::contains(&farming_pool.pool_table, pool_id), ERROR_FARMING_POOL_NOT_FOUND);

        let single_pool = table::borrow(&farming_pool.pool_table, pool_id);

        // Make sure the stake exists
        if (table::contains(&single_pool.stake_table, account_address)) {
            table::borrow(&single_pool.stake_table, account_address).amount
        } else return 0
    }

    public fun get_pool_stake_amount(
        rfp_storage: &RevenueFarmingPoolStorage,
        pool_address: address,
        pool_id: u64,
    ): u64 {
        // Make sure farming pool for this account exists
        assert!(table::contains(&rfp_storage.pool_table, pool_address), ERROR_FARMING_POOL_NOT_FOUND);

        let farming_pool = table::borrow(&rfp_storage.pool_table, pool_address);

        // Make sure the pool exists
        assert!(table::contains(&farming_pool.pool_table, pool_id), ERROR_FARMING_POOL_NOT_FOUND);

        balance::value(&table::borrow(&farming_pool.pool_table, pool_id).balance)
    }

    // =================== @Helpers ===================

    /// add_farming_pool_ is the internal implementation of the add_farming_pool entry method
    fun add_farming_pool_(
        rfp_storage: &mut RevenueFarmingPoolStorage,
        account_address: address,
        ctx: &mut TxContext
    ) {
        // Make sure farming pool for this account does not exist
        assert!(!table::contains(&rfp_storage.pool_table, account_address), ERROR_FARMING_POOL_ALREADY_EXISTS);

        let farming_pool = FarmingPoolStorage {
            pool_id: 0,
            active_pools: vec_set::empty(),
            pool_table: table::new(ctx),
            pool_requests: vec_map::empty(),
        };
        table::add(&mut rfp_storage.pool_table, account_address, farming_pool);
    }

    /// request_pool_ is the internal implementation of the request_pool entry method
    fun request_pool_(
        rfp_storage: &mut RevenueFarmingPoolStorage,
        name: string::String,
        description: string::String,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        // Make sure farming pool for this account exists
        assert!(table::contains(&rfp_storage.pool_table, account_address), ERROR_FARMING_POOL_NOT_FOUND);

        // Borrow the farming pool
        let farming_pool = table::borrow_mut(&mut rfp_storage.pool_table, account_address);

        // Increment the pool ID
        let pool_id = farming_pool.pool_id + 1;

        // Create a new single pool storage
        let single_pool = SinglePoolStorage {
            name,
            description,
            stake_table: table::new(ctx),
            balance: balance::zero(),
            liquidity_request: option::none()
        };

        // Insert the pool request into the farming pool
        vec_map::insert(&mut farming_pool.pool_requests, pool_id, single_pool);
    }

    /// approve_pool_request_ is the internal implementation of the approve_pool_request entry method
    fun approve_pool_request_(
        rfp_storage: &mut RevenueFarmingPoolStorage,
        account_address: address,
        pool_id: u64,
    ) {
        // Make sure farming pool for this account exists
        assert!(table::contains(&rfp_storage.pool_table, account_address), ERROR_FARMING_POOL_NOT_FOUND);

        let farming_pool = table::borrow_mut(&mut rfp_storage.pool_table, account_address);

        // Make sure the pool request exists
        assert!(vec_map::contains(&farming_pool.pool_requests, &pool_id), ERROR_POOL_REQUEST_NOT_FOUND);

        // Remove the pool request from farming pool
        let (pool_id, single_pool) = vec_map::remove(&mut farming_pool.pool_requests, &pool_id);

        // Insert the pool into the farming pool
        table::add(&mut farming_pool.pool_table, pool_id, single_pool);

        // Add the pool to the active pools
        vec_set::insert(&mut farming_pool.active_pools, pool_id);
    }

    /// deposit_ is the internal implementation of the deposit entry method
    fun deposit_(
        rfp_publisher: &RevenueFarmingPoolPublisher,
        rfp_storage: &mut RevenueFarmingPoolStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        pool_address: address,
        pool_id: u64,
        stable_coin: Coin<RUSD_STABLE_COIN>,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);
        let amount = coin::value(&stable_coin);

        // Make sure farming pool exists for pool address
        assert!(table::contains(&rfp_storage.pool_table, pool_address), ERROR_FARMING_POOL_NOT_FOUND);

        let farming_pool = table::borrow_mut(&mut rfp_storage.pool_table, pool_address);
        let single_pool = table::borrow_mut(&mut farming_pool.pool_table, pool_id);

        // Create a new stake if it does not exist
        if (!check_stake_exists(single_pool, account_address)) {
            table::add(&mut single_pool.stake_table, account_address,
                FarmingPoolStake {
                    account_address,
                    amount: 0,
                }
            )
        };

        // Update the stake amount for the user
        let stake = table::borrow_mut(&mut single_pool.stake_table, account_address);
        stake.amount = stake.amount + amount;

        // Update the balance of the pool
        coin::put(&mut single_pool.balance, stable_coin);

        // Update the balance of the user in the stable coin
        rusd_stable_coin::update_account_balance(
            rsc_storage,
            get_publisher(rfp_publisher),
            account_address,
            amount,
            false
        )
    }

    /// withdraw_ is the internal implementation of the withdraw entry method
    fun withdraw_(
        rfp_publisher: &RevenueFarmingPoolPublisher,
        rfp_storage: &mut RevenueFarmingPoolStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        pool_address: address,
        pool_id: u64,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        // Make sure farming pool exists for pool address
        assert!(table::contains(&rfp_storage.pool_table, pool_address), ERROR_FARMING_POOL_NOT_FOUND);

        let farming_pool = table::borrow_mut(&mut rfp_storage.pool_table, pool_address);
        let single_pool = table::borrow_mut(&mut farming_pool.pool_table, pool_id);

        // Make sure the stake exists
        assert!(check_stake_exists(single_pool, account_address), ERROR_STAKE_NOT_FOUND);

        // Update the stake amount for the user
        let stake = table::borrow_mut(&mut single_pool.stake_table, account_address);
        stake.amount = stake.amount - amount;

        // If the stake amount is equal to the amount being withdrawn, remove the stake
        if (stake.amount == 0) {
            table::remove(&mut single_pool.stake_table, account_address);
        };

        // Transfer the stable coin to the account
        let stable_coin = coin::take(
            &mut single_pool.balance,
            amount,
            ctx
        );
        transfer::public_transfer(stable_coin, account_address);

        // Update the balance of the user in the stable coin
        rusd_stable_coin::update_account_balance(
            rsc_storage,
            get_publisher(rfp_publisher),
            account_address,
            amount,
            true
        )
    }

    /// request_liquidity_ is the internal implementation of the request_liquidity entry method
    fun request_liquidity_(
        rfp_storage: &mut RevenueFarmingPoolStorage,
        pool_id: u64,
        amount: u64,
        ctx: &mut TxContext
    ) {
        let account_address = tx_context::sender(ctx);

        // Make sure farming pool exists for pool address
        assert!(table::contains(&rfp_storage.pool_table, account_address), ERROR_FARMING_POOL_NOT_FOUND);
        let farming_pool = table::borrow_mut(&mut rfp_storage.pool_table, account_address);

        assert!(table::contains(&farming_pool.pool_table, pool_id), ERROR_POOL_NOT_FOUND);
        let single_pool = table::borrow_mut(&mut farming_pool.pool_table, pool_id);

        // Make sure the liquidity request does not exist already
        assert!(option::is_none(&single_pool.liquidity_request), ERROR_LIQUIDITY_REQUEST_ALREADY_EXISTS);

        // Make sure amount is less than the balance of the pool
        assert!(amount <= balance::value(&single_pool.balance), ERROR_POOL_INSUFFICIENT_BALANCE);

        // Create a new liquidity request
        single_pool.liquidity_request = option::some(amount);
    }

    /// approve_liquidity_request_ is the internal implementation of the approve_liquidity_request entry method
    fun approve_liquidity_request_(
        rfp_publisher: &RevenueFarmingPoolPublisher,
        rfp_storage: &mut RevenueFarmingPoolStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        pool_address: address,
        pool_id: u64,
        ctx: &mut TxContext
    ) {
        // Make sure farming pool exists for pool address
        assert!(table::contains(&rfp_storage.pool_table, pool_address), ERROR_FARMING_POOL_NOT_FOUND);
        let farming_pool = table::borrow_mut(&mut rfp_storage.pool_table, pool_address);

        assert!(table::contains(&farming_pool.pool_table, pool_id), ERROR_POOL_NOT_FOUND);
        let single_pool = table::borrow_mut(&mut farming_pool.pool_table, pool_id);

        // Make sure the liquidity request exists
        assert!(option::is_some(&single_pool.liquidity_request), ERROR_LIQUIDITY_REQUEST_NOT_FOUND);

        // Get the liquidity request
        let liquidity_request = option::destroy_some(single_pool.liquidity_request);

        // Remove the liquidity request
        single_pool.liquidity_request = option::none();

        // Take the stable coin from the pool
        let stable_coin = coin::take(
            &mut single_pool.balance,
            liquidity_request,
            ctx
        );
        // Update the balance of the account in the stable coin
        rusd_stable_coin::update_account_balance(
            rsc_storage,
            get_publisher(rfp_publisher),
            pool_address,
            coin::value(&stable_coin),
            true
        );
        // Transfer the stable coin to the account
        transfer::public_transfer(stable_coin, pool_address);

        // TODO: We also need to save user stakes to calculate their rewards
    }

    fun check_stake_exists(storage: &SinglePoolStorage, account_address: address): bool {
        table::contains(&storage.stake_table, account_address)
    }

    #[test_only]
    public fun add_farming_pool_for_testing(
        rfp_storage: &mut RevenueFarmingPoolStorage,
        account_address: address,
        ctx: &mut TxContext
    ) {
        add_farming_pool_(
            rfp_storage,
            account_address,
            ctx
        );
    }

    #[test_only]
    public fun request_pool_for_testing(
        rfp_storage: &mut RevenueFarmingPoolStorage,
        name: string::String,
        description: string::String,
        ctx: &mut TxContext
    ) {
        request_pool_(
            rfp_storage,
            name,
            description,
            ctx
        )
    }

    #[test_only]
    public fun approve_pool_request_for_testing(
        rfp_storage: &mut RevenueFarmingPoolStorage,
        account_address: address,
        pool_id: u64,
    ) {
        approve_pool_request_(
            rfp_storage,
            account_address,
            pool_id,
        )
    }

    #[test_only]
    public fun deposit_for_testing(
        rfp_publisher: &RevenueFarmingPoolPublisher,
        rfp_storage: &mut RevenueFarmingPoolStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        pool_address: address,
        pool_id: u64,
        stable_coin: Coin<RUSD_STABLE_COIN>,
        ctx: &mut TxContext
    ) {
        deposit_(
            rfp_publisher,
            rfp_storage,
            rsc_storage,
            pool_address,
            pool_id,
            stable_coin,
            ctx
        )
    }

    #[test_only]
    public fun withdraw_for_testing(
        rfp_publisher: &RevenueFarmingPoolPublisher,
        rfp_storage: &mut RevenueFarmingPoolStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        pool_address: address,
        pool_id: u64,
        amount: u64,
        ctx: &mut TxContext
    ) {
        withdraw_(
            rfp_publisher,
            rfp_storage,
            rsc_storage,
            pool_address,
            pool_id,
            amount,
            ctx
        )
    }

    #[test_only]
    public fun request_liquidity_for_testing(
        rfp_storage: &mut RevenueFarmingPoolStorage,
        pool_id: u64,
        amount: u64,
        ctx: &mut TxContext
    ) {
        request_liquidity_(
            rfp_storage,
            pool_id,
            amount,
            ctx
        );
    }

    #[test_only]
    public fun approve_liquidity_request_for_testing(
        rp_publisher: &RevenueFarmingPoolPublisher,
        rfp_storage: &mut RevenueFarmingPoolStorage,
        rsc_storage: &mut RUSDStableCoinStorage,
        pool_address: address,
        pool_id: u64,
        ctx: &mut TxContext
    ) {
        approve_liquidity_request_(
            rp_publisher,
            rfp_storage,
            rsc_storage,
            pool_address,
            pool_id,
            ctx
        )
    }

    #[test_only]
    public fun get_active_pools_size_for_testing(
        fp_storage: &FarmingPoolStorage,
    ): u64 {
        vec_set::size(&fp_storage.active_pools)
    }

    #[test_only]
    public fun get_single_pool_for_testing(
        fp_storage: &FarmingPoolStorage,
        pool_id: u64,
    ): (string::String, string::String) {
        let pool = table::borrow(&fp_storage.pool_table, pool_id);
        (pool.name, pool.description)
    }

    #[test_only]
    public fun get_single_pool_liquidity_request_for_testing(
        fp_storage: &FarmingPoolStorage,
        pool_id: u64,
    ): Option<u64> {
        let pool = table::borrow(&fp_storage.pool_table, pool_id);
        pool.liquidity_request
    }

    #[test_only]
    public fun get_pool_requests_size_for_testing(
        fp_storage: &FarmingPoolStorage,
    ): u64 {
        vec_map::size(&fp_storage.pool_requests)
    }

    public fun get_publisher(storage: &RevenueFarmingPoolPublisher): &Publisher {
        &storage.publisher
    }

    #[test_only]
    public fun get_publisher_id(publisher: &RevenueFarmingPoolPublisher): ID {
        object::id(&publisher.publisher)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(REVENUE_FARMING_POOL {}, ctx)
    }
}
