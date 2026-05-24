use chrono::{NaiveDate, DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::db::DbPool;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DocumentMetadataRecord {
    pub id: Uuid,
    pub document_id: Uuid,
    pub workspace_id: Uuid,

    pub domain: Option<String>,
    pub sub_domain: Option<String>,
    pub document_type: Option<String>,
    pub language: Option<String>,

    pub authority: Option<String>,
    pub author: Option<String>,
    pub publisher: Option<String>,
    pub source_url: Option<String>,

    pub publish_date: Option<NaiveDate>,
    pub effective_date: Option<NaiveDate>,
    pub expiry_date: Option<NaiveDate>,
    pub fiscal_year: Option<i32>,

    pub jurisdiction: Option<String>,
    pub regulation_id: Option<String>,
    pub case_number: Option<String>,

    pub ticker_symbol: Option<String>,
    pub report_type: Option<String>,
    pub currency: Option<String>,

    pub doi: Option<String>,
    pub pmid: Option<String>,
    pub clinical_trial_id: Option<String>,

    pub confidence_score: f64,
    pub is_verified: bool,
    pub verified_by: Option<String>,
    pub verified_at: Option<DateTime<Utc>>,

    pub tags: Vec<String>,
    #[serde(default)]
    pub extra: serde_json::Value,

    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct UpsertDocumentMetadata {
    pub document_id: Uuid,
    pub workspace_id: Uuid,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub domain: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub sub_domain: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub document_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub language: Option<String>,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub authority: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub author: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub publisher: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub source_url: Option<String>,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub publish_date: Option<NaiveDate>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub effective_date: Option<NaiveDate>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub expiry_date: Option<NaiveDate>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fiscal_year: Option<i32>,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub jurisdiction: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub regulation_id: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub case_number: Option<String>,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub ticker_symbol: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub report_type: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub currency: Option<String>,

    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub doi: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub pmid: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub clinical_trial_id: Option<String>,

    #[serde(default)]
    pub confidence_score: f64,
    #[serde(default)]
    pub is_verified: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub verified_by: Option<String>,

    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub tags: Vec<String>,
    #[serde(default)]
    pub extra: serde_json::Value,
}

#[cfg(feature = "postgres")]
pub async fn upsert_metadata(
    pool: &DbPool,
    input: &UpsertDocumentMetadata,
) -> anyhow::Result<Uuid> {
    let row: (Uuid,) = sqlx::query_as(
        r#"
        INSERT INTO document_metadata (
            document_id, workspace_id,
            domain, sub_domain, document_type, language,
            authority, author, publisher, source_url,
            publish_date, effective_date, expiry_date, fiscal_year,
            jurisdiction, regulation_id, case_number,
            ticker_symbol, report_type, currency,
            doi, pmid, clinical_trial_id,
            confidence_score, is_verified, verified_by,
            tags, extra
        ) VALUES (
            $1, $2,
            $3, $4, $5, $6,
            $7, $8, $9, $10,
            $11, $12, $13, $14,
            $15, $16, $17,
            $18, $19, $20,
            $21, $22, $23,
            $24, $25, $26,
            $27, $28
        )
        ON CONFLICT (document_id) DO UPDATE SET
            domain = EXCLUDED.domain,
            sub_domain = EXCLUDED.sub_domain,
            document_type = EXCLUDED.document_type,
            language = EXCLUDED.language,
            authority = EXCLUDED.authority,
            author = EXCLUDED.author,
            publisher = EXCLUDED.publisher,
            source_url = EXCLUDED.source_url,
            publish_date = EXCLUDED.publish_date,
            effective_date = EXCLUDED.effective_date,
            expiry_date = EXCLUDED.expiry_date,
            fiscal_year = EXCLUDED.fiscal_year,
            jurisdiction = EXCLUDED.jurisdiction,
            regulation_id = EXCLUDED.regulation_id,
            case_number = EXCLUDED.case_number,
            ticker_symbol = EXCLUDED.ticker_symbol,
            report_type = EXCLUDED.report_type,
            currency = EXCLUDED.currency,
            doi = EXCLUDED.doi,
            pmid = EXCLUDED.pmid,
            clinical_trial_id = EXCLUDED.clinical_trial_id,
            confidence_score = EXCLUDED.confidence_score,
            is_verified = EXCLUDED.is_verified,
            verified_by = EXCLUDED.verified_by,
            tags = EXCLUDED.tags,
            extra = EXCLUDED.extra,
            updated_at = NOW()
        RETURNING id
        "#,
    )
    .bind(input.document_id)
    .bind(input.workspace_id)
    .bind(&input.domain)
    .bind(&input.sub_domain)
    .bind(&input.document_type)
    .bind(&input.language)
    .bind(&input.authority)
    .bind(&input.author)
    .bind(&input.publisher)
    .bind(&input.source_url)
    .bind(input.publish_date)
    .bind(input.effective_date)
    .bind(input.expiry_date)
    .bind(input.fiscal_year)
    .bind(&input.jurisdiction)
    .bind(&input.regulation_id)
    .bind(&input.case_number)
    .bind(&input.ticker_symbol)
    .bind(&input.report_type)
    .bind(&input.currency)
    .bind(&input.doi)
    .bind(&input.pmid)
    .bind(&input.clinical_trial_id)
    .bind(input.confidence_score)
    .bind(input.is_verified)
    .bind(&input.verified_by)
    .bind(&input.tags)
    .bind(&input.extra)
    .fetch_one(pool)
    .await?;

    Ok(row.0)
}

#[cfg(feature = "postgres")]
pub async fn get_metadata_by_document(
    pool: &DbPool,
    document_id: Uuid,
) -> anyhow::Result<Option<serde_json::Value>> {
    let row: Option<(serde_json::Value,)> = sqlx::query_as(
        "SELECT row_to_json(dm.*) FROM document_metadata dm WHERE dm.document_id = $1",
    )
    .bind(document_id)
    .fetch_optional(pool)
    .await?;

    Ok(row.map(|r| r.0))
}

#[cfg(feature = "postgres")]
pub async fn list_metadata_for_workspace(
    pool: &DbPool,
    workspace_id: Uuid,
    limit: i64,
    offset: i64,
) -> anyhow::Result<Vec<serde_json::Value>> {
    let rows: Vec<(serde_json::Value,)> = sqlx::query_as(
        r#"
        SELECT row_to_json(dm.*)
        FROM document_metadata dm
        WHERE dm.workspace_id = $1
        ORDER BY dm.created_at DESC
        LIMIT $2 OFFSET $3
        "#,
    )
    .bind(workspace_id)
    .bind(limit)
    .bind(offset)
    .fetch_all(pool)
    .await?;

    Ok(rows.into_iter().map(|r| r.0).collect())
}

#[cfg(feature = "postgres")]
pub async fn delete_metadata(pool: &DbPool, document_id: Uuid) -> anyhow::Result<bool> {
    let result = sqlx::query("DELETE FROM document_metadata WHERE document_id = $1")
        .bind(document_id)
        .execute(pool)
        .await?;
    Ok(result.rows_affected() > 0)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_upsert_input_default() {
        let input = UpsertDocumentMetadata {
            document_id: Uuid::new_v4(),
            workspace_id: Uuid::new_v4(),
            ..Default::default()
        };
        assert!(input.domain.is_none());
        assert!(input.tags.is_empty());
        assert!(!input.is_verified);
        assert_eq!(input.confidence_score, 0.0);
    }

    #[test]
    fn test_upsert_input_serde_roundtrip() {
        let input = UpsertDocumentMetadata {
            document_id: Uuid::new_v4(),
            workspace_id: Uuid::new_v4(),
            domain: Some("legal".to_string()),
            jurisdiction: Some("US-CA".to_string()),
            fiscal_year: Some(2025),
            tags: vec!["compliance".to_string(), "sec".to_string()],
            ..Default::default()
        };
        let json = serde_json::to_string(&input).unwrap();
        assert!(json.contains("legal"));
        assert!(json.contains("US-CA"));
        assert!(json.contains("2025"));

        let back: UpsertDocumentMetadata = serde_json::from_str(&json).unwrap();
        assert_eq!(back.domain.as_deref(), Some("legal"));
        assert_eq!(back.jurisdiction.as_deref(), Some("US-CA"));
        assert_eq!(back.fiscal_year, Some(2025));
        assert_eq!(back.tags.len(), 2);
    }

    #[test]
    fn test_upsert_input_empty_optionals_omitted() {
        let input = UpsertDocumentMetadata {
            document_id: Uuid::new_v4(),
            workspace_id: Uuid::new_v4(),
            ..Default::default()
        };
        let json = serde_json::to_string(&input).unwrap();
        assert!(!json.contains("domain"));
        assert!(!json.contains("jurisdiction"));
        assert!(!json.contains("fiscal_year"));
        assert!(!json.contains("tags"));
    }

    #[test]
    fn test_upsert_input_finance_fields() {
        let input = UpsertDocumentMetadata {
            document_id: Uuid::new_v4(),
            workspace_id: Uuid::new_v4(),
            domain: Some("finance".to_string()),
            ticker_symbol: Some("AAPL".to_string()),
            report_type: Some("10-K".to_string()),
            currency: Some("USD".to_string()),
            fiscal_year: Some(2024),
            ..Default::default()
        };
        let json = serde_json::to_string(&input).unwrap();
        let back: UpsertDocumentMetadata = serde_json::from_str(&json).unwrap();
        assert_eq!(back.ticker_symbol.as_deref(), Some("AAPL"));
        assert_eq!(back.report_type.as_deref(), Some("10-K"));
        assert_eq!(back.currency.as_deref(), Some("USD"));
    }

    #[test]
    fn test_upsert_input_medical_fields() {
        let input = UpsertDocumentMetadata {
            document_id: Uuid::new_v4(),
            workspace_id: Uuid::new_v4(),
            domain: Some("medical".to_string()),
            doi: Some("10.1000/test.doi".to_string()),
            pmid: Some("12345678".to_string()),
            clinical_trial_id: Some("NCT00000001".to_string()),
            ..Default::default()
        };
        let json = serde_json::to_string(&input).unwrap();
        let back: UpsertDocumentMetadata = serde_json::from_str(&json).unwrap();
        assert_eq!(back.doi.as_deref(), Some("10.1000/test.doi"));
        assert_eq!(back.pmid.as_deref(), Some("12345678"));
        assert_eq!(back.clinical_trial_id.as_deref(), Some("NCT00000001"));
    }

    #[test]
    fn test_upsert_input_with_extra_jsonb() {
        let input = UpsertDocumentMetadata {
            document_id: Uuid::new_v4(),
            workspace_id: Uuid::new_v4(),
            extra: serde_json::json!({"custom_field": "value", "score": 42}),
            ..Default::default()
        };
        let json = serde_json::to_string(&input).unwrap();
        let back: UpsertDocumentMetadata = serde_json::from_str(&json).unwrap();
        assert_eq!(back.extra["custom_field"], "value");
        assert_eq!(back.extra["score"], 42);
    }

    #[test]
    fn test_record_struct_fields_exist() {
        let record = DocumentMetadataRecord {
            id: Uuid::new_v4(),
            document_id: Uuid::new_v4(),
            workspace_id: Uuid::new_v4(),
            domain: Some("tech".to_string()),
            sub_domain: None,
            document_type: Some("article".to_string()),
            language: Some("en".to_string()),
            authority: None,
            author: Some("Alice".to_string()),
            publisher: None,
            source_url: None,
            publish_date: None,
            effective_date: None,
            expiry_date: None,
            fiscal_year: None,
            jurisdiction: None,
            regulation_id: None,
            case_number: None,
            ticker_symbol: None,
            report_type: None,
            currency: None,
            doi: None,
            pmid: None,
            clinical_trial_id: None,
            confidence_score: 0.85,
            is_verified: true,
            verified_by: Some("Bob".to_string()),
            verified_at: Some(Utc::now()),
            tags: vec!["ai".to_string()],
            extra: serde_json::json!({}),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };
        assert_eq!(record.domain.as_deref(), Some("tech"));
        assert!(record.is_verified);
        assert_eq!(record.confidence_score, 0.85);
    }
}
