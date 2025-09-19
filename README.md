### Introduction:

In order to be able to use any EVM blockchain, users must pay their transaction costs in native currency, such as Ether.
This has been already acknowledged by the community for a long time as a major pain in the user experience and as a significant blocker for mass
adoption, where newly onboarded users may eventually receive cryptocurrency but kept blocked from doing anything with it due to the 
lack of native currency to pay for the gas, which may be really frustrating.

This led to extensive research and innovation which has produced several ERCs and EIPs aiming to solve this issue, 
eventually giving birth to the concept of "**_Gas Abstraction_**", as a sub-topic of the broader "**_Account Abstraction_**" space.

Among various approaches, ERC-4337 has emerged as the current leading solution due to its unique advantage: enabling gas abstraction without requiring Ethereum core protocol changes. However, while ERC-4337 provides an elegant off-protocol architecture for alternative gas payment methods, most current paymaster implementations remain centralized and immature. 

##### Requirements for useful gas abstraction:

- **Universal token support**: Users should be able to pay gas with any token
- **Zero downtime availability**: permanently available, censorship-resistant infrastructure is a must, since users cannot be sponsored during downtimes
- **Minimal cost overhead**: costs should be extremely low to make the system feasible and acceptable.



### Current Paymaster landscape

Today's Paymasters suffer from fundamental centralization issues with strong consequences:

- **Ecosystem dominated by few players**: Most users rely on a single provider, and outages blocks users from using their funds with no built-in aggregation to switch providers.
- **Limited token support**: Token selection based solely on paymaster owner capacity and profitability - users are at the mercy of provider decisions.
- **Poor user experience**: Users must manually switch between providers (Pimlico, Alchemy, Biconomy) for different tokens, similar to pre-DEX aggregator swapping.
- **Monopolistic pricing, large players win it all**: The centralized paymaster owner captures 100% of service fees and solely decides pricing without sane competition because of the high bar to enter the gas sponsoring market, similar to CEX fees before Uniswap enabled market-driven fee discovery.
- **Operational overhead**: Centralized Paymasters relies on manual or partially automated rebalancing required at all times with large operational costs, where any rebalancing downtime causes a denial of service for the users and apps that rely on them.


_Did you know that centralized paymasters today charge between 5% and 100%?, based on a quick search, ZeroDev, Circle, and Pimlico Paymasters charge between 5-10%?, while another less competent services charge up to 100%_

---

# A decentralized alternative: Uniswap Paymaster + Paymaster Pools

a decentralized paymaster infraestructure is proposed instead, aiming to enhance the landscape in the following manners:

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
- **Just-in-time liquidity**: Uses the pool's existing liquidity to perform token→ETH swaps during UserOperation validation
- **Permit2 integration**: Enables gasless approvals, allowing EOAs without native currency to pre-pay for sponsorship
- **EntryPoint deposit management**: Automatically manages ETH deposits in the ERC-4337 EntryPoint for UserOperation prefunding

### Technical Flow
1. User signs Permit2 allowance for token spending
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

*Building the infrastructure for truly decentralized gas abstraction on Ethereum.*
