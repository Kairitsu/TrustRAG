# Review Reports API

## Get Review Report (JSON)

Returns aggregated review statistics and recent review records.

```http
GET /reviews/report
Authorization: Bearer <token>
```

### Response

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
  "recent_reviews": [
    {
      "id": "uuid",
      "citation_id": "uuid",
      "status": "approved",
      "comment": "Verified against source",
      "corrected_text": null,
      "quoted_text": "The original passage...",
      "document_title": "Research Paper.pdf",
      "heading_path": "Chapter 1 > Introduction",
      "page_number": 5,
      "created_at": "2026-05-22 05:30:00"
    }
  ]
}
```

### Metrics

| Field | Description |
|-------|-------------|
| `approval_rate` | `approved / (approved + rejected + flagged + pending) * 100` |
| `rejection_rate` | `rejected / reviewed * 100` |
| `hallucination_rate` | `(rejected + flagged) / reviewed * 100` |
| `review_coverage` | `reviewed / total_citations * 100` |

## Get Review Report (Markdown)

Returns a pre-formatted Markdown report string.

```http
GET /reviews/report/markdown
Authorization: Bearer <token>
```

### Response

Returns plain text Markdown containing:
- Overview table with citation counts
- Review results distribution
- Key metrics (hallucination rate, coverage, approval rate)
- Detailed review records with document context

## List All Reviews

```http
GET /reviews?limit=50&offset=0
Authorization: Bearer <token>
```

Returns paginated list of all review records.

## Get Conversation Review Stats

```http
GET /conversations/{conv_id}/review-stats
Authorization: Bearer <token>
```

Returns review statistics scoped to a single conversation.
