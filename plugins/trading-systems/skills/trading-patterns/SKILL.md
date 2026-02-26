# Trading System Patterns

Domain-specific patterns for order management, FIX protocol integration, matching engines, and algorithmic execution.

## Core Patterns

### Pattern: Idempotent Order State Machine

```typescript
// Order state transitions must be idempotent - receiving the same execution report twice
// (exchange retransmission) must not double-fill or create incorrect state

type OrdStatus = 'PENDING_NEW' | 'NEW' | 'PARTIALLY_FILLED' | 'FILLED' | 'CANCELLED' | 'REJECTED';

const VALID_TRANSITIONS: Record<OrdStatus, OrdStatus[]> = {
  PENDING_NEW:      ['NEW', 'REJECTED'],
  NEW:              ['PARTIALLY_FILLED', 'FILLED', 'CANCELLED'],
  PARTIALLY_FILLED: ['PARTIALLY_FILLED', 'FILLED', 'CANCELLED'],
  FILLED:           [],  // Terminal - no further transitions
  CANCELLED:        [],  // Terminal
  REJECTED:         [],  // Terminal
};

async function processExecutionReport(execReport: FIXExecutionReport): Promise<void> {
  const clOrdId = execReport.tag11_clOrdId;

  // Idempotency: check if this execution report already processed
  const execId = execReport.tag17_execId;
  const alreadyProcessed = await db.executionReport.findUnique({ where: { execId } });
  if (alreadyProcessed) return;  // Duplicate - exchange retransmission

  const order = await db.order.findUnique({ where: { clOrdId } });
  const newStatus = mapFIXOrdStatusToInternal(execReport.tag39_ordStatus);

  // Validate state transition
  if (!VALID_TRANSITIONS[order.status].includes(newStatus)) {
    await db.orderStateError.create({
      data: {
        clOrdId, currentStatus: order.status, attemptedStatus: newStatus,
        execId, message: 'Invalid state transition from execution report',
      },
    });
    return;  // Do not apply invalid transition
  }

  // Atomic: persist execution report and update order state together
  await db.$transaction([
    db.executionReport.create({
      data: { execId, clOrdId, ordStatus: newStatus, lastPx: execReport.tag31,
              lastQty: execReport.tag32, cumQty: execReport.tag14, leavesQty: execReport.tag151 },
    }),
    db.order.update({
      where: { clOrdId },
      data: {
        status: newStatus,
        cumQty: execReport.tag14,
        leavesQty: execReport.tag151,
        avgPx: execReport.tag6,
      },
    }),
  ]);

  if (newStatus === 'FILLED') {
    await updatePositions(order.portfolioId, order.symbol, order.side, execReport.tag14);
  }
}
```

### Pattern: VWAP Algorithm Execution

```python
import pandas as pd
from decimal import Decimal
from datetime import datetime, timedelta

def generate_vwap_schedule(
    total_quantity: int,
    symbol: str,
    start_time: datetime,
    end_time: datetime,
    volume_curve: pd.Series,   # Index: time buckets, values: % of daily volume
) -> list[dict]:
    """
    VWAP: slice order proportionally to historical volume distribution.
    Volume concentrates at open and close (U-shaped curve for equities).
    By following the curve, participation rate stays constant = market impact constant.
    """
    # Filter volume curve to execution window
    period_curve = volume_curve.between_time(
        start_time.strftime('%H:%M'),
        end_time.strftime('%H:%M')
    )
    # Normalize to sum to 100%
    normalized_curve = period_curve / period_curve.sum()

    slices = []
    remaining = total_quantity

    for time_bucket, pct_of_volume in normalized_curve.items():
        # Quantity for this bucket (round to lot size)
        bucket_qty = int(total_quantity * pct_of_volume)
        bucket_qty = max(1, bucket_qty)  # Minimum 1 share per bucket
        bucket_qty = min(bucket_qty, remaining)

        slices.append({
            'time': time_bucket,
            'quantity': bucket_qty,
            'pct_of_volume': float(pct_of_volume),
            'cumulative_pct': sum(s['quantity'] for s in slices) / total_quantity,
        })

        remaining -= bucket_qty
        if remaining <= 0:
            break

    # Assign any rounding remainder to largest bucket
    if remaining > 0:
        largest = max(slices, key=lambda s: s['quantity'])
        largest['quantity'] += remaining

    return slices
```

### Pattern: Price-Time Priority Order Book

```python
from sortedcontainers import SortedDict
from collections import deque
from decimal import Decimal

class OrderBook:
    """
    Price-time priority matching engine.
    Bids: sorted descending (best bid = highest price)
    Asks: sorted ascending (best ask = lowest price)

    SortedDict provides O(log n) insert/delete/lookup.
    Each price level holds a deque (FIFO queue) of orders.
    """
    def __init__(self, symbol: str):
        self.symbol = symbol
        # SortedDict with negated key for bids (descending sort trick)
        self.bids: SortedDict[Decimal, deque] = SortedDict(lambda k: -k)
        self.asks: SortedDict[Decimal, deque] = SortedDict()
        self.orders: dict[str, dict] = {}  # clOrdId -> order details

    def add_limit_order(self, order: dict) -> list[dict]:
        """Returns list of trades (fills) generated."""
        fills = []
        remaining = order['quantity']

        # Try to match against opposite side
        opposite = self.bids if order['side'] == 'sell' else self.asks
        for price, queue in list(opposite.items()):
            # Check if prices cross
            if order['side'] == 'buy' and price > order['price']:
                break
            if order['side'] == 'sell' and price < order['price']:
                break

            while queue and remaining > 0:
                resting = queue[0]
                fill_qty = min(remaining, resting['quantity'])
                fills.append({
                    'aggressor_clord_id': order['clOrdId'],
                    'resting_clord_id': resting['clOrdId'],
                    'price': price,
                    'quantity': fill_qty,
                })
                resting['quantity'] -= fill_qty
                remaining -= fill_qty
                if resting['quantity'] == 0:
                    queue.popleft()
                    del self.orders[resting['clOrdId']]

            if not queue:
                del opposite[price]

        # Add unfilled remainder to book
        if remaining > 0:
            order['quantity'] = remaining
            side_book = self.bids if order['side'] == 'buy' else self.asks
            if order['price'] not in side_book:
                side_book[order['price']] = deque()
            side_book[order['price']].append(order)
            self.orders[order['clOrdId']] = order

        return fills
```

### Pattern: FIX Session Sequence Number Recovery

```typescript
// FIX sessions use sequence numbers. Must not skip.
// On reconnect, exchange requires sequence number gap resolution.

interface FIXSessionState {
  senderCompId: string;
  targetCompId: string;
  nextSenderSeqNum: number;   // My next outgoing sequence number
  nextTargetSeqNum: number;   // Expected next incoming sequence number
}

async function recoverFIXSession(
  state: FIXSessionState,
  exchangeReportedSeqNum: number,  // From Logon response (tag 34)
): Promise<void> {
  if (exchangeReportedSeqNum > state.nextTargetSeqNum) {
    // Gap detected: exchange has messages we didn't receive
    // Send ResendRequest (35=2) to request retransmission
    await sendResendRequest({
      beginSeqNo: state.nextTargetSeqNum,
      endSeqNo: 0,  // 0 = "all messages up to now"
    });
  } else if (exchangeReportedSeqNum < state.nextTargetSeqNum) {
    // Exchange sequence is behind: they may have reset
    // This is abnormal - requires investigation
    await alertOperations({
      message: `FIX sequence number discrepancy: expected ${state.nextTargetSeqNum}, got ${exchangeReportedSeqNum}`,
      severity: 'CRITICAL',
    });
    // Do NOT silently accept lower sequence - could miss fills
  }
}
```

## Anti-Patterns

### Anti-Pattern: Reusing ClOrdID

```typescript
// WRONG: Increment a counter for ClOrdID
let orderId = 1;
function nextClOrdId() { return `ORDER-${++orderId}`; }
// After system restart, counter resets to 1
// ORDER-1 already used - exchange REJECTS with duplicate order error
// Or worse: exchange accepts it and you now have position uncertainty

// RIGHT: Include persistent monotonic component
function generateClOrdId(): string {
  // Unix milliseconds + random suffix ensures uniqueness across restarts
  return `${Date.now()}-${Math.random().toString(36).slice(2, 14)}`;
  // Or use UUID v4: import { v4 as uuidv4 } from 'uuid'; return uuidv4();
}
```

### Anti-Pattern: Processing Fills Without Position Update Atomicity

```typescript
// WRONG: Update OMS order status, then update positions separately
// A crash between these two creates position vs OMS inconsistency
await db.order.update({ where: { id }, data: { status: 'FILLED', avgPx: price } });
// CRASH HERE -> order shows FILLED but position not updated -> short on the book
await db.position.update({ where: { symbol }, data: { quantity: { increment: qty } } });

// RIGHT: Atomic transaction - both updates succeed or both fail
await db.$transaction([
  db.order.update({ where: { id }, data: { status: 'FILLED', avgPx: price } }),
  db.position.update({ where: { symbol }, data: { quantity: { increment: qty } } }),
  db.executionReport.create({ data: { orderId: id, price, qty, executedAt: new Date() } }),
]);
```

### Anti-Pattern: Skipping Pre-Trade Risk Checks for Speed

```
WRONG: "Pre-trade checks add 2ms latency, disable for high-frequency flow"
- A runaway algorithm without checks can place millions of orders in seconds
- Knight Capital (2012): Software bug bypassed risk checks -> $440M loss in 45 minutes
- FINRA/SEC pre-trade risk controls are MANDATORY under Reg SCI and FINRA Rule 15c3-5

RIGHT: Optimize checks, don't remove them
- Cache position data in memory (Redis or in-process) for sub-millisecond lookup
- Use circuit breakers: halt after N orders/second or M orders/minute
- Test kill switch weekly: can you halt all trading in under 1 second?
- Pre-trade checks must run in < 500 microseconds for most latency budgets
```

## References

- **FIX Protocol Specification**: https://www.fixtrading.org/standards/
- **FIX 4.4 Tag Definitions**: https://www.onixs.biz/fix-dictionary/4.4/
- **QuickFIX/n (C#/.NET FIX engine)**: https://quickfixn.org/
- **QuickFIX/J (Java)**: https://www.quickfixj.org/
- **Reg NMS (SEC)**: https://www.sec.gov/rules/final/34-51808.pdf
- **FINRA Rule 15c3-5 (Market Access Rule)**: https://www.finra.org/rules-guidance/rulebooks/finra-rules/15c3-5
- **MiFID II RTS 27/28**: https://www.esma.europa.eu/policy-rules/mifid-ii-and-mifir
- **Almgren & Chriss (2000)**: "Optimal Execution of Portfolio Transactions" - Jounal of Risk
- **Knight Capital incident (SEC)**: https://www.sec.gov/litigation/admin/2013/34-70694.pdf
- **SortedContainers (Python)**: https://grantjenks.com/docs/sortedcontainers/ (for order book implementation)
