# Review Reports

TrustRAG provides comprehensive review report generation to help you track citation quality and identify potential hallucinations.

## Generating a Report

1. Navigate to the **Review Records** page from the sidebar
2. Click the **Export Report** button (summarize icon) in the top toolbar
3. A visual report dialog opens with metrics and details

## Report Contents

### Overview Section

| Metric | Description |
|--------|-------------|
| Total Citations | All citations across all conversations |
| Reviewed | Citations with at least one review |
| Unreviewed | Citations not yet reviewed |
| Review Coverage | Percentage of citations that have been reviewed |

### Key Metrics

- **Approval Rate** — Percentage of reviewed citations marked as approved
- **Rejection Rate** — Percentage marked as rejected
- **Hallucination Rate** — Combined rejected + flagged as a percentage of reviewed (indicates potential AI hallucination)

### Review Details

Each reviewed citation is shown with:
- Status (approved/rejected/flagged/pending)
- Source document title
- Section/heading path
- Page number
- Quoted text
- Reviewer comments
- Corrections (if provided)

## Markdown Export

Click **Copy Markdown** in the report dialog to copy the full report as Markdown. The generated Markdown includes:

- Summary tables
- Key metrics with percentages
- Detailed review records with status icons
- Generated timestamp

## API Access

Reports are also available via REST API:

- `GET /reviews/report` — JSON report data
- `GET /reviews/report/markdown` — Pre-formatted Markdown string
