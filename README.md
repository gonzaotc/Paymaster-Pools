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

#### **2. Distributed Profit Sharing**
Distributes the sponsoring profits proportionally across all liquidity providers.

#### **3. Free-Market Price Discovery**
Allows creation of different paymaster pools with any determined sponsoring fee configuration, enabling the market to discover the right sponsoring fee.

#### **5. Permissionless **
Paymaster Pools are immutable contracts where anyone can provide liquidity and exit at all times, creating a strong and decentralized resistant system.

### **6. Increased Yields


Currently, the project consists in three main components:

The Uniswap Paymaster, handling the sponsorship of user operations.

LP's providing liquidity to Paymaster Pools (which is any pool conformed by ETH and a particular token). Altrough the idea 

LP's providing deposit for the entry point.



---

*Building the infrastructure for truly decentralized gas abstraction on Ethereum.*
