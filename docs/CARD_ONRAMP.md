# Debit / credit card → crypto → bot

This bot is a smart contract. It can hold **ETH** and allowed **ERC-20s**. It cannot charge a Visa or Mastercard.

**You can still fund it from a card.** A licensed on-ramp charges the card, sends crypto to **your wallet**, and you deposit that crypto into **your** contract.

```
Card  →  on-ramp (MoonPay / Transak / Coinbase / MetaMask Buy)
      →  ETH or USDC/USDT in your MetaMask
      →  transfer / depositEth() to the bot
```

## What you will not find in this repo

- No card number field
- No Stripe/Square charge on the contract
- No `depositWithCard()` Solidity function

Card networks are off-chain. Putting a card form in a trading-bot UI is how people get phished. If a site asks for the card **and** the bot’s seed phrase or “deposit to start arbitrage,” close it.

## Checklist (do this in order)

### 1. Deploy first, buy second

You need the **owner wallet** and the **contract address** before you size a card purchase.

1. Deploy `contract.sol` from the wallet that should own the bot.
2. Copy the contract address (the bot). Keep it somewhere you will paste from — not a screenshot in a group chat.
3. Confirm you still have a little ETH (or will buy extra) on the **owner wallet** for gas. Automation transactions are paid by the owner, not only by the contract.

### 2. Buy crypto to your wallet, not to the contract

In MetaMask (same account that deployed):

1. Open the account → **Buy**.
2. Choose **Ethereum** as the network.
3. Choose **ETH** (inventory + gas) or **USDC** / **USDT** (stable inventory).
4. Pay with debit or credit card. Debit is accepted more often.
5. Finish KYC if the provider asks. First-time card buys almost always require an ID.

You can do the same on [Coinbase](https://www.coinbase.com/), [MoonPay](https://www.moonpay.com/buy), [Transak](https://transak.com/), or [Ramp](https://ramp.network/), then **withdraw to MetaMask**.

**Do not set the bot contract as the on-ramp destination.** Many providers reject contract addresses. If they accept it and the token/network is wrong, funds can be stuck. Buy to an EOA you control, then forward.

### 3. Wait until it is actually in MetaMask

Card authorization ≠ on-chain credit. The on-ramp may show “complete” while the Ethereum transaction is still pending. When MetaMask shows the ETH or token balance, you are safe to deposit.

### 4. Deposit into the bot

**ETH**

- Send any amount to the contract address (plain transfer), or
- Call `depositEth()` with `msg.value > 0`

Either path credits the contract balance and emits `Deposit`.

**USDC / USDT / WETH / WBTC**

- In MetaMask, send the token to the **same contract address**.
- Those four are allowed in the constructor. Any other ERC-20 needs `setTokenAllowed(token, true)` first.

**Leave ETH on the owner wallet** as well. If every last wei goes into the contract, you cannot pay gas to start, pause, or withdraw.

### 5. Size after fees, not before

Card on-ramps usually take about **2.5–7%** (stated fee plus spread). A **$200** card charge is not **$200** of ETH.

There is still **no minimum** on the contract. Small tests (0.05–0.2 ETH) are enough to learn the loop. Card fees make tiny tests expensive relative to size — if you only want to try the bot, a bank-funded exchange withdrawal is cheaper.

## Network and asset gotchas

| Mistake | What happens |
| --- | --- |
| Buy ETH on Base / Arbitrum / Polygon and send to an Ethereum-mainnet bot | Wrong chain; recovery is hard or impossible |
| Buy “USDT” on Tron or Solana | Not the ERC-20 the contract holds |
| Send to a copy-paste address from a DM | Not your bot; funds gone |
| Credit card issued in a blocked region | On-ramp declines; try debit or an exchange |
| On-ramp destination = contract | Often rejected; sometimes delivered, sometimes not |

This `contract.sol` uses Ethereum mainnet addresses (Uniswap V3 router, WETH, USDT, USDC, WBTC). Card buys must be **Ethereum mainnet** unless you fork and re-wire those constants yourself.

## Why not add a card form to the bot?

| Issue | Why it blocks a Solidity “card deposit” |
| --- | --- |
| PCI-DSS | Handling PAN/CVV makes you a card processor. This repo will not do that. |
| Chargebacks | Cards reverse; Ethereum does not. Someone has to eat that risk (on-ramps do). |
| Licensing | Fiat→crypto for others is a money-transmitter / VASP activity. |
| Custody | This contract is **owner-only**. It does not track per-depositor shares. A public “pay with card, we credit you” flow would pool other people’s money. Do not do that. |

A future **widget** (MoonPay/Transak embed with your API key, wallet = owner, then a one-click forward to the contract) is a website feature, not a contract feature. It still uses their checkout. It still should not collect raw card data.

## If you already have an exchange account

Skip the in-wallet on-ramp:

1. Buy ETH or USDC on the exchange (card or bank).
2. Withdraw to your MetaMask on **Ethereum**.
3. Forward to the bot as above.

This is usually cheaper than MetaMask Buy for anything above a tiny test.
