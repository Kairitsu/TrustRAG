use std::collections::HashMap;
use std::path::{Path, PathBuf};

use anyhow::{Context, Result};
use serde::{Deserialize, Serialize};

use crate::services::evidence::VerificationMode;
use crate::services::search::SearchMode;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct YamlDomainProfile {
    pub name: String,
    pub display_name: String,
    pub description: String,
    #[serde(default)]
    pub search: SearchProfileConfig,
    #[serde(default)]
    pub retrieval: RetrievalProfileConfig,
    #[serde(default)]
    pub verification: VerificationProfileConfig,
    #[serde(default)]
    pub terminology: Vec<String>,
    #[serde(default)]
    pub query_expansion: QueryExpansionConfig,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SearchProfileConfig {
    #[serde(default = "default_search_mode")]
    pub mode: SearchMode,
    #[serde(default = "default_top_k")]
    pub top_k: usize,
    #[serde(default = "default_min_score")]
    pub min_score: f64,
    #[serde(default = "default_rrf_k")]
    pub rrf_k: f64,
}

impl Default for SearchProfileConfig {
    fn default() -> Self {
        Self {
            mode: default_search_mode(),
            top_k: default_top_k(),
            min_score: default_min_score(),
            rrf_k: default_rrf_k(),
        }
    }
}

fn default_search_mode() -> SearchMode {
    SearchMode::Hybrid
}
fn default_top_k() -> usize {
    10
}
fn default_min_score() -> f64 {
    0.3
}
fn default_rrf_k() -> f64 {
    60.0
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct RetrievalProfileConfig {
    #[serde(default = "default_context_budget")]
    pub context_budget_chars: usize,
    #[serde(default)]
    pub enable_rerank: bool,
    #[serde(default = "default_rerank_top_n")]
    pub rerank_top_n: usize,
}

impl Default for RetrievalProfileConfig {
    fn default() -> Self {
        Self {
            context_budget_chars: default_context_budget(),
            enable_rerank: false,
            rerank_top_n: default_rerank_top_n(),
        }
    }
}

fn default_context_budget() -> usize {
    6000
}
fn default_rerank_top_n() -> usize {
    5
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VerificationProfileConfig {
    #[serde(default)]
    pub mode: VerificationMode,
    #[serde(default = "default_min_trust")]
    pub min_trust_score: f64,
}

impl Default for VerificationProfileConfig {
    fn default() -> Self {
        Self {
            mode: VerificationMode::default(),
            min_trust_score: default_min_trust(),
        }
    }
}

fn default_min_trust() -> f64 {
    0.5
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
pub struct QueryExpansionConfig {
    #[serde(default)]
    pub enabled: bool,
    #[serde(default)]
    pub synonyms: HashMap<String, Vec<String>>,
}

/// In-memory registry of all loaded YAML domain profiles.
#[derive(Debug, Clone, Default)]
pub struct DomainProfileRegistry {
    profiles: HashMap<String, YamlDomainProfile>,
}

impl DomainProfileRegistry {
    pub fn new() -> Self {
        Self {
            profiles: HashMap::new(),
        }
    }

    /// Load all YAML profiles from a directory.
    pub fn load_from_dir(dir: &Path) -> Result<Self> {
        let mut registry = Self::new();

        if !dir.exists() {
            tracing::warn!(path = %dir.display(), "Domain profiles directory not found, using empty registry");
            return Ok(registry);
        }

        let entries = std::fs::read_dir(dir)
            .with_context(|| format!("Failed to read domain profiles directory: {}", dir.display()))?;

        for entry in entries {
            let entry = entry?;
            let path = entry.path();

            if path.extension().and_then(|e| e.to_str()) == Some("yaml")
                || path.extension().and_then(|e| e.to_str()) == Some("yml")
            {
                match load_profile_from_file(&path) {
                    Ok(profile) => {
                        tracing::info!(name = %profile.name, path = %path.display(), "Loaded domain profile");
                        registry.profiles.insert(profile.name.clone(), profile);
                    }
                    Err(e) => {
                        tracing::warn!(path = %path.display(), error = %e, "Failed to load domain profile, skipping");
                    }
                }
            }
        }

        tracing::info!(count = registry.profiles.len(), "Domain profile registry initialized");
        Ok(registry)
    }

    pub fn get(&self, name: &str) -> Option<&YamlDomainProfile> {
        self.profiles.get(name)
    }

    pub fn list(&self) -> Vec<&YamlDomainProfile> {
        let mut profiles: Vec<_> = self.profiles.values().collect();
        profiles.sort_by(|a, b| a.name.cmp(&b.name));
        profiles
    }

    pub fn names(&self) -> Vec<&str> {
        let mut names: Vec<_> = self.profiles.keys().map(|s| s.as_str()).collect();
        names.sort();
        names
    }

    pub fn len(&self) -> usize {
        self.profiles.len()
    }

    pub fn is_empty(&self) -> bool {
        self.profiles.is_empty()
    }

    pub fn insert(&mut self, profile: YamlDomainProfile) {
        self.profiles.insert(profile.name.clone(), profile);
    }
}

/// Load a single YAML domain profile from file.
pub fn load_profile_from_file(path: &Path) -> Result<YamlDomainProfile> {
    let content = std::fs::read_to_string(path)
        .with_context(|| format!("Failed to read {}", path.display()))?;
    parse_profile_yaml(&content)
}

/// Parse YAML content into a domain profile.
pub fn parse_profile_yaml(yaml_content: &str) -> Result<YamlDomainProfile> {
    serde_yaml::from_str(yaml_content).context("Failed to parse domain profile YAML")
}

/// Default path for built-in domain profiles relative to the binary.
pub fn default_profiles_dir() -> PathBuf {
    let mut path = std::env::current_dir().unwrap_or_default();
    path.push("configs");
    path.push("domain_profiles");
    path
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_general_profile() {
        let yaml = include_str!("../../configs/domain_profiles/general.yaml");
        let profile = parse_profile_yaml(yaml).unwrap();
        assert_eq!(profile.name, "general");
        assert_eq!(profile.search.mode, SearchMode::Hybrid);
        assert_eq!(profile.search.top_k, 10);
        assert!(!profile.retrieval.enable_rerank);
        assert_eq!(profile.verification.mode, VerificationMode::Warn);
    }

    #[test]
    fn test_parse_legal_profile() {
        let yaml = include_str!("../../configs/domain_profiles/legal.yaml");
        let profile = parse_profile_yaml(yaml).unwrap();
        assert_eq!(profile.name, "legal");
        assert_eq!(profile.search.top_k, 15);
        assert!(profile.retrieval.enable_rerank);
        assert_eq!(profile.verification.mode, VerificationMode::Strict);
        assert!(profile.verification.min_trust_score >= 0.7);
        assert!(!profile.terminology.is_empty());
        assert!(profile.query_expansion.enabled);
        assert!(profile.query_expansion.synonyms.contains_key("contract"));
    }

    #[test]
    fn test_parse_finance_profile() {
        let yaml = include_str!("../../configs/domain_profiles/finance.yaml");
        let profile = parse_profile_yaml(yaml).unwrap();
        assert_eq!(profile.name, "finance");
        assert_eq!(profile.verification.mode, VerificationMode::Strict);
        assert!(profile.query_expansion.synonyms.contains_key("stock"));
    }

    #[test]
    fn test_parse_accounting_profile() {
        let yaml = include_str!("../../configs/domain_profiles/accounting.yaml");
        let profile = parse_profile_yaml(yaml).unwrap();
        assert_eq!(profile.name, "accounting");
        assert!(profile.terminology.contains(&"depreciation".to_string()));
    }

    #[test]
    fn test_parse_audit_profile() {
        let yaml = include_str!("../../configs/domain_profiles/audit.yaml");
        let profile = parse_profile_yaml(yaml).unwrap();
        assert_eq!(profile.name, "audit");
        assert_eq!(profile.verification.min_trust_score, 0.8);
        assert!(profile.terminology.contains(&"materiality".to_string()));
    }

    #[test]
    fn test_parse_compliance_profile() {
        let yaml = include_str!("../../configs/domain_profiles/compliance.yaml");
        let profile = parse_profile_yaml(yaml).unwrap();
        assert_eq!(profile.name, "compliance");
        assert!(profile.terminology.contains(&"GDPR".to_string()));
    }

    #[test]
    fn test_parse_minimal_yaml() {
        let yaml = r#"
name: test
display_name: Test Profile
description: Minimal test
"#;
        let profile = parse_profile_yaml(yaml).unwrap();
        assert_eq!(profile.name, "test");
        assert_eq!(profile.search.mode, SearchMode::Hybrid);
        assert_eq!(profile.search.top_k, 10);
        assert!(!profile.retrieval.enable_rerank);
        assert!(profile.terminology.is_empty());
        assert!(!profile.query_expansion.enabled);
    }

    #[test]
    fn test_registry_load_from_dir() {
        let dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("configs")
            .join("domain_profiles");
        let registry = DomainProfileRegistry::load_from_dir(&dir).unwrap();
        assert!(registry.len() >= 6, "Expected at least 6 profiles, got {}", registry.len());
        assert!(registry.get("general").is_some());
        assert!(registry.get("legal").is_some());
        assert!(registry.get("finance").is_some());
        assert!(registry.get("accounting").is_some());
        assert!(registry.get("audit").is_some());
        assert!(registry.get("compliance").is_some());
    }

    #[test]
    fn test_registry_list_and_names() {
        let mut registry = DomainProfileRegistry::new();
        registry.insert(YamlDomainProfile {
            name: "beta".to_string(),
            display_name: "Beta".to_string(),
            description: "test".to_string(),
            search: SearchProfileConfig::default(),
            retrieval: RetrievalProfileConfig::default(),
            verification: VerificationProfileConfig::default(),
            terminology: vec![],
            query_expansion: QueryExpansionConfig::default(),
        });
        registry.insert(YamlDomainProfile {
            name: "alpha".to_string(),
            display_name: "Alpha".to_string(),
            description: "test".to_string(),
            search: SearchProfileConfig::default(),
            retrieval: RetrievalProfileConfig::default(),
            verification: VerificationProfileConfig::default(),
            terminology: vec![],
            query_expansion: QueryExpansionConfig::default(),
        });

        let names = registry.names();
        assert_eq!(names, vec!["alpha", "beta"]);

        let listed = registry.list();
        assert_eq!(listed[0].name, "alpha");
        assert_eq!(listed[1].name, "beta");
    }

    #[test]
    fn test_registry_empty_dir() {
        let dir = PathBuf::from("/tmp/nonexistent_domain_profiles_dir_12345");
        let registry = DomainProfileRegistry::load_from_dir(&dir).unwrap();
        assert!(registry.is_empty());
    }

    #[test]
    fn test_profile_serde_roundtrip() {
        let yaml = include_str!("../../configs/domain_profiles/legal.yaml");
        let profile = parse_profile_yaml(yaml).unwrap();
        let json = serde_json::to_string(&profile).unwrap();
        let deserialized: YamlDomainProfile = serde_json::from_str(&json).unwrap();
        assert_eq!(deserialized.name, profile.name);
        assert_eq!(deserialized.search.top_k, profile.search.top_k);
        assert_eq!(deserialized.verification.mode, profile.verification.mode);
    }
}
