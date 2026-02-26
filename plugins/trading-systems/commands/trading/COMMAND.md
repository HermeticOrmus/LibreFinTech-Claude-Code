# /trading

Trading system operations: order submission, execution monitoring, OMS state management, and post-trade analysis.

## Trigger

`/trading <action> [options]`

## Actions

- `order` - Create and route a new order (single or algorithmic)
- `cancel` - Cancel an open order or replace it with new parameters
- `status` - Query order status and fill details from OMS
- `tca` - Run transaction cost analysis for a completed order or period

## Options

- `--symbol <ticker|isin>` - Instrument identifier
- `--side <buy|sell>` - Order direction
- `--quantity <int>` - Order quantity in shares/contracts
- `--order-type <market|limit|stop|ioc|fok>` - Order type
- `--price <decimal>` - Limit or stop price
- `--algo <twap|vwap|is|pov>` - Algorithmic execution strategy
- `--venue <MIC>` - Target venue MIC code (e.g., XNAS, XLON)
- `--clordid <id>` - Client order ID (for cancel/replace)
- `--from <ISO8601>` - TCA period start

## Process

### order

FIX 4.4 new order single construction and pre-trade risk validation:

```typescript
import { v4 as uuidv4 } from 'uuid';

interface NewOrderSingle {
  msgType: '35=D';
  clOrdId: string;    // Tag 11 - globally unique, never reuse
  symbol: string;     // Tag 55
  side: '1' | '2';   // Tag 54 - 1=Buy, 2=Sell
  orderQty: number;   // Tag 38
  ordType: '1' | '2' | '3' | '4';  // Tag 40 - 1=Market, 2=Limit, 3=Stop, 4=StopLimit
  price?: number;     // Tag 44 - Required for Limit/StopLimit
  stopPx?: number;    // Tag 99 - Required for Stop/StopLimit
  timeInForce: '0' | '1' | '3' | '6';  // Tag 59 - 0=Day, 1=GTC, 3=IOC, 6=GTD
  transactTime: string;  // Tag 60 - UTC timestamp
}

async function submitOrder(params: OrderParams): Promise<OrderResult> {
  // 1. Pre-trade risk checks - MUST PASS before any routing
  const riskChecks = await runPreTradeRiskChecks({
    symbol: params.symbol,
    side: params.side,
    quantity: params.quantity,
    price: params.price,
    traderId: params.traderId,
    portfolioId: params.portfolioId,
  });

  if (!riskChecks.passed) {
    throw new PreTradeRiskError(riskChecks.failedChecks);
  }

  // 2. Generate unique ClOrdID - must be unique across all time
  // Use timestamp prefix + UUID to ensure uniqueness even across system restarts
  const clOrdId = `${Date.now()}-${uuidv4().replace(/-/g, '').slice(0, 12)}`;

  // 3. Persist order BEFORE sending to exchange
  // If we crash between send and persist, we have no record of the order
  await db.order.create({
    data: {
      clOrdId,
      symbol: params.symbol,
      side: params.side,
      quantity: params.quantity,
      price: params.price,
      status: 'PENDING_NEW',
      createdAt: new Date(),
    },
  });

  // 4. Build FIX message
  const fixMsg: NewOrderSingle = {
    msgType: '35=D',
    clOrdId,
    symbol: params.symbol,
    side: params.side === 'buy' ? '1' : '2',
    orderQty: params.quantity,
    ordType: params.orderType === 'market' ? '1' : '2',
    price: params.price,
    timeInForce: '0',  // Day order
    transactTime: new Date().toISOString(),
  };

  // 5. Route via FIX session
  const fixSession = await getFixSession(params.venue);
  await fixSession.sendOrderSingle(fixMsg);

  return { clOrdId, status: 'PENDING_NEW' };
}
```

Pre-trade risk check framework:

```typescript
async function runPreTradeRiskChecks(order: OrderParams): Promise<RiskCheckResult> {
  const checks = await Promise.all([
    checkPositionLimit(order),           // Would this breach position limit?
    checkNotionalLimit(order),           // Exceeds daily notional limit?
    checkDuplicateOrder(order),          // Same symbol/side/qty in last 100ms?
    checkPriceReasonability(order),      // Price within 10% of last trade?
    checkInstrumentRestrictions(order),  // Symbol not on restricted list?
    checkTraderAuthorization(order),     // Trader approved for this instrument?
  ]);

  const failed = checks.filter(c => !c.passed);
  return { passed: failed.length === 0, failedChecks: failed };
}
```

### cancel

FIX 4.4 order cancel request (35=F):

```typescript
async function cancelOrder(
  clOrdId: string,
  reason: string,
): Promise<CancelResult> {
  const order = await db.order.findUnique({ where: { clOrdId } });

  if (!order || !['PENDING_NEW', 'NEW', 'PARTIALLY_FILLED'].includes(order.status)) {
    throw new OrderNotCancellableError(clOrdId, order?.status);
  }

  // New ClOrdID required for cancel request (FIX protocol requirement)
  const cancelClOrdId = `${Date.now()}-${uuidv4().replace(/-/g, '').slice(0, 12)}`;

  const cancelMsg = {
    msgType: '35=F',
    clOrdId: cancelClOrdId,     // Tag 11 - NEW ID for this cancel request
    origClOrdId: clOrdId,        // Tag 41 - ID of order being cancelled
    symbol: order.symbol,
    side: order.side === 'buy' ? '1' : '2',
    transactTime: new Date().toISOString(),
  };

  await db.order.update({
    where: { clOrdId },
    data: { status: 'PENDING_CANCEL' },
  });

  await fixSession.sendCancelRequest(cancelMsg);
  return { originalClOrdId: clOrdId, cancelClOrdId, status: 'PENDING_CANCEL' };
}
```

### tca

Transaction cost analysis - compare execution to benchmark:

```python
from decimal import Decimal

def analyze_execution(
    fills: list[dict],  # {timestamp, price, quantity, venue}
    arrival_mid: Decimal,     # Mid-price when order was received
    vwap_benchmark: Decimal,  # Market VWAP for the execution period
    side: str,                # 'buy' or 'sell'
) -> dict:
    """
    Implementation Shortfall = (arrival_price - avg_execution_price) * quantity
    For buys: we paid more than arrival mid (negative = bad)
    For sells: we received less than arrival mid (negative = bad)
    Express as basis points (bps) = (price diff / arrival mid) * 10000
    """
    total_qty = sum(f['quantity'] for f in fills)
    vwap_exec = sum(f['price'] * f['quantity'] for f in fills) / total_qty

    sign = -1 if side == 'buy' else 1

    implementation_shortfall_bps = (
        sign * (Decimal(str(vwap_exec)) - arrival_mid) / arrival_mid * 10000
    )
    vwap_shortfall_bps = (
        sign * (Decimal(str(vwap_exec)) - vwap_benchmark) / vwap_benchmark * 10000
    )

    return {
        'avg_execution_price': vwap_exec,
        'arrival_mid': arrival_mid,
        'market_vwap': vwap_benchmark,
        'implementation_shortfall_bps': implementation_shortfall_bps,
        'vwap_shortfall_bps': vwap_shortfall_bps,
        'total_shares': total_qty,
        'fill_rate': f"{len(fills)} fills across {len(set(f['venue'] for f in fills))} venues",
    }
```

## Examples

```bash
# Submit a 10,000-share limit buy order on Nasdaq
/trading order --symbol AAPL --side buy --quantity 10000 --order-type limit --price 185.50 --venue XNAS

# Route a large order using VWAP algo to minimize market impact
/trading order --symbol MSFT --side sell --quantity 50000 --algo vwap --from 2024-11-01T14:00:00Z

# Cancel an open order
/trading cancel --clordid 1730500000000-abc123def456

# Run TCA for all orders executed yesterday
/trading tca --from 2024-10-31 --symbol AAPL
```
