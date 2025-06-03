module x_oracle::price_feed;

const PRICE_DECIMALS: u8 = 9;

public struct PriceFeed has copy, drop, store {
    value: u64,
    last_updated: u64,
}

public fun new(value: u64, last_updated: u64): PriceFeed {
    PriceFeed {
        value,
        last_updated,
    }
}

public fun value(feed: &PriceFeed): u64 {
    feed.value
}

public fun last_updated(feed: &PriceFeed): u64 {
    feed.last_updated
}

public fun decimals(): u8 {
    PRICE_DECIMALS
}

#[test_only]
public fun update_price_feed(feed: &mut PriceFeed, new_value: u64, new_last_updated: u64) {
    feed.value = new_value;
    feed.last_updated = new_last_updated;
}
