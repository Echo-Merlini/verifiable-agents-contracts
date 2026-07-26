# Recomputable Agents — Contracts

On-chain contracts behind **[Recomputable Agents](https://github.com/Echo-Merlini/verifiable-agents)** (live at [demo.verticecriativo.pt](https://demo.verticecriativo.pt)) — the anchor that every attested agent action is committed to, and that the `/verify` page reads straight back from public chain data.

> **Don't trust. Recompute.**

---

## `TruthAnchor` — the ERC-8281 commitment anchor

[`src/TruthAnchor.sol`](src/TruthAnchor.sol) is the whole thing: a permissionless, storage-less, ownerless contract whose only job is to emit a commitment.

```solidity
event Recorded(bytes32 indexed digest, address indexed committer);
function record(bytes32 digest) external { emit Recorded(digest, msg.sender); }
```

*"The log is the ledger."* An agent action's attestation digest is committed with `record(digest)`; anyone reads the `Recorded` event back and **recomputes** the digest from public data. Nothing about this contract, its deployer, or any server has to be trusted — the event either matches the recomputed hash or it doesn't.

- `topic0(Recorded)` = `0xdca60c2087041cbb12d9a57628c6cad28ecbd0437e47c7ab6c3aa6e162bf4497`
- `/verify` reads **topic1** as the committed digest and re-derives it in the browser; tamper one byte of the input and the match breaks (red).
- The same digest may be recorded any number of times — every identical agent action re-commits the same digest, and each call is an independent, valid anchor.

## Deployments

The **same** contract, deployed unchanged to three chains — one action can be committed on more than one, giving independent commitments a verifier cross-checks.

| Chain | Address | Role |
|---|---|---|
| **Ethereum mainnet** (1) | [`0x1e2A118a2bf1C240aE6fDe187c07f905D360f094`](https://etherscan.io/address/0x1e2A118a2bf1C240aE6fDe187c07f905D360f094) | Showcase anchor — `/verify` reads mainnet |
| **Base Sepolia** (84532) | [`0x0963Fd33DF80c94360F2DC22e5c09517AeE7ED5c`](https://sepolia.basescan.org/address/0x0963Fd33DF80c94360F2DC22e5c09517AeE7ED5c) | Live per-action anchors (cheap, high-frequency) |
| **0G Galileo testnet** (16602) | [`0x29A45029DE2439925f2525E01Be6b6631fC9DD85`](https://chainscan-galileo.0g.ai/address/0x29A45029DE2439925f2525E01Be6b6631fC9DD85) | Second, independent commitment |

Committer / attestor across all three: `0x85Fa13511D170FBe173761b63D7f8DD4A6f6Bf1A`.

## Indexed by The Graph

Two subgraphs index the `Recorded` events so a commitment isn't just on-chain but **queryable** — and its answer must agree with the raw RPC log read. Subgraph manifests + AssemblyScript mappings live in the app repo ([`subgraph/`](https://github.com/Echo-Merlini/verifiable-agents/tree/main/subgraph) · [`subgraph-base/`](https://github.com/Echo-Merlini/verifiable-agents/tree/main/subgraph-base)).

| Network | Slug | Start block |
|---|---|---|
| Mainnet | `recomputable-agents-anchor` | 25548334 |
| Base Sepolia | `recomputable-agents-anchor-base` | 41658338 |

## Build & test

```bash
forge install foundry-rs/forge-std   # deps (lib/ is gitignored)
forge test                            # unit + fuzz over record()/Recorded
forge script script/Deploy.s.sol:Deploy --rpc-url $RPC --private-key $PK --broadcast
```

## Related contracts

The rest of the on-chain surface (open core, built ahead of the hackathon):

- **[trustless-ai/agent-ercs](https://github.com/trustless-ai/agent-ercs)** — the ERC interfaces this stack composes: ERC-8004 (identity), ERC-8299 (input provenance / WYRIWE), ERC-8281 (this anchor), ERC-8275 (reputation), ERC-8323 (source-token binding), plus `ConsultEscrow.sol` (agent-to-agent settlement).
- **[trustless-ai/agent-contracts-examples](https://github.com/trustless-ai/agent-contracts-examples)** — `GenesisAgentRegistry.sol`, the ERC-721 registry where the agent NFTs are minted.
- **[trustless-ai/recompute-kit](https://github.com/trustless-ai/recompute-kit)** — the verification library (recipes that re-derive each committed field).

## License

Apache-2.0 — see [`LICENSE`](LICENSE).
