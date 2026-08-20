# 知数（FinSight）Domain Model（Phase 0）

## 关系

```
User 1──* Account 1──* Transaction
User 1──* Debt 1──* DebtEvent
User 1──* Debt 1──* RepaymentPlan
Transaction *──? Debt          (relatedDebtId，可选)
Transaction *──1 Account
User 1──* Asset | Budget | Goal | Subscription | FinancialInsight
```

## 权威事实 vs 派生

| 数据 | 性质 |
|------|------|
| Transaction | 权威事实 |
| Account.openingBalance | 权威事实（期初） |
| Account 当前余额 | **派生**：opening + transactions |
| Debt.outstandingBalance | 跟踪余额，应由 DebtEvent 重放更新 |
| 总负债 | **派生**：对 Debt 聚合 |
| FinancialInsight | 结论缓存，必须带 source*Ids |

## 金额

一律使用 `Money`（`Decimal` + `currencyCode`），禁止用 `Double` 做账。
