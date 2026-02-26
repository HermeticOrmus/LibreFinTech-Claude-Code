# /fraud-detect

Real-time fraud scoring, rule analysis, model tuning, and fraud reporting. Covers transaction risk scoring, feature vector inspection, rule evaluation, and false-positive/negative analysis.

## Trigger

`/fraud-detect <action> [options]`

## Actions

- `score` - Score a transaction or batch of transactions against current rules and model
- `analyze` - Explain fraud score breakdown for a specific transaction
- `tune-rules` - Evaluate and suggest improvements to rule engine configuration
- `report` - Generate fraud metrics report (fraud rate, FPR, chargeback analysis)

## Options

- `--transaction-id <id>` - Specific transaction to analyze
- `--batch-file <path>` - CSV of transactions for batch scoring
- `--threshold <float>` - Decision threshold (0.0-1.0) for score/approve cutoff
- `--period <YYYY-MM>` - Reporting period
- `--segment <card-present|card-not-present|ach|wire>` - Payment segment

## Process

### score

Real-time fraud scoring pipeline. Must complete end-to-end in <100ms.

```typescript
interface TransactionContext {
  transactionId: string;
  amount: Decimal;
  currency: string;
  merchantId: string;
  merchantCategory: string;     // MCC code
  cardId: string;
  cardholderCountry: string;
  transactionCountry: string;
  deviceFingerprint: string;
  ipAddress: string;
  timestamp: Date;
}

interface FraudScore {
  transactionId: string;
  score: number;           // 0.0 (clean) to 1.0 (certain fraud)
  decision: 'APPROVE' | 'CHALLENGE' | 'DECLINE';
  triggeredRules: string[];
  topFeatures: Array<{ feature: string; contribution: number }>;
  latencyMs: number;
}

async function scoreTransaction(ctx: TransactionContext): Promise<FraudScore> {
  const start = performance.now();

  // Parallel feature computation
  const [velocityFeatures, deviceFeatures, historicalFeatures, networkFeatures] =
    await Promise.all([
      computeVelocityFeatures(ctx),   // Redis lookups: counts in 1m/5m/1h/24h windows
      computeDeviceFeatures(ctx),      // Device fingerprint, IP reputation
      computeHistoricalFeatures(ctx),  // Cardholder baseline from feature store
      computeNetworkFeatures(ctx),     // Graph features: connected fraud nodes
    ]);

  const featureVector = {
    ...velocityFeatures,
    ...deviceFeatures,
    ...historicalFeatures,
    ...networkFeatures,

    // Real-time features (computed inline, no store needed)
    amount_log: Math.log(ctx.amount.toNumber() + 1),
    is_cross_border: ctx.cardholderCountry !== ctx.transactionCountry ? 1 : 0,
    hour_of_day: ctx.timestamp.getHours(),
    day_of_week: ctx.timestamp.getDay(),
  };

  // Rule engine evaluation (fast, deterministic)
  const ruleResults = await ruleEngine.evaluate(featureVector, ctx);

  // Hard block rules short-circuit before ML
  const hardBlock = ruleResults.find(r => r.action === 'DECLINE' && r.hardBlock);
  if (hardBlock) {
    return { ...buildScore(1.0, 'DECLINE', [hardBlock.ruleId], []), latencyMs: performance.now() - start };
  }

  // ML model inference (ONNX Runtime, typically 5-20ms)
  const mlScore = await fraudModel.predict(featureVector);

  // Combine rule scores and ML score
  const finalScore = combineScores(ruleResults, mlScore);
  const decision = getDecision(finalScore);

  return {
    transactionId: ctx.transactionId,
    score: finalScore,
    decision,
    triggeredRules: ruleResults.filter(r => r.triggered).map(r => r.ruleId),
    topFeatures: getTopFeatureContributions(featureVector, mlScore),
    latencyMs: performance.now() - start,
  };
}
```

### analyze

SHAP (SHapley Additive exPlanations) values explain model decisions:

```python
import shap
import pandas as pd

# Explain why a specific transaction was scored high
explainer = shap.TreeExplainer(fraud_model)
feature_vector = get_feature_vector(transaction_id)
shap_values = explainer.shap_values(feature_vector)

# Top contributing features
feature_importance = pd.DataFrame({
    'feature': feature_names,
    'shap_value': shap_values[0],
    'absolute_contribution': abs(shap_values[0])
}).sort_values('absolute_contribution', ascending=False)

print(feature_importance.head(10))
# Example output:
# feature                           shap_value  absolute_contribution
# tx_count_1min                         +0.312              0.312
# ip_is_vpn                             +0.287              0.287
# amount_vs_cardholder_mean_zscore      +0.241              0.241
# device_age_days                       -0.183              0.183
# merchant_fraud_rate_30d               +0.165              0.165
```

### tune-rules

Evaluate rule effectiveness on historical data:

```python
# Calculate precision/recall for each rule
rule_analysis = []
for rule in rule_engine.get_all_rules():
    triggered = historical_txns[historical_txns['triggered_rules'].apply(lambda r: rule.id in r)]
    true_fraud = triggered[triggered['is_fraud'] == 1]

    precision = len(true_fraud) / len(triggered) if len(triggered) > 0 else 0
    recall = len(true_fraud) / total_fraud_count
    # False positive cost: avg transaction value * 1-precision
    # False negative cost: avg fraud loss * (1-recall)

    rule_analysis.append({
        'rule_id': rule.id,
        'triggers_per_day': len(triggered) / analysis_days,
        'precision': precision,
        'recall': recall,
        'estimated_daily_fp_cost': len(triggered) * (1 - precision) * avg_txn_value / analysis_days,
    })
```

### report

Key metrics for fraud ops:

- **Fraud rate**: Fraud transactions / Total transactions (target: <0.1% for card-not-present)
- **False positive rate**: Declined legitimate / Total legitimate (target: <1%)
- **Chargeback rate**: Chargebacks / Total transactions (Visa VAMP threshold: 1%)
- **Fraud loss rate**: Total fraud losses / Total GMV
- **Rule efficacy**: Precision/recall per rule

## Examples

```bash
# Score a single transaction
/fraud-detect score --transaction-id TXN-001234

# Explain why transaction was declined
/fraud-detect analyze --transaction-id TXN-001234

# Analyze rule effectiveness for card-not-present segment
/fraud-detect tune-rules --segment card-not-present --period 2024-11

# Monthly fraud metrics report
/fraud-detect report --period 2024-11 --segment card-not-present
```
