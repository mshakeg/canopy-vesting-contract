# Vesting Contract Challenge

## Instructions
The goal of this challenge is to implement a vesting contract in the Move language, with functionality to allow an owner to set up vesting streams for multiple users. Each user should be able to check their vested balance and claim the tokens as they vest over time. The contract must handle vesting streams with individual cliff and duration parameters for each user.

### Requirements:

 1. Owner Role: The contract should allow the owner to set up and manage vesting streams for different users.
 2. Vesting Stream: Each user has their own vesting stream, defined by the following parameters:
  • Beneficiary: The address of the user receiving the vested tokens.
  • Amount: The total number of tokens to be vested.
  • Start Time: The time when the vesting period starts.
  • Cliff: The duration of the cliff, before tokens can be claimed.
  • Duration: The total duration of the vesting period.
 3. User Functions:
  • Users can check their vested token balance (the amount of tokens they are eligible to claim).
  • Users can claim the vested tokens that have been unlocked by the vesting schedule.
 4. Security:
  • Only the owner can set up and modify vesting streams.
  • Users can only claim their vested tokens (they cannot modify the vesting stream).
  • The contract must handle cases where users have already claimed their full amount.

The project should include unit tests to verify the correct implementation of the functionality as well as edge cases.


## Solution

This project is created using the [Scaffold Move template](https://github.com/arjanjohan/scaffold-move). Use the following commands to setup the project and run the tests:
```
yarn install
yarn compile
yarn test
```
### Smart contract
The [vesting.move](packages/move/sources/vesting.move) contract contains the solution for the challenge. The entry functions are:
#### create_vesting_stream
Creates a new stream and stores the details mapped to the beneficiary's address. Transfers the FA token amount to the vesting streams primary fungible store.

#### claim_tokens
Callable by anyone by passing the VestingStream Object. If the stream exists, it checks if the claimable amount is positive before transferring the tokens to the beneficiary. After a claim, the `claimed_amount` value is updated. When the full amount is claimed, the VestingStream Object is  deleted.

### Tests
The tests are located in [test_end_to_end.move](packages/move/tests/test_end_to_end.move). To run these tests, use the command `yarn test` from either the project root or the `packages/move` directory. The output should look like this:
```
Running Move unit tests
[ PASS    ] 0xf6f67805e60b18ee9ced00c3f71e030b2487af5480610e9324dd14d6f6b92690::test_end_to_end::test_calculate_vested_amount
[ PASS    ] 0xf6f67805e60b18ee9ced00c3f71e030b2487af5480610e9324dd14d6f6b92690::test_end_to_end::test_cant_create_stream_with_cliff_amount_greater_than_amount
[ PASS    ] 0xf6f67805e60b18ee9ced00c3f71e030b2487af5480610e9324dd14d6f6b92690::test_end_to_end::test_cant_create_stream_with_duration_zero
[ PASS    ] 0xf6f67805e60b18ee9ced00c3f71e030b2487af5480610e9324dd14d6f6b92690::test_end_to_end::test_claim_zero_amount_error
[ PASS    ] 0xf6f67805e60b18ee9ced00c3f71e030b2487af5480610e9324dd14d6f6b92690::test_end_to_end::test_create_stream_starting_in_the_past
[ PASS    ] 0xf6f67805e60b18ee9ced00c3f71e030b2487af5480610e9324dd14d6f6b92690::test_end_to_end::test_create_stream_with_after_other_stream_completed
[ PASS    ] 0xf6f67805e60b18ee9ced00c3f71e030b2487af5480610e9324dd14d6f6b92690::test_end_to_end::test_create_stream_with_cliff_amount_equal_to_amount
[ PASS    ] 0xf6f67805e60b18ee9ced00c3f71e030b2487af5480610e9324dd14d6f6b92690::test_end_to_end::test_create_stream_with_duration_zero_and_cliff_amount_equal_to_amount
[ PASS    ] 0xf6f67805e60b18ee9ced00c3f71e030b2487af5480610e9324dd14d6f6b92690::test_end_to_end::test_happy_path
[ PASS    ] 0xf6f67805e60b18ee9ced00c3f71e030b2487af5480610e9324dd14d6f6b92690::test_end_to_end::test_happy_path_two_fa
[ PASS    ] 0xf6f67805e60b18ee9ced00c3f71e030b2487af5480610e9324dd14d6f6b92690::test_end_to_end::test_multiple_identical_streams_per_user
[ PASS    ] 0xf6f67805e60b18ee9ced00c3f71e030b2487af5480610e9324dd14d6f6b92690::test_end_to_end::test_vesting_stream_deleted_upon_completion
[ PASS    ] 0xf6f67805e60b18ee9ced00c3f71e030b2487af5480610e9324dd14d6f6b92690::test_end_to_end::test_view_functions
Test result: OK. Total tests: 13; passed: 13; failed: 0
{
  "Result": "Success"
}
```