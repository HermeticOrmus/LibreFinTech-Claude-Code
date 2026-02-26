# /crypto

Manage blockchain operations: wallet generation, transaction signing, smart contract deployment, and on-chain verification.

## Trigger

`/crypto <action> [options]`

## Actions

- `wallet` - Generate or derive HD wallet addresses
- `sign` - Sign a transaction offline without broadcasting
- `deploy` - Deploy a smart contract to a network
- `verify` - Verify a transaction, contract, or signature on-chain

## Options

- `--network <mainnet|sepolia|polygon|arbitrum|bitcoin|signet>` - Target network
- `--path <derivation-path>` - BIP44 derivation path (default: m/44'/60'/0'/0/0 for ETH)
- `--contract <address>` - Smart contract address
- `--tx <hash>` - Transaction hash for verification
- `--gas-priority <low|medium|high|custom>` - Gas priority tier

## Process

### wallet

Generate a BIP39 mnemonic and derive the first address. For security, this should run in a secure environment - never in a browser for production key generation.

```typescript
import { ethers } from 'ethers';

// Generate new wallet
const wallet = ethers.Wallet.createRandom();
console.log('Mnemonic:', wallet.mnemonic?.phrase);   // 24 words - store securely
console.log('Address:', wallet.address);
console.log('Private key:', wallet.privateKey);      // Never log in production

// Derive from existing mnemonic
const hdNode = ethers.HDNodeWallet.fromPhrase(mnemonic);
const derived = hdNode.derivePath("m/44'/60'/0'/0/0");

// Derive multiple addresses (e.g., for exchange deposit address generation)
for (let i = 0; i < 10; i++) {
  const child = hdNode.derivePath(`m/44'/60'/0'/0/${i}`);
  console.log(`Address ${i}:`, child.address);
}
```

For Bitcoin (using @scure/bip32 and @scure/bip39):
```typescript
import { generateMnemonic, mnemonicToSeedSync } from '@scure/bip39';
import { HDKey } from '@scure/bip32';
import { p2wpkh } from '@scure/btc-signer';
import { secp256k1 } from '@noble/curves/secp256k1';

const mnemonic = generateMnemonic(wordlist, 256); // 24 words
const seed = mnemonicToSeedSync(mnemonic);
const hdKey = HDKey.fromMasterSeed(seed);
const child = hdKey.derive("m/84'/0'/0'/0/0"); // BIP84 for native SegWit
const pubkey = child.publicKey!;
const address = p2wpkh(pubkey, 'mainnet').address; // Native SegWit (bc1...)
```

### sign

Construct and sign an EIP-1559 transaction without broadcasting (for offline signing workflows):

```typescript
import { ethers } from 'ethers';

const provider = new ethers.JsonRpcProvider(RPC_URL);
const wallet = new ethers.Wallet(privateKey); // Loaded from secure storage

// Build transaction
const nonce = await provider.getTransactionCount(wallet.address, 'latest');
const feeData = await provider.getFeeData();

const tx = {
  type: 2,  // EIP-1559
  chainId: 1,  // Mainnet
  nonce,
  to: recipientAddress,
  value: ethers.parseEther('0.1'),
  gasLimit: 21000n,
  maxFeePerGas: feeData.maxFeePerGas! * 2n,       // 2x current base fee
  maxPriorityFeePerGas: feeData.maxPriorityFeePerGas!,
};

const signedTx = await wallet.signTransaction(tx);
console.log('Signed tx:', signedTx);  // Broadcast separately: provider.broadcastTransaction(signedTx)
```

### deploy

Deploy a compiled contract:

```typescript
import { ethers } from 'ethers';

const factory = new ethers.ContractFactory(abi, bytecode, wallet);
const contract = await factory.deploy(constructorArg1, constructorArg2, {
  maxFeePerGas: feeData.maxFeePerGas! * 2n,
  maxPriorityFeePerGas: ethers.parseUnits('2', 'gwei'),
});
await contract.waitForDeployment();
console.log('Deployed at:', await contract.getAddress());
```

### verify

```typescript
// Verify a transaction was included and succeeded
const receipt = await provider.getTransactionReceipt(txHash);
if (!receipt) throw new Error('Transaction not yet mined');
if (receipt.status === 0) throw new Error('Transaction reverted');
console.log('Confirmed in block:', receipt.blockNumber);
console.log('Gas used:', receipt.gasUsed.toString());

// Verify an EIP-712 signature (used in DeFi permit patterns)
const signerAddress = ethers.verifyTypedData(domain, types, value, signature);
console.log('Signed by:', signerAddress);
```

## Examples

```bash
# Generate new Ethereum mainnet wallet
/crypto wallet --network mainnet

# Sign a Bitcoin transaction offline
/crypto sign --network bitcoin --tx <unsigned-psbt>

# Deploy ERC-20 token to Sepolia testnet
/crypto deploy --network sepolia --contract ./artifacts/MyToken.json

# Verify transaction confirmation and status
/crypto verify --network mainnet --tx 0xabc123...
```
