module x_oracle::x_oracle;

use std::type_name::TypeName;
use sui::package;
use sui::table::Table;
use x_oracle::price_feed::PriceFeed;
use x_oracle::price_update_policy::{Self, PriceUpdatePolicy, PriceUpdatePolicyCap, PriceUpdateRequest};

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

public struct XOraclePriceUpdateRequest<phantom T> {
    primary_price_update_request: PriceUpdateRequest<T>,
    secondary_price_update_request: PriceUpdateRequest<T>
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

public fun add_primary_price_update_rule<CoinType, Rule: drop>(self: &mut XOracle, cap: &XOraclePolicyCap) {
    price_update_policy::add_rule(&mut self.primary_price_update_policy, &cap.primary_price_update_policy_cap);
}

public fun remove_primary_price_update_rule<Rule: drop>(self: &mut XOracle, cap: &XOraclePolicyCap) {
    price_update_policy::remove_rule<Rule>(&mut self.primary_price_update_policy, &cap.primary_price_update_policy_cap);
}


