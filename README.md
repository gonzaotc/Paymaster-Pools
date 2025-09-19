### Introduction:

In order to use an EVM blockchain, users must pay transaction costs in native currency (Ether), creating a significant UX barrier for mass adoption. New users receiving cryptocurrency often find themselves unable to transact their just obtained shiny tokens due to lack of native currency for gas fees.

This led to extensive research, eventually giving birth to "Gas Abstraction" - enabling alternative payment methods for transaction fees. ERC-4337 has emerged as the leading solution, providing gas abstraction without requiring Ethereum protocol changes. However, current paymaster implementations remain centralized, creating new bottlenecks.

#### Requirements for the next-gen gas abstraction:

- **Universal token support**: Users should be able to pay gas with any token
- **Zero downtime availability**: permanently available, censorship-resistant infrastructure is a must, since relying users experience a denial of service during downtimes.
- **Minimal cost overhead**: costs should be strictly low to make the system feasible and acceptable.



### Current Paymaster landscape

Today's Paymasters suffer from fundamental centralization issues and the consequences from their design:

- **Limited competition**: Most users rely on a single provider, and outages block users from using their funds with no built-in aggregation to switch providers.
- **Restricted token support**: Token selection based solely on paymaster owner capacity and profitability - users are at the mercy of provider decisions.
- **Poor user experience**: Users must manually switch between providers (Pimlico, Alchemy, Biconomy) for different tokens, similar to pre-DEX aggregator swapping.
- **Monopolistic pricing**: Centralized paymaster owners capture 100% of service fees and solely decide pricing without competition due to the high barrier to enter the gas sponsoring market, similar to CEX fees before Uniswap enabled market-driven fee discovery.
- **Operational overhead**: Centralized paymasters rely on manual or partially automated rebalancing with large operational costs, where any rebalancing downtime causes denial of service for users and apps that depend on them.


---

# A permissionless alternative: Uniswap Paymaster + Paymaster Pools

A different paymster design is proposed instead, aiming to enhance the landscape in the following manners:

#### **1. Permissionless Liquidity Provision**
Allows anyone to become a sponsoring liquidity provider of any size, removing the high bar to enter the gas sponsoring market.
At the same time, The Uniswap Paymaster and the Paymaster Pools are immutable ungoverned pieces of code, and users can exit at all times.

#### **2. Distributed Profit Sharing**
Distributes the sponsoring profits proportionally across all liquidity providers.

#### **3. Free-Market Price Discovery**
Allows the creation of paymaster pools with different fee configurations, enabling the market to discover the right sponsoring fee.

#### **4. Enhanced Yields thanks to increased capital efficiency** 
By making use of Paymaster Pools, the capital from liquidity providers can provide more utility to the market; 
it is not only being used for swaps, it also serves for anyone looking to pay for a transaction in a particular token.

### Components

## Uniswap Paymaster
An ERC-4337 compliant Paymaster that leverages existing Uniswap V4 pools to enable gasless transactions paid in any ERC-20 token.

### Core Mechanism
- **Permissionless**: Works with any existing [ETH, Token] Uniswap V4 pool without requiring pool modifications
- **Just-in-time swaps**: Uses the pool's existing liquidity to perform token→ETH swaps during UserOperation validation
- **Permit2 integration**: Enables gasless approvals, allowing EOAs without native currency to pre-pay for sponsorship
- **EntryPoint deposit management**: Automatically manages ETH deposits in the ERC-4337 EntryPoint for UserOperation prefunding

### Technical Flow
1. User signs [Permit2](https://docs.uniswap.org/contracts/permit2/overview) allowance for token spending
2. Paymaster validates UserOperation and executes token→ETH swap via pool callback
3. ETH is used to prefund the EntryPoint for UserOperation execution
4. Excess ETH is refunded to user post-execution

## Paymaster Pool (Existing Uniswap Pools)
Any Uniswap V4 pool with [ETH, Token] pair automatically becomes a Paymaster Pool without modification.

### Economic Benefits
- **Increased capital utility**: LP tokens serve dual purpose - trading liquidity + transaction sponsorship
- **Competitive fee discovery**: Pool fees determine sponsorship costs, creating market-driven pricing
- **No additional infrastructure**: Leverages existing Uniswap infrastructure and liquidity

## Paymaster Pool Hooks (Optional)
- **AsymmetricFeeHook**: Reduces swap fees in the token→ETH direction to minimize transaction costs for users
- **Custom hooks**: Developers can create specialized hooks for specific paymaster pool behaviors

## Paymaster Pool Aggregator (WIP)
Off-chain service that finds the lowest-cost Paymaster Pool for a given token, enabling optimal routing for users.


---

*Building the infrastructure for the next gen decentralized gas abstraction on Ethereum.*
