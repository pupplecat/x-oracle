module switchboard_rule::switchboard_registry;

use std::type_name::{Self, TypeName};
use sui::table::{Self, Table};
use switchboard_std::aggregator::Aggregator;

const ERR_ILLEGAL_SWITCHBOARD_AGGREGATOR: u64 = 0x11405;
const ERR_ILLEGAL_REGISTRY_CAP: u64 = 0x11406;

public struct SwitchboardRegistry has key {
    id: UID,
    table: Table<TypeName, ID>,
}
public struct SwitchboardRegistryCap has key, store {
    id: UID,
    for_registry: ID,
}

fun init(ctx: &mut TxContext) {
    let switchboard_registry = SwitchboardRegistry {
        id: object::new(ctx),
        table: table::new(ctx),
    };
    let switchboard_registry_cap = SwitchboardRegistryCap {
        id: object::new(ctx),
        for_registry: object::id(&switchboard_registry),
    };
    transfer::share_object(switchboard_registry);
    transfer::transfer(switchboard_registry_cap, tx_context::sender(ctx));
}

public entry fun register_switchboard_aggregator<CoinType>(
    switchboard_registry: &mut SwitchboardRegistry,
    switchboard_registry_cap: &SwitchboardRegistryCap,
    switchboard_aggregator: &Aggregator,
) {
    assert!(
        object::id(switchboard_registry) == switchboard_registry_cap.for_registry,
        ERR_ILLEGAL_REGISTRY_CAP,
    );
    let coin_type = type_name::get<CoinType>();
    if (table::contains(&switchboard_registry.table, coin_type)) {
        table::remove<TypeName, ID>(&mut switchboard_registry.table, coin_type);
    };
    table::add(&mut switchboard_registry.table, coin_type, object::id(switchboard_aggregator));
}

public fun assert_switchboard_aggregator<CoinType>(
    switchboard_registry: &SwitchboardRegistry,
    switchboard_aggregator: &Aggregator,
) {
    let coin_type = type_name::get<CoinType>();
    let coin_aggregator_id = table::borrow(&switchboard_registry.table, coin_type);
    assert!(
        object::id(switchboard_aggregator) == *coin_aggregator_id,
        ERR_ILLEGAL_SWITCHBOARD_AGGREGATOR,
    );
}
