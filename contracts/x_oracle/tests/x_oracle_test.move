module x_oracle::x_oracle_test;

use std::type_name::get;
use std::unit_test::assert_eq;
use std::uq32_32;
use sui::clock::{Self, Clock};
use sui::sui::SUI;
use sui::test_scenario::{Self as ts, Scenario};
use sui::test_utils;
use x_oracle::pyth_mock_adapter::PythRule;
use x_oracle::supra_mock_adapter::SupraRule;
use x_oracle::switchboard_mock_adapter::SwitchboardRule;
use x_oracle::x_oracle::{
    XOracle,
    XOraclePolicyCap,
    init_for_testing as init_x_oracle_for_testing,
    init_rules_if_not_exist,
    add_primary_price_update_rule,
    remove_primary_price_update_rule,
    add_secondary_price_update_rule,
    remove_secondary_price_update_rule,
    price_update_request,
    confirm_price_update_request
};

const ADMIN: address = @0xAD;

public struct ETH has drop {}

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
    let ctx = ts::ctx(&mut scenario);

    init_x_oracle_for_testing(ctx);

    scenario.next_tx(ADMIN);
    {
        let x_oracle = ts::take_shared<XOracle>(&scenario);

        assert_eq!(x_oracle.prices().length(), 0);

        ts::return_shared(x_oracle);
    };

    ts::end(scenario);
}

#[test]
fun test_primary() {
    let mut scenario = ts::begin(ADMIN);

    let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_x_oracle(&mut scenario);

    scenario.next_tx(ADMIN);
    {
        let ctx = ts::ctx(&mut scenario);
        init_rules_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, ctx);
        clock::set_for_testing(&mut clock, 1000*1000);

        add_primary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);

        let mut request = price_update_request(&x_oracle);
        x_oracle::pyth_mock_adapter::update_price_as_primary<SUI>(
            &mut request,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        assert!(
            uq32_32::int_mul(1, x_oracle::test_utils::get_price<SUI>(&x_oracle, &clock)) == 10,
            0,
        ); // check if the price accruately updated
    };

    test_utils::destroy(clock);
    ts::return_to_address(ADMIN, x_oracle_policy_cap);
    ts::return_shared(x_oracle);
    ts::end(scenario);
}

#[
    test,
    expected_failure(
        abort_code = x_oracle::price_update_policy::REQUIRE_ALL_RULES_FOLLOWED,
        location = x_oracle::price_update_policy,
    ),
]
fun test_primary_error_not_follow_rule() {
    let mut scenario = ts::begin(ADMIN);

    let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_x_oracle(&mut scenario);

    scenario.next_tx(ADMIN);
    {
        let ctx = ts::ctx(&mut scenario);
        init_rules_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, ctx);
        clock::set_for_testing(&mut clock, 1000*1000);

        add_primary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);

        let request = price_update_request(&x_oracle);
        confirm_price_update_request<SUI>(&mut x_oracle, request, &clock);

        assert!(
            uq32_32::int_mul(1, x_oracle::test_utils::get_price<SUI>(&x_oracle, &clock)) == 10,
            0,
        ); // check if the price accruately updated
    };

    test_utils::destroy(clock);
    ts::return_to_address(ADMIN, x_oracle_policy_cap);
    ts::return_shared(x_oracle);
    ts::end(scenario);
}

#[test]
fun test_primary_for_multiple_prices() {
    let mut scenario = ts::begin(ADMIN);
    let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_x_oracle(&mut scenario);

    scenario.next_tx(ADMIN);
    {
        let ctx = ts::ctx(&mut scenario);
        init_rules_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, ctx);
        clock::set_for_testing(&mut clock, 1000 * 1000);

        add_primary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_primary_price_update_rule<ETH, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);

        let mut request_update_sui = price_update_request(&x_oracle);
        let mut request_update_eth = price_update_request(&x_oracle);

        x_oracle::pyth_mock_adapter::update_price_as_primary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        x_oracle::supra_mock_adapter::update_price_as_primary<ETH>(
            &mut request_update_eth,
            1000 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );

        confirm_price_update_request<SUI>(&mut x_oracle, request_update_sui, &clock);
        confirm_price_update_request<ETH>(&mut x_oracle, request_update_eth, &clock);

        assert!(
            uq32_32::int_mul(1, x_oracle::test_utils::get_price<SUI>(&x_oracle, &clock)) == 10,
            0,
        ); // check if the price accruately updated
        assert!(
            uq32_32::int_mul(1, x_oracle::test_utils::get_price<ETH>(&x_oracle, &clock)) == 1000,
            0,
        ); // check if the price accruately updated
    };

    test_utils::destroy(clock);
    ts::return_to_address(ADMIN, x_oracle_policy_cap);
    ts::return_shared(x_oracle);
    ts::end(scenario);
}

#[
    test,
    expected_failure(
        abort_code = x_oracle::x_oracle::ONLY_SUPPORT_ONE_PRIMARY,
        location = x_oracle::x_oracle,
    ),
]
fun test_two_primary_error() {
    let mut scenario = ts::begin(ADMIN);
    let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_x_oracle(&mut scenario);

    scenario.next_tx(ADMIN);
    {
        let ctx = ts::ctx(&mut scenario);
        init_rules_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, ctx);
        clock::set_for_testing(&mut clock, 1000 * 1000);

        add_primary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_primary_price_update_rule<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);

        let mut request_update_sui = price_update_request(&x_oracle);

        x_oracle::pyth_mock_adapter::update_price_as_primary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        x_oracle::supra_mock_adapter::update_price_as_primary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );

        confirm_price_update_request<SUI>(&mut x_oracle, request_update_sui, &clock);
    };

    test_utils::destroy(clock);
    ts::return_to_address(ADMIN, x_oracle_policy_cap);
    ts::return_shared(x_oracle);
    ts::end(scenario);
}

#[test]
fun test_primary_with_secondary() {
    let mut scenario = ts::begin(ADMIN);
    let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_x_oracle(&mut scenario);

    scenario.next_tx(ADMIN);
    {
        let ctx = ts::ctx(&mut scenario);
        init_rules_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, ctx);
        clock::set_for_testing(&mut clock, 1000 * 1000);

        add_primary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_secondary_price_update_rule<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);

        let mut request_update_sui = price_update_request(&x_oracle);
        x_oracle::pyth_mock_adapter::update_price_as_primary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        x_oracle::supra_mock_adapter::update_price_as_secondary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        confirm_price_update_request<SUI>(&mut x_oracle, request_update_sui, &clock);

        assert!(
            uq32_32::int_mul(1, x_oracle::test_utils::get_price<SUI>(&x_oracle, &clock)) == 10,
            0,
        ); // check if the price accruately updated
    };

    test_utils::destroy(clock);
    ts::return_to_address(ADMIN, x_oracle_policy_cap);
    ts::return_shared(x_oracle);
    ts::end(scenario);
}

#[test]
fun test_primary_with_multiple_secondary() {
    let mut scenario = ts::begin(ADMIN);
    let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_x_oracle(&mut scenario);

    scenario.next_tx(ADMIN);
    {
        let ctx = ts::ctx(&mut scenario);
        init_rules_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, ctx);
        clock::set_for_testing(&mut clock, 1000 * 1000);

        add_primary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_secondary_price_update_rule<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_secondary_price_update_rule<SUI, SwitchboardRule>(&mut x_oracle, &x_oracle_policy_cap);

        let mut request_update_sui = price_update_request(&x_oracle);
        x_oracle::pyth_mock_adapter::update_price_as_primary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        x_oracle::supra_mock_adapter::update_price_as_secondary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        x_oracle::switchboard_mock_adapter::update_price_as_secondary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        confirm_price_update_request<SUI>(&mut x_oracle, request_update_sui, &clock);

        assert!(
            uq32_32::int_mul(1, x_oracle::test_utils::get_price<SUI>(&x_oracle, &clock)) == 10,
            0,
        ); // check if the price accruately updated
    };

    test_utils::destroy(clock);
    ts::return_to_address(ADMIN, x_oracle_policy_cap);
    ts::return_shared(x_oracle);
    ts::end(scenario);
}

#[test]
fun test_primary_with_multiple_secondary_with_low_price_gap() {
    let mut scenario = ts::begin(ADMIN);
    let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_x_oracle(&mut scenario);

    scenario.next_tx(ADMIN);
    {
        let ctx = ts::ctx(&mut scenario);
        init_rules_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, ctx);
        clock::set_for_testing(&mut clock, 1000 * 1000);

        add_primary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_secondary_price_update_rule<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_secondary_price_update_rule<SUI, SwitchboardRule>(&mut x_oracle, &x_oracle_policy_cap);

        let mut request_update_sui = price_update_request(&x_oracle);
        x_oracle::pyth_mock_adapter::update_price_as_primary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        x_oracle::supra_mock_adapter::update_price_as_secondary<SUI>(
            &mut request_update_sui,
            99 * std::u64::pow(10, x_oracle::price_feed::decimals()) / 10,
            1000,
        );
        x_oracle::switchboard_mock_adapter::update_price_as_secondary<SUI>(
            &mut request_update_sui,
            101 * std::u64::pow(10, x_oracle::price_feed::decimals()) / 10,
            1000,
        );
        // Price from pyth = $10
        // Price from supra = $9.9
        // Price from svb = $10.1
        // since the gap between pyth and all the secondary is less than or equal to 1% the price update should succeed
        confirm_price_update_request<SUI>(&mut x_oracle, request_update_sui, &clock);

        assert!(
            uq32_32::int_mul(1, x_oracle::test_utils::get_price<SUI>(&x_oracle, &clock)) == 10,
            0,
        ); // check if the price accruately updated
    };

    test_utils::destroy(clock);
    ts::return_to_address(ADMIN, x_oracle_policy_cap);
    ts::return_shared(x_oracle);
    ts::end(scenario);
}

#[test]
fun test_primary_with_multiple_secondary_with_one_high_price_gap() {
    let mut scenario = ts::begin(ADMIN);
    let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_x_oracle(&mut scenario);

    scenario.next_tx(ADMIN);
    {
        let ctx = ts::ctx(&mut scenario);
        init_rules_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, ctx);
        clock::set_for_testing(&mut clock, 1000 * 1000);

        add_primary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_secondary_price_update_rule<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_secondary_price_update_rule<SUI, SwitchboardRule>(&mut x_oracle, &x_oracle_policy_cap);

        let mut request_update_sui = price_update_request(&x_oracle);
        x_oracle::pyth_mock_adapter::update_price_as_primary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        x_oracle::supra_mock_adapter::update_price_as_secondary<SUI>(
            &mut request_update_sui,
            95 * std::u64::pow(10, x_oracle::price_feed::decimals()) / 10,
            1000,
        );
        x_oracle::switchboard_mock_adapter::update_price_as_secondary<SUI>(
            &mut request_update_sui,
            101 * std::u64::pow(10, x_oracle::price_feed::decimals()) / 10,
            1000,
        );
        // Price from pyth = $10
        // Price from supra = $9.5 // more than threshold 1%
        // Price from svb = $10.1
        confirm_price_update_request<SUI>(&mut x_oracle, request_update_sui, &clock);

        assert!(
            uq32_32::int_mul(1, x_oracle::test_utils::get_price<SUI>(&x_oracle, &clock)) == 10,
            0,
        ); // check if the price accruately updated
    };

    test_utils::destroy(clock);
    ts::return_to_address(ADMIN, x_oracle_policy_cap);
    ts::return_shared(x_oracle);
    ts::end(scenario);
}

#[
    test,
    expected_failure(
        abort_code = x_oracle::price_update_policy::REQUIRE_ALL_RULES_FOLLOWED,
        location = x_oracle::price_update_policy,
    ),
]
fun test_primary_with_multiple_secondary_rules_incomplete_error() {
    let mut scenario = ts::begin(ADMIN);
    let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_x_oracle(&mut scenario);

    scenario.next_tx(ADMIN);
    {
        let ctx = ts::ctx(&mut scenario);
        init_rules_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, ctx);
        clock::set_for_testing(&mut clock, 1000 * 1000);

        add_primary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_secondary_price_update_rule<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_secondary_price_update_rule<SUI, SwitchboardRule>(&mut x_oracle, &x_oracle_policy_cap);

        let mut request_update_sui = price_update_request(&x_oracle);
        x_oracle::pyth_mock_adapter::update_price_as_primary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        x_oracle::supra_mock_adapter::update_price_as_secondary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        confirm_price_update_request<SUI>(&mut x_oracle, request_update_sui, &clock);

        assert!(
            uq32_32::int_mul(1, x_oracle::test_utils::get_price<SUI>(&x_oracle, &clock)) == 10,
            0,
        ); // check if the price accruately updated
    };

    test_utils::destroy(clock);
    ts::return_to_address(ADMIN, x_oracle_policy_cap);
    ts::return_shared(x_oracle);
    ts::end(scenario);
}

#[test, expected_failure(abort_code = sui::vec_set::EKeyAlreadyExists, location = sui::vec_set)]
fun test_primary_with_multiple_secondary_rules_duplicate_error() {
    let mut scenario = ts::begin(ADMIN);
    let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_x_oracle(&mut scenario);

    scenario.next_tx(ADMIN);
    {
        let ctx = ts::ctx(&mut scenario);
        init_rules_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, ctx);
        clock::set_for_testing(&mut clock, 1000 * 1000);

        add_primary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_secondary_price_update_rule<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_secondary_price_update_rule<SUI, SwitchboardRule>(&mut x_oracle, &x_oracle_policy_cap);

        let mut request_update_sui = price_update_request(&x_oracle);
        x_oracle::pyth_mock_adapter::update_price_as_primary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        x_oracle::supra_mock_adapter::update_price_as_secondary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        x_oracle::supra_mock_adapter::update_price_as_secondary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        confirm_price_update_request<SUI>(&mut x_oracle, request_update_sui, &clock);

        assert!(
            uq32_32::int_mul(1, x_oracle::test_utils::get_price<SUI>(&x_oracle, &clock)) == 10,
            0,
        ); // check if the price accruately updated
    };

    test_utils::destroy(clock);
    ts::return_to_address(ADMIN, x_oracle_policy_cap);
    ts::return_shared(x_oracle);
    ts::end(scenario);
}

#[
    test,
    expected_failure(
        abort_code = x_oracle::x_oracle::PRIMARY_PRICE_NOT_QUALIFIED,
        location = x_oracle::x_oracle,
    ),
]
fun test_primary_with_multiple_secondary_with_all_high_price_gap_error() {
    let mut scenario = ts::begin(ADMIN);
    let (mut clock, mut x_oracle, x_oracle_policy_cap) = init_x_oracle(&mut scenario);

    scenario.next_tx(ADMIN);
    {
        let ctx = ts::ctx(&mut scenario);
        init_rules_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, ctx);
        clock::set_for_testing(&mut clock, 1000 * 1000);

        add_primary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_secondary_price_update_rule<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_secondary_price_update_rule<SUI, SwitchboardRule>(&mut x_oracle, &x_oracle_policy_cap);

        let mut request_update_sui = price_update_request(&x_oracle);
        x_oracle::pyth_mock_adapter::update_price_as_primary<SUI>(
            &mut request_update_sui,
            10 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );
        x_oracle::supra_mock_adapter::update_price_as_secondary<SUI>(
            &mut request_update_sui,
            95 * std::u64::pow(10, x_oracle::price_feed::decimals()) / 10,
            1000,
        );
        x_oracle::switchboard_mock_adapter::update_price_as_secondary<SUI>(
            &mut request_update_sui,
            11 * std::u64::pow(10, x_oracle::price_feed::decimals()),
            1000,
        );

        // Price from pyth = $10
        // Price from supra = $9.5 // more than threshold 1%
        // Price from svb = $11 // more than threshold 1%

        confirm_price_update_request<SUI>(&mut x_oracle, request_update_sui, &clock);

        assert!(
            uq32_32::int_mul(1, x_oracle::test_utils::get_price<SUI>(&x_oracle, &clock)) == 10,
            0,
        ); // check if the price accruately updated
    };

    test_utils::destroy(clock);
    ts::return_to_address(ADMIN, x_oracle_policy_cap);
    ts::return_shared(x_oracle);
    ts::end(scenario);
}

#[test]
fun test_add_and_remove_primary_price_update_rule() {
    let mut scenario = ts::begin(ADMIN);
    let (clock, mut x_oracle, x_oracle_policy_cap) = init_x_oracle(&mut scenario);

    scenario.next_tx(ADMIN);
    {
        add_primary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_primary_price_update_rule<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);

        let primary_price_update_rules = x_oracle.get_primary_price_update_policy<SUI>();

        assert_eq!(primary_price_update_rules.size(), 2);
        assert_eq!(primary_price_update_rules.contains(&get<PythRule>()), true);
        assert_eq!(primary_price_update_rules.contains(&get<SupraRule>()), true);
        assert_eq!(primary_price_update_rules.contains(&get<SwitchboardRule>()), false);
    };

    scenario.next_tx(ADMIN);
    {
        remove_primary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);

        let primary_price_update_rules = x_oracle.get_primary_price_update_policy<SUI>();

        assert_eq!(primary_price_update_rules.size(), 1);
        assert_eq!(primary_price_update_rules.contains(&get<PythRule>()), false);
        assert_eq!(primary_price_update_rules.contains(&get<SupraRule>()), true);
    };

    test_utils::destroy(clock);
    ts::return_shared(x_oracle);
    ts::return_to_address(ADMIN, x_oracle_policy_cap);
    ts::end(scenario);
}

#[test]
fun test_add_and_remove_secondary_price_update_rule() {
    let mut scenario = ts::begin(ADMIN);
    let (clock, mut x_oracle, x_oracle_policy_cap) = init_x_oracle(&mut scenario);

    scenario.next_tx(ADMIN);
    {
        add_secondary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);
        add_secondary_price_update_rule<SUI, SupraRule>(&mut x_oracle, &x_oracle_policy_cap);

        let secondary_price_update_rules = x_oracle.get_secondary_price_update_policy<SUI>();

        assert_eq!(secondary_price_update_rules.size(), 2);
        assert_eq!(secondary_price_update_rules.contains(&get<PythRule>()), true);
        assert_eq!(secondary_price_update_rules.contains(&get<SupraRule>()), true);
        assert_eq!(secondary_price_update_rules.contains(&get<SwitchboardRule>()), false);
    };

    scenario.next_tx(ADMIN);
    {
        remove_secondary_price_update_rule<SUI, PythRule>(&mut x_oracle, &x_oracle_policy_cap);

        let secondary_price_update_rules = x_oracle.get_secondary_price_update_policy<SUI>();

        assert_eq!(secondary_price_update_rules.size(), 1);
        assert_eq!(secondary_price_update_rules.contains(&get<PythRule>()), false);
        assert_eq!(secondary_price_update_rules.contains(&get<SupraRule>()), true);
    };

    test_utils::destroy(clock);
    ts::return_shared(x_oracle);
    ts::return_to_address(ADMIN, x_oracle_policy_cap);
    ts::end(scenario);
}
