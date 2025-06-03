module x_oracle::price_update_policy;

use std::type_name::{Self, TypeName};
use sui::dynamic_field;
use sui::table::{Self, Table};
use sui::vec_set::{Self, VecSet};
use x_oracle::price_feed::PriceFeed;

const WRONG_POLICY_CAP: u64 = 723;

public struct PriceUpdateRequest<phantom T> {
    for_policy: ID,
    receipts: VecSet<TypeName>,
    price_feeds: vector<PriceFeed>,
}

public struct PriceUpdatePolicy has key, store {
    id: UID,
    rules: VecSet<TypeName>,
}

public struct PriceUpdatePolicyCap has key, store {
    id: UID,
    for_policy: ID,
}

public struct PriceUpdatePolicyRulesKey has copy, drop, store {}

public fun new(ctx: &mut TxContext): (PriceUpdatePolicy, PriceUpdatePolicyCap) {
    let policy = PriceUpdatePolicy {
        id: object::new(ctx),
        rules: vec_set::empty(),
    };

    let policy_cap = PriceUpdatePolicyCap {
        id: object::new(ctx),
        for_policy: object::id(&policy),
    };

    (policy, policy_cap)
}

public fun new_request<T>(policy: &PriceUpdatePolicy): PriceUpdateRequest<T> {
    PriceUpdateRequest {
        for_policy: object::id(policy),
        receipts: vec_set::empty(),
        price_feeds: vector::empty(),
    }
}

public(package) fun init_rules_if_not_exist(
    _policy_cap: &PriceUpdatePolicyCap,
    policy: &mut PriceUpdatePolicy,
    ctx: &mut TxContext,
) {
    if (
        !sui::dynamic_field::exists_<PriceUpdatePolicyRulesKey>(
            &policy.id,
            PriceUpdatePolicyRulesKey {},
        )
    ) {
        sui::dynamic_field::add<PriceUpdatePolicyRulesKey, Table<TypeName, VecSet<TypeName>>>(
            &mut policy.id,
            PriceUpdatePolicyRulesKey {},
            sui::table::new(ctx),
        );
    }
}

public(package) fun add_rule<CoinType, Rule>(
    policy: &mut PriceUpdatePolicy,
    policy_cap: &PriceUpdatePolicyCap,
) {
    assert!(object::id(policy) == policy_cap.for_policy, WRONG_POLICY_CAP);

    let rules_table = dynamic_field::borrow_mut<
        PriceUpdatePolicyRulesKey,
        Table<TypeName, VecSet<TypeName>>,
    >(
        &mut policy.id,
        PriceUpdatePolicyRulesKey {},
    );

    let coin_type = type_name::get<CoinType>();

    if (!table::contains(rules_table, coin_type)) {
        table::add(rules_table, coin_type, vec_set::empty());
    };

    let rules = table::borrow_mut(rules_table, coin_type);

    vec_set::insert(rules, type_name::get<Rule>());
}

public fun remove_rule<Rule>(policy: &mut PriceUpdatePolicy, cap: &PriceUpdatePolicyCap) {
    assert!(object::id(policy) == cap.for_policy, WRONG_POLICY_CAP);
    vec_set::remove<TypeName>(&mut policy.rules, &type_name::get<Rule>());
}
