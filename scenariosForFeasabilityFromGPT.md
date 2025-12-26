# Scenario Examples of a Game Season

### ✅ Season rule

From **gross season revenue G** (ERC-20):

1. **10%** goes to the **project/team takings** (ops/dev).
2. Remaining **net = 90% of G**.
3. From **net**:

   * **20%** goes to the **profit treasury** (for future boosted pools / marketing / ops)
   * **80%** goes to **harvested plants rewards**
4. Harvested plants split the **80% rewards pot** (ideally weighted by quality and/or flowers).

So:

* Team takings = `0.10G`
* Profit treasury (boost pot) = `0.20 * 0.90G = 0.18G`
* Harvested rewards = `0.80 * 0.90G = 0.72G`

✅ That means **72% of all season revenue** goes back to harvested winners.
That’s *very* attractive compared to most games — the catch is death rate + quality/yield decide who gets it.

---

# Payout formula (recommended so rewards pot always fully paid)

Let harvested plants be `i = 1..N`.

Weight per plant:

* **Option (best):** `w_i = flowers_i * qualityBps_i / 10_000`

Then:

* `W = Σ w_i`
* `payout_i = rewardsPot * w_i / W`

This ensures the full 80% rewards pot pays out (no leftover complexity).

---

# Scenario set (3 models): Player-friendly / Balanced / High-stakes

I’ll keep your base pricing:

* 100 seeds @ $10 = $1,000
* Consumables: water $0.10, fert $0.50
  We’ll model weekly spend per active plant (water+fert combined).

## Scenario 1 — Player-friendly “mostly win” season

**Goal:** lots of winners, payouts feel frequent, keeps casuals playing.

**Assumptions**

* 100 planted
* **70 harvested**, **30 died**
* Avg death at week 5
* Consumable spend: **$0.80/week**
* Upgrades total: **$150**
* Total consumables:

  * survivors: 70×12×0.80 = **$672**
  * dead: 30×5×0.80 = **$120**
  * consumables total = **$792**

**Gross revenue**

* Seeds: $1,000
* Consumables: $792
* Upgrades: $150
* **G = $1,942**

**Splits**

* Team takings (10%): **$194.20**
* Net = $1,747.80
* Profit treasury (20% of net): **$349.56**
* Rewards pot (80% of net): **$1,398.24**

**What a typical harvested plant earns**
If you split evenly (just for intuition):

* $1,398.24 / 70 = **$19.98 average** (before weighting)

If weighting by flowers×quality, typical outcomes might be:

* “Good grower” (high care, 90% quality): ends up **above average**, say $23–$30
* “Lazy but survived” (60–70%): **below average**, say $14–$18

**Why it’s fun**

* Most people finish → feels fair
* Rewards pot still large
* Treasury still healthy for promos

---

## Scenario 2 — Balanced “skill matters” season

**Goal:** winners feel rewarded; deaths matter; good care wins.

**Assumptions**

* **50 harvested**, **50 died**
* Avg death at week 6
* Consumable spend: **$1.00/week**
* Upgrades total: **$250**
* Consumables:

  * survivors: 50×12×1.00 = **$600**
  * dead: 50×6×1.00 = **$300**
  * total = **$900**

**Gross revenue**

* Seeds: $1,000
* Consumables: $900
* Upgrades: $250
* **G = $2,150**

**Splits**

* Team takings (10%): **$215.00**
* Net = $1,935.00
* Profit treasury (20% of net): **$387.00**
* Rewards pot (80% of net): **$1,548.00**

**Average per harvested plant**

* $1,548 / 50 = **$30.96** (before weighting)

**How it feels**

* If you survive with decent quality, payout is meaningful.
* Skilled players (high flowers + high quality) can realistically land **$40–$70** depending on distribution.
* Casual survivors may still make **$18–$28**.

**Why it’s replayable**

* You can “get better” and feel it in your returns.
* Project has enough treasury to run boosted seasons or promotions.

---

## Scenario 3 — High-stakes “survivor jackpot” season

**Goal:** fewer winners but big payouts → hype / viral / “bank” rewards.

**Assumptions**

* **15 harvested**, **85 died**
* Avg death at week 5
* Consumable spend: **$1.25/week**
* Upgrades total: **$350**
* Consumables:

  * survivors: 15×12×1.25 = **$225**
  * dead: 85×5×1.25 = **$531.25**
  * total = **$756.25**

**Gross revenue**

* Seeds: $1,000
* Consumables: $756.25
* Upgrades: $350
* **G = $2,106.25**

**Splits**

* Team takings (10%): **$210.63**
* Net = $1,895.62
* Profit treasury (20% of net): **$379.12**
* Rewards pot (80% of net): **$1,516.50**

**Average per harvested plant**

* $1,516.50 / 15 = **$101.10** (before weighting)

**How it feels**

* Survivors absolutely get paid.
* But the death rate can feel brutal unless you message it as “hardcore season” or add safety mechanics.

---

# Feasibility + “worth building / worth playing” conclusions

### Why this model is attractive

Because your structure returns **72% of revenue to winners**, it’s not a stingy game. The “house edge” comes from:

* death rate (non-harvesters get nothing)
* player mistakes / neglect
* upgrades/consumables spend
* 28% total to project (10% + 18% treasury)

### What makes it “mostly worth playing”

You need **a believable player path** where:

* a normal player can harvest with good behavior
* better play improves payout (flowers/quality)
* the “jackpot” seasons exist sometimes, not always

### Recommended product strategy

Run two season types:

1. **Casual seasons** (Scenario 1–2 settings): 50–70% harvest rate
2. **Hardcore seasons** (Scenario 3 settings): 10–25% harvest rate + boosted promo from treasury

That makes it fun *and* gives your treasury a use: “boosted rewards season” creates hype without changing core rules.

---

# Quick knob targets to hit these scenarios

If you want the game to land in Scenario 1–2 most of the time:

* tune decay so a plant dies only after multiple missed care windows
* quality should be reachable: average survivor quality **75–90%**
* upgrades should help:

  * “stability” (slower decay / bigger caps) more than raw speed
  * speed increases risk (faster stage changes) to keep it balanced

---

If you want, next I can turn this into a proper “mini feasibility report” format:

* summary
* KPI targets (harvest rate, avg quality, ARPPU, retention)
* economic projections (monthly based on seasons/week)
* risk list (exploits, perception, balancing)
* recommended launch plan (testnet → season 0 free → season 1 paid)
