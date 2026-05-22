# Citations & Review

Citations are the core differentiator of TrustRAG. Every AI-generated answer can be traced back to its original source.

## Citation Structure

Each citation contains:

| Field | Description |
|-------|-------------|
| `document_id` | The source document |
| `chunk_id` | The specific text chunk |
| `citation_index` | Position in the answer |
| `quoted_text` | The exact quoted passage |
| `page_number` | Page in the original document |
| `heading_path` | Section hierarchy |
| `relevance_score` | How relevant the chunk is |

## Review Workflow

Citations can be reviewed for accuracy:

- **Approve** — Citation is accurate and well-sourced
- **Reject** — Citation is inaccurate or misleading
- **Flag** — Citation needs further investigation

Review records are stored with timestamps and reviewer information, providing a full audit trail.

## Viewing Citations

When you re-enter a conversation, all citations are loaded alongside the messages. Click any citation to see:

- The quoted text
- The source document and page
- The heading path
- Review status and history

## Review Reports

Export comprehensive review reports from the Review Records page. Reports include:

- **Overview**: Total citations, reviewed/unreviewed counts, review coverage percentage
- **Key Metrics**: Approval rate, rejection rate, hallucination rate (rejected + flagged / reviewed)
- **Review Results**: Distribution across approved, rejected, flagged, and pending statuses
- **Review Details**: Individual review records with document context, quoted text, comments, and corrections

Reports are generated as Markdown and can be copied to clipboard for sharing or documentation.

## Review Statistics per Conversation

Each conversation shows real-time review statistics:
- Total citations in the conversation
- Breakdown by status (approved/rejected/flagged/pending/unreviewed)

Access via the review stats endpoint: `GET /conversations/{conv_id}/review-stats`
