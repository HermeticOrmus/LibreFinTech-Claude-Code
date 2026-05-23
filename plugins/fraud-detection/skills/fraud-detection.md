# Fraud detection pattern library

## Signal strength matrix

| Signal | False positive risk | False negative risk | Implementation cost |
|---|---|---|---|
| CVV mismatch | Low | High (fraudsters often know CVV) | Free (provider returns it) |
| AVS mismatch (street + ZIP) | Low | Medium | Free |
| BIN country mismatch | Medium (travelers) | Low | Free |
| Device fingerprint | Low | Medium | Per-vendor cost (FingerprintJS, etc.) |
| Velocity (per device) | Low | Low | Application code |
| Velocity (per IP) | Medium (NATs) | Low | Application code |
| Email domain | Medium | High (real emails used too) | Application code |
| Customer behavioral baseline | Low (when ample history) | Medium | Requires training data |
| Geolocation vs. address | Medium (VPNs, travel) | Medium | Free (from IP) |
| 3DS challenge | Low | Low | Provider supports |
| ML score | Variable | Variable | Provider built-in or custom |

## Common rule patterns

### Velocity by device

```python
def velocity_device(tx, history):
    recent = history.tx_count_for_device(tx.device_id, hours=1)
    if recent > 10: return "DECLINE"
    if recent > 5: return "STEP_UP"
    return "ALLOW"
```

### BIN mismatch with amount threshold

```python
def bin_check(tx, customer):
    if tx.bin_country != customer.country:
        if tx.amount > 50000: return "DECLINE"
        return "STEP_UP"
    return "ALLOW"
```

### Velocity by email pattern (catching disposable)

```python
def disposable_email(tx):
    if tx.email_domain in DISPOSABLE_DOMAINS:
        if tx.amount > 10000: return "DECLINE"
        return "STEP_UP"
    return "ALLOW"
```

### Behavioral baseline deviation

```python
def baseline_deviation(tx, customer):
    avg = customer.average_tx_amount or 0
    if avg > 0 and tx.amount > avg * 5:
        return "STEP_UP"
    return "ALLOW"
```

## Threshold calibration

```
Total cost = (FP rate) × LTV + (FN rate) × (chargeback + dispute fee)

Optimal threshold minimizes total cost.
```

Plot the ROC curve (FP rate vs. FN rate). The operating point depends on cost asymmetry:

- High-LTV customer: shift toward fewer FPs
- Low-margin transactions with cheap refunds: shift toward fewer FNs

## Provider comparison

| Provider | Strengths | Weaknesses |
|---|---|---|
| **Stripe Radar** | Built into Stripe; large training data; out-of-box rules | Limited customization for non-Stripe stacks |
| **Adyen RevenueProtect** | Strong multi-region; integrates with their orchestration | Adyen-only |
| **Sift** | Cross-customer training data; rule engine + ML | Per-transaction cost; vendor lock-in |
| **Sardine** | Real-time API; identity + fraud combined | Newer; less battle-tested at scale |
| **Custom ML** | Full control; tuned to your business | Requires ML team; cold-start hard |

## Dispute defense evidence checklist

For every dispute, file:

- [ ] Receipt URL
- [ ] Customer email (matches the charge's billing email)
- [ ] IP at purchase (matches expected geolocation)
- [ ] 3DS authentication result (if applicable)
- [ ] Prior transaction history (count + success rate)
- [ ] Customer service interactions (if any)
- [ ] Shipping (if physical): tracking, carrier, date, delivery confirmation
- [ ] T&Cs and refund policy URL
- [ ] Anything else specific to dispute reason

Win rate correlates with completeness of evidence.

## Common mistakes catalog

### "Fraud rate dropped to zero"

Suspicious. Either you're over-blocking (and losing legitimate transactions) or your measurement is wrong. Audit FP rate.

### "Chargebacks climbed after we shipped"

Likely: under-detection. Check:

- Did you ship in a new geography with different fraud patterns?
- Did your detection logic miss a new attack pattern (synthetic identity, etc.)?
- Did a third-party tool change its API without notice?

### "Disputes auto-lost because we didn't respond"

Build a dispute response queue. Webhook → ticket → file evidence within window.

### "Legitimate customers complain about 3DS"

3DS friction is real. Use 3DS strategically:

- Mandatory in EU (PSD2)
- Step-up for borderline signals elsewhere
- Don't blanket-apply to every transaction

### "ML model performance degraded"

Retrain. Fraud patterns shift. Monthly retraining is standard for active fraud surfaces.

## Cross-references

- [`payment-processing`](../payment-processing/) — for pre-payment screening
- [`kyc-aml`](../kyc-aml/) — identity verification (KYC) is distinct from fraud detection
- [`risk-management`](../risk-management/) — for broader risk frameworks
- [`audit-trails`](../audit-trails/) — for fraud-decision audit trail
