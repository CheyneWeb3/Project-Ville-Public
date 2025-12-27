## Mini feasibility report — Living NFT seasonal grow game (ERC-6551 + 1155 consumables)

### Core rule recap (the economics you set)

For each season, all revenue `G` (ERC-20) goes to the pool contract, then:

* **10%** → project/team takings (ops/dev)
* Remaining **90% = net**

  * **20% of net (18% of G)** → profit treasury (used to boost future pools / promos / ops)
  * **80% of net (72% of G)** → harvested winners reward pot

Winners split the reward pot by **weight** (recommended):
`weight = flowersHarvested * qualityBps / 10_000`
`payout = rewardPot * weight / totalWeight`

This is attractive because a very large portion of revenue returns to winners, while the game still funds itself via deaths, upgrades, and treasury skim.

---

# 1) Summary (is it worth building + playing?)

**Yes, if you tune for 2 “modes”:**

* **Mainline casual seasons** (50–70% harvest rate) where most players can finish if they engage.
* **Occasional hardcore seasons** (10–25% harvest rate) marketed as “high risk / high payout,” boosted using profit treasury.

Why this works:

* Players see a believable path to earning returns (especially if they manage care well).
* The project has dependable income (10% takings + 18% treasury).
* The game loop encourages repeat play (higher quality/yield = higher payout).

---

# 2) KPI targets (what to measure and aim for)

### Gameplay KPIs

**Harvest rate (season completion)**

* Target for normal seasons: **55–70%**
* Acceptable range: **45–75%**
* Hardcore promo seasons: **10–25%** (clearly labeled)

**Average survivor quality**

* Target: **80–90%**
* Minimum viable: **75%**
* Red flag: < **70%** (survivors feel cheated: “I survived and still got wrecked”)

**Average flowers per survivor**

* Target baseline: **20–40** flowers
* With upgrades: **30–60**
* Cap to prevent whales: hard cap like **100** per plant per season

### Revenue KPIs (Web3 “ARPPU-style”)

You’ll want to track per plant attempt:

* **ARPPA (avg revenue per plant attempt)** = total season revenue / plants minted
  Target: **$15–$30** (with $10 seed price + some items)
* **Consumables share**: 30–55% of revenue is healthy
* **Upgrades share**: 10–25% of revenue (if higher, it becomes pay-to-win)

### Retention KPIs (the “fun factor”)

* **D1 retention** (players return next day): **25–40%**
* **D7 retention**: **8–15%**
* **Season-to-season retention** (buy again next season): **30–55%**
* **Care compliance**: % of plants with 8+ care actions/season (your “engagement proxy”)

### Win experience KPIs

* Median survivor payout should feel meaningful:

  * Target: **1.2× to 3× seed price** (so $12–$30+)
* “High skill” (top 10%) should feel exceptional:

  * Target: **3× to 10× seed price** (so $30–$100+ depending on season)

---

# 3) Economic projections (monthly, based on seasons/week)

Assume:

* Seed price: **$10**
* Seasons are **weekly** (12-day cycle is “game time,” but you can run overlapping seasons if you want—here I keep it simple: 1 season/week).
* Reward token is a stable.

### Projection template

Let:

* `M` = mints/season
* `R` = avg revenue per mint (seed + items + upgrades)

Then:

* Gross/season `G = M * R`
* Team takings/season = `0.10G`
* Profit treasury/season = `0.18G`
* Winners pot/season = `0.72G`

Monthly (≈ 4 seasons):

* Team takings/month = `0.40G_month`
* Profit treasury/month = `0.72G_month`
* Winners pot/month = `2.88G_month`

### Three monthly scenarios

## A) Conservative launch month

* `M = 500 mints/season`
* `R = $18` (seed $10 + $6 consumables + $2 upgrades)
* Gross/season `G = $9,000`
* Gross/month `= $36,000`

Monthly splits:

* Team takings: `10%` → **$3,600**
* Profit treasury: `18%` → **$6,480**
* Winners pot: `72%` → **$25,920**

This is already enough to sustain a small dev loop if ops are lean.

## B) Realistic “it’s catching on”

* `M = 2,000 mints/season`
* `R = $22`
* Gross/season `G = $44,000`
* Gross/month `= $176,000`

Monthly splits:

* Team takings: **$17,600**
* Profit treasury: **$31,680**
* Winners pot: **$126,720**

Here you can run frequent boosted seasons and still build product.

## C) Upside “hit game”

* `M = 10,000 mints/season`
* `R = $25`
* Gross/season `G = $250,000`
* Gross/month `= $1,000,000`

Monthly splits:

* Team takings: **$100,000**
* Profit treasury: **$180,000**
* Winners pot: **$720,000**

At this scale, you’ll need serious anti-bot + brand + community management.

---

# 4) Risk list (what can break it) + mitigations

### A) Exploits / technical

**1) Season pool manipulation**

* Risk: fake “harvest registration” or fake weights.
* Fix: only `PlantCore` can register harvest + weight, and weight computed on-chain from stored plant state.

**2) ERC-6551 permission gotchas**

* Risk: users can’t easily approve PlantCore to burn items from TBA.
* Fix: use the “build calldata” helper and have UI call TBA.executeCall; add clear UX.

**3) Whale dominance / pay-to-win**

* Risk: upgrades let whales guarantee survival + massive yield.
* Fix:

  * caps (time reduction, yield boost, quality boost)
  * diminishing returns
  * “stability upgrades” > “yield upgrades”
  * per-season max flowers minted

**4) Sybil / multi-wallet farming**

* Risk: bots mint thousands, optimize, drain winners pot.
* Fix:

  * per-wallet mint caps (soft)
  * allowlists in early seasons
  * optional KYC-gated “boosted” seasons (if you ever want)
  * anti-bot mint windows

**5) Randomness gaming (genetics/seed outcomes)**

* Risk: block-based randomness can be gamed at scale.
* Fix:

  * keep genetics mostly cosmetic at first
  * if genetics affects money materially, consider VRF later

### B) Perception / product

**1) “Feels like gambling”**

* It is a high-variance game with winners and losers.
* Mitigation:

  * market as a game with skill/strategy
  * show transparent economics dashboards
  * avoid real-world drug messaging where possible (theme is fine, but be careful on distribution platforms)

**2) Players rage when they survive but earn low**

* Mitigation:

  * ensure average survivor quality is high (80–90%)
  * reward pot is always 72% of revenue so “winners get paid”
  * make quality improveable with clear actions

**3) Death rate too high**

* Mitigation:

  * tune so casual seasons have 55–70% harvest
  * hardcore seasons are opt-in and labeled

### C) Balancing

**1) Too easy → boring**

* Everyone survives, rewards spread thin.
* Fix: slightly stricter decay, slightly higher consumable usage, or cap number of survivors per season using “season capacity.”

**2) Too hard → churn**

* Fix: “grace mechanics”:

  * health doesn’t crash instantly
  * warning UI
  * 1 “revive token” per season (paid)

---

# 5) Recommended launch plan (step-by-step)

## Phase 0 — Testnet prototype (1–2 weeks)

Goals:

* validate ERC-6551 flows
* verify pool splits and payouts
* tune decay/quality

Deliverables:

* Plant mint → creates TBA
* Deposit items to TBA
* TBA approves PlantCore (helper call)
* Care actions burn items
* Harvest registers into season pool
* Season close + claim works

Success metrics:

* 90%+ of testers can complete the loop without support
* harvest rate and quality distributions are measurable

## Phase 1 — Season 0 “free-to-play” on mainnet (no real rewards)

Goals:

* stress test with real wallets
* test retention and UX
* collect balancing data safely

Mechanics:

* Seed NFTs either free or very cheap
* Consumables cheap or faucet-like
* Reward token payout is either:

  * a worthless test ERC-20, or
  * points leaderboard

Success metrics:

* D1 > 25%
* season-to-season return > 30%
* user reports show care loop is understandable

## Phase 2 — Season 1 paid (real rewards)

Start conservative:

* mint cap (e.g. 1,000–5,000)
* simple upgrade set
* standard season payout

Include:

* transparent pool dashboard: gross, takings, treasury, winners pot, number of harvesters

## Phase 3 — Growth + boosted seasons

Use profit treasury (18% of gross) to:

* boost special seasons
* referral/affiliate incentives
* partner seasons (co-marketing)

Suggested cadence:

* 3 normal seasons + 1 boosted/hardcore per month

---

# Go / No-Go criteria (practical)

**Go** if after Season 0:

* Harvest rate is in 55–70% band (or can be tuned there)
* Avg survivor quality ≥ 80%
* 30%+ players come back next season
* No critical exploits found

**No-Go / rethink** if:

* Users can’t handle TBA approvals (UX friction)
* Quality system feels random/unfair
* Botting dominates early

---
