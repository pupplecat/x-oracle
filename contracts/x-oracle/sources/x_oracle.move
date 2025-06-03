module x_oracle::x_oracle;

use std::type_name::{TypeName, get};
use sui::clock::{Self, Clock};
use sui::package;
use sui::table::{Self, Table};
use x_oracle::price_feed::{Self, PriceFeed};
use x_oracle::price_update_policy::{
    Self,
    PriceUpdatePolicy,
    PriceUpdatePolicyCap,
    PriceUpdateRequest
};
use sui::vec_set::VecSet;

const PRIMARY_PRICE_NOT_QUALIFIED: u64 = 720;
const ONLY_SUPPORT_ONE_PRIMARY: u64 = 721;

public struct X_ORACLE has drop {}

public struct XOracle has key {
    id: UID,
    primary_price_update_policy: PriceUpdatePolicy,
    secondary_price_update_policy: PriceUpdatePolicy,
    prices: Table<TypeName, PriceFeed>,
    ema_prices: Table<TypeName, PriceFeed>,
}

public struct XOraclePolicyCap has key, store {
    id: UID,
    primary_price_update_policy_cap: PriceUpdatePolicyCap,
    secondary_price_update_policy_cap: PriceUpdatePolicyCap,
}

public struct XOraclePriceUpdateRequest<phantom CoinType> {
    primary_price_update_request: PriceUpdateRequest<CoinType>,
    secondary_price_update_request: PriceUpdateRequest<CoinType>,
}

fun init(otw: X_ORACLE, ctx: &mut TxContext) {
    let (mut x_oracle, x_oracle_policy_cap) = new(ctx);

    init_rules_if_not_exist(&x_oracle_policy_cap, &mut x_oracle, ctx);

    transfer::share_object(x_oracle);
    transfer::transfer(x_oracle_policy_cap, tx_context::sender(ctx));

    package::claim_and_keep(otw, ctx);
}

fun new(ctx: &mut TxContext): (XOracle, XOraclePolicyCap) {
    let (primary_price_update_policy, primary_price_update_policy_cap) = price_update_policy::new(
        ctx,
    );
    let (
        secondary_price_update_policy,
        secondary_price_update_policy_cap,
    ) = price_update_policy::new(ctx);

    let x_oracle = XOracle {
        id: object::new(ctx),
        primary_price_update_policy,
        secondary_price_update_policy,
        prices: sui::table::new(ctx),
        ema_prices: sui::table::new(ctx),
    };
    let x_oracle_update_policy = XOraclePolicyCap {
        id: object::new(ctx),
        primary_price_update_policy_cap,
        secondary_price_update_policy_cap,
    };

    (x_oracle, x_oracle_update_policy)
}

public fun prices(self: &XOracle): &Table<TypeName, PriceFeed> { &self.prices }

public fun init_rules_if_not_exist(
    policy_cap: &XOraclePolicyCap,
    x_oracle: &mut XOracle,
    ctx: &mut TxContext,
) {
    price_update_policy::init_rules_if_not_exist(
        &policy_cap.primary_price_update_policy_cap,
        &mut x_oracle.primary_price_update_policy,
        ctx,
    );
    price_update_policy::init_rules_if_not_exist(
        &policy_cap.secondary_price_update_policy_cap,
        &mut x_oracle.secondary_price_update_policy,
        ctx,
    );
}

public fun add_primary_price_update_rule<CoinType, Rule: drop>(
    self: &mut XOracle,
    cap: &XOraclePolicyCap,
) {
    price_update_policy::add_rule<CoinType, Rule>(
        &mut self.primary_price_update_policy,
        &cap.primary_price_update_policy_cap,
    );
}

public fun remove_primary_price_update_rule<CoinType, Rule: drop>(
    self: &mut XOracle,
    cap: &XOraclePolicyCap,
) {
    price_update_policy::remove_rule<CoinType, Rule>(
        &mut self.primary_price_update_policy,
        &cap.primary_price_update_policy_cap,
    );
}

public fun add_secondary_price_update_rule<CoinType, Rule: drop>(
    self: &mut XOracle,
    cap: &XOraclePolicyCap,
) {
    price_update_policy::add_rule<CoinType, Rule>(
        &mut self.secondary_price_update_policy,
        &cap.secondary_price_update_policy_cap,
    );
}

public fun remove_secondary_price_update_rule<CoinType, Rule: drop>(
    self: &mut XOracle,
    cap: &XOraclePolicyCap,
) {
    price_update_policy::remove_rule<CoinType, Rule>(
        &mut self.secondary_price_update_policy,
        &cap.secondary_price_update_policy_cap,
    );
}

public fun price_update_request<CoinType>(self: &XOracle): XOraclePriceUpdateRequest<CoinType> {
    let primary_price_update_request = price_update_policy::new_request<CoinType>(
        &self.primary_price_update_policy,
    );
    let secondary_price_update_request = price_update_policy::new_request<CoinType>(
        &self.secondary_price_update_policy,
    );
    XOraclePriceUpdateRequest {
        primary_price_update_request,
        secondary_price_update_request,
    }
}

public fun set_primary_price<CoinType, Rule: drop>(
    rule: Rule,
    request: &mut XOraclePriceUpdateRequest<CoinType>,
    price_feed: PriceFeed,
) {
    price_update_policy::add_price_feed(
        rule,
        &mut request.primary_price_update_request,
        price_feed,
    );
}

public fun set_secondary_price<CoinType, Rule: drop>(
    rule: Rule,
    request: &mut XOraclePriceUpdateRequest<CoinType>,
    price_feed: PriceFeed,
) {
    price_update_policy::add_price_feed(
        rule,
        &mut request.secondary_price_update_request,
        price_feed,
    );
}

public fun confirm_price_update_request<CoinType>(
    self: &mut XOracle,
    request: XOraclePriceUpdateRequest<CoinType>,
    clock: &Clock,
) {
    let XOraclePriceUpdateRequest { primary_price_update_request, secondary_price_update_request } =
        request;

    let mut  primary_price_feeds = price_update_policy::confirm_request(
        primary_price_update_request,
        &self.primary_price_update_policy,
    );

    let mut secondary_price_feeds = price_update_policy::confirm_request(
        secondary_price_update_request,
        &self.secondary_price_update_policy,
    );

    let coin_type = get<CoinType>();
    if (!table::contains(&self.prices, coin_type)) {
        table::add(&mut self.prices, coin_type, price_feed::new(0, 0));
    };
    let price_feed = determine_price(&mut primary_price_feeds, &mut secondary_price_feeds);

    let current_price_feed = table::borrow_mut(&mut self.prices, get<CoinType>());

    let now = clock::timestamp_ms(clock) / 1000;
    let new_price_feed = price_feed::new(
        price_feed::value(&price_feed),
        now,
    );
    *current_price_feed = new_price_feed;
}

fun determine_price(
    primary_price_feeds: &mut vector<PriceFeed>,
    secondary_price_feeds: &mut vector<PriceFeed>,
): PriceFeed {
    // current we only support one primary price feed
    assert!(primary_price_feeds.length() == 1, ONLY_SUPPORT_ONE_PRIMARY);
    let primary_price_feed = vector::pop_back( primary_price_feeds);
    let secondary_price_feed_num = vector::length(secondary_price_feeds);

    // We require the primary price feed to be confirmed by at least half of the secondary price feeds
    let required_secondary_match_num = (secondary_price_feed_num + 1) / 2;
    let mut matched: u64 = 0;
    let mut i = 0;
    while (i < secondary_price_feed_num) {
        let secondary_price_feed = vector::pop_back( secondary_price_feeds);
        if (price_feed_match(primary_price_feed, secondary_price_feed)) {
            matched = matched + 1;
        };
        i = i + 1;
    };
    assert!(matched >= required_secondary_match_num, PRIMARY_PRICE_NOT_QUALIFIED);

    // Use the primary price feed as the final price feed
    primary_price_feed
}

// Check if two price feeds are within a reasonable range
// If price_feed1 is within 1% away from price_feed2, then they are considered to be matched
fun price_feed_match(price_feed1: PriceFeed, price_feed2: PriceFeed): bool {
    let value1 = price_feed::value(&price_feed1);
    let value2 = price_feed::value(&price_feed2);

    let scale = 1000;
    let reasonable_diff_percent = 1;
    let reasonable_diff = reasonable_diff_percent * scale / 100;
    let diff = value1 * scale / value2;
    diff <= scale + reasonable_diff && diff >= scale - reasonable_diff
}

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init( X_ORACLE {}, ctx)
}

#[test_only]
public fun get_primary_price_update_policy<CoinType>(self: &mut XOracle): VecSet<TypeName> {
    self.primary_price_update_policy.get_price_update_policy<CoinType>()
}

#[test_only]
public fun get_secondary_price_update_policy<CoinType>(self: &mut XOracle): VecSet<TypeName> {
    self.secondary_price_update_policy.get_price_update_policy<CoinType>()
}