module deployment_addr::vesting {
    use std::option::{Self, Option};
    use std::signer;
    use aptos_std::simple_map::{Self, SimpleMap};

    use aptos_framework::fungible_asset::{Self, Metadata, FungibleStore};
    use aptos_framework::object::{Self, Object, ExtendRef, ObjectCore};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

    // ================================= Errors ================================= //

    /// Start time must be in the future
    const ERR_START_TIME_MUST_BE_IN_THE_FUTURE: u64 = 1;
    /// Vesting stream does not exist
    const ERR_VESTING_STREAM_DOES_NOT_EXIST: u64 = 2;
    /// Vesting stream already exists
    const ERR_VESTING_STREAM_ALREADY_EXISTS: u64 = 4;
    /// Only admin can add stream
    const ERR_ONLY_ADMIN_CAN_ADD_VESTING_STREAM: u64 = 5;
    /// Only admin can set pending admin
    const ERR_ONLY_ADMIN_CAN_SET_PENDING_ADMIN: u64 = 6;
    /// Only pending admin can accept admin
    const ERR_ONLY_PENDING_ADMIN_CAN_ACCEPT_ADMIN: u64 = 7;
    /// User try to claim zero
    const ERR_AMOUNT_ZERO: u64 = 10;

    // FIX: key ability is not needed for VestingStream since it isn't keyed to an address in global storage

    // FIX: current implementation treats cliff as a delay period before linear vesting begins. Which is kind of redundant since the start_time can be specified
    // For a proper vesting cliff implementation, VestingStream should include a cliff_amount field
    // that represents tokens immediately unlocked when cliff is reached. Current implementation
    // seems to always start linear vesting from 0 at cliff time, whereas typically some percentage
    // of tokens should unlock immediately at cliff time(in your case that percentage is effectively 0).

    struct VestingStream has store, drop {
        amount: u64,
        claimed_amount: u64,
        start_time: u64,
        cliff: u64,
        duration: u64
    }

    // FIX: it seems like your implementation requires a new vesting module to be deployed for every FA to be streamed
    // and it also only supports a single VestingStream for a given address.
    // To generalize this I would instead allow anyone to create arbitrary VestingStream object instances i.e. Object<VestingStream>
    // The owner of the Object<VestingStream> is essentially the admin and can do admin actions
    // #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    // And the object signer associated with the Object<VestingStream> can be used to withdraw funds from the fungible store for that stream

    struct VestingData has key {
        // Fungible asset metadata object
        fa_metadata_object: Object<Metadata>,
        // Fungible store to hold vesting tokens
        vesting_store: Object<FungibleStore>,
        // Total vesting amount in the contract
        total_vesting_amount: u64,
        // Mapping of user address to vesting stream
        streams: SimpleMap<address, VestingStream>
    }

    /// Global per contract
    /// Generate signer to send tokens from vesting store to user
    struct FungibleStoreController has key {
        extend_ref: ExtendRef
    }

    /// Global per contract
    struct Config has key {
        // FIX: for something like Sablier's stream's that are decentralized i.e. anyone can create streams, we'd
        // want the admin to be per stream and not a single global admin

        // Admin can set pending admin, accept admin, and create vesting streams
        admin: address,
        // Pending admin can accept admin
        pending_admin: Option<address>
    }

    // - - - CONSTRUCTOR - - -

    /// If you deploy the module under an object, sender is the object's signer
    /// If you deploy the module under your own account, sender is your account's signer
    fun init_module(sender: &signer) {
        init_module_internal(sender, object::address_to_object<Metadata>(@fa_address));
    }

    // - - - CONSTRUCTOR HELPER FUNCTION - - -

    fun init_module_internal(sender: &signer, fa_metadata_object: Object<Metadata>) {
        let sender_addr = signer::address_of(sender);
        move_to(sender, Config { admin: sender_addr, pending_admin: option::none() });

        let fungible_store_constructor_ref = &object::create_object(sender_addr);
        move_to(
            sender,
            FungibleStoreController { extend_ref: object::generate_extend_ref(fungible_store_constructor_ref) }
        );

        move_to(
            sender,
            VestingData {
                fa_metadata_object,
                vesting_store: fungible_asset::create_store(
                    fungible_store_constructor_ref, fa_metadata_object
                ),
                total_vesting_amount: 0,
                streams: simple_map::new()
            }
        );
    }

    // ================================= Entry Functions ================================= //

    // FIX: the following global admin functions would not be needed if each VestingStream is a member of Object, since each Object has an owner

    // - - - ADMIN FUNCTIONS - - -

    /// Set pending admin of the contract, then pending admin can call accept_admin to become admin
    public entry fun set_pending_admin(sender: &signer, new_admin: address) acquires Config {
        let sender_addr = signer::address_of(sender);
        let config = borrow_global_mut<Config>(@deployment_addr);
        assert!(is_admin(config, sender_addr), ERR_ONLY_ADMIN_CAN_SET_PENDING_ADMIN);
        config.pending_admin = option::some(new_admin);
    }

    /// Accept admin of the contract
    public entry fun accept_admin(sender: &signer) acquires Config {
        let sender_addr = signer::address_of(sender);
        let config = borrow_global_mut<Config>(@deployment_addr);
        assert!(
            config.pending_admin == option::some(sender_addr),
            ERR_ONLY_PENDING_ADMIN_CAN_ACCEPT_ADMIN
        );
        config.admin = sender_addr;
        config.pending_admin = option::none();
    }

    //// - - - CLAIMER FUNCTIONS - - -

    // FIX: given the above suggested fixes, the VestingStream would have to track the claimer for that stream
    // the claim_tokens function would have to be adjusted to accept Object<VestingStream>
    // Additionally, it would not have to accept sender: &signer, since anyone should be able to call claim_tokens
    // which should transfer all tokens available to claim to the claimer
    // Additionally, on a claim_tokens call that is beyond the end time, you could cleanup storage and delete the VestingStream

    /// Claim vested tokens
    /// Any beneficiary can call
    public entry fun claim_tokens(sender: &signer) acquires VestingData, FungibleStoreController {
        let claimable_tokens = get_claimable_amount(signer::address_of(sender));
        assert!(claimable_tokens > 0, ERR_AMOUNT_ZERO);

        let sender_addr = signer::address_of(sender);
        let vesting_data = borrow_global_mut<VestingData>(@deployment_addr);

        transfer_tokens_to_claimer(claimable_tokens, sender_addr, vesting_data);

        let vesting_stream = simple_map::borrow_mut(&mut vesting_data.streams, &sender_addr);
        vesting_stream.claimed_amount = vesting_stream.claimed_amount + claimable_tokens;
    }

    // - - - CREATE STREAM - - -

    // FIX: given the above recommended fixes the create_vesting_stream function would have to be adjusted to allow the creation of arbitrary Object<VestingStream> instances
    // The current implementation only allows a given benefiary to have only a single stream.

    /// Create new vesting stream
    /// Only admin can call
    /// Abort if vesting stream already exists
    public entry fun create_vesting_stream(
        sender: &signer,
        beneficiary: address,
        amount: u64,
        start_time: u64,
        cliff: u64,
        duration: u64
    ) acquires VestingData, Config {
        let sender_addr = signer::address_of(sender);
        let config = borrow_global<Config>(@deployment_addr);
        assert!(config.admin == sender_addr, ERR_ONLY_ADMIN_CAN_ADD_VESTING_STREAM);

        // FIX: what's the concern with using >= instead of > below?
        assert!(start_time > timestamp::now_seconds(), ERR_START_TIME_MUST_BE_IN_THE_FUTURE);

        let vesting_pool_mut = borrow_global_mut<VestingData>(@deployment_addr);

        if (simple_map::contains_key(&vesting_pool_mut.streams, &beneficiary)) {
            let existing_vesting_stream = simple_map::borrow(&vesting_pool_mut.streams, &beneficiary);
            assert!(
                existing_vesting_stream.claimed_amount == existing_vesting_stream.amount,
                ERR_VESTING_STREAM_ALREADY_EXISTS
            );
        };

        let vesting_stream = VestingStream { amount, claimed_amount: 0, start_time, cliff, duration };

        simple_map::upsert(&mut vesting_pool_mut.streams, beneficiary, vesting_stream);

        fungible_asset::transfer(
            sender,
            primary_fungible_store::primary_store(sender_addr, vesting_pool_mut.fa_metadata_object),
            vesting_pool_mut.vesting_store,
            amount
        );
    }

    // ================================= View Functions ================================= //

    #[view]
    /// Get vesting data
    public fun get_vesting_data(): (Object<Metadata>, Object<FungibleStore>, u64) acquires VestingData {
        let vesting_data = borrow_global<VestingData>(@deployment_addr);
        (vesting_data.fa_metadata_object, vesting_data.vesting_store, vesting_data.total_vesting_amount)
    }

    #[view]
    /// Whether vesting stream exists
    public fun exists_vesting_stream(beneficiary: address): bool acquires VestingData {
        let vesting_data = borrow_global<VestingData>(@deployment_addr);
        simple_map::contains_key(&vesting_data.streams, &beneficiary)
    }

    #[view]
    /// Get vesting stream data
    public fun get_vesting_stream(beneficiary: address): (u64, u64, u64, u64, u64) acquires VestingData {
        let vesting_data = borrow_global<VestingData>(@deployment_addr);
        let vesting_stream = simple_map::borrow(&vesting_data.streams, &beneficiary);
        (
            vesting_stream.amount,
            vesting_stream.claimed_amount,
            vesting_stream.start_time,
            vesting_stream.cliff,
            vesting_stream.duration
        )
    }

    #[view]
    public fun get_claimable_amount(user: address): u64 acquires VestingData {
        // Check if the user has a vesting stream
        // Check if the user has any tokens to claim

        let vesting_data = borrow_global<VestingData>(@deployment_addr);
        assert!(
            simple_map::contains_key(&vesting_data.streams, &user),
            ERR_VESTING_STREAM_DOES_NOT_EXIST
        );
        let vesting_stream = simple_map::borrow(&vesting_data.streams, &user);
        let claimable_amount =
            calculate_vested_amount(
                vesting_stream.amount,
                vesting_stream.start_time,
                vesting_stream.cliff,
                vesting_stream.duration
            );
        claimable_amount - vesting_stream.claimed_amount

    }

    #[view]
    public fun calculate_vested_amount(
        amount: u64,
        start_time: u64,
        cliff: u64,
        duration: u64
    ): u64 {

        let begin_unlock_time = start_time + cliff;
        let end_unlock_time = start_time + cliff + duration;

        let current_time = timestamp::now_seconds();

        if (current_time < begin_unlock_time) {
            return 0
        };

        if (current_time > end_unlock_time) {
            return amount
        };

        let elapsed_time = current_time - begin_unlock_time;
        // let percentage_unlocked = elapsed_time / duration;
        (amount * elapsed_time) / duration
    }

    // ================================= Helper Functions ================================= //

    /// Check if sender is admin or owner of the object when package is published to object
    fun is_admin(config: &Config, sender: address): bool {
        if (sender == config.admin) { true }
        else {
            if (object::is_object(@deployment_addr)) {
                let obj = object::address_to_object<ObjectCore>(@deployment_addr);
                object::is_owner(obj, sender)
            } else { false }
        }
    }

    /// Generate signer to send tokens from vesting store to user
    fun generate_fungible_store_signer(): signer acquires FungibleStoreController {
        object::generate_signer_for_extending(
            &borrow_global<FungibleStoreController>(@deployment_addr).extend_ref
        )
    }

    /// Transfer tokens from vesting store to user
    fun transfer_tokens_to_claimer(
        amount: u64, user_addr: address, vesting_data: &VestingData
    ) acquires FungibleStoreController {
        fungible_asset::transfer(
            &generate_fungible_store_signer(),
            vesting_data.vesting_store,
            primary_fungible_store::ensure_primary_store_exists(user_addr, vesting_data.fa_metadata_object),
            amount
        );
    }

    // ================================= Unit Tests Helpers ================================= //

    #[test_only]
    public fun init_module_for_test(
        aptos_framework: &signer, sender: &signer, fa_metadata_object: Object<Metadata>
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        init_module_internal(sender, fa_metadata_object);
    }
}
