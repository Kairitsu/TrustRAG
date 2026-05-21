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
}
