# Cross-Chain Messaging on Arc with Chainlink CCIP

A complete, working example of sending a cross-chain message from [Arc](https://arc.network) using [Chainlink CCIP](https://chain.link/cross-chain)  with the addresses, the exact message shape, and the details that are easy to get wrong.

Most CCIP tutorials target Ethereum or Base. This one is written for Arc, where the fee is paid in USDC and there's no separate gas token to acquire first.

> Two contracts, two deploys, one message. No external Solidity dependencies the CCIP interfaces are inlined so you can read every line.

---

## What you'll learn

- How a CCIP message is structured, field by field
- The Router address, chain selector, and fee tokens for **Arc Testnet**
- How to quote a fee and send a message that pays in **USDC**
- How to write a receiver that can't be spoofed
- The details that cost people the most time

---

## The idea

Something gets decided on Arc a market settles, an oracle finalizes, a vote closes. Other chains need to know. CCIP carries that outcome across.

```
        ARC                                DESTINATION CHAIN
 ┌──────────────────┐                    ┌──────────────────┐
 │  ResultSender    │                    │  ResultReceiver  │
 │                  │                    │                  │
 │  1. quote fee    │                    │                  │
 │  2. ccipSend() ──┼──►  CCIP Router  ──┼──► ccipReceive()  │
 │     (pays USDC)  │      + lane        │    stores result  │
 └──────────────────┘                    └──────────────────┘
```

The payload here is a settled outcome, but the pattern is general. Swap the struct and you have cross-chain governance results, state sync, or attestations anything where one chain decides and others react.

---

## Arc Testnet reference

| Thing | Value |
|---|---|
| CCIP Router | `0xdE4E7FED43FAC37EB21aA0643d9852f75332eab8` |
| Chain selector | `3034092155422581607` |
| RMN | `0xD610B8f58689de7755947C05342A2DFaC30ebD57` |
| Token admin registry | `0xd3e461C55676B10634a5F81b747c324B85686Dd1` |
| Registry module owner | `0x524B83ae8208490151339c626fd0E35b964483e3` |
| Chain ID | `5042002` |
| RPC | `https://rpc.testnet.arc.network` |
| Explorer | `https://testnet.arcscan.app` |

**Fee tokens on Arc Testnet**

| Token | Address |
|---|---|
| USDC | native gas token — use `address(0)` |
| LINK | `0x3F1f176e347235858DD6Db905DDBA09Eaf25478a` |
| WUSDC | `0xbf4B839A7939a52acbF8fC52D5Bd5BFE69a064EA` |

**Current lane coverage**

| Direction | Destination | OnRamp | Version |
|---|---|---|---|
| Outbound | Ethereum Sepolia | `0x2016AA303B331bd739Fd072998e579a3052500A6` | 1.6.0 |

Destination chain selector for Ethereum Sepolia: `16015286601757825753`
Router on Ethereum Sepolia: `0x0BF3dE8c5D3e8A2B34D2BEeB17ABfCeBaf363A59`

Always confirm current values against the [CCIP Directory](https://docs.chain.link/ccip/directory/testnet/chain/arc-testnet) — lanes and tokens get added over time.

---

## Anatomy of a CCIP message

This is the whole thing. Five fields:

```solidity
Client.EVM2AnyMessage({
    receiver:     abi.encode(receiverAddress),   // encoded, not raw
    data:         abi.encode(yourPayload),       // anything you like
    tokenAmounts: new Client.EVMTokenAmount[](0),// empty = data-only message
    feeToken:     address(0),                    // address(0) = native = USDC on Arc
    extraArgs:    Client._argsToBytes(
        Client.EVMExtraArgsV2({
            gasLimit: 250_000,                   // gas for ccipReceive()
            allowOutOfOrderExecution: true       // required on v1.6 lanes
        })
    )
})
```

Then two calls:

```solidity
uint256 fee = router.getFee(destinationChainSelector, message);
bytes32 messageId = router.ccipSend{value: fee}(destinationChainSelector, message);
```

That's it. Everything else is application logic.

---

## Quick start

### 1. Install

```bash
forge install foundry-rs/forge-std
npm install
cp .env.example .env   # fill in PRIVATE_KEY
```

### 2. Deploy the receiver on the destination chain

```bash
forge script script/DeployReceiver.s.sol \
  --rpc-url $SEPOLIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

Note the printed address.

### 3. Deploy the sender on Arc

```bash
forge script script/DeploySender.s.sol \
  --rpc-url https://rpc.testnet.arc.network \
  --private-key $PRIVATE_KEY \
  --broadcast --legacy --skip-simulation
```

### 4. Fund the sender with a little USDC

The fee is paid in Arc's native gas token, so the sending wallet just needs a small USDC balance. Grab testnet USDC from [faucet.circle.com](https://faucet.circle.com).

### 5. Send a message

```bash
SENDER=0xYourSender RECEIVER=0xYourReceiver PRIVATE_KEY=0x... npm run broadcast
```

The script quotes the fee, sends with 10% headroom, and prints the transaction hash. Paste that hash into [ccip.chain.link](https://ccip.chain.link) to watch delivery.

### 6. Read it on the other side

```bash
cast call $RECEIVER "latest()" --rpc-url $SEPOLIA_RPC_URL
cast call $RECEIVER "outcomeOf(uint256)" 1 --rpc-url $SEPOLIA_RPC_URL
```

---

## Details worth knowing

**1. The receiver address is abi-encoded, not raw.**
`receiver: abi.encode(receiverAddress)` — a `bytes` field, not an `address`. CCIP supports non-EVM destinations, so the field is deliberately generic. Passing a raw address is the single most common mistake.

**2. Quote the fee every time.**
`getFee()` reflects current destination gas prices, so a value that worked yesterday can be short today. Quote, send with headroom, refund the difference that's the pattern in `ResultSender.broadcast()`.

**3. `allowOutOfOrderExecution` must be `true` on v1.6 lanes.**
Use `EVMExtraArgsV2`. The older `EVMExtraArgsV1` doesn't carry this field and will be rejected.

**4. Size your `gasLimit` deliberately.**
It budgets gas for `ccipReceive()` on the destination. Too low and delivery fails after you've already paid. Too high and you overpay on every message. Measure your receiver's cost and add margin — 250,000 is comfortable for a small struct.

**5. Only the Router may call `ccipReceive()`.**
Without an `onlyRouter` check, anyone can call your receiver directly and inject whatever they like. Add source-chain and sender allowlists too, so you only trust a deployment you control. Both are in `ResultReceiver.sol`.

**6. Never revert inside `ccipReceive()` for business-logic reasons.**
A revert marks the message failed on the lane. Emit an event and return instead — see the `MessageRejected` pattern in the receiver.

**7. Delivery isn't instant.**
CCIP waits for source-chain finality before executing on the destination. Expect minutes, not seconds. Build your UI around that: show a pending state and track the message id.

**8. Encode and decode in the same order.**
`abi.decode` has no idea what the sender intended — it trusts the types you give it. Change the payload on one side and you must change it on the other, or you'll silently read garbage.

**9. Fees are paid in USDC on Arc.**
Because USDC is the native gas token, `feeToken: address(0)` means your cross-chain fee is denominated in a stablecoin. No separate token to acquire, and the cost is predictable.

---

## What's in the repo

```
src/
  interfaces/ICCIP.sol   inlined CCIP types — no external deps
  ResultSender.sol       quotes and sends, refunds overpayment
  ResultReceiver.sol     router-gated, allowlist-capable, non-reverting
script/
  DeploySender.s.sol     deploy to Arc
  DeployReceiver.s.sol   deploy to the destination
  broadcast.ts           quote + send from the command line
```

---

## Resources

- [CCIP docs](https://docs.chain.link/ccip)
- [CCIP Directory — Arc Testnet](https://docs.chain.link/ccip/directory/testnet/chain/arc-testnet)
- [CCIP Explorer](https://ccip.chain.link)
- [Arc docs](https://docs.arc.io)
- [Circle faucet](https://faucet.circle.com)

