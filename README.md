### Introduction:

To use any EVM blockchain, users must pay their transaction costs (weighted in gas) in native currency, such as Ether.
This has been already acknowledged for a long time by the community as a major pain in user experience and a significant blocker for mass blockchain
adoption, where non-experienced users may eventually receive cryptocurrency in their account and be unable to do anything with it due to the 
lack of native currency to operate, which is a really frustrating.

This led to extensive research and innovation which has produced several ERCs and EIPs aiming to solve this issue, 
eventually deriving in the name of "**_Gas Abstraction_**", belonging as a sub-topic of the broader "**_Account Abstraction_**" space.

Among various approaches, ERC-4337 has emerged as the leading solution due to its unique advantage: enabling gas abstraction without requiring Ethereum core protocol changes. While ERC-4337 provides an elegant off-protocol architecture for alternative gas payment methods, current paymaster implementations remain centralized and, frankly, immature. 

##### Core requirements for gas abstraction:

- **Universal token support**: Users should be able to pay gas with any token
- **Zero downtime availability**: Users cannot operate during outages, requiring permanently available, censorship-resistant infrastructure
- **Minimal pricing and costs overheads**: Gas sponsoring costs should be extremely low to make the system usable.



### Current Paymaster landscape

Today's Paymasters suffer from fundamental centralization issues with strong consequences:

- **Ecosystem dominated by few players**: Most users rely on a single provider, and outages blocks users from using their funds with no built-in aggregation to switch providers
- **Limited token support**: Token selection based solely on paymaster owner capacity and profitability - users are at the mercy of provider decisions
- **Poor user experience**: Users must manually switch between providers (Pimlico, Alchemy, Biconomy) for different tokens, similar to pre-DEX aggregator swapping
- **Monopolistic pricing, large players win it all**: The centralized paymaster owner captures 100% of service fees and solely decides pricing without sane competition because of the high bar to enter the gas sponsoring market, similar to CEX fees before Uniswap enabled market-driven fee discovery
- **Operational overhead**: Centralized Paymasters relies on manual or partially automated rebalancing required at all times with large operational costs, where any rebalancing downtime causes transaction sponsoring downtime
- **Single capital provider**: A centralized paymaster owner provides all ETH for user operations, creating strict scalability limits constrained to what the owner can provide
- **Liquidity fragmentation**: Competing players create separate paymasters, fragmenting liquidity and decreasing capital efficiency
- **Concentrated volatility risk**: The owner bears all price risk from both ETH (gas payments) and accepted tokens (fees), with no risk distribution mechanism, forcing higher fees to cover risks and making the model unsustainable during market volatility

---

### A decentralized alternative: Paymaster Pools

To drive meaningful improvement, a decentralized paymaster infraestructure is proposed instead, aiming to enhance the landscape in the following manners:

#### **1. Permissionless Liquidity Provision**
Allows anyone to become a sponsoring liquidity provider of any size, removing the high bar to enter the gas sponsoring market.

#### **2. Distributed Profit Sharing**
Distributes the sponsoring profits proportionally across all liquidity providers.

#### **3. Free-Market Price Discovery**
Allows creation of different paymaster pools with any determined sponsoring fee configuration, enabling the market to discover the right sponsoring fee, inspired by the Uniswap model for swaps.

#### **4. Unified Paymaster Router**
Offer a PaymasterRouter (Singleton) that simply indicates which paymaster offers the lowest sponsoring fee at any moment for a given token while having sufficient liquidity, dramatically simplifying UX.

#### **5. Censorship-Resistant**
Paymaster Pools are immutable contracts where anyone can provide liquidity and exit at all times, creating a strong and decentralized resistant system.

#### **6. Increased Liquidity Yields**
Since Paymaster Pools are Uniswap V4 liquidity pools underneath, swaps between supported tokens and ether remains functional, novely increasing **capital utility **, as the provided liquidity can be simultaneously used for swapping **and** for gas sponsoring, potentially increasing LP's profits in [ETH, TOKEN] pairs in comparision with traditional Uniswap Pools that only make profits for LPs from swaps. This is achieved through an ongoing development effort of "liquidity rehypothecation", where ETH is locked in the ERC-4337 EntryPoint but moved into Uniswap's Pool Manager just-in-time when swaps happen (similar to Flash loans), virtually allowing ETH liquidity to sponsor transactions and serve as swap liquidity at the same time, making profits from both with the same capital.

#### **7. Autonomous Rebalancing**
Since Paymaster Pools are Uniswap V4 Pools underneath, the chosen rebalancing mechanism is permissionless swaps, allowing anyone to capture imbalances as arbitrage opportunities. Naturally, since gas sponsoring decreases ETH balances and increases token balances with included fees, there is constant pressure in the zeroForOne direction (ETH to Token), and these imbalances can be captured by anyone to make a profit, similar to how MakerDAO allows anyone to liquidate positions and make a profit by regulating the system. (Note that LPs earn fees on both sponsoring and rebalancing transactions, as rebalancing swaps also pays fees to LPs!)

---

*Building the infrastructure for truly decentralized gas abstraction on Ethereum.*
