use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::DbPool;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ReviewRecord {
    pub id: Uuid,
    pub citation_id: Uuid,
    pub reviewer_id: Uuid,
    pub status: String,
    pub comment: Option<String>,
    pub corrected_text: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

type ReviewRow = (String, String, String, String, Option<String>, Option<String>, String, String);

fn parse_review_row(r: ReviewRow) -> ReviewRecord {
    ReviewRecord {
        id: r.0.parse().unwrap_or_default(),
        citation_id: r.1.parse().unwrap_or_default(),
        reviewer_id: r.2.parse().unwrap_or_default(),
        status: r.3,
        comment: r.4,
        corrected_text: r.5,
        created_at: r.6,
        updated_at: r.7,
    }
}

#[derive(Debug, Deserialize)]
pub struct CreateReviewInput {
    pub status: String,
    pub comment: Option<String>,
    pub corrected_text: Option<String>,
}

pub async fn create_review(
    pool: &DbPool,
    citation_id: Uuid,
    reviewer_id: Uuid,
    input: &CreateReviewInput,
) -> anyhow::Result<ReviewRecord> {
    let valid_statuses = ["approved", "rejected", "flagged", "pending"];
    if !valid_statuses.contains(&input.status.as_str()) {
        anyhow::bail!("Invalid review status: {}", input.status);
    }

    let new_id: String = sqlx::query_scalar(
        r#"
        INSERT INTO review_records (citation_id, reviewer_id, status, comment, corrected_text)
        VALUES ($1, $2, $3, $4, $5)
        RETURNING id
        "#,
    )
    .bind(citation_id.to_string())
    .bind(reviewer_id.to_string())
    .bind(&input.status)
    .bind(&input.comment)
    .bind(&input.corrected_text)
    .fetch_one(pool)
    .await?;

    let row = sqlx::query_as::<_, ReviewRow>(
        "SELECT id, citation_id, reviewer_id, status, comment, corrected_text, CAST(created_at AS TEXT), CAST(updated_at AS TEXT) FROM review_records WHERE id = $1",
    )
    .bind(&new_id)
    .fetch_one(pool)
    .await?;
    let record = parse_review_row(row);

    if input.status == "approved" {
        sqlx::query("UPDATE citations SET verified = 1 WHERE id = $1")
            .bind(citation_id.to_string())
            .execute(pool)
            .await?;
    } else if input.status == "rejected" || input.status == "flagged" {
        sqlx::query("UPDATE citations SET verified = 0 WHERE id = $1")
            .bind(citation_id.to_string())
            .execute(pool)
            .await?;
    }

    Ok(record)
}

pub async fn list_reviews_for_citation(
    pool: &DbPool,
    citation_id: Uuid,
) -> anyhow::Result<Vec<ReviewRecord>> {
    let rows = sqlx::query_as::<_, ReviewRow>(
        r#"
        SELECT id, citation_id, reviewer_id, status, comment, corrected_text, CAST(created_at AS TEXT), CAST(updated_at AS TEXT)
        FROM review_records
        WHERE citation_id = $1
        ORDER BY created_at DESC
        "#,
    )
    .bind(citation_id.to_string())
    .fetch_all(pool)
    .await?;

    Ok(rows.into_iter().map(parse_review_row).collect())
}

pub async fn list_all_reviews(
    pool: &DbPool,
    limit: i64,
    offset: i64,
) -> anyhow::Result<Vec<ReviewRecord>> {
    let rows = sqlx::query_as::<_, ReviewRow>(
        r#"
        SELECT id, citation_id, reviewer_id, status, comment, corrected_text, CAST(created_at AS TEXT), CAST(updated_at AS TEXT)
        FROM review_records
        ORDER BY created_at DESC
        LIMIT $1 OFFSET $2
        "#,
    )
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok(rows.into_iter().map(parse_review_row).collect())
}

#[derive(Debug, Serialize)]
pub struct ReviewStats {
    pub total_citations: i64,
    pub approved: i64,
    pub rejected: i64,
    pub flagged: i64,
    pub pending: i64,
    pub unreviewed: i64,
}

pub async fn get_review_stats_for_conversation(
    pool: &DbPool,
    conversation_id: Uuid,
) -> anyhow::Result<ReviewStats> {
    let total_citations = sqlx::query_scalar::<_, i64>(
        r#"
        SELECT COUNT(*) FROM citations c
        JOIN messages m ON c.message_id = m.id
        WHERE m.conversation_id = $1
        "#,
    )
    .bind(conversation_id.to_string())
    .fetch_one(pool)
    .await?;

    let reviewed = sqlx::query_as::<_, (String, i64)>(
        r#"
        SELECT latest.status, COUNT(*) FROM (
            SELECT rr.status
            FROM review_records rr
            JOIN citations c ON rr.citation_id = c.id
            JOIN messages m ON c.message_id = m.id
            WHERE m.conversation_id = $1
              AND rr.created_at = (
                  SELECT MAX(rr2.created_at) FROM review_records rr2
                  WHERE rr2.citation_id = rr.citation_id
              )
            GROUP BY rr.citation_id, rr.status
        ) latest
        GROUP BY latest.status
        "#,
    )
    .bind(conversation_id.to_string())
    .fetch_all(pool)
    .await?;

    let mut approved = 0i64;
    let mut rejected = 0i64;
    let mut flagged = 0i64;
    let mut pending_count = 0i64;

    for (status, count) in &reviewed {
        match status.as_str() {
            "approved" => approved = *count,
            "rejected" => rejected = *count,
            "flagged" => flagged = *count,
            "pending" => pending_count = *count,
            _ => {}
        }
    }

    let reviewed_total = approved + rejected + flagged + pending_count;
    let unreviewed = total_citations - reviewed_total;

    Ok(ReviewStats {
        total_citations,
        approved,
        rejected,
        flagged,
        pending: pending_count,
        unreviewed: unreviewed.max(0),
    })
}

#[derive(Debug, Serialize)]
pub struct ReviewReportData {
    pub generated_at: String,
    pub stats: ReviewStats,
    pub approval_rate: f64,
    pub rejection_rate: f64,
    pub hallucination_rate: f64,
    pub review_coverage: f64,
    pub recent_reviews: Vec<ReviewRecordWithContext>,
}

#[derive(Debug, Serialize)]
pub struct ReviewRecordWithContext {
    pub id: String,
    pub citation_id: String,
    pub status: String,
    pub comment: Option<String>,
    pub corrected_text: Option<String>,
    pub quoted_text: Option<String>,
    pub document_title: Option<String>,
    pub heading_path: Option<String>,
    pub page_number: Option<i32>,
    pub created_at: String,
}

type ReportRow = (
    String, String, String, Option<String>, Option<String>,
    Option<String>, Option<String>, Option<String>, Option<i32>, String,
);

pub async fn generate_report(pool: &DbPool) -> anyhow::Result<ReviewReportData> {
    let total_citations: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM citations")
            .fetch_one(pool)
            .await?;

    let status_counts = sqlx::query_as::<_, (String, i64)>(
        r#"
        SELECT latest.status, COUNT(*) FROM (
            SELECT rr.status, rr.citation_id
            FROM review_records rr
            WHERE rr.created_at = (
                SELECT MAX(rr2.created_at) FROM review_records rr2
                WHERE rr2.citation_id = rr.citation_id
            )
            GROUP BY rr.citation_id, rr.status
        ) latest
        GROUP BY latest.status
        "#,
    )
    .fetch_all(pool)
    .await?;

    let mut approved = 0i64;
    let mut rejected = 0i64;
    let mut flagged = 0i64;
    let mut pending_count = 0i64;
    for (status, count) in &status_counts {
        match status.as_str() {
            "approved" => approved = *count,
            "rejected" => rejected = *count,
            "flagged" => flagged = *count,
            "pending" => pending_count = *count,
            _ => {}
        }
    }
    let reviewed_total = approved + rejected + flagged + pending_count;
    let unreviewed = (total_citations - reviewed_total).max(0);

    let stats = ReviewStats {
        total_citations,
        approved,
        rejected,
        flagged,
        pending: pending_count,
        unreviewed,
    };

    let approval_rate = if reviewed_total > 0 {
        (approved as f64 / reviewed_total as f64) * 100.0
    } else {
        0.0
    };
    let rejection_rate = if reviewed_total > 0 {
        (rejected as f64 / reviewed_total as f64) * 100.0
    } else {
        0.0
    };
    let hallucination_rate = if reviewed_total > 0 {
        ((rejected + flagged) as f64 / reviewed_total as f64) * 100.0
    } else {
        0.0
    };
    let review_coverage = if total_citations > 0 {
        (reviewed_total as f64 / total_citations as f64) * 100.0
    } else {
        0.0
    };

    let rows = sqlx::query_as::<_, ReportRow>(
        r#"
        SELECT
            rr.id, rr.citation_id, rr.status, rr.comment, rr.corrected_text,
            c.quoted_text, d.title, c.heading_path, c.page_number,
            CAST(rr.created_at AS TEXT)
        FROM review_records rr
        JOIN citations c ON rr.citation_id = c.id
        JOIN documents d ON c.document_id = d.id
        ORDER BY rr.created_at DESC
        LIMIT 50
        "#,
    )
    .fetch_all(pool)
    .await?;

    let recent_reviews = rows
        .into_iter()
        .map(|r| ReviewRecordWithContext {
            id: r.0,
            citation_id: r.1,
            status: r.2,
            comment: r.3,
            corrected_text: r.4,
            quoted_text: r.5,
            document_title: r.6,
            heading_path: r.7,
            page_number: r.8,
            created_at: r.9,
        })
        .collect();

    let now = chrono::Utc::now().format("%Y-%m-%d %H:%M:%S UTC").to_string();

    Ok(ReviewReportData {
        generated_at: now,
        stats,
        approval_rate: (approval_rate * 100.0).round() / 100.0,
        rejection_rate: (rejection_rate * 100.0).round() / 100.0,
        hallucination_rate: (hallucination_rate * 100.0).round() / 100.0,
        review_coverage: (review_coverage * 100.0).round() / 100.0,
        recent_reviews,
    })
}

pub fn report_to_markdown(report: &ReviewReportData) -> String {
    let mut md = String::new();
    md.push_str("# TrustRAG 审核报告 / Review Report\n\n");
    md.push_str(&format!("> Generated: {}\n\n", report.generated_at));
    md.push_str("---\n\n");

    md.push_str("## 概览 / Overview\n\n");
    md.push_str("| 指标 / Metric | 值 / Value |\n");
    md.push_str("|---|---|\n");
    md.push_str(&format!(
        "| 总引用数 / Total Citations | {} |\n",
        report.stats.total_citations
    ));
    md.push_str(&format!(
        "| 已审核 / Reviewed | {} |\n",
        report.stats.total_citations - report.stats.unreviewed
    ));
    md.push_str(&format!(
        "| 未审核 / Unreviewed | {} |\n",
        report.stats.unreviewed
    ));
    md.push_str(&format!(
        "| 审核覆盖率 / Review Coverage | {:.1}% |\n",
        report.review_coverage
    ));
    md.push_str("\n");

    md.push_str("## 审核结果分布 / Review Results\n\n");
    md.push_str("| 状态 / Status | 数量 / Count | 占比 / Rate |\n");
    md.push_str("|---|---|---|\n");
    md.push_str(&format!(
        "| ✅ 通过 / Approved | {} | {:.1}% |\n",
        report.stats.approved, report.approval_rate
    ));
    md.push_str(&format!(
        "| ❌ 拒绝 / Rejected | {} | {:.1}% |\n",
        report.stats.rejected, report.rejection_rate
    ));
    md.push_str(&format!(
        "| ⚠️ 存疑 / Flagged | {} | {:.1}% |\n",
        report.stats.flagged,
        if (report.stats.approved + report.stats.rejected + report.stats.flagged + report.stats.pending) > 0 {
            (report.stats.flagged as f64 / (report.stats.approved + report.stats.rejected + report.stats.flagged + report.stats.pending) as f64) * 100.0
        } else { 0.0 }
    ));
    md.push_str(&format!(
        "| ⏳ 待定 / Pending | {} | - |\n",
        report.stats.pending
    ));
    md.push_str("\n");

    md.push_str("## 关键指标 / Key Metrics\n\n");
    md.push_str(&format!(
        "- **幻觉率 / Hallucination Rate**: {:.1}% (rejected + flagged / reviewed)\n",
        report.hallucination_rate
    ));
    md.push_str(&format!(
        "- **审核覆盖率 / Review Coverage**: {:.1}%\n",
        report.review_coverage
    ));
    md.push_str(&format!(
        "- **通过率 / Approval Rate**: {:.1}%\n\n",
        report.approval_rate
    ));

    if !report.recent_reviews.is_empty() {
        md.push_str("---\n\n");
        md.push_str("## 审核明细 / Review Details\n\n");
        for (i, r) in report.recent_reviews.iter().enumerate() {
            let status_icon = match r.status.as_str() {
                "approved" => "✅",
                "rejected" => "❌",
                "flagged" => "⚠️",
                "pending" => "⏳",
                _ => "❓",
            };
            md.push_str(&format!("### {}. {} {}\n\n", i + 1, status_icon, r.status));
            if let Some(ref title) = r.document_title {
                md.push_str(&format!("- **文档 / Document**: {}\n", title));
            }
            if let Some(ref heading) = r.heading_path {
                md.push_str(&format!("- **章节 / Section**: {}\n", heading));
            }
            if let Some(page) = r.page_number {
                md.push_str(&format!("- **页码 / Page**: {}\n", page));
            }
            if let Some(ref text) = r.quoted_text {
                let truncated = if text.len() > 200 {
                    format!("{}...", &text[..200])
                } else {
                    text.clone()
                };
                md.push_str(&format!("- **引用 / Quote**: {}\n", truncated));
            }
            if let Some(ref comment) = r.comment {
                md.push_str(&format!("- **备注 / Comment**: {}\n", comment));
            }
            if let Some(ref corrected) = r.corrected_text {
                md.push_str(&format!("- **修正 / Correction**: {}\n", corrected));
            }
            md.push_str(&format!("- **时间 / Time**: {}\n\n", r.created_at));
        }
    }

    md.push_str("---\n\n");
    md.push_str("*Generated by TrustRAG*\n");

    md
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_create_review_input_deserialize() {
        let json = r#"{"status":"approved","comment":"Looks correct"}"#;
        let input: CreateReviewInput = serde_json::from_str(json).unwrap();
        assert_eq!(input.status, "approved");
        assert_eq!(input.comment, Some("Looks correct".to_string()));
        assert_eq!(input.corrected_text, None);
    }

    #[test]
    fn test_create_review_input_all_fields() {
        let json = r#"{"status":"rejected","comment":"Wrong source","corrected_text":"Fixed text"}"#;
        let input: CreateReviewInput = serde_json::from_str(json).unwrap();
        assert_eq!(input.status, "rejected");
        assert_eq!(input.comment, Some("Wrong source".to_string()));
        assert_eq!(input.corrected_text, Some("Fixed text".to_string()));
    }

    #[test]
    fn test_create_review_input_minimal() {
        let json = r#"{"status":"flagged"}"#;
        let input: CreateReviewInput = serde_json::from_str(json).unwrap();
        assert_eq!(input.status, "flagged");
        assert_eq!(input.comment, None);
        assert_eq!(input.corrected_text, None);
    }

    #[test]
    fn test_report_to_markdown_empty() {
        let report = ReviewReportData {
            generated_at: "2026-05-22 06:00:00 UTC".to_string(),
            stats: ReviewStats {
                total_citations: 0,
                approved: 0,
                rejected: 0,
                flagged: 0,
                pending: 0,
                unreviewed: 0,
            },
            approval_rate: 0.0,
            rejection_rate: 0.0,
            hallucination_rate: 0.0,
            review_coverage: 0.0,
            recent_reviews: vec![],
        };
        let md = report_to_markdown(&report);
        assert!(md.contains("# TrustRAG"));
        assert!(md.contains("Total Citations | 0"));
        assert!(md.contains("Review Coverage | 0.0%"));
        assert!(md.contains("Hallucination Rate"));
        assert!(!md.contains("Review Details"));
    }

    #[test]
    fn test_report_to_markdown_with_data() {
        let report = ReviewReportData {
            generated_at: "2026-05-22 06:00:00 UTC".to_string(),
            stats: ReviewStats {
                total_citations: 20,
                approved: 12,
                rejected: 3,
                flagged: 2,
                pending: 1,
                unreviewed: 2,
            },
            approval_rate: 66.67,
            rejection_rate: 16.67,
            hallucination_rate: 27.78,
            review_coverage: 90.0,
            recent_reviews: vec![
                ReviewRecordWithContext {
                    id: "r1".to_string(),
                    citation_id: "c1".to_string(),
                    status: "approved".to_string(),
                    comment: Some("Correct reference".to_string()),
                    corrected_text: None,
                    quoted_text: Some("Sample quoted text".to_string()),
                    document_title: Some("Test Document".to_string()),
                    heading_path: Some("Chapter 1 > Intro".to_string()),
                    page_number: Some(5),
                    created_at: "2026-05-22 05:30:00".to_string(),
                },
                ReviewRecordWithContext {
                    id: "r2".to_string(),
                    citation_id: "c2".to_string(),
                    status: "rejected".to_string(),
                    comment: Some("Hallucinated".to_string()),
                    corrected_text: Some("The actual text is...".to_string()),
                    quoted_text: None,
                    document_title: None,
                    heading_path: None,
                    page_number: None,
                    created_at: "2026-05-22 05:00:00".to_string(),
                },
            ],
        };
        let md = report_to_markdown(&report);
        assert!(md.contains("Total Citations | 20"));
        assert!(md.contains("Approved | 12"));
        assert!(md.contains("Rejected | 3"));
        assert!(md.contains("Review Coverage | 90.0%"));
        assert!(md.contains("27.8%"));
        assert!(md.contains("Review Details"));
        assert!(md.contains("Test Document"));
        assert!(md.contains("Chapter 1 > Intro"));
        assert!(md.contains("Page**: 5"));
        assert!(md.contains("Sample quoted text"));
        assert!(md.contains("Correct reference"));
        assert!(md.contains("Hallucinated"));
        assert!(md.contains("The actual text is..."));
    }

    #[test]
    fn test_report_data_serialization() {
        let report = ReviewReportData {
            generated_at: "2026-05-22 06:00:00 UTC".to_string(),
            stats: ReviewStats {
                total_citations: 10,
                approved: 8,
                rejected: 1,
                flagged: 1,
                pending: 0,
                unreviewed: 0,
            },
            approval_rate: 80.0,
            rejection_rate: 10.0,
            hallucination_rate: 20.0,
            review_coverage: 100.0,
            recent_reviews: vec![],
        };
        let json = serde_json::to_string(&report).unwrap();
        assert!(json.contains("\"approval_rate\":80.0"));
        assert!(json.contains("\"hallucination_rate\":20.0"));
        assert!(json.contains("\"review_coverage\":100.0"));
    }
}
