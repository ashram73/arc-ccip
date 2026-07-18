/**
 * broadcast.ts — quote a CCIP fee and send a cross-chain message from Arc.
 *
 * Run:
 *   npm install
 *   PRIVATE_KEY=0x... SENDER=0x... RECEIVER=0x... npx tsx script/broadcast.ts
 *
 * SENDER   = your ResultSender on Arc
 * RECEIVER = your ResultReceiver on the destination chain
 */

import { createWalletClient, createPublicClient, http, parseAbi } from "viem";
import { privateKeyToAccount } from "viem/accounts";

// ---- config ---------------------------------------------------------------

const ARC_RPC = "https://rpc.testnet.arc.network";

/** Chain selector of the destination. Ethereum Sepolia by default. */
const DEST_CHAIN_SELECTOR = 16015286601757825753n;

/** Gas budgeted for ccipReceive() on the destination. */
const GAS_LIMIT = 250_000n;

const SENDER = process.env.SENDER as `0x${string}`;
const RECEIVER = process.env.RECEIVER as `0x${string}`;
const PRIVATE_KEY = process.env.PRIVATE_KEY as `0x${string}`;

const arcTestnet = {
  id: 5042002,
  name: "Arc Testnet",
  nativeCurrency: { name: "USDC", symbol: "USDC", decimals: 18 },
  rpcUrls: { default: { http: [ARC_RPC] } },
} as const;

const SENDER_ABI = parseAbi([
  "struct Result { uint256 marketId; string question; uint8 winningOutcome; uint64 settledAt; }",
  "function quote(uint64 destinationChainSelector, address receiver, Result result, uint256 gasLimit) view returns (uint256)",
  "function broadcast(uint64 destinationChainSelector, address receiver, Result result, uint256 gasLimit) payable returns (bytes32)",
]);

// ---- the payload we're shipping -------------------------------------------

const result = {
  marketId: 1n,
  question: "Will BTC close above $100,000 today?",
  winningOutcome: 1,
  settledAt: BigInt(Math.floor(Date.now() / 1000)),
};

// ---------------------------------------------------------------------------

async function main() {
  if (!SENDER || !RECEIVER || !PRIVATE_KEY) {
    throw new Error("Set SENDER, RECEIVER and PRIVATE_KEY");
  }

  const account = privateKeyToAccount(PRIVATE_KEY);
  const publicClient = createPublicClient({
    chain: arcTestnet as any,
    transport: http(ARC_RPC),
  });
  const wallet = createWalletClient({
    account,
    chain: arcTestnet as any,
    transport: http(ARC_RPC),
  });

  // 1) Quote first. The fee tracks destination gas prices, so never hardcode it.
  const fee = (await publicClient.readContract({
    address: SENDER,
    abi: SENDER_ABI,
    functionName: "quote",
    args: [DEST_CHAIN_SELECTOR, RECEIVER, result, GAS_LIMIT],
  })) as bigint;

  console.log(`CCIP fee: ${fee} wei of the native gas token`);

  // 2) Send with a little headroom. The contract refunds the difference.
  const value = (fee * 110n) / 100n;

  const hash = await wallet.writeContract({
    chain: arcTestnet as any,
    address: SENDER,
    abi: SENDER_ABI,
    functionName: "broadcast",
    args: [DEST_CHAIN_SELECTOR, RECEIVER, result, GAS_LIMIT],
    value,
  });

  console.log(`Sent: ${hash}`);
  const receipt = await publicClient.waitForTransactionReceipt({ hash });
  console.log(`Confirmed in block ${receipt.blockNumber}`);
  console.log();
  console.log("Track delivery at https://ccip.chain.link — paste the tx hash.");
  console.log("Delivery takes a few minutes; it waits for source-chain finality.");
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
