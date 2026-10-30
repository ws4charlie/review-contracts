# Review Protocol — Decentralized Review Verification & Rewards

Smart contracts that pay bounties only for **provably genuine** e-commerce reviews.

> Sponsors fund a bounty. Reviewers commit their review on-chain *before* it appears
> on the marketplace. Verifiers cross-check that the same content really appeared.
> Only verified reviews get paid — fake, copied or never-published reviews earn
> nothing and can be slashed at settlement.

Solidity ^0.8.9 · Hardhat · OpenZeppelin · April 2023 · Unaudited, exploratory — not for production use.
Full design notes: **[docs/DESIGN.md](docs/DESIGN.md)**

## Architecture

```mermaid
flowchart LR
    Sponsor([Sponsor]) -->|create campaign, lock bounty| Hub
    Reviewer([Reviewer]) -->|submit review commitment| Hub
    Verifier([Verifier]) -->|vote: rating, appearance, market ID| Hub
    subgraph Onchain[On-chain contracts]
        Hub[CampaignHub<br/>campaigns - domains - escrow - gate]
        Pool[ReviewPool<br/>reviews - voting - slashing - payout]
        Safe[ERC20Safe<br/>safe token custody]
        VPool[IVerifierPool<br/>verifier registry, interface only]
        Hub -->|submit / verify / close| Pool
        Hub --- Safe
        Pool --- Safe
        Pool -->|isVerifier / getPower| VPool
    end
    Token([ERC-20 bounty token]) <-->|bounty in, rewards and refund out| Hub
    Reviewer -.->|publish review| Mkt([Marketplaces<br/>Amazon, eBay, Walmart, ...])
    Mkt -.->|review appears| Verifier
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
    S->>H: newCampaign(products, bounty)
    H->>H: lock bounty in escrow
    R->>H: submitReview(rootHash, headHash)
    H->>P: submit(campaign, product, hashes)
    R->>M: publish the review
    V->>M: check content, rating, appearance time
    V->>H: verifyReview(bodyHash, rating, appearedAt, mktReviewID)
    H->>P: verify(reviewID, ...)
    Note over P: one opinion reaches 2/3 of total power<br/>and appearedAt is after submittedAt = Verified
    S->>H: closeCampaign(slashIDs)
    H->>P: close(campaign, bounty, portion, slashIDs)
    P->>R: pay portion to each Verified reviewer
    H->>S: refund unspent bounty
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
