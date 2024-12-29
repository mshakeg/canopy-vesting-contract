module deployment_addr::vesting {
    use std::bcs;
    use std::option::{Self, Option};
    use std::signer;
    use aptos_std::simple_map::{Self, SimpleMap};

    use aptos_std::fixed_point64::{Self, FixedPoint64};
    use aptos_std::math64;
    use aptos_std::string_utils;

    use aptos_framework::fungible_asset::{Self, Metadata, FungibleStore};
    use aptos_framework::object::{Self, Object, ExtendRef, ObjectCore};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

    // ================================= Errors ================================= //

    /// Reward schedule already exists
    const ERR_VESTING_STREAM_ALREADY_EXISTS: u64 = 4;
    /// Only reward creator can add reward
    const ERR_ONLY_STREAM_CREATOR_CAN_ADD_VESTING_STREAM: u64 = 5;
    /// Only admin can set pending admin
    const ERR_ONLY_ADMIN_CAN_SET_PENDING_ADMIN: u64 = 6;
    /// Only pending admin can accept admin
    const ERR_ONLY_PENDING_ADMIN_CAN_ACCEPT_ADMIN: u64 = 7;
    /// Not enough balance to add reward
    const ERR_NOT_ENOUGH_BALANCE_TO_ADD_REWARD: u64 = 8;
    /// Only admin can update reward creator
    const ERR_ONLY_ADMIN_CAN_UPDATE_STREAM_CREATOR: u64 = 9;
    /// User try to claim zero
    const ERR_AMOUNT_ZERO: u64 = 10;


    struct VestingStream has key, store, drop {
        amount: u64,
        claimed_amount: u64,
        start_time: u64,
        cliff: u64,
        duration: u64
    }
 
    struct VestingData has key {
        // Fungible asset stakers are staking and earning rewards in
        fa_metadata_object: Object<Metadata>,
        // Fungible store to hold rewards
        vesting_store: Object<FungibleStore>,
        // Total vesting amount in the contract
        total_vesting_amount: u64,
        // Mapping of user address to vesting stream
        streams: SimpleMap<address, VestingStream>,
    }

    /// Global per contract
    /// Generate signer to send reward from reward store and stake store to user
    struct FungibleStoreController has key {
        extend_ref: ExtendRef
    }

    /// Global per contract
    struct Config has key {
        // Creator can add reward
        stream_creator: address,
        // Admin can set pending admin, accept admin, update mint fee collector, create FA and update creator
        admin: address,
        // Pending admin can accept admin
        pending_admin: Option<address>
    }

    /// If you deploy the module under an object, sender is the object's signer
    /// If you deploy the module under your own account, sender is your account's signer
    fun init_module(sender: &signer) {
        init_module_internal(
            sender,
            @initial_stream_creator_addr,
            object::address_to_object<Metadata>(@fa_address)
        );
    }

    fun init_module_internal(
        sender: &signer,
        initial_stream_creator_addr: address,
        fa_metadata_object: Object<Metadata>
    ) {
        let sender_addr = signer::address_of(sender);
        move_to(
            sender,
            Config {
                stream_creator: initial_stream_creator_addr,
                admin: sender_addr,
                pending_admin: option::none()
            }
        );

        let fungible_store_constructor_ref = &object::create_object(sender_addr);
        move_to(
            sender,
            FungibleStoreController {
                extend_ref: object::generate_extend_ref(fungible_store_constructor_ref)
            }
        );

        move_to(
            sender,
            VestingData {
                fa_metadata_object,
                vesting_store: fungible_asset::create_store(
                    fungible_store_constructor_ref,
                    fa_metadata_object
                ),
                total_vesting_amount: 0,
                streams: simple_map::new()
            }
        );
    }

    // ================================= Entry Functions ================================= //

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
        assert!(config.pending_admin == option::some(sender_addr), ERR_ONLY_PENDING_ADMIN_CAN_ACCEPT_ADMIN);
        config.admin = sender_addr;
        config.pending_admin = option::none();
    }

    /// Update reward creator
    public entry fun update_reward_creator(sender: &signer, new_stream_creator: address) acquires Config {
        let sender_addr = signer::address_of(sender);
        let config = borrow_global_mut<Config>(@deployment_addr);
        assert!(is_admin(config, sender_addr), ERR_ONLY_ADMIN_CAN_UPDATE_STREAM_CREATOR);
        config.stream_creator = new_stream_creator;
    }

    /// Claim reward
    /// Any staker can call
    public entry fun claim_tokens(
        sender: &signer
    ) acquires VestingData, FungibleStoreController {
        let claimable_tokens = get_claimable_amount(signer::address_of(sender));
        assert!(claimable_tokens > 0, ERR_AMOUNT_ZERO);

        let sender_addr = signer::address_of(sender);
        let stake_pool = borrow_global<VestingData>(@deployment_addr);

        transfer_reward_to_claimer(claimable_tokens, sender_addr, stake_pool);
    }


    /// Create new reward schedule
    /// Only reward creator can call
    /// Abort if reward schedule already exists
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
        assert!(config.stream_creator == sender_addr, ERR_ONLY_STREAM_CREATOR_CAN_ADD_VESTING_STREAM);

        let vesting_pool_mut = borrow_global_mut<VestingData>(@deployment_addr);
        
        if (simple_map::contains_key(&vesting_pool_mut.streams, &beneficiary)) {
            // TODO: check if the vesting stream is already finished and completely claimed
            
            abort ERR_VESTING_STREAM_ALREADY_EXISTS
        };
        
        let vesting_stream = VestingStream {
            amount,
            claimed_amount: 0,
            start_time,
            cliff,
            duration
        };

        simple_map::upsert(
            &mut vesting_pool_mut.streams,
            beneficiary,
            vesting_stream
        );

        fungible_asset::transfer(
            sender,
            primary_fungible_store::primary_store(sender_addr, vesting_pool_mut.fa_metadata_object),
            vesting_pool_mut.vesting_store,
            amount,
        );
    }
    
    // ================================= View Functions ================================= //

    #[view]
    public fun get_claimable_amount(user: address): u64 acquires VestingData  {
        // Check if the user has a vesting stream
        // Check if the user has any tokens to claim
        
        let vesting_data = borrow_global<VestingData>(@deployment_addr);
        let vesting_stream = simple_map::borrow(&vesting_data.streams, &user);
        
        
        let claimable_amount = calculate_vested_amount(vesting_stream.amount, vesting_stream.start_time, vesting_stream.cliff, vesting_stream.duration);
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

    /// Generate signer to send reward from reward store and stake store to user
    fun generate_fungible_store_signer(): signer acquires FungibleStoreController {
        object::generate_signer_for_extending(
            &borrow_global<FungibleStoreController>(@deployment_addr).extend_ref
        )
    }


    /// Transfer reward from reward store to claimer
    fun transfer_reward_to_claimer(
        claimable_reward: u64, user_addr: address, stake_pool: &VestingData
    ) acquires FungibleStoreController {
        fungible_asset::transfer(
            &generate_fungible_store_signer(),
            stake_pool.vesting_store,
            primary_fungible_store::ensure_primary_store_exists(
                user_addr, stake_pool.fa_metadata_object
            ),
            claimable_reward
        );
    }

    // ================================= Unit Tests Helpers ================================= //

    #[test_only]
    public fun init_module_for_test(
        aptos_framework: &signer,
        sender: &signer,
        initial_stream_creator_addr: address,
        fa_metadata_object: Object<Metadata>
    ) {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        init_module_internal(
            sender,
            initial_stream_creator_addr,
            fa_metadata_object
        );
    }
}
