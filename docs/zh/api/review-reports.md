# 审核报告 API

## 获取审核报告（JSON）

返回聚合的审核统计数据和最近的审核记录。

```http
GET /reviews/report
Authorization: Bearer <token>
```

### 响应

```json
{
  "generated_at": "2026-05-22 06:00:00 UTC",
  "stats": {
    "total_citations": 20,
    "approved": 12,
    "rejected": 3,
    "flagged": 2,
    "pending": 1,
    "unreviewed": 2
  },
  "approval_rate": 66.67,
  "rejection_rate": 16.67,
  "hallucination_rate": 27.78,
  "review_coverage": 90.0,
  "recent_reviews": [...]
}
```

### 指标说明

| 字段 | 说明 |
|------|------|
| `approval_rate` | 通过率 = 通过数 / 已审核总数 × 100 |
| `rejection_rate` | 拒绝率 = 拒绝数 / 已审核总数 × 100 |
| `hallucination_rate` | 幻觉率 = (拒绝 + 存疑) / 已审核总数 × 100 |
| `review_coverage` | 审核覆盖率 = 已审核数 / 总引用数 × 100 |

## 获取审核报告（Markdown）

返回预格式化的 Markdown 报告字符串。

```http
GET /reviews/report/markdown
Authorization: Bearer <token>
```

响应为纯文本 Markdown，包含概览表格、审核结果分布、关键指标和详细审核记录。
