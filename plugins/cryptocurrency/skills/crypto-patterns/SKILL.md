# Crypto Patterns

Domain-specific patterns for blockchain integration, wallet management, smart contract interaction, and DeFi. Covers key security, transaction construction, and common Ethereum/Bitcoin patterns.

## Core Patterns

### Pattern: HD Wallet Derivation with Secure Randomness

```typescript
// CORRECT: Use @scure/bip39 (audited library, pure TypeScript)
import { generateMnemonic, mnemonicToSeedSync, validateMnemonic } from '@scure/bip39';
import { wordlist } from '@scure/bip39/wordlists/english';
import { HDKey } from '@scure/bip32';

// 256 bits = 24 words; 128 bits = 12 words
// 24 words is recommended for financial applications
const mnemonic = generateMnemonic(wordlist, 256);

// ALWAYS validate before using
if (!validateMnemonic(mnemonic, wordlist)) {
  throw new Error('Invalid mnemonic - check entropy source');
}

// Derive key - do NOT use in browser for production custody
const seed = mnemonicToSeedSync(mnemonic, passphrase); // passphrase adds extra entropy
const masterKey = HDKey.fromMasterSeed(seed);
```

### Pattern: EIP-1559 Gas Estimation

Never use legacy gas pricing. EIP-1559 separates base fee (burned, market-set) from priority fee (to validator).

```typescript
async function estimateGas(provider: ethers.JsonRpcProvider) {
  const feeData = await provider.getFeeData();
  const block = await provider.getBlock('latest');

  // base fee from latest block
  const baseFee = block?.baseFeePerGas ?? 0n;

  // Priority fee: user-specified tip to validator
  const maxPriorityFeePerGas = ethers.parseUnits('2', 'gwei');  // Typical 2 gwei tip

  // maxFeePerGas: you're willing to pay up to this; base fee is burned
  // 2x base fee provides buffer if base fee spikes in next block
  const maxFeePerGas = baseFee * 2n + maxPriorityFeePerGas;

  return { maxFeePerGas, maxPriorityFeePerGas };
}
```

### Pattern: ERC-20 Safe Transfer with Approval Check

Always check allowance before transferring on behalf of a user. Always use `safeTransfer` pattern for ERC-20.

```typescript
import { erc20Abi } from 'viem';

// Check existing allowance before requesting approval (gas optimization + UX)
const allowance = await publicClient.readContract({
  address: tokenAddress,
  abi: erc20Abi,
  functionName: 'allowance',
  args: [userAddress, spenderAddress],
});

if (allowance < requiredAmount) {
  // Use increaseAllowance (not approve) to avoid double-spend race condition
  // Or use permit (EIP-2612) for gasless approvals if token supports it
  const hash = await walletClient.writeContract({
    address: tokenAddress,
    abi: erc20Abi,
    functionName: 'approve',
    args: [spenderAddress, requiredAmount],
  });
  await publicClient.waitForTransactionReceipt({ hash });
}
```

### Pattern: Multisig Transaction via Safe (Gnosis Safe)

```typescript
import Safe, { EthersAdapter } from '@safe-global/protocol-kit';
import SafeApiKit from '@safe-global/api-kit';

const ethAdapter = new EthersAdapter({ ethers, signerOrProvider: signer });
const safeSdk = await Safe.create({ ethAdapter, safeAddress });
const safeService = new SafeApiKit({ txServiceUrl: 'https://safe-transaction-mainnet.safe.global' });

// Build transaction
const safeTransactionData = {
  to: recipientAddress,
  value: ethers.parseEther('1').toString(),
  data: '0x',
};

const safeTransaction = await safeSdk.createTransaction({ transactions: [safeTransactionData] });
const safeTxHash = await safeSdk.getTransactionHash(safeTransaction);

// Sign (first signer)
const senderSignature = await safeSdk.signTransactionHash(safeTxHash);
await safeService.proposeTransaction({
  safeAddress,
  safeTransactionData: safeTransaction.data,
  safeTxHash,
  senderAddress: await signer.getAddress(),
  senderSignature: senderSignature.data,
});

// Second signer confirms and executes
const pendingTx = await safeService.getTransaction(safeTxHash);
await safeSdk.confirmTransaction(safeTxHash);
const executeTxResponse = await safeSdk.executeTransaction(pendingTx);
```

### Pattern: MEV Protection via Private Mempool

Large swaps on Uniswap are vulnerable to sandwich attacks. Route through Flashbots Protect or CoW Protocol.

```typescript
// Use Flashbots Protect RPC endpoint instead of public RPC
const provider = new ethers.JsonRpcProvider(
  'https://rpc.flashbots.net',  // Flashbots Protect
  // or 'https://rpc.mevblocker.io' (MEV Blocker)
);

// Alternatively: CoW Protocol for DEX trades (batch auctions prevent MEV)
// Submit via CoW API instead of directly to Uniswap
```

## Anti-Patterns

### Anti-Pattern: Using `Math.random()` for Key Generation

```typescript
// CATASTROPHICALLY WRONG: Math.random() is not cryptographically secure
function generatePrivateKey() {
  return [...Array(64)].map(() => Math.floor(Math.random() * 16).toString(16)).join('');
}
// Attackers can predict keys from time-seeded random number generators.

// RIGHT: Use OS-level CSPRNG
function generatePrivateKey() {
  const bytes = new Uint8Array(32);
  crypto.getRandomValues(bytes);  // Browser/Node Web Crypto API
  return Buffer.from(bytes).toString('hex');
}
```

### Anti-Pattern: Storing Private Keys in Plaintext

Environment variables, `.env` files, and database VARCHAR columns are all plaintext storage. For production custody:
- AWS KMS or HashiCorp Vault: keys never leave the HSM; sign operations happen inside
- Fireblocks MPC: key shares distributed across multiple parties; no single machine has the full key
- If you must store a key in a database, use AES-256-GCM with a KMS-managed key envelope

### Anti-Pattern: No Replay Protection (Missing chainId)

```typescript
// WRONG: Missing chainId - this transaction can be replayed on testnets or forks
const tx = {
  nonce,
  to: recipient,
  value: ethers.parseEther('1'),
  gasLimit: 21000n,
};

// RIGHT: Always include chainId in EIP-155 signed transactions
const tx = {
  type: 2,
  chainId: 1,  // Ethereum mainnet; Sepolia is 11155111
  nonce,
  to: recipient,
  value: ethers.parseEther('1'),
  gasLimit: 21000n,
  maxFeePerGas: feeData.maxFeePerGas!,
  maxPriorityFeePerGas: feeData.maxPriorityFeePerGas!,
};
```

### Anti-Pattern: Trusting Token Decimals Without Validation

```typescript
// WRONG: Assumes 18 decimals; USDC has 6, WBTC has 8
const amount = ethers.parseEther(userInput); // Wrong for USDC

// RIGHT: Read decimals from contract
const decimals = await tokenContract.decimals();
const amount = ethers.parseUnits(userInput, decimals);
```

## References

- **BIP32**: HD Wallets - https://github.com/bitcoin/bips/blob/master/bip-0032.mediawiki
- **BIP39**: Mnemonic code - https://github.com/bitcoin/bips/blob/master/bip-0039.mediawiki
- **EIP-1559**: Fee market change - https://eips.ethereum.org/EIPS/eip-1559
- **EIP-712**: Typed structured data signing - https://eips.ethereum.org/EIPS/eip-712
- **@scure/bip39**: https://github.com/paulmillr/scure-bip39 (audited)
- **ethers.js v6**: https://docs.ethers.org/v6/
- **viem**: https://viem.sh/
- **Gnosis Safe**: https://docs.safe.global/
- **Flashbots Protect**: https://docs.flashbots.net/flashbots-protect/overview
