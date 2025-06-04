# XOracle: A Composable Price Oracle for the Sui Blockchain

XOracle is a price oracle aggregator built on the Sui blockchain. It is designed to provide reliable and robust price feeds by integrating multiple oracle protocols, including Pyth, Supra, and Switchboard. The project leverages a "Hot Potato" design pattern for its core logic, inspired by the [Scallop Sui Lending Protocol](https://github.com/scallop-io/sui-lending-protocol).

## Key Features

* **Multiple Oracle Support**: Integrates with Pyth, Supra, and Switchboard oracles to provide diverse and resilient price data.
* **Composable Design**: Easily extendable to support additional oracle providers.
* **Hot Potato Pattern**: Utilizes a state-passing pattern where a central `PriceUpdateRequest` object is passed around and mutated by different oracle adapter rules. This allows for flexible and atomic updates.
* **Rule-Based Price Validation**: Implements a policy where primary and secondary oracle sources can be configured to validate price data, enhancing data integrity.
* **On-Chain Price Feeds**: Stores and serves aggregated price data directly on the Sui blockchain.

## Design Pattern: Hot Potato

The XOracle system employs a "Hot Potato" pattern for managing price update requests. Here's how it works:

1. **Initiation**: A price update process begins by creating a `PriceUpdateRequest` object. This object acts as the "hot potato."
2. **Rule-Based Processing**: The `PriceUpdateRequest` is then passed sequentially through a series of defined oracle adapter rules (e.g., PythRule, SupraRule). Each rule corresponds to an integrated oracle protocol.
3. **Data Enrichment & Validation**: Each adapter rule interacts with its respective oracle (via contracts in the `vendor` directory) to fetch the latest price data. It then enriches the `PriceUpdateRequest` with this data. Rules can also perform validation checks (e.g., comparing against other sources, checking timestamps).
4. **Confirmation**: Once the `PriceUpdateRequest` has been processed by all relevant rules according to the configured policy (e.g., primary source + a minimum number of secondary sources agreeing within a certain tolerance), the price update is confirmed and the new price is stored in the `PriceFeed` table within the XOracle.

This pattern allows for:

* **Atomicity**: Price updates are atomic operations. If any step in the rule chain fails or a policy condition is not met, the entire update can be reverted.
* **Flexibility**: New oracle providers (and their corresponding rules) can be added or removed with minimal changes to the core logic.
* **Clarity**: The flow of data and control is explicit, making the system easier to understand and audit.

## Project Structure

The project is organized into several key modules:

* `contracts/x_oracle/`: Contains the core XOracle logic.
  * `sources/x_oracle.move`: The main contract implementing the XOracle, price feed storage, and the Hot Potato pattern orchestration.
  * `sources/price_feed.move`: Defines the structure for storing price data.
  * `sources/price_update_policy.move`: Manages the rules and policies for validating price updates (e.g., which oracles are primary/secondary, deviation thresholds).
  * `tests/`: Contains integration and unit tests for the XOracle.
    * `test_utils.move`: Utility functions for testing.
    * `x_oracle_test.move`: Test scenarios for various XOracle functionalities.
    * `mock_adapter/`: Mock adapters for testing oracle integrations.

* `contracts/pyth_rule/`: Adapter for the Pyth Network oracle.
  * `sources/rule.move`: Implements the Pyth-specific logic for the Hot Potato pattern.
  * `sources/pyth_adaptor.move`: Interacts with the Pyth oracle contracts.
  * `vendors/pyth/`: Contains the actual Pyth oracle Move contracts.

* `contracts/supra_rule/`: Adapter for the SupraOracles.
  * `sources/rule.move`: Implements the Supra-specific logic.
  * `sources/supra_adaptor.move`: Interacts with the SupraOracles contracts.
  * `vendors/supra_oracle/`: Contains the actual SupraOracles Move contracts.

* `contracts/switchboard_rule/`: Adapter for the Switchboard oracle.
  * `sources/rule.move`: Implements the Switchboard-specific logic.
  * `sources/switchboard_adaptor.move`: Interacts with the Switchboard oracle contracts.
  * `vendors/switchboard_std/`: Contains the actual Switchboard Move contracts.

## Building and Testing

```bash
sui move build --path contracts/x_oracle
sui move test --path contracts/x_oracle
```

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.
