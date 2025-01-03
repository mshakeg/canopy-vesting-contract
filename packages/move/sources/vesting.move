module deployment_addr::vesting {
    use std::signer;

    use aptos_framework::fungible_asset::{Self, Metadata, FungibleStore};
    use aptos_framework::object::{Self, Object, ExtendRef};
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::event;

    #[test_only]
    use std::vector;
    #[test_only]
    use std::option::{Self, Option};

    // ================================= Events ================================= //

    #[event]
    struct CreateVestingStreamEvent has store, drop {
        object_address: address,
        vesting_stream: Object<VestingStream>
    }

    #[event]
    struct ClaimVestingStreamEvent has store, drop {
        object_address: address,
        vesting_stream: Object<VestingStream>,
        claimed_amount: u64
    }

    #[event]
    struct DeleteVestingStreamEvent has store, drop {
        vesting_stream: Object<VestingStream>,
        object_address: address
    }

    // ================================= Errors ================================= //

    /// Start time must be in the future
    const ERR_START_TIME_MUST_BE_IN_THE_FUTURE: u64 = 1;
    /// Vesting stream does not exist
    const ERR_VESTING_STREAM_DOES_NOT_EXIST: u64 = 2;
    /// User try to claim zero
    const ERR_AMOUNT_ZERO: u64 = 3;
    /// Duration must be greater than 0
    const ERR_DURATION_ZERO: u64 = 4;
    /// Cliff amount must be less than amount
    const ERR_CLIFF_AMOUNT_MUST_BE_LESS_OR_EQUAL_THAN_AMOUNT: u64 = 5;

    // ================================= Structs ================================= //

    // FIX: key ability is not needed for VestingStream since it isn't keyed to an address in global storage

    // FIX: current implementation treats cliff as a delay period before linear vesting begins. Which is kind of redundant since the start_time can be specified
    // For a proper vesting cliff implementation, VestingStream should include a cliff_amount field
    // that represents tokens immediately unlocked when cliff is reached. Current implementation
    // seems to always start linear vesting from 0 at cliff time, whereas typically some percentage
    // of tokens should unlock immediately at cliff time(in your case that percentage is effectively 0).

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct VestingStream has key {
        beneficiary: address,
        amount: u64,
        claimed_amount: u64,
        start_time: u64,
        cliff_amount: u64,
        duration: u64,
        fa_metadata_object: Object<Metadata>,
        vesting_store: Object<FungibleStore>
    }

    // FIX: it seems like your implementation requires a new vesting module to be deployed for every FA to be streamed
    // and it also only supports a single VestingStream for a given address.
    // To generalize this I would instead allow anyone to create arbitrary VestingStream object instances i.e. Object<VestingStream>
    // The owner of the Object<VestingStream> is essentially the admin and can do admin actions
    // #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    // And the object signer associated with the Object<VestingStream> can be used to withdraw funds from the fungible store for that stream

    #[resource_group_member(group = aptos_framework::object::ObjectGroup)]
    struct ObjectController has key {
        delete_ref: object::DeleteRef,
        extend_ref: ExtendRef
    }

    // FIX: for something like Sablier's stream's that are decentralized i.e. anyone can create streams, we'd
    // want the admin to be per stream and not a single global admin

    // ================================= Entry Functions ================================= //

    // FIX: the following global admin functions would not be needed if each VestingStream is a member of Object, since each Object has an owner

    //// - - - CLAIMER FUNCTIONS - - -

    // FIX: given the above suggested fixes, the VestingStream would have to track the claimer for that stream
    // the claim_tokens function would have to be adjusted to accept Object<VestingStream>
    // Additionally, it would not have to accept sender: &signer, since anyone should be able to call claim_tokens
    // which should transfer all tokens available to claim to the claimer
    // Additionally, on a claim_tokens call that is beyond the end time, you could cleanup storage and delete the VestingStream

    /// Claim vested tokens
    /// Any beneficiary can call
    public fun claim_tokens(vesting_stream_obj: &Object<VestingStream>) acquires ObjectController, VestingStream {
        let obj_address = object::object_address(vesting_stream_obj);
        let vesting_stream = borrow_global_mut<VestingStream>(obj_address);

        let claimable_amount = get_claimable_amount(vesting_stream);
        assert!(claimable_amount > 0, ERR_AMOUNT_ZERO);

        fungible_asset::transfer(
            &generate_fungible_store_signer(obj_address),
            vesting_stream.vesting_store,
            primary_fungible_store::ensure_primary_store_exists(
                vesting_stream.beneficiary, vesting_stream.fa_metadata_object
            ),
            claimable_amount
        );

        event::emit(
            ClaimVestingStreamEvent {
                object_address: obj_address,
                vesting_stream: *vesting_stream_obj,
                claimed_amount: claimable_amount
            }
        );

        let vesting_stream_completed = vesting_stream.claimed_amount + claimable_amount == vesting_stream.amount;

        if (!vesting_stream_completed) {
            vesting_stream.claimed_amount = vesting_stream.claimed_amount + claimable_amount;
        } else {
            let ObjectController { delete_ref, extend_ref: _ } = move_from<ObjectController>(obj_address);
            object::delete(delete_ref);
            event::emit(DeleteVestingStreamEvent { vesting_stream: *vesting_stream_obj, object_address: obj_address });
        };
    }

    // - - - CREATE STREAM - - --

    // FIX: given the above recommended fixes the create_vesting_stream function would have to be adjusted to allow the creation of arbitrary Object<VestingStream> instances
    // The current implementation only allows a given benefiary to have only a single stream.

    /// Create new vesting stream
    public entry fun create_vesting_stream(
        sender: &signer,
        beneficiary: address,
        amount: u64,
        start_time: u64,
        cliff_amount: u64,
        duration: u64,
        fa_metadata_object: Object<Metadata>
    ) {

        // FIX: what's the concern with using >= instead of > below?
        assert!(start_time > timestamp::now_seconds(), ERR_START_TIME_MUST_BE_IN_THE_FUTURE);
        assert!(amount > 0, ERR_AMOUNT_ZERO);
        assert!(cliff_amount <= amount, ERR_CLIFF_AMOUNT_MUST_BE_LESS_OR_EQUAL_THAN_AMOUNT);
        if (amount != cliff_amount) {
            // Duration 0 is only valid if cliff amount is equal to amount
            assert!(duration > 0, ERR_DURATION_ZERO);
        };

        let sender_addr = signer::address_of(sender);
        let constructor_ref = object::create_object(sender_addr);
        let object_signer = object::generate_signer(&constructor_ref);

        let vesting_store = fungible_asset::create_store(&constructor_ref, fa_metadata_object);
        let vesting_stream = VestingStream {
            beneficiary,
            amount,
            claimed_amount: 0,
            start_time,
            cliff_amount,
            duration,
            fa_metadata_object,
            vesting_store
        };

        move_to(&object_signer, vesting_stream);

        let extend_ref = object::generate_extend_ref(&constructor_ref);
        let delete_ref = object::generate_delete_ref(&constructor_ref);
        move_to(&object_signer, ObjectController { extend_ref, delete_ref });

        fungible_asset::transfer(
            sender,
            primary_fungible_store::primary_store(sender_addr, fa_metadata_object),
            vesting_store,
            amount
        );

        event::emit(
            CreateVestingStreamEvent {
                object_address: signer::address_of(&object_signer),
                vesting_stream: object::address_to_object<VestingStream>(signer::address_of(&object_signer))
            }
        );
    }

    // ================================= View Functions ================================= //

    #[view]
    public fun calculate_vested_amount(
        total_amount: u64,
        start_time: u64,
        cliff_amount: u64,
        duration: u64
    ): u64 {

        let end_time = start_time + duration;

        let current_time = timestamp::now_seconds();

        if (current_time < start_time) {
            return 0
        };

        if (current_time > end_time) {
            return total_amount
        };

        let elapsed_time = current_time - start_time;
        cliff_amount + ((total_amount - cliff_amount) * elapsed_time) / duration
    }

    // ================================= Helper Functions ================================= //

    public fun get_claimable_amount(vesting_stream: &mut VestingStream): u64 {
        let claimable_amount =
            calculate_vested_amount(
                vesting_stream.amount,
                vesting_stream.start_time,
                vesting_stream.cliff_amount,
                vesting_stream.duration
            );
        claimable_amount - vesting_stream.claimed_amount
    }

    /// Generate signer to send tokens from vesting store to user
    fun generate_fungible_store_signer(owner_address: address): signer acquires ObjectController {
        object::generate_signer_for_extending(&borrow_global<ObjectController>(owner_address).extend_ref)
    }

    // ================================= Unit Tests Helpers ================================= //

    #[test_only]
    public fun get_most_recent_stream(): Option<Object<VestingStream>> {
        let events = event::emitted_events<CreateVestingStreamEvent>();
        if (vector::length(&events) == 0) {
            return option::none()
        };
        let event = vector::pop_back(&mut events);
        return option::some(event.vesting_stream)
    }

    #[test_only]
    public fun get_vesting_store(vesting_stream: &Object<VestingStream>): Object<FungibleStore> acquires VestingStream {
        let obj_address = object::object_address(vesting_stream);
        let vesting_stream = borrow_global<VestingStream>(obj_address);
        vesting_stream.vesting_store
    }

    #[test_only]
    public fun get_claimable_amount_from_obj(vesting_stream: &Object<VestingStream>): u64 acquires VestingStream {
        let obj_address = object::object_address(vesting_stream);
        let vesting_stream = borrow_global<VestingStream>(obj_address);
        let claimable_amount =
            calculate_vested_amount(
                vesting_stream.amount,
                vesting_stream.start_time,
                vesting_stream.cliff_amount,
                vesting_stream.duration
            );
        claimable_amount - vesting_stream.claimed_amount
    }

    #[test_only]
    public fun get_vesting_stream_details(
        vesting_stream: &Object<VestingStream>
    ): (address, u64, u64, u64, u64, u64) acquires VestingStream {
        let obj_address = object::object_address(vesting_stream);
        let vesting_stream = borrow_global<VestingStream>(obj_address);
        (
            vesting_stream.beneficiary,
            vesting_stream.amount,
            vesting_stream.claimed_amount,
            vesting_stream.start_time,
            vesting_stream.cliff_amount,
            vesting_stream.duration
        )
    }
}
