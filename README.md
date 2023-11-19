# Aggregator Hook

The project aims to create a system that accurately maps the positions of liquidity providers on various DEX platforms to Uniswap V4 ticks. This involves a few key steps and components:

- Position Mapping: The core functionality is to translate or map the LP positions from different DEXs onto Uniswap’s infrastructure. This means converting the LP’s stake in one DEX’s pool into an equivalent position in a Uniswap V4 pool.
- Tick Alignment: Since Uniswap V4 utilizes a tick-based system for its liquidity pools, the project must align the LP's position to specific ticks within Uniswap. This alignment would ensure that the LP's assets are correctly priced and positioned for trading on Uniswap.
- Integration and Interoperability: The project would require integration mechanisms with various DEXs to access and interpret LP data. This could involve smart contract development, APIs, and cross-chain communication protocols, ensuring that the system is compatible with different blockchain architectures and DEX platforms.
- Liquidity Optimization: By mapping LP positions to Uniswap V4, liquidity can be optimized across platforms. This could potentially reduce slippage (the difference between expected and executed price of trades), provide better price discovery, and enhance overall market efficiency.
- Smart Contract Automation: The process would likely rely on smart contracts to automate the mapping and management of LP positions. These contracts would handle the conversion and alignment of positions, adhering to the rules and structures of both the originating DEX and Uniswap V4.


## Repository Structure

```solidity
contracts/
----hooks/
    ----examples/
        | GeomeanOracle.sol
        | LimitOrder.sol
        | TWAMM.sol
        | VolatilityOracle.sol
        | Aggregator.sol
----libraries/
    | Oracle.sol
BaseHook.sol
test/
```

To showcase the power of hooks, this repository provides some interesting examples in the `/hooks/examples/` folder. Note that none of the contracts in this repository are fully production-ready, and the final design for some of the example hooks could look different.

Eventually, some hooks that have been audited and are considered production-ready will be placed in the root `hooks` folder. Not all hooks will be safe or valuable to users. This repository will maintain a limited set of hook contracts. Even a well-designed and audited hook contract may not be accepted in this repo.

## Local Deployment and Usage

To utilize the contracts and deploy to a local testnet, you can install the code in your repo with forge:

```solidity
forge install https://github.com/Uniswap/periphery-next
```

Run test of AggregatorHook, we try to swap token0 to token1 twice and make no price difference.

```solidity
forge test --match-test testHook_SwapSecondTime
```

## License

The license for Uniswap V4 Periphery is the GNU General Public License (GPL 2.0), see [LICENSE](https://github.com/Uniswap/periphery-next/blob/main/LICENSE).
