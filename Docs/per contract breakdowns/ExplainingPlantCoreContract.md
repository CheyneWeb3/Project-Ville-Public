## What PlantCore is

**PlantCore is the game engine.**
It does **not** own the NFT itself — the NFT is `PlantNFT` (ERC-721). PlantCore stores the “living stats” (water/food/health/quality, pollination, harvest state) and applies time-based decay/growth rules.

It also ties together 3 key systems:

1. **ERC-721 PlantNFT** — ownership + genetics + minting children/seeds
2. **ERC-1155 Items1155** — consumables/upgrades/flower outputs in the plant’s wallet
3. **SeasonalGrowPool** — registers harvested plants for seasonal payout (quality-weighted)

And it uses:

4. **ERC-6551 TBA** — each plant NFT has its own “smart wallet” address that holds items.

---

## The mental model (how it plays)

Each plant NFT has a wallet (6551) that holds:

* WATER (1155 id 1)
* FOOD (1155 id 2)
* upgrades (time/yield/quality item IDs)
* harvested flowers (1155 id 201)

The user’s EOA **does not need to hold items** during gameplay if they transfer items into the plant’s TBA.

PlantCore burns/mints items **directly against the TBA address**.

So the loop is:

1. Mint seed NFT
2. Plant it (initialize state)
3. Transfer consumables to plant wallet (TBA)
4. Call `care()` to burn items from plant wallet and boost stats
5. Time passes → `sync()` decays water/food and changes health/quality
6. Optionally `pollinate()` a mother with a father
7. After duration, call `harvest()`

   * if not pollinated → flowers minted to TBA
   * if pollinated → seed harvest scheduled; seeds minted via `mintNextSeed()`
8. Harvest registers plant into season pool with its frozen `qualityBps`

---

## Key storage: PlantState

For each `tokenId`, PlantCore stores:

### Core “life stats”

* `plantedAt`, `lastUpdateAt`
* `water`, `food`, `health`, `quality`
* `wilted`, `dead`, `harvested`

### Pollination

* `pollinatedWith` (father tokenId)
* `pollinatedAt`

### Upgrades applied

* `timeReductionSec`
* `yieldBoostBps`
* `qualityBoostBps`

### Harvest snapshot (frozen at harvest)

* `harvestedQualityBps`
* `harvestSeasonId`

### Seed harvest scheduler

If pollinated harvest:

* `seedHarvestMode`
* `seedsRemaining`
* `seedFatherId`
* `seedNonce`
* `seedRandBase`

This “scheduler” exists so seed minting happens **1 per tx**, which avoids stack depth/gas blowups.

---

## Important concept: TBA (plant smart wallet)

### `tbaOf(tokenId)`

Computes the ERC-6551 account address for that plant NFT.

That address is where you send your ERC-1155 items:

* send WATER/FOOD to it
* upgrades to it
* flowers get minted to it

PlantCore calls `items.burn(tba, itemId, qty)` which burns from the TBA *as if it’s a normal address*.

**Note:** burning from another address requires `Items1155` to allow it (either operator approval OR role-based burn). In OZ’s `ERC1155Burnable`, burning another account typically requires approval (`isApprovedForAll`). That’s why you have the helper below.

---

## Functions (what each does)

### Admin / config

#### `setActiveSeason(seasonId)`

Sets which season `harvest()` should register into.

You’ll also separately configure the season inside `SeasonalGrowPool`.

---

## Init & planting

#### `mintAndPlant(to)`

* Generates random genes
* Calls `PlantNFT.mintSeed(to, genes)`
* Initializes stats in PlantCore via `_initPlant(tokenId)`

#### `initPlant(tokenId)`

If you minted elsewhere (or want manual), initializes the state once.

#### `_initPlant(tokenId)`

Sets:

* water=70, food=70, health=100, quality=1000
* timestamps
  Emits `Planted` and `Synced`.

---

## Simulation (time passing)

#### `sync(tokenId)`

This is the “tick”.

It calculates how much time passed since `lastUpdateAt`, converts to “days” fraction, then applies:

1. `_applyDecay`

   * water decays by `waterDecayPerDay`
   * food decays by `foodDecayPerDay`

2. `_applyHealth`
   if below thresholds:

   * health penalty when dry/hungry

3. `_applyQuality`
   if well cared (water>=60, food>=60, health>=70):

   * quality increases (boosted by quality upgrade)

4. `_applyWiltDead`

   * health <= dead threshold → dead
   * health <= wilt threshold → wilted

Then updates `lastUpdateAt` and emits `Synced`.

**Design note:** `sync()` is called inside `care()`, `pollinate()`, and `harvest()` so state stays accurate.

---

## Growth tracking

#### `effectiveDuration(tokenId)`

Base is **12 weeks** minus time reductions. Clamped to a minimum duration.

#### `progressBps(tokenId)`

Returns % progress as basis points 0..10,000.

#### `stageOf(tokenId)`

Maps progress into stages:

* Seed → Sprout → Veg → Bloom → Harvest Window
  And overrides for Wilted/Dead/Post-harvest.

---

## Gameplay actions

### Care

#### `care(tokenId, waterUsed, foodUsed)`

* Requires owner/approved on the plant NFT
* Calls `sync()`
* Burns WATER and FOOD from the plant’s **TBA**
* Increases water/food (capped at 100)
* If you used any items, bumps health a bit
* Emits `Cared` + `Synced`

So yes: **it consumes from the plant’s 6551 wallet**.

---

### Upgrades

#### `applyUpgrade(tokenId, upgradeId, qty)`

Burns upgrade items from the plant’s TBA and applies:

* time reduction
* yield boost
* quality boost

---

### Pollination

#### `pollinate(motherId, fatherId)`

Requires caller controls BOTH plants (owner/approved) then:

* syncs both
* requires both in BLOOM or HARVEST_WINDOW
* stores `pollinatedWith` into mother’s state

Only the **mother** records pollination; the father is “source genetics”.

---

## Harvesting

### `harvest(tokenId)`

Requires:

* planted, alive, not harvested
* sync
* progress == 100%

Then it:

1. `_registerHarvest(tokenId)`

   * freezes quality into `harvestedQualityBps`
   * registers in `SeasonalGrowPool` with (seasonId, tokenId, quality)

2. If pollinated:

   * `_scheduleSeedHarvest(tokenId)`
   * sets seedsRemaining etc.
   * you mint seeds later, one-per-tx

   If NOT pollinated:

   * `_mintFlowerHarvest(tokenId)`
   * mints FLOWER_BUD (id 201) into the plant TBA
   * amount depends on quality + yield boost

Finally: marks `harvested = true`

---

### Seed minting

#### `mintNextSeed(motherId)`

If seed harvest mode:

* computes deterministic-ish randomness from `seedRandBase + seedNonce`
* mixes genes mother+father via GeneticsLib
* calls `PlantNFT.mintChild(ownerOfMother, childGenes, motherId, fatherId, childGen)`
* initializes that child with `_initPlant(childId)`
* decrements seedsRemaining

When seedsRemaining hits 0 → finalizes.

#### `finalizeSeedHarvest(motherId)`

Emergency/manual “stop seed minting”.

---

## ERC-6551 operator approval helper

This part exists because Items1155 burning from TBA may require approval.

### `buildApproveItemsOperatorCall(approved)`

Just returns call data so a UI/wallet can execute it.

### `approveItemsOperatorViaTBA(tokenId, approved)`

This attempts to call:

`Items1155.setApprovalForAll(PlantCore, approved)`
from the **TBA account** via `executeCall`.

**Important:** this only works if your ERC-6551 account implementation allows the NFT owner to instruct it (typical 6551 accounts do). If your account implementation blocks it, burn will fail unless Items1155 uses a different permission model.

---

## First steps (what you do next)

Here’s the clean deployment + test flow:

1. **Deploy Items1155**

   * admin = you

2. **Deploy PlantNFT**

   * admin = you

3. **Deploy SeasonalGrowPool**

   * rewardToken = whatever ERC20 you pay seasons with
   * plantNFT = PlantNFT address
   * plantCore = (you can deploy PlantCore first or set after via constructor; currently fixed)

4. **Deploy PlantCore**

   * registry + accountImplementation + salt
   * plantNFT address
   * items1155 address
   * seasonPool address

5. **Grant roles**

   * `PlantNFT.grantRole(MINTER_ROLE, PlantCore)`
   * `Items1155.grantRole(MINTER_ROLE, PlantCore)` (so it can mint flowers)
   * You also need ability to mint items to TBAs (admin/minter)

6. **Configure a season**

   * `SeasonalGrowPool.configureSeason(seasonId, startAt, endAt, claimEndAt)`
   * `PlantCore.setActiveSeason(seasonId)`

7. **Mint + plant**

   * `PlantCore.mintAndPlant(user)`

8. **Send items to plant TBA**

   * compute `tba = PlantCore.tbaOf(tokenId)`
   * mint/transfer WATER/FOOD/UPGRADES to `tba`

9. **Approve burn operator (if needed)**

   * call `approveItemsOperatorViaTBA(tokenId, true)`
   * then `care()` will burn successfully

10. **Simulate**

* wait time or warp on test
* call `sync()`
* call `care()`

11. **Pollinate (optional)**

* `pollinate(mother, father)` when both are Bloom/Harvest window

12. **Harvest**

* `harvest(tokenId)`
* if pollinated: call `mintNextSeed(mother)` until done
* if not pollinated: flowers minted to TBA

That’s the full lifecycle.
