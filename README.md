## Paymaster Pools

Introduction:

To use any EVM blockchain, users must pay their transaction costs (weighted in gas) in native currency, such as Ether.
This has been acknowledged for a long time by the community as a major pain in user experience and a significant blocker for blockchain
adoption, where non-experienced users may receive cryptocurrency in their account and be unable to do anything with it due to the 
lack of native currency. 

This has led to extensive research and innovation which has produced several ERCs and EIPs aiming to solve this issue, 
achieving the name "gas abstraction", which belongs as a sub-topic of the broader "Account Abstraction" niche. 

Core requirements for gas abstraction:

- **Universal token support**: Users should be able to pay gas with any token
- **Zero downtime availability**: Users cannot operate during outages, requiring permanently available, censorship-resistant infrastructure - properties of decentralized systems
- **Minimal pricing and costs overheads**: Minimal fees and costs to maintain the system functional

Among various approaches, ERC-4337 has emerged as the leading solution due to its unique advantage: enabling gas abstraction without requiring Ethereum core protocol changes.

While ERC-4337 provides an elegant off-protocol architecture for alternative gas payment methods, current paymaster implementations remain centralized and, frankly, immature. 

### Current Paymaster landscape

Today's ERC-4337 ERC-20 paymasters suffer from fundamental centralization issues:

- **Ecosystem dominated by few players**: Most users rely on a single provider, and outages make the entire gas sponsoring system unavailable with no built-in aggregation to switch providers
- **Operational overhead**: Manual rebalancing required at all times with large operational costs, where any rebalancing downtime causes transaction sponsoring downtime
- **Single capital provider**: A centralized paymaster owner provides all ETH for user operations, creating strict scalability limits constrained to what the owner can provide
- **Monopolistic pricing**: The centralized paymaster owner captures 100% of service fees and solely decides pricing without strong competition because of the high bar to enter the gas sponsoring market, similar to CEX fees before Uniswap enabled market-driven fee discovery
- **Limited token support**: Token selection based solely on owner capacity and profitability - users are at the mercy of provider decisions
- **Poor user experience**: Users must manually switch between providers (Pimlico, Alchemy, Biconomy) for different tokens, similar to pre-DEX aggregator swapping
- **Liquidity fragmentation**: Competing players create separate paymasters, fragmenting liquidity and decreasing capital efficiency
- **Concentrated volatility risk**: The owner bears all price risk from both ETH (gas payments) and accepted tokens (fees), with no risk distribution mechanism, forcing higher fees to cover risks and making the model unsustainable during market volatility

---

### A potentially decentralized alternative: Paymaster Pools

To drive meaningful improvement, a decentralized paymaster should:

#### **1. Permissionless Liquidity Provision**
Allow anyone to become a sponsoring liquidity provider of any size, removing the high bar to enter the gas sponsoring market.

#### **2. Distributed Profit Sharing**
Distribute the sponsoring profits proportionally across all liquidity providers.

#### **3. Free-Market Price Discovery**
Allow creation of different paymaster pools with any sponsoring fee, enabling the market to discover the right sponsoring fee, inspired by the Uniswap model.

#### **4. Unified Paymaster Router**
Offer a PaymasterRouter (Singleton) that indicates which paymaster offers the lowest sponsoring fee at any moment while having sufficient liquidity, dramatically simplifying UX.

#### **5. Censorship-Resistant**
Paymaster Pools are immutable contracts where anyone can provide liquidity, creating a strong and decentralized resistant system.

#### **6. Increased Liquidity Yields**
Since Paymaster Pools are Uniswap V4 liquidity pools underneath, swaps remain available, increasing capital utility as the same provided liquidity can be used simultaneously for swapping and gas sponsoring, potentially increasing passive yield in [ETH, TOKEN] pairs. This is achieved through ongoing development of liquidity rehypothecation, where ETH is locked at the ERC-4337 EntryPoint but moved into Uniswap's Pool Manager just-in-time when swaps happen, virtually allowing ETH liquidity to sponsor transactions while being fully available in the pool for swaps.

#### **7. Autonomous Rebalancing**
Since Paymaster Pools are Uniswap V4 Pools underneath, the chosen rebalancing mechanism is permissionless swaps, allowing anyone to capture imbalances as arbitrage opportunities. Naturally, since gas sponsoring decreases ETH balances and increases token balances with included fees, there is constant pressure in the zeroForOne direction (ETH to Token), and these imbalances can be captured by anyone. Note that LPs earn fees on both sponsoring and rebalancing transactions (as rebalancing pays pool fees to LPs).
---

*Building the infrastructure for truly decentralized gas abstraction on Ethereum.*
