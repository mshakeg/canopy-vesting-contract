#[test_only]
module deployment_addr::test_end_to_end {
    use std::option;
    use std::signer;
    use std::string;

    use aptos_framework::fungible_asset;
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;
    use aptos_framework::event;
    use std::vector;
    use deployment_addr::vesting;

    fun setup_test_env(aptos_framework: &signer, sender: &signer): object::Object<fungible_asset::Metadata> {
        timestamp::set_time_has_started_for_testing(aptos_framework);

        let sender_addr = signer::address_of(sender);
        let mint_amount_creator = 10000;

        let fa_obj_constructor_ref = &object::create_sticky_object(sender_addr);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            fa_obj_constructor_ref,
            option::none(),
            string::utf8(b"Test FA"),
            string::utf8(b"TFA"),
            8,
            string::utf8(b"url"),
            string::utf8(b"url")
        );

        let fa_metadata_object = object::object_from_constructor_ref<fungible_asset::Metadata>(fa_obj_constructor_ref);
        primary_fungible_store::mint(
            &fungible_asset::generate_mint_ref(fa_obj_constructor_ref),
            sender_addr,
            mint_amount_creator
        );

        fa_metadata_object
    }

    #[test(aptos_framework = @0x1, sender = @deployment_addr, user1 = @0x101)]
    fun test_happy_path(aptos_framework: &signer, sender: &signer, user1: &signer) {
        let fa_metadata_object = setup_test_env(aptos_framework, sender);

        let total_amount = 100;
        let start_time = 100;
        let cliff_amount = 50;
        let duration = 100;

        let user1_addr = signer::address_of(user1);
        let sender_addr = signer::address_of(sender);

        // Verify initial sender balance
        let sender_initial_balance = primary_fungible_store::balance(sender_addr, fa_metadata_object);
        assert!(sender_initial_balance == 10000, sender_initial_balance);

        vesting::create_vesting_stream(
            sender,
            user1_addr,
            total_amount,
            start_time,
            cliff_amount,
            duration,
            fa_metadata_object
        );

        // Verify stream creation
        let vesting_stream = option::borrow(&vesting::get_most_recent_stream());
        assert!(object::is_owner(*vesting_stream, sender_addr), 0);

        // After creation and before start time, 0 should be claimable
        let claimable_amount = vesting::get_claimable_amount_from_obj(vesting_stream);
        assert!(claimable_amount == 0, claimable_amount);

        // Verify initial balances after stream creation
        let user1_initial_balance = primary_fungible_store::balance(user1_addr, fa_metadata_object);
        assert!(user1_initial_balance == 0, user1_initial_balance);

        let sender_balance_after_create_stream = primary_fungible_store::balance(sender_addr, fa_metadata_object);
        assert!(
            sender_balance_after_create_stream == sender_initial_balance - total_amount,
            sender_balance_after_create_stream
        );

        // FIX: for more thorough testing you'll want to add other assertions such as VestingStream, etc state being initialized correctly
        // and that the relevant fungible store increased it's holding appropriately.
        let vesting_store = vesting::get_vesting_store(vesting_stream);
        let vesting_store_balance_after_create_stream = fungible_asset::balance(vesting_store);
        assert!(
            vesting_store_balance_after_create_stream == total_amount,
            vesting_store_balance_after_create_stream
        );

        // let vesting_store_address = object::object_address(&vesting_store);
        // let vesting_store_balance = primary_fungible_store::balance(vesting_store_address, fa_metadata_object);
        // assert!(vesting_store_balance == total_amount, vesting_store_balance);

        // FIX: instead of using timestamp::update_global_time_for_test_secs to update the time
        // you could simply use timestamp::fast_forward_seconds to fast forward a specified number of seconds
        // making the tests for easily understandable

        // At start time - cliff amount claimable
        timestamp::update_global_time_for_test_secs(start_time);
        let claimable_amount = vesting::get_claimable_amount_from_obj(vesting_stream);
        assert!(claimable_amount == cliff_amount, claimable_amount);

        // At half duration - half of remaining amount claimable
        timestamp::update_global_time_for_test_secs(start_time + (duration / 2));
        let claimable_amount = vesting::get_claimable_amount_from_obj(vesting_stream);
        let expected_half_amount = cliff_amount + ((total_amount - cliff_amount) / 2);
        assert!(claimable_amount == expected_half_amount, claimable_amount);

        // Claim tokens at half duration
        vesting::claim_tokens(vesting_stream);
        let user1_balance = primary_fungible_store::balance(user1_addr, fa_metadata_object);
        assert!(user1_balance == expected_half_amount, user1_balance);

        // Verify claimed amount is updated correctly
        let (_, _, stream_claimed_amount, _, _, _) = vesting::get_vesting_stream_details(vesting_stream);
        assert!(stream_claimed_amount == expected_half_amount, stream_claimed_amount);

        // At end time - remaining amount claimable
        timestamp::update_global_time_for_test_secs(start_time + duration);
        let claimable_amount = vesting::get_claimable_amount_from_obj(vesting_stream);
        assert!(
            claimable_amount == total_amount - expected_half_amount,
            claimable_amount
        );

        // Claim remaining tokens
        vesting::claim_tokens(vesting_stream);
        let user1_final_balance = primary_fungible_store::balance(user1_addr, fa_metadata_object);
        assert!(user1_final_balance == total_amount, user1_final_balance);

        let vesting_store_balance_after_claim = fungible_asset::balance(vesting_store);
        assert!(vesting_store_balance_after_claim == 0, vesting_store_balance_after_claim);
    }

    #[test(aptos_framework = @0x1, sender = @deployment_addr, user1 = @0x101)]
    fun test_happy_path_two_fa(aptos_framework: &signer, sender: &signer, user1: &signer) {
        let first_fa_metadata_object = setup_test_env(aptos_framework, sender);

        let total_amount = 100;
        let start_time = 100;
        let cliff_amount = 50;
        let duration = 100;

        let user1_addr = signer::address_of(user1);
        let sender_addr = signer::address_of(sender);

        // Create second FA
        let second_fa_obj_constructor_ref = &object::create_sticky_object(sender_addr);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            second_fa_obj_constructor_ref,
            option::none(),
            string::utf8(b"Second FA"),
            string::utf8(b"SFA"),
            8,
            string::utf8(b"url"),
            string::utf8(b"url")
        );
        let second_fa_metadata_object =
            object::object_from_constructor_ref<fungible_asset::Metadata>(second_fa_obj_constructor_ref);
        primary_fungible_store::mint(
            &fungible_asset::generate_mint_ref(second_fa_obj_constructor_ref),
            sender_addr,
            20000
        );

        // Verify initial sender balances
        let sender_first_fa_initial_balance = primary_fungible_store::balance(sender_addr, first_fa_metadata_object);
        assert!(sender_first_fa_initial_balance == 10000, sender_first_fa_initial_balance);
        let sender_second_fa_initial_balance = primary_fungible_store::balance(sender_addr, second_fa_metadata_object);
        assert!(sender_second_fa_initial_balance == 20000, sender_second_fa_initial_balance);

        vesting::create_vesting_stream(
            sender,
            user1_addr,
            total_amount,
            start_time,
            cliff_amount,
            duration,
            first_fa_metadata_object
        );

        // Verify first stream creation
        let first_vesting_stream_object = vesting::get_most_recent_stream();
        assert!(option::is_some(&first_vesting_stream_object), 0);
        let first_vesting_stream = option::borrow(&first_vesting_stream_object);
        assert!(object::is_owner(*first_vesting_stream, sender_addr) == true, 0);

        // Verify first stream vesting store balance
        let first_vesting_store = vesting::get_vesting_store(first_vesting_stream);
        let first_vesting_store_balance_after_create_stream = fungible_asset::balance(first_vesting_store);
        assert!(
            first_vesting_store_balance_after_create_stream == total_amount,
            first_vesting_store_balance_after_create_stream
        );

        vesting::create_vesting_stream(
            sender,
            user1_addr,
            total_amount,
            start_time,
            cliff_amount,
            duration,
            second_fa_metadata_object
        );

        // Verify second stream creation
        let second_vesting_stream_object = vesting::get_most_recent_stream();
        assert!(option::is_some(&second_vesting_stream_object), 0);
        let second_vesting_stream = option::borrow(&second_vesting_stream_object);
        assert!(object::is_owner(*second_vesting_stream, sender_addr) == true, 0);

        // Verify second stream vesting store balance
        let second_vesting_store = vesting::get_vesting_store(second_vesting_stream);
        let second_vesting_store_balance_after_create_stream = fungible_asset::balance(second_vesting_store);
        assert!(
            second_vesting_store_balance_after_create_stream == total_amount,
            second_vesting_store_balance_after_create_stream
        );

        timestamp::update_global_time_for_test_secs(start_time + duration);
        // Claim first stream
        vesting::claim_tokens(first_vesting_stream);
        let user1_first_fa_final_balance = primary_fungible_store::balance(user1_addr, first_fa_metadata_object);
        assert!(user1_first_fa_final_balance == total_amount, user1_first_fa_final_balance);

        // Claim second stream
        vesting::claim_tokens(second_vesting_stream);
        let user1_second_fa_final_balance = primary_fungible_store::balance(user1_addr, second_fa_metadata_object);
        assert!(user1_second_fa_final_balance == total_amount, user1_second_fa_final_balance);

        // Verify vesting store balances
        let first_vesting_store_balance_after_claim = fungible_asset::balance(first_vesting_store);
        assert!(first_vesting_store_balance_after_claim == 0, first_vesting_store_balance_after_claim);
        let second_vesting_store_balance_after_claim = fungible_asset::balance(second_vesting_store);
        assert!(second_vesting_store_balance_after_claim == 0, second_vesting_store_balance_after_claim);

    }

    #[test(aptos_framework = @0x1, sender = @deployment_addr, user1 = @0x101)]
    #[expected_failure(abort_code = 393218, location = object)]
    fun test_vesting_stream_deleted_upon_completion(
        aptos_framework: &signer, sender: &signer, user1: &signer
    ) {
        let fa_metadata_object = setup_test_env(aptos_framework, sender);

        vesting::create_vesting_stream(
            sender,
            signer::address_of(user1),
            100,
            100,
            50,
            100,
            fa_metadata_object
        );
        let vesting_stream_object = vesting::get_most_recent_stream();
        assert!(option::is_some(&vesting_stream_object), 0);

        // Verify stream owner
        let vesting_stream = option::borrow(&vesting_stream_object);
        assert!(object::is_owner(*vesting_stream, signer::address_of(sender)) == true, 0);

        // Claim tokens after stream is completed
        timestamp::update_global_time_for_test_secs(1000);
        vesting::claim_tokens(vesting_stream);

        // Check if claim and delete events are emitted
        let claim_events = event::emitted_events<vesting::ClaimVestingStreamEvent>();
        assert!(vector::length(&claim_events) == 1, 0);
        let delete_events = event::emitted_events<vesting::DeleteVestingStreamEvent>();
        assert!(vector::length(&delete_events) == 1, 1);

        // Check if object is deleted by checking owner
        object::is_owner(*vesting_stream, signer::address_of(sender));
    }

    #[test(aptos_framework = @0x1, sender = @deployment_addr, user1 = @0x101)]
    #[expected_failure(abort_code = vesting::ERR_AMOUNT_ZERO, location = vesting)]
    fun test_claim_zero_amount_error(aptos_framework: &signer, sender: &signer, user1: &signer) {

        // Create stream and check if it's created
        let fa_metadata_object = setup_test_env(aptos_framework, sender);
        vesting::create_vesting_stream(
            sender,
            signer::address_of(user1),
            100,
            100,
            50,
            100,
            fa_metadata_object
        );
        let vesting_stream_object = vesting::get_most_recent_stream();
        assert!(option::is_some(&vesting_stream_object), 0);

        // Try to claim 0 amount
        let vesting_stream = option::borrow(&vesting_stream_object);
        vesting::claim_tokens(vesting_stream);
    }

    #[test(aptos_framework = @0x1)]
    fun test_calculate_vested_amount(aptos_framework: &signer) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        let start_time = 100;
        let amount = 100;
        let cliff_amount = 50;
        let duration = 100;

        // before start time (claimable amount should be 0)
        let claimable_amount = vesting::calculate_vested_amount(amount, start_time, cliff_amount, duration);
        assert!(claimable_amount == 0, 0);

        // exactly at start time (claimable amount should be cliff)
        timestamp::update_global_time_for_test_secs(start_time);
        let claimable_amount = vesting::calculate_vested_amount(amount, start_time, cliff_amount, duration);
        assert!(claimable_amount == cliff_amount, 1);

        // halfway through the duration (claimable amount should be cliff)
        timestamp::update_global_time_for_test_secs(start_time + (duration / 2));
        let claimable_amount = vesting::calculate_vested_amount(amount, start_time, cliff_amount, duration);
        assert!(claimable_amount == cliff_amount + ((amount - cliff_amount) / 2), 2);

        // after duration (claimable amount should be 100)
        timestamp::update_global_time_for_test_secs(start_time + duration);
        let claimable_amount = vesting::calculate_vested_amount(amount, start_time, cliff_amount, duration);
        assert!(claimable_amount == amount, 3);
    }

    #[test(aptos_framework = @0x1, sender = @deployment_addr, user1 = @0x101)]
    fun test_multiple_identical_streams_per_user(
        aptos_framework: &signer, sender: &signer, user1: &signer
    ) {
        let fa_metadata_object = setup_test_env(aptos_framework, sender);

        let total_amount = 100;
        let start_time = 100;
        let cliff_amount = 50;
        let duration = 100;

        let user1_addr = signer::address_of(user1);

        // Create two identical streams and store their details
        vesting::create_vesting_stream(
            sender,
            user1_addr,
            total_amount,
            start_time,
            cliff_amount,
            duration,
            fa_metadata_object
        );
        let first_vesting_stream = option::borrow(&vesting::get_most_recent_stream());
        let (
            first_stream_beneficiary,
            first_stream_amount,
            first_stream_claimed_amount,
            first_stream_start_time,
            first_stream_cliff_amount,
            first_stream_duration
        ) = vesting::get_vesting_stream_details(first_vesting_stream);

        vesting::create_vesting_stream(
            sender,
            user1_addr,
            total_amount,
            start_time,
            cliff_amount,
            duration,
            fa_metadata_object
        );
        let second_vesting_stream = option::borrow(&vesting::get_most_recent_stream());
        let (
            second_stream_beneficiary,
            second_stream_amount,
            second_stream_claimed_amount,
            second_stream_start_time,
            second_stream_cliff_amount,
            second_stream_duration
        ) = vesting::get_vesting_stream_details(second_vesting_stream);

        // Check if both streams are created and values are identical
        assert!(first_stream_beneficiary == second_stream_beneficiary, 0);
        assert!(first_stream_amount == second_stream_amount, 1);
        assert!(first_stream_claimed_amount == second_stream_claimed_amount, 2);
        assert!(first_stream_start_time == second_stream_start_time, 3);
        assert!(first_stream_cliff_amount == second_stream_cliff_amount, 4);
        assert!(first_stream_duration == second_stream_duration, 5);
    }

    #[test(aptos_framework = @0x1, sender = @deployment_addr, user1 = @0x101)]
    fun test_create_stream_with_after_other_stream_completed(
        aptos_framework: &signer, sender: &signer, user1: &signer
    ) {
        let fa_metadata_object = setup_test_env(aptos_framework, sender);

        let total_amount = 100;
        let start_time = 100;
        let cliff_amount = 50;
        let duration = 100;

        let user1_addr = signer::address_of(user1);

        vesting::create_vesting_stream(
            sender,
            user1_addr,
            total_amount,
            start_time,
            cliff_amount,
            duration,
            fa_metadata_object
        );
        timestamp::update_global_time_for_test_secs(2000);
        let first_vesting_stream = option::borrow(&vesting::get_most_recent_stream());
        let (
            first_stream_beneficiary,
            first_stream_amount,
            first_stream_claimed_amount,
            first_stream_start_time,
            first_stream_cliff_amount,
            first_stream_duration
        ) = vesting::get_vesting_stream_details(first_vesting_stream);
        assert!(first_stream_beneficiary == user1_addr, 0);
        assert!(first_stream_amount == total_amount, 1);
        assert!(first_stream_claimed_amount == 0, 2);
        assert!(first_stream_start_time == start_time, 3);
        assert!(first_stream_cliff_amount == cliff_amount, 4);
        assert!(first_stream_duration == duration, 5);

        // Claim tokens
        vesting::claim_tokens(first_vesting_stream);
        let user1_balance_after_claim = primary_fungible_store::balance(user1_addr, fa_metadata_object);
        assert!(user1_balance_after_claim == total_amount, user1_balance_after_claim);

        // create new stream after the previous one is completed, starting in the future

        let new_total_amount = 200;
        let new_start_time = 3000;
        let new_cliff_amount = 20;
        let new_duration = 200;

        vesting::create_vesting_stream(
            sender,
            user1_addr,
            new_total_amount,
            new_start_time,
            new_cliff_amount,
            new_duration,
            fa_metadata_object
        );

        let second_vesting_stream = option::borrow(&vesting::get_most_recent_stream());
        let (
            second_stream_beneficiary,
            second_stream_amount,
            second_stream_claimed_amount,
            second_stream_start_time,
            second_stream_cliff_amount,
            second_stream_duration
        ) = vesting::get_vesting_stream_details(second_vesting_stream);
        assert!(second_stream_beneficiary == user1_addr, 0);
        assert!(second_stream_amount == new_total_amount, 1);
        assert!(second_stream_claimed_amount == 0, 2);
        assert!(second_stream_start_time == new_start_time, 3);
        assert!(second_stream_cliff_amount == new_cliff_amount, 4);
        assert!(second_stream_duration == new_duration, 5);

    }

    #[test(aptos_framework = @0x1, sender = @deployment_addr, user1 = @0x101)]
    #[expected_failure(abort_code = vesting::ERR_START_TIME_MUST_BE_IN_THE_FUTURE, location = vesting)]
    fun test_create_stream_starting_in_the_past(
        aptos_framework: &signer, sender: &signer, user1: &signer
    ) {
        let fa_metadata_object = setup_test_env(aptos_framework, sender);
        let start_time = 100;
        let future_time = 2000;
        // Update time to after start time and try to create stream
        timestamp::update_global_time_for_test_secs(future_time);
        vesting::create_vesting_stream(
            sender,
            signer::address_of(user1),
            100,
            start_time,
            50,
            100,
            fa_metadata_object
        );

    }

    // #[test(
    //     aptos_framework = @0x1, sender = @deployment_addr, user1 = @0x101, user2 = @0x102
    // )]
    // #[expected_failure(abort_code = 4008, location = vesting)]
    // fun test_claim_when_stream_does_not_exist(
    //     aptos_framework: &signer,
    //     sender: &signer,
    //     user1: &signer,
    //     user2: &signer
    // ) {
    //     let fa_metadata_object = setup_test_env(aptos_framework, sender);

    //     let total_amount = 100;
    //     let start_time = 100;
    //     let cliff_amount = 50;
    //     let duration = 100;

    //     let user1_addr = signer::address_of(user1);

    //     vesting::create_vesting_stream(
    //         sender,
    //         user1_addr,
    //         total_amount,
    //         start_time,
    //         cliff_amount,
    //         duration,
    //         fa_metadata_object
    //     );

    //     let vesting_stream = option::borrow(&vesting::get_most_recent_stream());
    //     timestamp::update_global_time_for_test_secs(start_time + duration);
    //     vesting::claim_tokens(vesting_stream);

    //     // Stream is deleted after claiming, so this should fail
    //     vesting::claim_tokens(vesting_stream);
    // }

    #[test(aptos_framework = @0x1, sender = @deployment_addr, user1 = @0x101)]
    fun test_view_functions(aptos_framework: &signer, sender: &signer, user1: &signer) {
        let fa_metadata_object = setup_test_env(aptos_framework, sender);

        let total_amount = 100;
        let start_time = 100;
        let cliff_amount = 50;
        let duration = 100;

        let user1_addr = signer::address_of(user1);

        vesting::create_vesting_stream(
            sender,
            user1_addr,
            total_amount,
            start_time,
            cliff_amount,
            duration,
            fa_metadata_object
        );

        // Verify stream creation
        let vesting_stream = option::borrow(&vesting::get_most_recent_stream());

        let (
            stream_beneficiary,
            stream_amount,
            stream_claimed_amount,
            stream_start_time,
            stream_cliff_amount,
            stream_duration
        ) = vesting::get_vesting_stream_details(vesting_stream);
        assert!(stream_beneficiary == user1_addr, 0);
        assert!(stream_amount == total_amount, 2);
        assert!(stream_claimed_amount == 0, 3);
        assert!(stream_start_time == start_time, 4);
        assert!(stream_cliff_amount == cliff_amount, 5);
        assert!(stream_duration == duration, 6);
    }

    #[test(aptos_framework = @0x1, sender = @deployment_addr, user1 = @0x101)]
    #[expected_failure(abort_code = vesting::ERR_CLIFF_AMOUNT_MUST_BE_LESS_OR_EQUAL_THAN_AMOUNT, location = vesting)]
    fun test_cant_create_stream_with_cliff_amount_greater_than_amount(
        aptos_framework: &signer, sender: &signer, user1: &signer
    ) {
        let fa_metadata_object = setup_test_env(aptos_framework, sender);

        let total_amount = 100;
        let cliff_amount = 200;

        vesting::create_vesting_stream(
            sender,
            signer::address_of(user1),
            total_amount,
            100,
            cliff_amount,
            100,
            fa_metadata_object
        );
    }

    #[test(aptos_framework = @0x1, sender = @deployment_addr, user1 = @0x101)]
    fun test_create_stream_with_cliff_amount_equal_to_amount(
        aptos_framework: &signer, sender: &signer, user1: &signer
    ) {
        let fa_metadata_object = setup_test_env(aptos_framework, sender);

        let total_amount = 100;
        let cliff_amount = 100;
        let start_time = 40;
        let duration = 100;

        vesting::create_vesting_stream(
            sender,
            signer::address_of(user1),
            total_amount,
            start_time,
            cliff_amount,
            duration,
            fa_metadata_object
        );

        // Verify claimable amount is equal to cliff amount at start time.
        timestamp::update_global_time_for_test_secs(start_time);
        let vesting_stream = option::borrow(&vesting::get_most_recent_stream());
        let claimable_amount = vesting::get_claimable_amount_from_obj(vesting_stream);
        assert!(claimable_amount == cliff_amount, claimable_amount);
    }

    #[test(aptos_framework = @0x1, sender = @deployment_addr, user1 = @0x101)]
    #[expected_failure(abort_code = vesting::ERR_DURATION_ZERO, location = vesting)]
    fun test_cant_create_stream_with_duration_zero(
        aptos_framework: &signer, sender: &signer, user1: &signer
    ) {
        let fa_metadata_object = setup_test_env(aptos_framework, sender);

        // Create stream with duration 0 should fail
        let duration = 0;
        vesting::create_vesting_stream(
            sender,
            signer::address_of(user1),
            100,
            100,
            50,
            duration,
            fa_metadata_object
        );
    }

    #[test(aptos_framework = @0x1, sender = @deployment_addr, user1 = @0x101)]
    fun test_create_stream_with_duration_zero_and_cliff_amount_equal_to_amount(
        aptos_framework: &signer, sender: &signer, user1: &signer
    ) {
        let fa_metadata_object = setup_test_env(aptos_framework, sender);

        // Create stream with duration 0 should fail
        let duration = 0;
        let amount = 100;
        let cliff_amount = 100;
        vesting::create_vesting_stream(
            sender,
            signer::address_of(user1),
            100,
            amount,
            cliff_amount,
            duration,
            fa_metadata_object
        );
    }
}
