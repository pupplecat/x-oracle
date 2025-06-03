
module x_oracle::x_oracle_test;

use sui::clock;
use sui::test_scenario::{Self as ts};
use sui::object;
use sui::table;
use sui::vec_set;
use std::type_name::{Self, get};
use x_oracle::x_oracle::{Self, XOracle, XOraclePolicyCap, init_for_testing as init_x_oracle_for_testing};
use x_oracle::price_feed::{PriceFeed};
use x_oracle::price_update_policy;
use std::unit_test::assert_eq;
use sui::test_scenario::Scenario;
use sui::clock::Clock;

const ADMIN: address = @0xAD;

fun init_x_oracle(scenario: &mut Scenario): (Clock, XOracle, XOraclePolicyCap) {
    let ctx = ts::ctx(scenario);
    init_x_oracle_for_testing(ctx);

    scenario.next_tx(ADMIN);
    let x_oracle = ts::take_shared<XOracle>(scenario);
    let x_oracle_policy_cap = ts::take_from_sender<XOraclePolicyCap>(scenario);

    let clock = clock::create_for_testing(ts::ctx(scenario));

    (clock, x_oracle, x_oracle_policy_cap)
}

#[test]
fun test_x_oracle_initialization() {
    let mut scenario = ts::begin(ADMIN);
    let ctx= ts::ctx(&mut scenario);

    init_x_oracle_for_testing(ctx);

    scenario.next_tx(ADMIN);
    {
        let x_oracle = ts::take_shared<XOracle>(&scenario);

        assert_eq!(x_oracle.prices().length(), 0);

        ts::return_shared(x_oracle);
    };

    ts::end(scenario);
}

// #[test]
// fun test_add_and_remove_primary_price_update_rule() {
//     let mut scenario = ts::begin(ADMIN);

//     let (clock, x_oracle, x_oracle_policy_cap) = init_x_oracle(&mut scenario);

//     scenario.next_tx(ADMIN);
//     {


//         x_oracle::add_primary_price_update_rule<u64, u64>(&mut x_oracle, &x_oracle_policy_cap);
//         let rules = price_update_policy::add_rule(policy, policy_cap)<u64>(&x_oracle.priceup);
//         assert!(vec_set::contains(&rules, &get<u64>()), "Rule should be added");


//     };

// ts::return_shared(x_oracle);
// ts::return_to_address(ADMIN, x_oracle_policy_cap);
//     ts::end(scenario);


// }

// #[test]
// fun test_price_update_request_and_confirmation() {
//     let ctx = ts::new_tx_context();
//     let clock = clock::new();
//     let (mut x_oracle, x_oracle_policy_cap) = x_oracle::new(&mut ctx);

//     let mut request = x_oracle::price_update_request<u64>(&x_oracle);
//     let price_feed = price_feed::new(1000, clock::timestamp_ms(&clock) / 1000);

//     x_oracle::set_primary_price<u64, u64>(100, &mut request, price_feed);
//     x_oracle::confirm_price_update_request(&mut x_oracle, request, &clock);

//     let updated_price_feed = table::borrow(&x_oracle.prices, get<u64>());
//     assert!(price_feed::value(&updated_price_feed) == 1000, "Price feed value should be updated");
// }