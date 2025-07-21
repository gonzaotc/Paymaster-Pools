## Decentralized Paymasters

ERC-4337 has provided an entire off-protocol architecture to allow Ethereum users to pay for their transactions in other ways than using ETH, which is great. However, most implementations today are still very immature and centralized.

### The Current Problem

Today's ERC-20 paymasters suffer from critical centralization issues:

#### **1. Capital Constraints**
- **Single capital provider**: The paymaster owner provides all the ETH necessary to pay for user operations
- **Limited scalability**: Capital is strictly limited to what the paymaster owner can provide

#### **2. Centralized Profit Capture** 
- **Owner keeps all fees**: The paymaster owner captures 100% of service fees
- **Liquidity fragmentation**: Competing players must create separate paymasters, increasing liquidity fragmentation and decreasing efficiency

#### **3. Manual Rebalancing Burden**
- **Constant monitoring**: The paymaster owner must manually rebalance to keep it functional at all times
- **Operational overhead**: Huge effort required to constantly monitor and rebalance the ETH balance

#### **4. Limited Token Support & Poor UX**
- **Owner-gated decisions**: The paymaster owner decides which tokens to support based on their capacity to monitor and rebalance
- **Poor UX**: Users struggle to find paymasters that support their desired tokens and must be highly technical to search for compatible ERC-20 paymasters

#### **5. Systemic Risk & Single Points of Failure**
- **Ecosystem dominated by 2-3 players**: The majority of ERC-4337 users rely on just a few major paymaster providers
- **Service dependency**: If these major providers go offline, the entire gas sponsoring system becomes unavailable

---

### A potential alternative

To drive meaningful improvement, a decentralized paymaster should:

#### 🌊 **1. Permissionless Liquidity Provision**
Allow anyone to provide liquidity (ETH) for sponsoring transactions

#### 💸 **2. Distributed Profit Sharing**
Distribute profits proportionally across all liquidity providers

#### 🔄 **3. Autonomous Rebalancing**
Implement automatic or permissionless rebalancing mechanisms, similar to:
- **MakerDAO liquidations** for letting anyone trigger a rebalance under certain treshold, and claiming a fee.
- **Uniswap arbitrage opportunities** for setting the paymaster pool as a swapping pool and allowing traders to arbitrage unbalances.

#### 🗺️ **4. Unified Paymaster Router**
Offer a PaymasterRouter (Singleton) that indicates which paymaster to use for a given token at any moment, dramatically simplifying UX

#### 🛡️ **5. Censorship-Resistant**
The decentralized paymaster should be unstoppable and not depend on any single participant, remaining resistant to censorship
---

*Building the infrastructure for truly decentralized gas abstraction on Ethereum.*
