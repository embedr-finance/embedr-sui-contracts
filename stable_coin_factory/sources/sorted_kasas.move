module stable_coin_factory::sorted_kasas {
    use std::option::{Self, Option};

    use sui::object::{Self, UID};
    use sui::table::{Self, Table};
    use sui::tx_context::TxContext;
    use sui::transfer;

    use stable_coin_factory::kasa_storage::{Self, KasaManagerStorage};
    // use library::utils::logger;

    friend stable_coin_factory::kasa_operations;
    friend stable_coin_factory::kasa_manager;

    // =================== Errors ===================

    const ERROR_LIST_FULL: u64 = 1;
    const ERROR_EXISTING_ITEM: u64 = 2;
    // const ERROR_INVALID: u64 = 3;
    const ERROR_RATIO: u64 = 3;

    // =================== Storage ===================

    struct Node has store, drop {
        exists: bool,
        next_id: Option<address>,
        prev_id: Option<address>,
    }

    struct SortedKasasStorage has key {
        id: UID,
        head: Option<address>,
        tail: Option<address>,
        max_size: u64,
        size: u64,
        node_table: Table<address, Node>
    }

    // =================== Initialize ===================

    fun init(ctx: &mut TxContext) {
        transfer::share_object(SortedKasasStorage {
            id: object::new(ctx),
            head: option::none(),
            tail: option::none(),
            max_size: 1000000,
            size: 0,
            node_table: table::new(ctx)
        });
    }

    // =================== Entries ===================

    public(friend) fun insert(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasas_storage: &mut SortedKasasStorage,
        id: address,
        nicr: u256,
        prev_id: Option<address>,
        next_id: Option<address>,
        _ctx: &mut TxContext
    ) {
        // TODO: Make sure only kasa manager module can call this contract

        insert_node(
            kasa_manager_storage,
            sorted_kasas_storage,
            id,
            nicr,
            prev_id,
            next_id
        );
    }

    public(friend) fun remove(
        sorted_kasas_storage: &mut SortedKasasStorage,
        id: address,
    ) {
        // TODO: Make sure only kasa manager module can call this contract

        remove_node(
            sorted_kasas_storage,
            id
        );
    }

    public(friend) fun reinsert(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasas_storage: &mut SortedKasasStorage,
        id: address,
        nicr: u256,
        prev_id: Option<address>,
        next_id: Option<address>,
        _ctx: &mut TxContext
    ) {
        // TODO: Make sure only kasa manager module can call this contract

        // Make sure the list contains the item
        assert!(contains(sorted_kasas_storage, id), ERROR_EXISTING_ITEM);
        // Nominal collateral ratio must be higher than 0
        assert!(nicr > 0, ERROR_RATIO);

        remove_node(
            sorted_kasas_storage,
            id
        );

        insert_node(
            kasa_manager_storage,
            sorted_kasas_storage,
            id,
            nicr,
            prev_id,
            next_id
        );
    }

    // =================== Queries ===================

    public fun check_insert_position(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasas_storage: &mut SortedKasasStorage,
        nicr: u256,
        prev_id: Option<address>,
        next_id: Option<address>,
        _ctx: &mut TxContext
    ): bool {
        check_node_position(
            kasa_manager_storage,
            sorted_kasas_storage,
            nicr,
            prev_id,
            next_id
        )
    }

    public fun find_insert_position(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasas_storage: &mut SortedKasasStorage,
        nicr: u256,
        prev_id: Option<address>,
        next_id: Option<address>,
        _ctx: &mut TxContext
    ): (Option<address>, Option<address>) {
        find_node_position(
            kasa_manager_storage,
            sorted_kasas_storage,
            nicr,
            prev_id,
            next_id
        )
    }

    public fun get_size(sorted_kasas_storage: &SortedKasasStorage): u64 {
        sorted_kasas_storage.size
    }

    public fun get_first(sorted_kasas_storage: &SortedKasasStorage): Option<address> {
        sorted_kasas_storage.head
    }

    public fun get_last(sorted_kasas_storage: &SortedKasasStorage): Option<address> {
        sorted_kasas_storage.tail
    }

    public fun get_next(sorted_kasas_storage: &SortedKasasStorage, id: address): Option<address> {
        table::borrow(&sorted_kasas_storage.node_table, id).next_id
    }

    public fun get_prev(sorted_kasas_storage: &SortedKasasStorage, id: address): Option<address> {
        table::borrow(&sorted_kasas_storage.node_table, id).prev_id
    }

    // =================== Helpers ===================

    fun contains(sorted_kasas_storage: &mut SortedKasasStorage, id: address): bool {
        table::contains(&sorted_kasas_storage.node_table, id)
    }

    fun is_full(sorted_kasas_storage: &mut SortedKasasStorage): bool {
        sorted_kasas_storage.size == sorted_kasas_storage.max_size
    }

    fun is_empty(sorted_kasas_storage: &mut SortedKasasStorage): bool {
        sorted_kasas_storage.size == 0
    }

    // fun get_max_size(sorted_kasas_storage: &mut SortedKasasStorage): u64 {
    //     sorted_kasas_storage.max_size
    // }

    fun insert_node(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasas_storage: &mut SortedKasasStorage,
        id: address,
        nicr: u256,
        prev_id: Option<address>,
        next_id: Option<address>
    ) {
        let prev_id = prev_id;
        let next_id = next_id;

        // List must not be full
        assert!(!is_full(sorted_kasas_storage), ERROR_LIST_FULL);
        // List must have only one item for an address
        assert!(!contains(sorted_kasas_storage, id), ERROR_EXISTING_ITEM);
        // Nominal collateral ratio must be higher than 0 
        assert!(nicr > 0, ERROR_RATIO);

        // Check for the insert positon
        if (
            !check_node_position(
                kasa_manager_storage,
                sorted_kasas_storage,
                nicr,
                prev_id,
                next_id
            )
        ) {
            (prev_id, next_id) = find_node_position(
                kasa_manager_storage,
                sorted_kasas_storage,
                nicr,
                prev_id,
                next_id
            );
        };

        // Save the node in the table
        let node = Node {
            exists: true,
            prev_id,
            next_id
        };
        table::add(&mut sorted_kasas_storage.node_table, id, node);

        if (option::is_none(&prev_id) && option::is_none(&next_id)) {
            // Insert as the head and tail
            sorted_kasas_storage.head = option::some(id);
            sorted_kasas_storage.tail = option::some(id);
        } else if (option::is_none(&prev_id)) {
            // Insert before prev_id as the head
            table::borrow_mut(
                &mut sorted_kasas_storage.node_table,
                id
            ).next_id = sorted_kasas_storage.head;
            table::borrow_mut(
                &mut sorted_kasas_storage.node_table,
                option::destroy_some(sorted_kasas_storage.head)
            ).prev_id = option::some(id);
            sorted_kasas_storage.head = option::some(id);
        } else if (option::is_none(&next_id)) {
            // Insert before the next_id as the tail
            table::borrow_mut(
                &mut sorted_kasas_storage.node_table,
                id
            ).prev_id = sorted_kasas_storage.tail;
            table::borrow_mut(
                &mut sorted_kasas_storage.node_table,
                option::destroy_some(sorted_kasas_storage.tail)
            ).next_id = option::some(id);
            sorted_kasas_storage.tail = option::some(id);
        } else {
            // Insert at insert position between `prevId` and `nextId`
            table::borrow_mut(
                &mut sorted_kasas_storage.node_table,
                id
            ).prev_id = prev_id;
            table::borrow_mut(
                &mut sorted_kasas_storage.node_table,
                id
            ).next_id = next_id;
            table::borrow_mut(
                &mut sorted_kasas_storage.node_table,
                option::destroy_some(prev_id)
            ).next_id = option::some(id);
            table::borrow_mut(
                &mut sorted_kasas_storage.node_table,
                option::destroy_some(next_id)
            ).prev_id = option::some(id);
        };
        
        // Update the size
        sorted_kasas_storage.size = sorted_kasas_storage.size + 1;
    }

    fun remove_node(
        sorted_kasas_storage: &mut SortedKasasStorage,
        id: address,
    ) {
        // Make sure the list contains the item
        assert!(contains(sorted_kasas_storage, id), ERROR_EXISTING_ITEM);

        if (sorted_kasas_storage.size > 1) {
            // List contains more than a single node
            if (
                option::is_some(&sorted_kasas_storage.head) &&
                id == option::destroy_some(sorted_kasas_storage.head)
            ) {
                // The removed node is the head
                // Set head to next node
                sorted_kasas_storage.head = table::borrow(
                    &sorted_kasas_storage.node_table,
                    id
                ).next_id;
                // Set prev pointer of new head to null
                table::borrow_mut(
                    &mut sorted_kasas_storage.node_table,
                    option::destroy_some(sorted_kasas_storage.head)
                ).prev_id = option::none();
            } else if (
                option::is_some(&sorted_kasas_storage.tail) &&
                id == option::destroy_some(sorted_kasas_storage.tail)
            ) {
                // The removed node is the tail
                // Set tail to previous node
                sorted_kasas_storage.tail = table::borrow(
                    &sorted_kasas_storage.node_table,
                    id
                ).prev_id;
                // Set next pointer of new tail to null
                table::borrow_mut(
                    &mut sorted_kasas_storage.node_table,
                    option::destroy_some(sorted_kasas_storage.tail)
                ).next_id = option::none();
            } else {
                // The removed node is neither the head nor the tail
                // Set next pointer of previous node to the next node
                let prev_id = table::borrow(
                    &sorted_kasas_storage.node_table,
                    id
                ).prev_id;
                table::borrow_mut(
                    &mut sorted_kasas_storage.node_table,
                    option::destroy_some(prev_id)
                ).next_id = table::borrow(
                    &sorted_kasas_storage.node_table,
                    id
                ).next_id;
                // Set next pointer of next node to the previous node
                let next_id = table::borrow(
                    &sorted_kasas_storage.node_table,
                    id
                ).next_id;
                table::borrow_mut(
                    &mut sorted_kasas_storage.node_table,
                    option::destroy_some(next_id)
                ).prev_id = table::borrow(
                    &sorted_kasas_storage.node_table,
                    id
                ).prev_id;
            }
        } else {
            // List has only one item
            // Set head and tail to none
            sorted_kasas_storage.head = option::none();
            sorted_kasas_storage.tail = option::none();
        };

        // Remove the node from the table
        table::remove(&mut sorted_kasas_storage.node_table, id);
        
        // Update the size of the list
        sorted_kasas_storage.size = sorted_kasas_storage.size - 1;
    }

    #[allow(unused_assignment)]
    fun check_node_position(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasas_storage: &mut SortedKasasStorage,
        nicr: u256,
        prev_id: Option<address>,
        next_id: Option<address>,
    ): bool {
        let res = false;
        if (option::is_none(&prev_id) && option::is_none(&next_id)) {
            // `(null, null)` is a valid insert position if the list is empty
            res = is_empty(sorted_kasas_storage);
        } else if (option::is_none(&prev_id) && option::is_some(&next_id)) {
            // `(null, next_id)` is a valid insert position if `next_id` is the head of the list
            res = sorted_kasas_storage.head == next_id &&
                nicr >= kasa_storage::get_nominal_collateral_ratio(
                    kasa_manager_storage,
                    option::destroy_some(next_id)
                )
        } else if (option::is_none(&next_id) && option::is_some(&prev_id)) {
            // `(prev_id, null)` is a valid insert position if `prev_id` is the tail of the list
            res = sorted_kasas_storage.tail == prev_id &&
                nicr <= kasa_storage::get_nominal_collateral_ratio(
                    kasa_manager_storage,
                    option::destroy_some(prev_id)
                )
        } else {
            res = table::borrow(
                    &mut sorted_kasas_storage.node_table,
                    option::destroy_some(prev_id)
                ).next_id == next_id &&
                kasa_storage::get_nominal_collateral_ratio(
                    kasa_manager_storage,
                    option::destroy_some(prev_id)
                ) >= nicr &&
                nicr >= kasa_storage::get_nominal_collateral_ratio(
                    kasa_manager_storage,
                    option::destroy_some(next_id)
                )
        };
        res
    }

    fun find_node_position(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasas_storage: &mut SortedKasasStorage,
        nicr: u256,
        prev_id: Option<address>,
        next_id: Option<address>,
    ): (Option<address>, Option<address>) {
        let prev_id = prev_id;
        let next_id = next_id;
        let head = sorted_kasas_storage.head;

        if (option::is_some(&prev_id)) {
            if (
                !contains(sorted_kasas_storage, option::destroy_some(prev_id)) ||
                nicr > kasa_storage::get_nominal_collateral_ratio(
                    kasa_manager_storage,
                    option::destroy_some(prev_id)
                )
            ) {
                // `prev_id` does not exist anymore or now has a smaller NICR than the given NICR
                prev_id = option::none();
            }
        };

        if (option::is_some(&next_id)) {
            if (
                !contains(sorted_kasas_storage, option::destroy_some(next_id)) ||
                nicr > kasa_storage::get_nominal_collateral_ratio(
                    kasa_manager_storage,
                    option::destroy_some(next_id)
                )
            ) {
                // `next_id` does not exist anymore or now has a smaller NICR than the given NICR
                next_id = option::none();
            }
        };

        if (option::is_none(&prev_id) && option::is_none(&next_id)) {
            // No hint - descend list starting from head
            return descend_list(
                kasa_manager_storage,
                sorted_kasas_storage,
                nicr,
                option::destroy_some(head)
            )
        } else if (option::is_none(&prev_id)) {
            // No `prev_id` for hint - ascend list starting from `next_id`
            return ascend_list(
                kasa_manager_storage,
                sorted_kasas_storage,
                nicr,
                option::destroy_some(next_id)
            )
        } else if (option::is_none(&next_id)) {
            // No `next_id` for hint - descend list starting from `prev_id`
            return descend_list(
                kasa_manager_storage,
                sorted_kasas_storage,
                nicr,
                option::destroy_some(prev_id)
            )
        };

        // Descend list starting from `prev_id`
        descend_list(
            kasa_manager_storage,
            sorted_kasas_storage,
            nicr,
            option::destroy_some(prev_id)
        )
    }

    fun descend_list(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasas_storage: &mut SortedKasasStorage,
        nicr: u256,
        start_id: address,
    ): (Option<address>, Option<address>) {
        // If `start_id` is the head, check if the insert position is before the head
        if (
            option::destroy_some(sorted_kasas_storage.head) == start_id &&
            nicr >= kasa_storage::get_nominal_collateral_ratio(
                kasa_manager_storage,
                start_id
            )
        ) return (option::none(), option::some(start_id));

        let prev_id = option::some(start_id);
        let next_id = table::borrow(
            &mut sorted_kasas_storage.node_table,
            start_id
        ).next_id;

        // Descend the list until we reach the end or until we find a valid insert position
        while(
            option::is_some(&prev_id) &&
            !check_node_position(
                kasa_manager_storage,
                sorted_kasas_storage,
                nicr,
                prev_id,
                next_id
            )
        ) {
            prev_id = table::borrow(
                &mut sorted_kasas_storage.node_table,
                option::destroy_some(prev_id)
            ).next_id;
            next_id = table::borrow(
                &mut sorted_kasas_storage.node_table,
                option::destroy_some(prev_id)
            ).next_id;
        };

        (prev_id, next_id)
    }

    fun ascend_list(
        kasa_manager_storage: &mut KasaManagerStorage,
        sorted_kasas_storage: &mut SortedKasasStorage,
        nicr: u256,
        start_id: address,
    ): (Option<address>, Option<address>) {
        // If `start_id` is the tail, check if the insert position is after the tail
        if (
            option::destroy_some(sorted_kasas_storage.tail) == start_id &&
            nicr <= kasa_storage::get_nominal_collateral_ratio(
                kasa_manager_storage,
                start_id
            )
        ) return (option::some(start_id), option::none());

        let prev_id = option::some(start_id);
        let next_id = table::borrow(
            &mut sorted_kasas_storage.node_table,
            start_id
        ).prev_id;

        // Ascend the list until we reach the end or until we find a valid insert position
        while(
            option::is_some(&next_id) &&
            !check_node_position(
                kasa_manager_storage,
                sorted_kasas_storage,
                nicr,
                prev_id,
                next_id
            )
        ) {
            prev_id = table::borrow(
                &mut sorted_kasas_storage.node_table,
                option::destroy_some(next_id)
            ).prev_id;
            next_id = table::borrow(
                &mut sorted_kasas_storage.node_table,
                option::destroy_some(next_id)
            ).prev_id;
        };

        (prev_id, next_id)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx);
    }
}