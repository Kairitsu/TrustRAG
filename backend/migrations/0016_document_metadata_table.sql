-- Dedicated document_metadata table for structured, domain-aware metadata.
-- Supplements the JSONB metadata column on the documents table with typed fields
-- for efficient querying and filtering.

CREATE TABLE IF NOT EXISTS document_metadata (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    document_id UUID NOT NULL REFERENCES documents(id) ON DELETE CASCADE,
    workspace_id UUID NOT NULL,

    -- Classification
    domain VARCHAR(100),
    sub_domain VARCHAR(100),
    document_type VARCHAR(50),
    language VARCHAR(10),

    -- Authority & provenance
    authority VARCHAR(255),
    author VARCHAR(255),
    publisher VARCHAR(255),
    source_url TEXT,

    -- Temporal
    publish_date DATE,
    effective_date DATE,
    expiry_date DATE,
    fiscal_year INTEGER,

    -- Domain-specific (legal/regulatory)
    jurisdiction VARCHAR(100),
    regulation_id VARCHAR(100),
    case_number VARCHAR(100),

    -- Domain-specific (finance)
    ticker_symbol VARCHAR(20),
    report_type VARCHAR(50),
    currency VARCHAR(10),

    -- Domain-specific (medical/scientific)
    doi VARCHAR(255),
    pmid VARCHAR(50),
    clinical_trial_id VARCHAR(50),

    -- Quality & confidence
    confidence_score DOUBLE PRECISION DEFAULT 0.0,
    is_verified BOOLEAN DEFAULT FALSE,
    verified_by VARCHAR(255),
    verified_at TIMESTAMPTZ,

    -- Flexible extension
    tags TEXT[] DEFAULT '{}',
    extra JSONB DEFAULT '{}',

    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT uq_document_metadata_doc UNIQUE (document_id)
);

CREATE INDEX idx_doc_meta_workspace ON document_metadata(workspace_id);
CREATE INDEX idx_doc_meta_domain ON document_metadata(domain);
CREATE INDEX idx_doc_meta_language ON document_metadata(language);
CREATE INDEX idx_doc_meta_authority ON document_metadata(authority);
CREATE INDEX idx_doc_meta_jurisdiction ON document_metadata(jurisdiction);
CREATE INDEX idx_doc_meta_fiscal_year ON document_metadata(fiscal_year);
CREATE INDEX idx_doc_meta_document_type ON document_metadata(document_type);
CREATE INDEX idx_doc_meta_tags ON document_metadata USING gin(tags);
CREATE INDEX idx_doc_meta_extra ON document_metadata USING gin(extra jsonb_path_ops);
