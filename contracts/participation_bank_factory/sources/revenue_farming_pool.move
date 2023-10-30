module participation_bank_factory::revenue_farming_pool {
    use std::string;

    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::balance::{Self, Balance};
    use sui::vec_set::{Self, VecSet};
    use sui::vec_map::{Self, VecMap};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;

    use tokens::rusd_stable_coin::{RUSD_STABLE_COIN};

    // =================== Errors ===================

    const ERROR_FARMING_POOL_ALREADY_EXISTS: u64 = 1;
    const ERROR_FARMING_POOL_NOT_FOUND: u64 = 2;
    const ERROR_POOL_REQUEST_NOT_FOUND: u64 = 3;

    // =================== Storage ===================

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

    // =================== Initializer ===================

    fun init(ctx: &mut TxContext) {
        transfer::share_object(RevenueFarmingPoolStorage {
            id: object::new(ctx),
            pool_table: table::new(ctx),
        });
        transfer::transfer(
            RevenueFarmingPoolAdminCap { id: object::new(ctx) },
            tx_context::sender(ctx)
        );
    }

    // =================== Entry Methods ===================

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
    entry fun deposit() {}

    /// Withdraws stable coin from a given pool
    entry fun withdraw() {}

    /// Requests liquidity from a given pool
    entry fun request_liquidity() {}

    // =================== Query Methods ===================

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

    // =================== Helpers ===================

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
    public fun deposit_for_testing() {

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
    public fun get_pool_requests_size_for_testing(
        fp_storage: &FarmingPoolStorage,
    ): u64 {
        vec_map::size(&fp_storage.pool_requests)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }
}
