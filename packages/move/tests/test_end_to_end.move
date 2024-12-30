#[test_only]
module deployment_addr::test_end_to_end {
    use std::option;
    use std::signer;
    use std::string;

    use aptos_std::debug;
    use aptos_std::string_utils;

    use aptos_framework::fungible_asset;
    use aptos_framework::object;
    use aptos_framework::primary_fungible_store;
    use aptos_framework::timestamp;

    use deployment_addr::vesting;

    #[test(
        aptos_framework = @0x1,
        sender = @deployment_addr,
        initial_stream_creator = @0x100,
        user1 = @0x101,
    )]
    fun test_happy_path(
        aptos_framework: &signer,
        sender: &signer,
        initial_stream_creator: &signer,
        user1: &signer,
    ) {
        let fa_metadata_object = setup_test_env(aptos_framework, sender, initial_stream_creator, user1);

        let total_reward_amount = 100;
        let start_time = 100;
        let cliff = 100;
        let duration = 100;

        let sender_addr = signer::address_of(sender);
        let user1_addr = signer::address_of(user1);

        vesting::create_vesting_stream(
            initial_stream_creator,
            user1_addr,
            total_reward_amount,
            start_time,
            cliff,
            duration
        );

        let user1_balance = primary_fungible_store::balance(user1_addr, fa_metadata_object);
        assert!(user1_balance == 0, user1_balance);

        // at the start of the cliff, 0 should be claimable
        timestamp::update_global_time_for_test_secs(start_time + cliff);
        let claimable_amount = vesting::get_claimable_amount(user1_addr);
        assert!(claimable_amount == 0, claimable_amount);

        // after half of the duration, half of the amount should be claimable
        timestamp::update_global_time_for_test_secs(start_time + cliff + (duration / 2));
        let claimable_amount = vesting::get_claimable_amount(user1_addr);
        assert!(claimable_amount == total_reward_amount / 2, claimable_amount);
        vesting::claim_tokens(user1);

        // after duration the remaining half should be claimable
        timestamp::update_global_time_for_test_secs(start_time + cliff + duration);
        let claimable_amount = vesting::get_claimable_amount(user1_addr);
        assert!(claimable_amount == total_reward_amount / 2, claimable_amount);
        vesting::claim_tokens(user1);

        // After claiming twice, the total amount should be claimed
        let user1_balance_after_claim = primary_fungible_store::balance(user1_addr, fa_metadata_object);
        assert!(user1_balance_after_claim == total_reward_amount, user1_balance_after_claim);
    }

    #[test(
        aptos_framework = @0x1,
        sender = @deployment_addr,
        initial_stream_creator = @0x100,
        user1 = @0x101,
    )]
    #[expected_failure(abort_code = 10, location = vesting)]
    fun test_claim_zero_amount_error(
        aptos_framework: &signer,
        sender: &signer,
        initial_stream_creator: &signer,
        user1: &signer,
    ) {
        let fa_metadata_object = setup_test_env(aptos_framework, sender, initial_stream_creator, user1);

        let total_reward_amount = 100;
        let start_time = 100;
        let cliff = 100;
        let duration = 100;

        let sender_addr = signer::address_of(sender);
        let user1_addr = signer::address_of(user1);

        vesting::create_vesting_stream(
            initial_stream_creator,
            user1_addr,
            total_reward_amount,
            start_time,
            cliff,
            duration
        );

        let claimable_amount = vesting::get_claimable_amount(user1_addr);
        assert!(claimable_amount == 0, claimable_amount);
        vesting::claim_tokens(user1);
    }



    #[test(aptos_framework = @0x1)]
    fun test_calculate_vested_amount(aptos_framework: &signer) {
        timestamp::set_time_has_started_for_testing(aptos_framework);
        timestamp::update_global_time_for_test_secs(1000);
        let current_time = timestamp::now_seconds();

        let amount = 100;
        let cliff = 100;
        let duration = 100;

        // before start time (claimable amount should be 0)
        let start_time = current_time + 100;
        let claimable_amount =
            vesting::calculate_vested_amount(
                amount, start_time, cliff, duration
            );
        assert!(claimable_amount == 0, 0);

        // exactly at start time (claimable amount should be 0)
        start_time = current_time;
        let claimable_amount =
            vesting::calculate_vested_amount(
                amount, start_time, cliff, duration
            );
        assert!(claimable_amount == 0, 1);

        // exactly at cliff (claimable amount should be 0)
        start_time = current_time - cliff;
        let claimable_amount =
            vesting::calculate_vested_amount(
                amount, start_time, cliff, duration
            );
        assert!(claimable_amount == 0, 2);

        // after duration (claimable amount should be 100)
        start_time = current_time - cliff - duration;
        let claimable_amount =
            vesting::calculate_vested_amount(
                amount, start_time, cliff, duration
            );
        assert!(claimable_amount == 100, 3);

        start_time = current_time - cliff - 50;
        let claimable_amount =
            vesting::calculate_vested_amount(
                amount, start_time, cliff, duration
            );
        assert!(claimable_amount == 50, 4);

    }

    #[test(
        aptos_framework = @0x1,
        sender = @deployment_addr,
        initial_stream_creator = @0x100,
        user1 = @0x101,
    )]
    #[expected_failure(abort_code = 4, location = vesting)]
    fun test_only_one_stream_per_user(
        aptos_framework: &signer,
        sender: &signer,
        initial_stream_creator: &signer,
        user1: &signer,
    ) {       
        let fa_metadata_object = setup_test_env(aptos_framework, sender, initial_stream_creator, user1);

        let total_reward_amount = 100;
        let start_time = 100;
        let cliff = 100;
        let duration = 100;

        let sender_addr = signer::address_of(sender);
        let user1_addr = signer::address_of(user1);

        vesting::create_vesting_stream(
            initial_stream_creator,
            user1_addr,
            total_reward_amount,
            start_time,
            cliff,
            duration
        );
        vesting::create_vesting_stream(
            initial_stream_creator,
            user1_addr,
            total_reward_amount,
            start_time,
            cliff,
            duration
        );

    }


    #[test(
        aptos_framework = @0x1,
        sender = @deployment_addr,
        initial_stream_creator = @0x100,
        user1 = @0x101,
    )]
    #[expected_failure(abort_code = 5, location = vesting)]
    fun test_only_admin_can_create_stream(
        aptos_framework: &signer,
        sender: &signer,
        initial_stream_creator: &signer,
        user1: &signer,
    ) {
        let fa_metadata_object = setup_test_env(aptos_framework, sender, initial_stream_creator, user1);

        let total_reward_amount = 100;
        let start_time = 100;
        let cliff = 100;
        let duration = 100;

        let sender_addr = signer::address_of(sender);
        let user1_addr = signer::address_of(user1);

        vesting::create_vesting_stream(
            user1,
            user1_addr,
            total_reward_amount,
            start_time,
            cliff,
            duration
        );

    }

    #[test(
        aptos_framework = @0x1,
        sender = @deployment_addr,
        initial_stream_creator = @0x100,
        user1 = @0x101,
    )]
    fun test_create_stream_with_after_other_stream_completed(
        aptos_framework: &signer,
        sender: &signer,
        initial_stream_creator: &signer,
        user1: &signer,
    ) {
                let fa_metadata_object = setup_test_env(aptos_framework, sender, initial_stream_creator, user1);

        let total_reward_amount = 100;
        let start_time = 100;
        let cliff = 100;
        let duration = 100;

        let sender_addr = signer::address_of(sender);
        let user1_addr = signer::address_of(user1);

        vesting::create_vesting_stream(
            initial_stream_creator,
            user1_addr,
            total_reward_amount,
            start_time,
            cliff,
            duration
        );
        timestamp::update_global_time_for_test_secs(2000);
        vesting::claim_tokens(user1);
        let user1_balance_after_claim = primary_fungible_store::balance(user1_addr, fa_metadata_object);
        assert!(user1_balance_after_claim == total_reward_amount, user1_balance_after_claim);

        // create new stream after the previous one is completed, starting in the future
        let new_start_time = 3000;
        vesting::create_vesting_stream(
            initial_stream_creator,
            user1_addr,
            total_reward_amount,
            new_start_time,
            cliff,
            duration
        );

    }


    #[test(
        aptos_framework = @0x1,
        sender = @deployment_addr,
        initial_stream_creator = @0x100,
        user1 = @0x101,
    )]
    #[expected_failure(abort_code = 1, location = vesting)]
    fun test_create_stream_starting_in_the_past(
        aptos_framework: &signer,
        sender: &signer,
        initial_stream_creator: &signer,
        user1: &signer,
    ) {
                let fa_metadata_object = setup_test_env(aptos_framework, sender, initial_stream_creator, user1);

        let total_reward_amount = 100;
        let start_time = 100;
        let cliff = 100;
        let duration = 100;

        let sender_addr = signer::address_of(sender);
        let user1_addr = signer::address_of(user1);

        timestamp::update_global_time_for_test_secs(2000);
        vesting::create_vesting_stream(
            initial_stream_creator,
            user1_addr,
            total_reward_amount,
            start_time,
            cliff,
            duration
        );

    }

    fun setup_test_env(
        aptos_framework: &signer,
        sender: &signer,
        initial_stream_creator: &signer,
        user1: &signer,
    ): object::Object<fungible_asset::Metadata> {
        timestamp::set_time_has_started_for_testing(aptos_framework);
       
        let sender_addr = signer::address_of(sender);
        let initial_stream_creator_addr = signer::address_of(initial_stream_creator);
        let user1_addr = signer::address_of(user1);

        let total_reward_amount = 100;
        let start_time = 100;
        let cliff = 100;
        let duration = 100;


        let fa_obj_constructor_ref = &object::create_sticky_object(sender_addr);
        primary_fungible_store::create_primary_store_enabled_fungible_asset(
            fa_obj_constructor_ref,
            option::none(),
            string::utf8(b"Test FA"),
            string::utf8(b"TFA"),
            8,
            string::utf8(b"url"),
            string::utf8(b"url"),
        );
        let fa_metadata_object = object::object_from_constructor_ref<fungible_asset::Metadata>(fa_obj_constructor_ref);
        primary_fungible_store::mint(
            &fungible_asset::generate_mint_ref(fa_obj_constructor_ref),
            signer::address_of(initial_stream_creator),
            total_reward_amount
        );

        vesting::init_module_for_test(
            aptos_framework,
            sender,
            initial_stream_creator_addr,
            fa_metadata_object,
        );
        fa_metadata_object
    }
}