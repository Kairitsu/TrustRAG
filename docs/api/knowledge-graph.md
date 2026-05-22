# Knowledge Graph API

## Get Knowledge Graph

Returns the full graph (nodes + edges) for a workspace.

```http
GET /workspaces/{ws_id}/knowledge-graph
Authorization: Bearer <token>
```

### Response

```json
{
  "nodes": [
    {
      "id": "uuid",
      "label": "Machine Learning",
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

### Node Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Entity identifier |
| `label` | string | Display name |
| `entity_type` | string | Type classification (person, organization, concept, etc.) |
| `document_id` | UUID? | Source document, if applicable |

### Edge Fields

| Field | Type | Description |
|-------|------|-------------|
| `source` | UUID | Source node ID |
| `target` | UUID | Target node ID |
| `relation` | string | Relationship type label |
| `weight` | float | Relationship strength (0-1) |

## List Entities

Returns entities for a workspace with metadata, ordered by creation date.

```http
GET /workspaces/{ws_id}/knowledge-graph/entities
Authorization: Bearer <token>
```

### Response

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

### Entity Fields

| Field | Type | Description |
|-------|------|-------------|
| `id` | UUID | Entity identifier |
| `name` | string | Entity name |
| `entity_type` | string | Classification type |
| `document_id` | UUID? | Source document |
| `metadata` | object | Additional structured data |
| `created_at` | string | Creation timestamp |

## Access Control

Both endpoints require workspace access. Users can access graphs for:
- Workspaces they own
- Workspaces they are members of
- Public workspaces
