# 知识图谱 API

## 获取知识图谱

返回工作区的完整图谱数据（节点 + 边）。

```http
GET /workspaces/{ws_id}/knowledge-graph
Authorization: Bearer <token>
```

### 响应

```json
{
  "nodes": [
    {
      "id": "uuid",
      "label": "机器学习",
      "entity_type": "concept",
      "document_id": "uuid"
    }
  ],
  "edges": [
    {
      "source": "node-uuid-1",
      "target": "node-uuid-2",
      "relation": "related_to",
      "weight": 0.85
    }
  ]
}
```

## 获取实体列表

返回工作区的实体列表，按创建时间降序排列，最多 200 条。

```http
GET /workspaces/{ws_id}/knowledge-graph/entities
Authorization: Bearer <token>
```

### 响应

```json
[
  {
    "id": "uuid",
    "name": "TrustRAG",
    "entity_type": "technology",
    "document_id": "uuid",
    "metadata": { "aliases": ["TRAG"] },
    "created_at": "2026-05-22T06:00:00Z"
  }
]
```

## 访问控制

两个接口都需要工作区访问权限。用户可以访问：
- 自己拥有的工作区
- 作为成员加入的工作区
- 公开的工作区
