Below is a **professional-grade, institutionally aligned trading-system architecture**, presented **bottom-up**, exactly as requested.

This is not retail-EA folklore. This is how production systems are structured so they can scale, be audited, and be maintained.

---

# 1. DEPARTMENT / MODULE NAMES (BOTTOM → TOP)

### **Infrastructure Layer (Lowest Level)**

1. **Utils / Core**
2. **Market Data Layer**
3. **Symbol Management**
4. **Time & Session Control**

---

### **Risk & Control Layer**

5. **Account Manager**
6. **Risk Manager**
7. **Portfolio Manager**

---

### **Strategy Layer**

8. **Indicator Engine**
9. **Market State Engine**
10. **Trend Engine**
11. **Setup / Signal Engine**

---

### **Execution Layer**

12. **Trade Validator**
13. **Execution Engine**
14. **Position Manager**

---

### **Governance & Oversight**

15. **Logging & Audit**
16. **Configuration & Profiles**
17. **Fail-Safe / Watchdog**

---

# 2. RESPONSIBILITIES (CLEAR AND NON-OVERLAPPING)

## 1. Utils / Core

**Responsibilities**

* Math helpers
* Price normalization
* Lot rounding
* Time helpers
* Error translation
* Enum/string converters

**Rules**

* No trading logic
* No symbol awareness

---

## 2. Market Data Layer

**Responsibilities**

* Bid/Ask retrieval
* OHLC access
* Tick handling
* Bar indexing
* Data validity checks

**Consumes:** Utils
**Provides:** Clean market data

---

## 3. Symbol Management

**Responsibilities**

* Symbol discovery
* Tradability validation
* Symbol locking
* Tick size / point value normalization
* Asset-class filtering

**Does NOT**

* Decide risk
* Decide strategy

---

## 4. Time & Session Control

**Responsibilities**

* Market open/close detection
* Session filters (London/NY/Asia)
* News blackout windows
* Day-of-week rules

---

## 5. Account Manager

**Responsibilities**

* Determine account tier
* Read balance/equity
* Detect account type (cent/standard/prop)
* Expose account profile (read-only)

**Outputs**

* Tier
* Allowed aggressiveness
* Risk ceilings

---

## 6. Risk Manager

**Responsibilities**

* Position sizing
* Max risk per trade
* Stop distance validation
* Drawdown protection
* Emergency kill switch

**Consumes**

* Account Manager profile

---

## 7. Portfolio Manager

**Responsibilities**

* Track open positions
* Enforce max exposure
* Correlation limits
* Scaling permissions
* Directional caps

**Consumes**

* Risk Manager limits
* Account tier

---

## 8. Indicator Engine

**Responsibilities**

* Create indicators
* Cache handles
* Refresh values
* Timeframe abstraction

**Does NOT**

* Interpret signals

---

## 9. Market State Engine

**Responsibilities**

* Volatility state
* Range vs trend
* Liquidity condition
* Spread regime

---

## 10. Trend Engine

**Responsibilities**

* Trend direction
* Trend strength
* Trend stability
* Multi-TF alignment

**Outputs**

* UP / DOWN / NONE

---

## 11. Setup / Signal Engine

**Responsibilities**

* Pullback detection
* Breakout logic
* Mean reversion logic
* Entry readiness flags

**Consumes**

* Trend state
* Market state

---

## 12. Trade Validator

**Responsibilities**

* One-trade-per-bar logic
* Duplicate signal prevention
* Direction conflict blocking
* Timeframe throttling

**Last gate before execution**

---

## 13. Execution Engine

**Responsibilities**

* Order construction
* Order submission
* Slippage handling
* Retry logic
* Broker error handling

**Blind executor — no strategy**

---

## 14. Position Manager

**Responsibilities**

* Trailing stop logic
* Partial closes
* Break-even logic
* Exit signals
* Trade lifecycle control

---

## 15. Logging & Audit

**Responsibilities**

* Decision trace
* Execution logs
* Error reporting
* Replay support

**Required for debugging and compliance**

---

## 16. Configuration & Profiles

**Responsibilities**

* External parameters
* Tier profiles
* Strategy presets
* Environment overrides

---

## 17. Fail-Safe / Watchdog

**Responsibilities**

* Detect EA freeze
* Detect abnormal behavior
* Emergency shutdown
* Broker disconnection handling

---

# 3. FLOW OF CONTROL (END-TO-END)

```
OnTick()
│
├── Market Data Update
│
├── Time & Session Control
│
├── Symbol Manager (locked symbol)
│
├── Account Manager (read-only)
│
├── Risk Manager (limits)
│
├── Portfolio Manager (exposure check)
│
├── Indicator Engine
│
├── Market State Engine
│
├── Trend Engine
│
├── Setup / Signal Engine
│
├── Trade Validator
│
├── Execution Engine
│
└── Position Manager
```

**Control always flows downward.
No upward dependencies.**

---

# 4. PROFESSIONAL GRADE PRINCIPLES (NON-NEGOTIABLE)

### Separation of Concerns

Each department has **one job only**.

### Deterministic Decisions

No tick-level randomness or flicker.

### Idempotent Execution

Same inputs → same outputs.

### Stateless Strategy

State lives in managers, not strategy logic.

### Defensive Programming

Every external call validated.

### Auditability

Every decision explainable via logs.

---

# 5. WHY THIS MATTERS FOR YOU (SPECIFICALLY)

This structure will:

* Fix your trend detection inconsistency
* Eliminate duplicate entries
* Prevent wrong-symbol execution
* Make scaling logic safe
* Allow future expansion (multi-symbol, prop rules)
* Make debugging **obvious instead of painful**

Most retail EAs collapse because they skip layers 5–7 and mash logic together.

You are now past that level.

---

## NEXT STEP OPTIONS

If you want, next I can:

1. Map your **current files** into this architecture
2. Provide a **folder + file structure** (`.mqh`)
3. Write a **clean skeleton EA** with these departments
4. Refactor your current executor into this flow
5. Create a **gold-specific Account + Risk profile**

Tell me which one you want to do next.
