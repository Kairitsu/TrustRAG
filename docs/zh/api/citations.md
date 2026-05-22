# 引用与审核

## 获取消息的引用

```http
GET /messages/{message_id}/citations
Authorization: Bearer <token>
```

### 响应

```json
[
  {
    "id": "uuid",
    "message_id": "uuid",
    "document_id": "uuid",
    "chunk_id": "uuid",
    "citation_index": 1,
    "quoted_text": "引用的原始文本...",
    "page_number": 5,
    "heading_path": "第一章 > 引言",
    "relevance_score": 0.92,
    "verified": 1,
    "created_at": "2026-05-22T06:00:00Z"
  }
]
```

## 提交审核

```http
POST /citations/{citation_id}/reviews
Authorization: Bearer <token>
Content-Type: application/json

{"status": "approved", "comment": "与原文档核实一致"}
```

### 请求参数

| 字段 | 类型 | 必填 | 说明 |
|------|------|------|------|
| `status` | string | 是 | approved / rejected / flagged / pending |
| `comment` | string | 否 | 审核备注 |
| `corrected_text` | string | 否 | 修正后的引用文本 |

引用被通过时，`verified` 标记为 `true`；被拒绝或标记存疑时，设为 `false`。

## 审核历史

```http
GET /citations/{citation_id}/reviews
Authorization: Bearer <token>
```

返回指定引用的所有审核记录，按创建时间降序排列。

## 全局审核列表

```http
GET /reviews?limit=50&offset=0
Authorization: Bearer <token>
```

分页返回所有审核记录，最大 limit 为 200。

## 对话审核统计

```http
GET /conversations/{conv_id}/review-stats
Authorization: Bearer <token>
```

返回指定对话的审核统计：

```json
{
  "total_citations": 20,
  "approved": 12,
  "rejected": 3,
  "flagged": 2,
  "pending": 1,
  "unreviewed": 2
}
```

另见：[审核报告 API](/zh/api/review-reports) 获取综合报告。
