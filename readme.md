# Budsville GameFi Plant Sim

Budsville is a “living NFT” weed/plant simulation built around **ERC-721 Plant NFTs**, **ERC-6551 token-bound accounts (TBAs)** (smart wallets per plant), and an **ERC-1155 item economy** for consumables, upgrades, and harvest outputs. Each Plant NFT owns its own smart wallet, which holds the items it needs to survive, grow, and produce results over a **12-week lifecycle**. 

---

## Core idea

Each **Plant NFT (ERC-721)** maps to an **ERC-6551 Token Bound Account (TBA)** (“plant wallet”). The plant wallet holds: 

* **Consumables (ERC-1155):** water / food / nutrients / etc
* **Upgrades (ERC-1155):** time reducers, yield boosts, quality boosts, genetics modifiers
* **Outputs & loot (ERC-1155):** bud harvest, seed harvest, trophies, etc

Plants progress through growth stages (seed → sprout → vegetation → bloom → harvest window) based on **time + care metrics** (water/food/health/quality), with failure states like **wilted** or **dead** if neglected. 

---

## High-level architecture

### Contracts

* **PlantNFT (ERC-721)**

  * Mints seeds/plants
  * Resolves each token’s ERC-6551 account from the registry/account manager
  * `tokenURI()` reflects current stage/health/genetics/outcomes (via renderer or on-chain JSON) 

* **PlantCore (rules engine / simulation)**
  Single source of truth for: lifecycle timing (12 weeks base), stage computation, care metrics, pollination status, harvest logic (buds vs seeds), point assignment, and upgrade tracking. 

* **Items1155 (ERC-1155)**
  Holds all in-game items: care items, upgrades, and outputs (buds, seeds, trim/essence, etc). 

* **HarvestPool**
  Receives “harvest returns” and distributes rewards **pro-rata by plant points** (designed to avoid loops). 

* **GeneticsLib**
  Encodes traits and produces child genetics from two parents (deterministic mixing with optional randomness). 

---

## The 12-week lifecycle

* **Base duration:** 12 weeks
* **Stage progression:** derived from timestamps + modifiers (no weekly on-chain updates required) 

Example mapping:

* `SEED → SPROUT → VEGETATION → BLOOM → HARVEST_WINDOW → POST_HARVEST`
* Failure paths: `WILTED`, `DEAD` 

Stage is derived from: 

* `elapsed = now - plantedAt`
* `effectiveTotalDuration = 12 weeks - timeReductionFromUpgrades`
* `progress = elapsed / effectiveTotalDuration` (clamped)
* Health gating (poor care can force wilt/dead regardless of time)

---

## Care loop (items spent from the plant wallet)

Users “care” for a plant by consuming items held by the plant’s TBA. Typical flow: 

1. User calls `PlantCore.care(tokenId, actions...)`
2. `PlantCore` verifies caller is owner/approved
3. `PlantCore` resolves the plant TBA address
4. `PlantCore` consumes required ERC-1155 items from the TBA (e.g., `safeTransferFrom(tba, ...)`)
5. Care updates water/food/health/quality (with decay computed from `lastCareAt`) 

**One-tx UX:** have the TBA grant operator approval to `PlantCore` once, then care can be executed in a single transaction. 

---

## Upgrades (ERC-1155)

Upgrades are ERC-1155 items stored in the plant TBA and “applied” to set modifiers. 

Common upgrade types:

* **Time Reduction:** reduces total lifecycle duration (capped)
* **Yield Boost:** increases buds/seeds output (capped)
* **Quality Boost:** increases final points / reward multiplier
* Optional: “stability” upgrades to reduce decay or prevent wilt thresholds 

Implementation sketch:

* `applyUpgrade(tokenId, upgradeId, qty)`

  * consumes upgrade items from TBA
  * updates stored modifiers
  * enforces caps to prevent infinite scaling 

---

## Pollination & harvest outcomes

During **BLOOM**, plants can be pollinated (directional “mother” plant or symmetric—your choice). 

At harvest:

* **Not pollinated → Bud harvest**
* **Pollinated → Seed harvest** (optionally reduced buds) 

Recommendation: mint/transfer outputs into the **plant TBA** for consistent inventory behavior. 

---

## Genetics (seed inheritance)

Each plant stores packed genes (e.g., `uint256`). When producing seeds: 

* `childGenes = GeneticsLib.mix(genesA, genesB, randomness)`
* Seed count can depend on: mother quality, yield boosts, fertility traits, etc.
* Metadata includes genetics summary so seeds can show parent traits, generation, rarity bands 

Randomness options:

* VRF (best)
* commit/reveal (good)
* pseudo-random for low-stakes (e.g., `keccak256(block.prevrandao, tokenId, pollinatedAt, ...)`) 

---

## Rewards: HarvestPool (no-loop pro-rata distribution)

Harvest results feed a pool where rewards are distributed **pro-rata** by “points” assigned at harvest. 

Points can incorporate:

* Successful completion (base points)
* Quality multiplier
* Genetics multiplier
* Yield/quality boosts
* Optional: speed bonus (finishing early) 

Claims can route to:

* the **NFT owner**, or
* the **plant TBA** (then owner withdraws) 

---

## Metadata & rendering

`tokenURI()` should reflect: stage, alive/wilted/dead, water/food/health/quality, pollination state, genetics summary, modifiers applied, and (if harvested) outputs + points. 

Rendering can use `animation_url` for an evolving “closet scene” or similar dynamic visual that changes with stage/health/traits. 

---

## Multicall-friendly reads (dApp UX)

Expose compact view methods so the UI can batch read everything via **Multicall3**. Examples: 

* `getPlant(tokenId)` → full state required for UI
* `computeStage(tokenId)` → stage enum + progress bps
* `getModifiers(tokenId)` → timeReduction / yieldBoost / qualityBoost
* `getPollination(tokenId)`
* `pendingRewards(tokenId)` (via HarvestPool)

---

## Repo layout (suggested)

```
/contracts
  PlantNFT.sol
  PlantCore.sol
  Items1155.sol
  HarvestPool.sol
  GeneticsLib.sol
  (ERC-6551 registry + account implementation)
/scripts
/test
/frontend (optional)
```

---
