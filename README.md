# Review Protocol — Decentralized Review Verification & Rewards

Smart contracts for paying bounties only for **provably genuine** e-commerce reviews.

Sponsors fund a bounty campaign for their products on marketplaces such as Amazon,
eBay or Walmart. Reviewers commit their review on-chain *before* it appears on the
marketplace; a pool of verifiers then cross-checks that the same content actually
appeared, and only reviews that pass verification get paid. Fake, copied or
never-published reviews earn nothing — and can be slashed at settlement.

Built with Solidity ^0.8.9, Hardhat and OpenZeppelin (April 2023).

## How it works

1. **Campaign** — A sponsor creates a campaign in `CampaignHub` for a whole
   marketplace domain or a list of products, and locks the bounty (ERC-20) into
   the contract. Each campaign fixes a per-review portion, a distribution mode,
   and the time windows for submission, moderation and closing.
2. **Submit (commit)** — A reviewer submits a review through `CampaignHub`,
   which fans it out to every open campaign for that product. Only hashes go
   on-chain: the review body is committed as a hash chain
   (`rootHash = keccak256(headHash, bodyHash)`), so the content stays off-chain
   until it is revealed, while the commitment is timestamped.
3. **Verify** — Verifiers check the review on the marketplace and vote with the
   data they observed (rating, appearance time, marketplace review ID). Votes
   are weighted by verifier *power*; when one opinion reaches **≥ 2/3 of total
   power**, the review becomes `Verified`. The winning opinion must also show
   the review appeared on the marketplace **after** its on-chain submission —
   the commit-before-publish ordering that stops copy-paste of existing reviews.
4. **Close & settle** — After the moderation window, the sponsor closes the
   campaign: reviews flagged in the slash list lose their reward, every
   remaining `Verified` review is paid its portion from the bounty, and the
   unspent remainder is refunded to the sponsor. Campaigns that are never
   closed can be settled by anyone via `expireCampaign` after the closing
   window, so funds cannot get stuck.

## Contracts

| Contract | Lines | Role |
| --- | ---: | --- |
| `contracts/CampaignHub.sol` | 330 | Campaign lifecycle: marketplace domains, products, bounty escrow, submission/verification entry points, settlement. Access-controlled (`AccessControl`), acts as the single gate into the pool. |
| `contracts/ReviewPool.sol` | 211 | Review state machine (`Submitted → Verified → Rewarded / Slashed / Missed / Expired`), hash-chain commitments, power-weighted verifier voting, slashing and bounty distribution. |
| `contracts/ERC20Safe.sol` | 58 | Safe ERC-20 custody helpers (`lockERC20` / `releaseERC20`) used for bounty escrow and payouts. |
| `interfaces/` | — | `IReviewPool` and `IVerifierPool` — the cross-contract surface, including the verifier registry abstraction. |

## Design decisions worth noting

- **Content commitment instead of on-chain text.** Reviews live on the
  marketplaces, not on-chain. The hash chain commits the author to exact
  content at a point in time, and verification checks reveal-against-commitment
  — cheap, private until reveal, and tamper-evident.
- **Power-weighted supermajority, not one-person-one-vote.** Verifier opinions
  carry power from the verifier pool; a review is verified only when a single
  consistent opinion (same rating, appearance time and marketplace ID) holds
  at least two thirds of total power.
- **Single-gate mediation.** `ReviewPool` accepts state changes only from its
  gate contract (`CampaignHub`), which owns validation that needs campaign and
  domain context (rating scales, moderation windows, duplicate submissions
  across campaigns).
- **Per-marketplace configuration.** Each listed domain carries its own rating
  scale and moderation delay, because marketplaces publish reviews at very
  different speeds — the campaign cutoff extends automatically when a slow
  marketplace needs more moderation time.

## Status & limitations

Exploratory project from 2023 — **unaudited, not deployed, not for production use**.

- The verifier pool implementation is intentionally not included; the
  contracts are written against the `IVerifierPool` interface
  (`contracts/VerifierPool.sol` is a stub).
- Only the equal-distribution bounty mode (`DISTRIB_EQUAL`) is implemented.
- The `test/` folder still contains the default Hardhat sample test;
  the contracts do not yet have a dedicated test suite.

## Build

```shell
npm install
npx hardhat compile
npx hardhat test          # sample test only, see Status above
npx hardhat run scripts/deploy.js
```
