请基于以下事实与确定性风险评估，生成本月财务总结。



## financial_context



{{.FinancialContextJSON}}



## monthly_summary_facts



{{.MonthlySummaryFactsJSON}}



## financial_risk_assessment



{{.FinancialRiskAssessmentJSON}}



## allowed_amount_keys



{{.AllowedAmountKeysJSON}}



## allowed_fact_keys



{{.AllowedFactKeysJSON}}



## allowed_reference_keys



{{.AllowedReferenceKeysJSON}}



## expected_output_schema



{{.OutputSchemaJSON}}



## task



基于以上事实与 financial_risk_assessment 中已确定的结论，用简洁中文解释用户本月财务状况。



输出优先级：schema → authoritative assessment → 每个 signal exactly once → exact reasonCode → 每个 required unknown exactly once → registered facts → narrative。



- body 与 answer 应语义一致

- citedFactKeys 只能来自 allowed_amount_keys 与 allowed_fact_keys

- references 只能来自 allowed_reference_keys（fact-backed key 须 fact present；navigation key 如 cashFlow30/debt/transactions/accounts 始终允许）

- riskExplanations：`financial_risk_assessment.signals` 是 authoritative explanation worklist；每个 warning/risk signal 必须恰好一条；reasonCode 必须与 signal.reasonCode 完全一致且保留 machine value；只输出 reasonCode 与 text（citations 由系统注入）；正文已提到该风险也不能省略 structured explanation

- partial 只限制未提供的完整领域结论，不使已 supplied signal 失效；debtDataState=partial 时仍必须覆盖所有 supplied signals

- debtDataState=knownNoDebt 时不得暗示用户当前承担债务或建议偿还现有债务；语义约束而非字面词组禁用

- unknownExplanations：与 requiredUnknownReasonCodes 完全一致；无 required unknown 时必须为空数组

- 不要输出 warnings 或 actions

- confidence 必须是 JSON number（0 到 1）

- keyFacts 中 type=money 的 amount 必须是 JSON number
