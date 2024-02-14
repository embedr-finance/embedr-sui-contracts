module registry::registry {
    // ========== IMPORTS ==========

    use std::ascii::{Self, String};
    use std::vector;

    use sui::object::{Self, UID, ID};
    use sui::table::{Self, Table};
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_object_field as dof;

    // ========== CONSTANTS ==========

    const VERSION: u64 = 1;

    // These are the functions that can be called by users
    const OPEN_KASA: vector<u8> = b"open_kasa";
    const DEPOSIT_COLLATERAL: vector<u8> = b"deposit_collateral";
    const WITHDRAW_COLLATERAL: vector<u8> = b"withdraw_collateral";
    const BORROW_LOAN: vector<u8> = b"borrow_loan";
    const REPAY_LOAN: vector<u8> = b"repay_loan";
    const REDEEM: vector<u8> = b"redeem";

    // These are the functions that can be called by enterprises
    // const ....

    // These are the packages that make up the protocol
    const TOKENS: vector<u8> = b"tokens";
    const STABLE_COIN_FACTORY: vector<u8> = b"stable_coin_factory";
    const REVENUE_FARMING_FACTORY: vector<u8> = b"revenue_farming_factory";

    // ========== ERRORS ==========

    const EExistingStorageObject: u64 = 1;
    // TODO: Only allow authorized calls for some functions
    const EUnauthorizedCall: u64 = 2;

    // ========== STRUCTS ==========

    struct AdminCap has key, store {
        id: UID
    }

    // Main storage object for our contract
    //
    // All of the other main module storage objects
    // will be tied to this object by dynamic object fields.
    // This will make sure we will be able to access storage information
    // for each function to execute by account contracts
    struct RegistryStorage has key, store {
        id: UID,
        version: u64,
        // List of package names that is registered
        package_names: vector<String>,
        // All of the package IDs in the protocol
        // Package name is mapped to its ID
        package_ids: Table<String, ID>,
        // All of the functions for a package
        // Package name is mapped to a list of function names
        functions: Table<String, vector<String>>,
        storage_object_list: vector<String>
    }

    struct StorageWrapper<T: store> has key, store {
        id: UID,
        name: String,
        storage: T
    }

    // ========== ADMIN FUNCTIONS ==========

    // Registers a new storage object to registry
    // These objects are added using dynamic_field_objects
    entry fun register_storage_object<T: store>(
        _: &AdminCap,
        self: &mut RegistryStorage,
        wrapper: StorageWrapper<T>
    ) {
        // Add the storage object to the list
        vector::push_back(&mut self.storage_object_list, wrapper.name);

        // Add the storage object to the dynamic object field
        dof::add(&mut self.id, wrapper.name, wrapper);
    }

    entry fun unregister_storage_object<T: store>(
        _: &AdminCap,
        self: &mut RegistryStorage,
        name: String,
        ctx: &mut TxContext
    ) {
        // Remove the storage object from the list
        let (_, index) = vector::index_of(&self.storage_object_list, &name);
        vector::remove(&mut self.storage_object_list, index);

        // Remove the storage object from the dynamic object field
        let wrapper = dof::remove<String, StorageWrapper<T>>(&mut self.id, name);
        transfer::public_transfer(wrapper, tx_context::sender(ctx));
    }

    // ========== FRIEND FUNCTIONS ==========

    public(friend) fun borrow_storage_object<T: store>(
        self: &mut RegistryStorage,
        name: String
    ): &mut T {
        let wrapper = dof::borrow_mut<String, StorageWrapper<T>>(&mut self.id, name);
        &mut wrapper.storage
    }

    // ========== PUBLIC FUNCTIONS ==========

    public fun create_storage_wrapper<T: key + store>(
        name: String,
        storage: T,
        ctx: &mut TxContext
    ): StorageWrapper<T> {
        StorageWrapper {
            id: object::new(ctx),
            name,
            storage
        }
    }

    public(friend) fun read_storage_object<T: key + store>(
        self: &mut RegistryStorage,
        name: String
    ): &T {
        dof::borrow<String, T>(&self.id, name)
    }

    // public fun get_user_functions(): (
    //     String,
    //     String,
    //     String,
    //     String,
    //     String,
    //     String,
    // ) {
    //     ascii::string(OPEN_KASA),
    //     ascii::string(DEPOSIT_COLLATERAL),
    //     ascii::string(WITHDRAW_COLLATERAL),
    //     ascii::string(BORROW_LOAN),
    //     ascii::string(REPAY_LOAN),
    //     ascii::string(REDEEM)   
    // }
}