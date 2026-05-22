# Citations & Reviews

## Get Citations for a Message

```http
GET /messages/{message_id}/citations
Authorization: Bearer <token>
```

### Response

```json
[
  {
    "id": "uuid",
    "message_id": "uuid",
    "document_id": "uuid",
    "chunk_id": "uuid",
    "citation_index": 1,
    "quoted_text": "The referenced passage...",
    "page_number": 5,
    "heading_path": "Chapter 1 > Introduction",
    "relevance_score": 0.92,
    "verified": 1,
    "created_at": "2026-05-22T06:00:00Z"
  }
]
```

## Submit Review

```http
POST /citations/{citation_id}/reviews
Authorization: Bearer <token>
Content-Type: application/json

{"status": "approved", "comment": "Verified against source document"}
```

Status values: `approved`, `rejected`, `flagged`, `pending`.

When a citation is approved, its `verified` flag is set to `true`. When rejected or flagged, it is set to `false`.

### Request Body

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `status` | string | Yes | One of: approved, rejected, flagged, pending |
| `comment` | string | No | Review comment |
| `corrected_text` | string | No | Corrected version of the cited text |

## Review History

```http
GET /citations/{citation_id}/reviews
Authorization: Bearer <token>
```

Returns all reviews for a specific citation, ordered by creation date (newest first).

## List All Reviews

```http
GET /reviews?limit=50&offset=0
Authorization: Bearer <token>
```

Returns paginated list of all review records across all citations. Maximum limit is 200.

## Conversation Review Stats

```http
GET /conversations/{conv_id}/review-stats
Authorization: Bearer <token>
```

Returns aggregated review statistics for a conversation:

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

See also: [Review Reports API](/api/review-reports) for comprehensive report generation.
