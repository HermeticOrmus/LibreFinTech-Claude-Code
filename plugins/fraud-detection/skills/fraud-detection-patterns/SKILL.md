# Fraud Detection Patterns

Domain-specific patterns for real-time fraud scoring, feature engineering, rule engine design, model feedback loops, and false positive management.

## Core Patterns

### Pattern: Velocity Feature Computation with Redis

Velocity counts are the most powerful and fastest-to-compute fraud signals. Store in Redis sorted sets for sub-millisecond window queries.

```typescript
class VelocityCounter {
  constructor(private redis: Redis) {}

  // Increment counter for a key (e.g., card, device, IP) and get counts for multiple windows
  async incrementAndGet(
    key: string,
    timestampMs: number,
    windows: number[] = [60, 300, 3600, 86400]  // 1min, 5min, 1hr, 24hr in seconds
  ): Promise<Record<number, number>> {
    const pipeline = this.redis.pipeline();
    const member = `${timestampMs}:${Math.random()}`; // Unique member for this event

    // Add to sorted set with score = timestamp
    pipeline.zadd(key, timestampMs, member);
    pipeline.expire(key, Math.max(...windows) + 60); // Auto-expire

    // Remove old entries and count for each window
    for (const windowSec of windows) {
      const windowStart = timestampMs - windowSec * 1000;
      pipeline.zremrangebyscore(key, 0, windowStart);
      pipeline.zcount(key, windowStart, timestampMs);
    }

    const results = await pipeline.exec();
    const counts: Record<number, number> = {};

    windows.forEach((window, i) => {
      counts[window] = results[3 + i * 2 + 1][1] as number;
    });

    return counts;
  }
}

// Usage in scoring
const cardVelocity = await velocityCounter.incrementAndGet(
  `velocity:card:${cardId}`,
  Date.now()
);
// cardVelocity[60] = count in last 1 minute
// cardVelocity[86400] = count in last 24 hours
```

### Pattern: Impossible Travel Detection

```typescript
interface GeolocationEvent {
  cardId: string;
  latitude: number;
  longitude: number;
  timestamp: Date;
}

const MAX_HUMAN_SPEED_KMH = 900; // ~max commercial flight speed

async function detectImpossibleTravel(
  current: GeolocationEvent
): Promise<{ isImpossible: boolean; speedKmh: number }> {
  const previous = await redis.get<GeolocationEvent>(`last-location:${current.cardId}`);

  if (!previous) {
    await redis.set(`last-location:${current.cardId}`, current, { ex: 86400 });
    return { isImpossible: false, speedKmh: 0 };
  }

  const distanceKm = haversineDistance(
    previous.latitude, previous.longitude,
    current.latitude, current.longitude
  );
  const timeDiffHours = (current.timestamp.getTime() - previous.timestamp.getTime()) / 3600000;

  if (timeDiffHours < 0.001) return { isImpossible: distanceKm > 1, speedKmh: Infinity };

  const speedKmh = distanceKm / timeDiffHours;
  const isImpossible = speedKmh > MAX_HUMAN_SPEED_KMH;

  await redis.set(`last-location:${current.cardId}`, current, { ex: 86400 });

  return { isImpossible, speedKmh };
}
```

### Pattern: Rule Engine with Explainable Results

```typescript
interface FraudRule {
  id: string;
  name: string;
  description: string;
  condition: (features: FeatureVector, ctx: TransactionContext) => boolean;
  action: 'DECLINE' | 'CHALLENGE' | 'FLAG';
  hardBlock: boolean;  // Hard blocks skip ML scoring
  score: number;       // Contribution to final score if triggered
}

const rules: FraudRule[] = [
  {
    id: 'VELOCITY_1MIN_CARD',
    name: 'High card velocity - 1 minute',
    description: 'More than 3 transactions on same card in 1 minute',
    condition: (f) => f.card_tx_count_1min > 3,
    action: 'DECLINE',
    hardBlock: true,
    score: 1.0,
  },
  {
    id: 'IMPOSSIBLE_TRAVEL',
    name: 'Impossible travel velocity',
    description: 'Transaction location requires >900 km/h travel from previous',
    condition: (f) => f.travel_speed_kmh > 900,
    action: 'DECLINE',
    hardBlock: true,
    score: 1.0,
  },
  {
    id: 'VPN_HIGH_AMOUNT',
    name: 'VPN with high transaction amount',
    description: 'Transaction from VPN/proxy with amount > $500',
    condition: (f, ctx) => f.ip_is_vpn === 1 && ctx.amount.greaterThan(500),
    action: 'CHALLENGE',
    hardBlock: false,
    score: 0.4,
  },
];
```

### Pattern: Model Feedback Loop

```python
# Label transactions as fraud/legitimate based on chargebacks and investigations
# Chargebacks lag by 60-120 days - account for this in training data cutoff

def prepare_training_data(start_date, end_date):
    # Use temporal train/test split - NEVER random split for fraud
    # Random split allows future data to leak into training
    transactions = db.query("""
        SELECT t.*,
               COALESCE(c.is_fraud, 0) AS label
        FROM transactions t
        LEFT JOIN chargebacks c ON c.transaction_id = t.id
        WHERE t.created_at BETWEEN :start AND :end
        -- Exclude last 90 days - chargebacks not yet resolved
        AND t.created_at < NOW() - INTERVAL '90 days'
    """, start=start_date, end=end_date)

    # Class imbalance: fraud is typically 0.1-0.5% of transactions
    # Use class weights or SMOTE for minority class
    fraud_weight = (1 - fraud_rate) / fraud_rate  # Approx 200-1000x for 0.1% fraud

    return transactions, fraud_weight
```

## Anti-Patterns

### Anti-Pattern: High False Positive Rate Blocking Legitimate Users

Rule: "Block all transactions from IP addresses in high-risk countries" - this blocks many legitimate travelers and immigrants, creates massive customer service burden, and often gets reversed anyway after user complaint. Use it as a signal (raise score), not a hard block.

```typescript
// WRONG: Hard block on country
if (HIGH_RISK_COUNTRIES.includes(transactionCountry)) {
  return { decision: 'DECLINE' }; // Blocks many legitimate users
}

// RIGHT: Use as risk signal, let composite score decide
const countryRiskScore = HIGH_RISK_COUNTRIES.includes(transactionCountry) ? 0.3 : 0;
featureVector.country_risk = countryRiskScore;
// Score combines with other signals - borderline transactions might still pass
```

### Anti-Pattern: Static Rules Without ML

Static rule-based systems are gamed within days of deployment. Fraudsters probe the rules (small transactions to find thresholds, test cards, VPN rotation). ML models adapt and are harder to probe systematically.

### Anti-Pattern: No Feedback Loop

A fraud model without labeled feedback will drift. Confirmed fraud (chargebacks) and confirmed legitimate (representments won, no chargeback) must feed back to re-training. Without this, model accuracy degrades 5-15% per quarter as fraud patterns evolve.

### Anti-Pattern: Model Drift Without Monitoring

```python
# Monitor feature distribution shift with Population Stability Index (PSI)
def calculate_psi(expected, actual, buckets=10):
    expected_percents = np.histogram(expected, bins=buckets)[0] / len(expected)
    actual_percents = np.histogram(actual, bins=buckets)[0] / len(actual)

    psi = np.sum(
        (actual_percents - expected_percents) *
        np.log(actual_percents / (expected_percents + 1e-10) + 1e-10)
    )
    # PSI < 0.1: no significant change
    # PSI 0.1-0.25: some change, investigate
    # PSI > 0.25: significant change, retrain model
    return psi
```

## References

- **FICO Score**: https://www.fico.com/en/products/fico-falcon-fraud-manager
- **3DS2 Specification**: https://www.emvco.com/emv-technologies/3-d-secure/
- **Visa VAMP Program**: https://usa.visa.com/dam/VCOM/global/support-legal/documents/chargeback-management-guidelines.pdf
- **SHAP Library**: https://shap.readthedocs.io/
- **Scikit-learn Fraud Detection**: https://scikit-learn.org/stable/auto_examples/applications/plot_outlier_detection_wine.html
- **Stripe Radar (ML fraud)**: https://stripe.com/radar
- **Featureform (Feature Store)**: https://www.featureform.com/
