# Review Protocol — Decentralized Review Verification & Rewards

Smart contracts that pay bounties only for **provably genuine** e-commerce reviews.

> Sponsors fund a bounty. Reviewers commit their review on-chain *before* it appears
> on the marketplace. Verifiers cross-check that the same content really appeared.
> Only verified reviews get paid — fake, copied or never-published reviews earn
> nothing and can be slashed at settlement.

Solidity ^0.8.9 · Hardhat · OpenZeppelin · April 2023 · Unaudited, exploratory — not for production use.
Full design notes: **[docs/DESIGN.md](docs/DESIGN.md)**

## Architecture

System overview — who interacts with the protocol:

```mermaid
flowchart TB
    Sponsor([Sponsor]) -->|funds bounty| Hub
    Reviewer([Reviewer]) -->|commits review| Hub
    Verifier([Verifier]) -->|verifies| Hub
    Hub[Review Protocol<br/>smart contracts]
    Hub <-->|bounty, rewards, refunds| Token([ERC-20 token])
    Reviewer -.->|publishes| Mkt([Marketplaces])
    Mkt -.->|review appears| Verifier
```

Inside the contracts:

```mermaid
flowchart TB
    Hub[CampaignHub<br/>campaigns and escrow]
    Pool[ReviewPool<br/>verification and payouts]
    Safe[ERC20Safe<br/>token custody]
    VPool[IVerifierPool<br/>verifier registry]
    Hub --> Pool
    Hub --- Safe
    Pool --- Safe
    Pool --> VPool
```

## Flow

```mermaid
sequenceDiagram
    participant S as Sponsor
    participant H as CampaignHub
    participant P as ReviewPool
    participant R as Reviewer
    participant M as Marketplace
    participant V as Verifiers
    S->>H: create campaign, fund the bounty
    R->>H: commit a review (hashes only)
    H->>P: record the commitment
    R->>M: publish the review
    V->>M: check the published review
    V->>H: vote with the observed facts
    H->>P: tally the votes
    Note over P: verified when one opinion<br/>reaches 2/3 of voting power
    S->>H: close the campaign
    P->>R: pay the verified reviewers
    H->>S: refund the remainder
```

## Contracts

| Contract | Lines | Role |
| --- | ---: | --- |
| `contracts/CampaignHub.sol` | 330 | Campaign lifecycle, marketplace domains, bounty escrow; the single gate into the pool |
| `contracts/ReviewPool.sol` | 211 | Review state machine, hash-chain commitments, power-weighted voting, slashing, payouts |
| `contracts/ERC20Safe.sol` | 58 | Safe ERC-20 custody helpers for escrow and payouts |
| `interfaces/` | — | `IReviewPool`, `IVerifierPool` — the cross-contract surface |

Mechanics, the voting math, the trust model and known limitations live in
**[docs/DESIGN.md](docs/DESIGN.md)**.

## Build

```shell
npm install
npx hardhat compile
npx hardhat run scripts/deploy.js
```
