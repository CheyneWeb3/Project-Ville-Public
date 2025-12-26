Below is a **team-dev report** you can drop straight into your internal docs. It explains the **system operations**, the **control knobs** (difficulty/season tuning), and what the **frontend + server** must do to run the game end-to-end.

---

# Living NFTs (ERC-6551) — System Operations & Controls Report

**Purpose:** align contract ops + frontend + server/indexer so the team can build the full game and tune seasons (difficulty knobs, obstacles, progression) safely over time.

## 0) One-paragraph overview

Each Plant NFT (ERC-721) has an ERC-6551 smart wallet (TBA) that holds ERC-1155 consumables/upgrades. The PlantCore contract simulates growth over a 12-week cycle (compressed to 12 days in “season time”), decays resources, updates health/quality, and allows care actions that **burn items from the plant’s TBA**. Successful harvests qualify a plant for the season reward pool. Season revenue is collected in an ERC-20 pool and split per rules: **10% takings**, then from net **20% profit treasury**, **80% harvested reward pot**. Seasons can be tuned via knobs: decay rates, thresholds, upgrade caps, random events, and obstacles to control survival rate and return dynamics.

---

# 1) System components (what we’re building)

## On-chain contracts

### Core

* **PlantNFT (ERC-721)**
  Holds ownership and lineage/genetics. Mint seed + mint child seeds.
* **ERC-6551 Registry + Account Implementation**
  Derives a TBA per plant tokenId (plant smart wallet).
* **Items1155 (ERC-1155)**
  Water, fert, upgrades, plus optional harvest outputs (flowers, seeds).
* **PlantCore (engine)**
  The growth simulation + care operations. Burns 1155 from plant TBA. Mints harvest outputs. Registers harvest into SeasonPool.
* **SeasonPool (ERC-20)**
  Receives revenue, performs splits, allocates reward pot to harvested plants, and supports claims.

### Optional add-ons (later)

* **Renderer contract** for on-chain `tokenURI` (or off-chain renderer).
* **Obstacles/Event contract** that PlantCore can query/use to adjust difficulty per season.

---

## Off-chain systems

### Frontend (dApp)

Must support:

* mint seed + show plant list
* show plant wallet (TBA) + inventory (1155 balances)
* “one-click approve” from TBA → allow PlantCore to burn from TBA
* care actions (water/fert), upgrades, pollination
* season dashboard (pool size, survivors, pot splits)
* claim rewards

### Server/Indexing

Must support:

* event indexing (plant state changes, harvest, season pool deposits/claims)
* metadata hosting / dynamic rendering (stage, health, quality, genetics, status)
* analytics + tuning dashboards (survival rate, average quality, revenue, ARPPU)
* optional “game master” admin panel (season configs, obstacle schedules, boosted pools)

---

# 2) The end-to-end gameplay flow (operations)

## A) Mint / Initialize

1. User buys Plant seed NFT (PlantNFT mint via PlantCore or shop contract).
2. TBA address is derived for the plant using ERC-6551 registry:

   * `tba = registry.account(impl, chainId, PlantNFT, tokenId, salt)`
3. PlantCore `initPlant(tokenId)` sets baseline stats: water/food/health/quality.

**Frontend tasks:** display plant, compute TBA, show “Deposit Items” CTA.

---

## B) Items & approvals (critical ERC-6551 UX)

**Goal:** PlantCore must burn items from the plant’s TBA.

Requirement:

* TBA must have the 1155 items
* TBA must approve PlantCore as operator on Items1155:

  * `Items1155.setApprovalForAll(PlantCore, true)` executed by the TBA

**Best practice UX:**

* PlantCore exposes `buildApproveItemsOperatorCall(true)` returning (target, calldata)
* Frontend calls `TBA.executeCall(target, 0, calldata)` (user signs)

**Frontend tasks:**

* “Approve PlantCore” button (executes TBA call)
* show approval status (read `isApprovedForAll(tba, PlantCore)`)

---

## C) Care loop (the core mechanic)

User triggers care:

* `PlantCore.care(tokenId, waterUsed, fertUsed)`
  PlantCore:
* runs `sync(tokenId)` (applies decay since last update)
* burns `waterUsed` and `fertUsed` from the **TBA**
* increases internal water/food metrics, affects health/quality

**Frontend tasks:**

* show current metrics and predicted decay
* show how many items TBA has
* enforce max amounts / prevent pointless calls

---

## D) Upgrades (player acceleration / safety knobs)

User triggers upgrade:

* `PlantCore.applyUpgrade(tokenId, upgradeId, qty)`
  PlantCore burns upgrade items from the **TBA** and adjusts:
* time reduction, yield boost, quality boost (capped)

**Frontend tasks:**

* show upgrade effects and caps
* show time reduction remaining

---

## E) Pollination (breeding path)

User calls:

* `PlantCore.pollinate(motherId, fatherId)`
  PlantCore validates stage (bloom/harvest window) and stores pair.

**Frontend tasks:**

* show “Pollinate” options for eligible plants
* warn about stage requirement

---

## F) Harvest (survival gating)

On harvest:

* `PlantCore.harvest(tokenId)`
  PlantCore:
* validates finished + alive
* freezes harvest quality
* mints outputs (flowers or seed children)
* registers harvest in season pool (qualifies for rewards)

**Frontend tasks:**

* show harvest readiness
* show expected flowers/seed outcome

---

## G) Season reward pool (economics + claims)

Revenue is deposited into SeasonPool (ERC-20 stable/WETH):

* `depositRevenue(seasonId, amount)` from shop/treasury

Split rule (final):

* **10%** team takings (immediate)
* **net = 90%**
* from net:

  * **20%** → profit treasury
  * **80%** → harvested rewards pot

Harvested plants claim:

* `claim(seasonId, tokenId, to)`

**Recommended distribution (so 80% is fully paid):**

* weight = `flowers * qualityBps / 10_000`
* payout = rewardPot * weight / totalWeight

**Frontend tasks:**

* season dashboard: G, takings, treasury, rewardPot
* plant claim UI: pending amount, claimed status

---

# 3) Difficulty knobs & progressive season control (what devs can tune)

These knobs exist to:

* tune survival rate (e.g. casual 60–70%, hardcore 10–25%)
* tune “skill matters” via quality and yield
* keep seasons interesting via obstacles/events

## A) Core tuning knobs (contract-level)

**Decay**

* waterDecayPerDay
* fertDecayPerDay

**Penalty thresholds**

* dryThreshold, hungryThreshold
* healthPenaltyPerDayWhenDry / WhenHungry

**Life/death edges**

* wiltHealthThreshold
* deadHealthThreshold

**Quality gain**

* qualityGainBpsPerDayWhenWell
* qualityBoostBps (from upgrades)

**Cycle length**

* BASE_DURATION (12 weeks) and MIN_DURATION
* timeReduction caps and per-upgrade effect

**Yield**

* yieldBoostBps (caps)
* flowerMint formula and caps

**Genetics**

* mutationChanceBps, mutationMaxDelta
* trait count/weights (affects rarity outcomes)

### How to use knobs for progressive difficulty

* Increase decay rates / penalties over seasons to reduce survival
* Increase event frequency or severity
* Reduce “free quality gain” so quality must be maintained intentionally
* Adjust upgrade caps to prevent guaranteed wins

---

## B) Obstacles/events framework (recommended approach)

To avoid redeploying PlantCore constantly, implement obstacles as **data-driven season modifiers**.

### Option 1: On-chain “SeasonConfig” contract (best long-term)

A small contract storing:

* `seasonId -> modifiers`
* `seasonId -> event schedule seeds` (optional)
  PlantCore queries it in `sync()` and applies modifiers.

Modifiers examples:

* `decayMultiplierBps` (e.g. 12000 = +20% decay)
* `qualityGainMultiplierBps` (e.g. 8000 = -20% quality gain)
* `randomStressChanceBps` (chance of a health hit on sync)
* `pestSeason` boolean
* `moldRisk` boolean if water too high too long

### Option 2: Off-chain event suggestions (simpler)

Server computes “event forecasts” and UI suggests actions, but on-chain truth remains core knobs only.

* Pros: easier, flexible
* Cons: events aren’t enforceable on-chain

**Recommendation:** build Option 1 once the base game is stable.

---

# 4) Frontend build spec (must-have screens & behaviors)

## Plant list / dashboard

* list owned plants
* show stage, progress %, health/water/fert, alive/wilt/dead
* show seasonId and eligibility status

## Plant details

* TBA address
* inventory balances (water/fert/upgrades/flowers)
* approval status (TBA → Items1155 operator)
* care buttons (with sliders)
* upgrades panel
* pollination panel
* harvest panel
* claim panel (if harvested + season closed)

## One-click “Approve PlantCore” (TBA executeCall)

* call PlantCore `buildApproveItemsOperatorCall(true)`
* user signs TBA `executeCall`
* read `isApprovedForAll(tba, PlantCore)`

## Season dashboard

* gross revenue (indexed)
* splits: 10% takings, 20% treasury, 80% reward pot
* harvested count, totalWeight
* top plants (quality/yield)
* claim status and time windows

---

# 5) Server/indexer spec (what we need off-chain)

## Indexed events

From PlantCore:

* Planted
* Synced
* Cared
* UpgradeApplied
* Pollinated
* Harvested

From SeasonPool:

* RevenueDeposited
* SeasonClosed (if present)
* Claimed

From Items1155:

* TransferSingle/Batch (optional for inventory changes)

## Data products

* **Per-plant state cache** (for fast UI)
* **Season analytics:**

  * survival rate
  * avg quality of survivors
  * avg spend per plant
  * revenue mix (seeds vs items vs upgrades)
  * whales vs casual distributions
* **Metadata renderer**

  * Stage-specific visuals
  * Genetics display
  * “grow closet” scene parameters
  * final harvest stats

## Admin tooling

* season creation/config
* obstacle schedule configuration
* boosted pool deposits (from treasury) and announcements
* monitoring: stuck claims, abnormal survival collapse, exploit detection

---

# 6) Controls & governance (who can change what)

Define roles clearly:

### Owner / Governance (multi-sig)

* sets active season ID
* sets decay/threshold knobs
* configures season windows (if used)
* sets treasury addresses
* triggers “boosted pool” funding

### PlantCore (trusted engine)

* registers harvest/weights in SeasonPool
* mints harvest outputs
* burns consumables from TBAs

### Users

* care/upgrade/pollinate/harvest
* claim rewards

---

# 7) Launch & iteration plan (beta tuning to “final system”)

## Phase 0: internal testnet

* focus: approvals, burn-from-TBA, season payouts correct
* tune baseline knobs to hit target survival bands

## Phase 1: Season 0 (free or low-stake mainnet)

* no meaningful rewards; use points
* goal: retention, UX comprehension, difficulty calibration

## Phase 2: Season 1 paid (real ERC-20 pot)

* conservative caps
* monitor exploit vectors
* start with player-friendly settings (55–70% harvest)

## Phase 3: Progressive seasons

* rotate difficulty (casual / balanced / hardcore)
* use treasury to boost occasional seasons
* introduce obstacles once base loop proven

---

# 8) What the team should build next (concrete work packages)

### WP1 — Contracts finalize

* SeasonPool implements: deposit splits (10%, 20%, 80%)
* Weight method locked (flowers×quality)
* onlyCore permissions for harvest registration
* events emitted for all critical actions

### WP2 — Frontend MVP

* Plant list + details + approve flow
* Inventory balances from 1155
* Care loop and harvest
* Claim flow + season dashboard basics

### WP3 — Indexer + metadata

* index PlantCore + SeasonPool events
* cached plant state endpoints
* dynamic metadata renderer for stage visuals

### WP4 — Balancing tools

* admin panel to set season knobs
* dashboards: survival/quality distribution & revenue split

---

If you want, paste your **exact current contract interfaces/addresses** (or the latest repo layout), and I’ll turn this report into:

* a precise **API list** (every function the frontend must call),
* event schemas for the indexer,
* and a “season config JSON” format your team can use to run progressive difficulty without chaos.
