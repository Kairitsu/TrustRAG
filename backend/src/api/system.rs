use std::collections::HashMap;
use std::sync::Arc;

use tokio::process::Child;

use axum::{
    extract::{Path, Query, State},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;

use crate::auth::middleware::AuthUser;
use crate::error::AppError;

use super::AppState;

pub use crate::services::ocr_install::{
    new_child_store, new_task_store, OcrChildStore, OcrInstallMethod, OcrInstallStage,
    OcrInstallTask, OcrTaskStatus, OcrTaskStore,
};

pub fn new_ocr_task_store() -> OcrTaskStore {
    new_task_store()
}

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/system/db-info", get(db_info))
        .route("/system/backup-db", post(backup_db))
        .route("/system/reset-db", post(reset_db))
        .route("/system/validate-token", get(validate_token))
        .route("/system/ocr-status", get(ocr_status))
        .route("/system/ocr-install-options", get(ocr_install_options))
        .route("/system/ocr-install", post(ocr_install))
        .route("/system/ocr-install/start", post(ocr_install_start))
        .route("/system/ocr-install/status/{task_id}", get(ocr_install_status))
        .route("/system/ocr-install/task/{task_id}", get(ocr_install_status))
        .route("/system/ocr-install/task/{task_id}/logs", get(ocr_install_task_logs))
        .route("/system/ocr-install/cancel/{task_id}", post(ocr_install_cancel))
        .route("/system/ocr-preflight", get(ocr_preflight))
        .route("/system/ocr-install/log/latest", get(ocr_install_latest_log))
        .route("/system/ocr-config", get(ocr_config_get))
        .route("/system/ocr-config/paths", post(ocr_config_save))
        .route("/system/ocr-verify", post(ocr_verify))
}

#[derive(Serialize)]
struct DbInfo {
    schema_version: i32,
    current_version: i32,
    needs_migration: bool,
    db_path: String,
}

async fn db_info(
    State(state): State<AppState>,
    _auth: AuthUser,
) -> Result<Json<DbInfo>, AppError> {
    let version = crate::db::get_schema_version(&state.pool).await
        .map_err(|e| AppError::Internal(e))?;

    let current = crate::db::CURRENT_SCHEMA_VERSION;

    let db_path = std::env::var("TRUSTRAG__DATABASE_URL")
        .unwrap_or_else(|_| "unknown".into());

    Ok(Json(DbInfo {
        schema_version: version,
        current_version: current,
        needs_migration: version < current,
        db_path,
    }))
}

#[derive(Serialize)]
struct BackupResult {
    success: bool,
    backup_path: Option<String>,
    message: String,
}

async fn backup_db(
    State(_state): State<AppState>,
    _auth: AuthUser,
) -> Result<Json<BackupResult>, AppError> {
    let data_dir = crate::config::AppConfig::load()
        .map(|c| c.data_dir)
        .unwrap_or_else(|_| ".".into());

    match crate::db::backup_database(&data_dir).await {
        Ok(path) => Ok(Json(BackupResult {
            success: true,
            backup_path: Some(path.clone()),
            message: format!("数据库已备份到: {}", path),
        })),
        Err(e) => Ok(Json(BackupResult {
            success: false,
            backup_path: None,
            message: format!("备份失败: {}", e),
        })),
    }
}

#[derive(Serialize)]
struct ResetResult {
    success: bool,
    message: String,
}

async fn reset_db(
    State(state): State<AppState>,
    _auth: AuthUser,
) -> Result<Json<ResetResult>, AppError> {
    let data_dir = crate::config::AppConfig::load()
        .map(|c| c.data_dir)
        .unwrap_or_else(|_| ".".into());

    match crate::db::backup_database(&data_dir).await {
        Ok(backup_path) => {
            tracing::info!(backup = %backup_path, "Database backed up before reset");
        }
        Err(e) => {
            tracing::warn!(error = %e, "Could not backup before reset, proceeding anyway");
        }
    }

    let tables = vec![
        "review_comments", "source_reviews", "review_tasks",
        "answer_reviews", "claim_reviews", "answer_versions",
        "retrieval_traces", "audit_trail", "document_metadata",
        "entity_relations", "entities",
        "review_records", "citations", "messages", "conversations",
        "embedding_configs", "model_configs",
        "document_chunks", "documents",
        "workspace_members", "workspaces", "users",
    ];

    tracing::info!(data_dir = %data_dir, "Resetting local database tables");

    for table in &tables {
        let sql = format!("DELETE FROM {}", table);
        match sqlx::query(&sql).execute(&state.pool).await {
            Ok(_) => tracing::debug!(table = table, "Table cleared"),
            Err(e) => tracing::warn!(table = table, error = %e, "Failed to clear table"),
        }
    }

    tracing::info!(data_dir = %data_dir, "Local database reset completed");

    Ok(Json(ResetResult {
        success: true,
        message: "本地数据已重置，请重新注册账号".into(),
    }))
}

#[derive(Serialize)]
struct TokenValidation {
    valid: bool,
    user_exists: bool,
    message: String,
}

async fn validate_token(
    State(state): State<AppState>,
    auth: AuthUser,
) -> Result<Json<TokenValidation>, AppError> {
    let user_id = auth.id.to_string();
    let exists = crate::db::validate_token_user(&state.pool, &user_id).await
        .unwrap_or(false);

    if exists {
        Ok(Json(TokenValidation {
            valid: true,
            user_exists: true,
            message: "Token 有效且用户存在".into(),
        }))
    } else {
        Ok(Json(TokenValidation {
            valid: true,
            user_exists: false,
            message: "Token 有效但当前数据库中不存在对应用户，请重新登录".into(),
        }))
    }
}

#[derive(Serialize)]
struct OcrToolStatus {
    name: String,
    display_name: String,
    available: bool,
    version: Option<String>,
    path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    languages: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    missing_hint: Option<String>,
}

#[derive(Serialize)]
struct OcrStatus {
    any_available: bool,
    pdf_ocr_ready: bool,
    overall_status: String,
    tesseract_path: Option<String>,
    poppler_path: Option<String>,
    tessdata_dir: Option<String>,
    tools: Vec<OcrToolStatus>,
    recommendation: String,
    ocr_config: crate::services::ocr_install::OcrConfig,
}

async fn check_binary(name: &str, args: &[&str]) -> (bool, Option<String>, Option<String>) {
    let try_commands = build_ocr_check_commands(name, args);
    for (prog, cmd_args) in &try_commands {
        if let Ok(output) = tokio::process::Command::new(prog).args(cmd_args).output().await {
            if output.status.success() {
                let combined = format!(
                    "{}\n{}",
                    String::from_utf8_lossy(&output.stdout),
                    String::from_utf8_lossy(&output.stderr)
                );
                let ver = combined.lines().next().unwrap_or("").trim().to_string();
                return (true, Some(ver), Some(prog.clone()));
            }
        }
    }
    (false, None, None)
}

async fn detect_tesseract_languages(tess_path: &str) -> Vec<String> {
    let result = tokio::process::Command::new(tess_path)
        .args(["--list-langs"])
        .output()
        .await;
    match result {
        Ok(output) => {
            let text = format!(
                "{}\n{}",
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
            text.lines()
                .skip(1) // first line is header
                .map(|l| l.trim().to_string())
                .filter(|l| !l.is_empty())
                .collect()
        }
        Err(_) => vec![],
    }
}

async fn ocr_status(
    _auth: AuthUser,
) -> Result<Json<OcrStatus>, AppError> {
    let config = crate::services::ocr_install::load_ocr_config();
    let overall = crate::services::ocr_install::compute_overall_status(&config).await;
    let mut tools = Vec::new();

    let tess_path = crate::services::ocr_install::resolve_tesseract_executable(&config);
    let (tess_ok, tess_ver, tess_path_check) = if let Some(ref p) = tess_path {
        if let Ok(output) = tokio::process::Command::new(p).args(["--version"]).output().await {
            if output.status.success() {
                let ver = String::from_utf8_lossy(&output.stdout).lines().next().unwrap_or("").trim().to_string();
                (true, Some(ver), Some(p.clone()))
            } else {
                (false, None, Some(p.clone()))
            }
        } else {
            (false, None, Some(p.clone()))
        }
    } else {
        check_binary("tesseract", &["tesseract", "--version"]).await
    };
    let tess_path = tess_path_check.or(tess_path);
    let mut tess_langs = Vec::new();
    if tess_ok {
        if let Some(ref p) = tess_path {
            tess_langs = detect_tesseract_languages(p).await;
        }
    }
    let tess_hint = if !tess_ok {
        Some("安装 Tesseract: brew install tesseract / apt install tesseract-ocr / choco install tesseract".into())
    } else if !tess_langs.contains(&"eng".to_string()) {
        Some("缺少 eng 语言包".into())
    } else {
        None
    };
    tools.push(OcrToolStatus {
        name: "tesseract".into(),
        display_name: "Tesseract OCR".into(),
        available: tess_ok,
        version: tess_ver,
        path: tess_path.clone(),
        languages: if tess_ok { Some(tess_langs.clone()) } else { None },
        missing_hint: tess_hint,
    });

    let has_chi_sim = tess_langs.contains(&"chi_sim".to_string());
    tools.push(OcrToolStatus {
        name: "chi_sim".into(),
        display_name: "中文简体语言包 (chi_sim)".into(),
        available: tess_ok && has_chi_sim,
        version: None,
        path: None,
        languages: None,
        missing_hint: if tess_ok && !has_chi_sim {
            Some("安装中文语言包: apt install tesseract-ocr-chi-sim / brew install tesseract-lang".into())
        } else { None },
    });

    let (pdftoppm_ok, pdftoppm_ver, pdftoppm_path) = check_binary("pdftoppm", &["pdftoppm", "-v"]).await;
    tools.push(OcrToolStatus {
        name: "pdftoppm".into(),
        display_name: "Poppler / pdftoppm (PDF 转图片)".into(),
        available: pdftoppm_ok,
        version: pdftoppm_ver,
        path: pdftoppm_path,
        languages: None,
        missing_hint: if !pdftoppm_ok {
            Some("安装 Poppler: brew install poppler / apt install poppler-utils / choco install poppler".into())
        } else { None },
    });

    let (pdfinfo_ok, pdfinfo_ver, pdfinfo_path) = check_binary("pdfinfo", &["pdfinfo", "-v"]).await;
    tools.push(OcrToolStatus {
        name: "pdfinfo".into(),
        display_name: "Poppler / pdfinfo".into(),
        available: pdfinfo_ok,
        version: pdfinfo_ver,
        path: pdfinfo_path,
        languages: None,
        missing_hint: if !pdfinfo_ok {
            Some("pdfinfo 通常与 pdftoppm 一同随 Poppler 安装".into())
        } else { None },
    });

    let (paddle_ok, paddle_ver, paddle_path) = check_binary(
        "paddleocr",
        &["python3", "-c", "import paddleocr; print(paddleocr.VERSION)"],
    ).await;
    tools.push(OcrToolStatus {
        name: "paddleocr".into(),
        display_name: "PaddleOCR".into(),
        available: paddle_ok,
        version: paddle_ver,
        path: paddle_path,
        languages: None,
        missing_hint: if !paddle_ok { Some("安装: pip3 install paddleocr paddlepaddle".into()) } else { None },
    });

    let any_ocr = tess_ok || paddle_ok;
    let pdf_ocr_ready = (tess_ok && pdftoppm_ok) || paddle_ok;

    Ok(Json(OcrStatus {
        any_available: any_ocr,
        pdf_ocr_ready,
        overall_status: overall.status,
        tesseract_path: overall.tesseract_path,
        poppler_path: overall.poppler_path,
        tessdata_dir: overall.tessdata_dir,
        tools,
        recommendation: overall.recommendation,
        ocr_config: config,
    }))
}

fn build_ocr_check_commands(_name: &str, default_commands: &[&str]) -> Vec<(String, Vec<String>)> {
    let attempts = vec![(
        default_commands[0].to_string(),
        default_commands[1..].iter().map(|s| s.to_string()).collect(),
    )];

    #[cfg(target_os = "windows")]
    let attempts = {
        let mut a = attempts;
        if _name == "tesseract" {
            for dir in &[
                r"C:\Program Files\Tesseract-OCR",
                r"C:\Program Files (x86)\Tesseract-OCR",
            ] {
                let exe = format!(r"{}\tesseract.exe", dir);
                a.push((exe, vec!["--version".to_string()]));
            }
        }
        a
    };

    attempts
}

// ---------------------------------------------------------------------------
// 17.9.1  Platform detection & install options
// ---------------------------------------------------------------------------

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum OsPlatform {
    Linux,
    MacOs,
    Windows,
}

impl std::fmt::Display for OsPlatform {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Linux => write!(f, "linux"),
            Self::MacOs => write!(f, "macos"),
            Self::Windows => write!(f, "windows"),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum PackageManager {
    Apt,
    Brew,
    Choco,
    Winget,
    Pip,
    None,
}

impl std::fmt::Display for PackageManager {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::Apt => write!(f, "apt"),
            Self::Brew => write!(f, "brew"),
            Self::Choco => write!(f, "choco"),
            Self::Winget => write!(f, "winget"),
            Self::Pip => write!(f, "pip"),
            Self::None => write!(f, "none"),
        }
    }
}

pub fn detect_platform() -> OsPlatform {
    if cfg!(target_os = "macos") {
        OsPlatform::MacOs
    } else if cfg!(target_os = "windows") {
        OsPlatform::Windows
    } else {
        OsPlatform::Linux
    }
}

pub async fn detect_package_managers() -> Vec<PackageManager> {
    let mut found = Vec::new();
    let candidates: &[(&str, PackageManager)] = &[
        ("apt", PackageManager::Apt),
        ("brew", PackageManager::Brew),
        ("choco", PackageManager::Choco),
        ("winget", PackageManager::Winget),
        ("pip3", PackageManager::Pip),
        ("pip", PackageManager::Pip),
    ];
    for &(bin, pm) in candidates {
        if which::which(bin).is_ok() && !found.contains(&pm) {
            found.push(pm);
        }
    }
    found
}

#[derive(Serialize)]
struct InstallMethod {
    package_manager: PackageManager,
    engine: String,
    command: String,
    needs_sudo: bool,
    description: String,
}

#[derive(Serialize)]
struct OcrInstallOptions {
    platform: OsPlatform,
    available_package_managers: Vec<PackageManager>,
    methods: Vec<InstallMethod>,
    recommended: Option<String>,
}

async fn ocr_install_options(
    _auth: AuthUser,
) -> Result<Json<OcrInstallOptions>, AppError> {
    let platform = detect_platform();
    let managers = detect_package_managers().await;

    let mut methods = Vec::new();

    match platform {
        OsPlatform::Linux => {
            if managers.contains(&PackageManager::Apt) {
                methods.push(InstallMethod {
                    package_manager: PackageManager::Apt,
                    engine: "tesseract".into(),
                    command: "sudo apt install -y tesseract-ocr tesseract-ocr-chi-sim tesseract-ocr-eng poppler-utils".into(),
                    needs_sudo: true,
                    description: "通过 apt 安装 Tesseract OCR 及中英文语言包".into(),
                });
            }
            if managers.contains(&PackageManager::Brew) {
                methods.push(InstallMethod {
                    package_manager: PackageManager::Brew,
                    engine: "tesseract".into(),
                    command: "brew install tesseract tesseract-lang poppler".into(),
                    needs_sudo: false,
                    description: "通过 Homebrew 安装 Tesseract OCR (Linuxbrew)".into(),
                });
            }
        }
        OsPlatform::MacOs => {
            if managers.contains(&PackageManager::Brew) {
                methods.push(InstallMethod {
                    package_manager: PackageManager::Brew,
                    engine: "tesseract".into(),
                    command: "brew install tesseract tesseract-lang poppler".into(),
                    needs_sudo: false,
                    description: "通过 Homebrew 安装 Tesseract OCR 及全部语言包".into(),
                });
            }
        }
        OsPlatform::Windows => {
            if managers.contains(&PackageManager::Choco) {
                methods.push(InstallMethod {
                    package_manager: PackageManager::Choco,
                    engine: "tesseract".into(),
                    command: "choco install tesseract poppler -y --no-progress".into(),
                    needs_sudo: true,
                    description: "通过 Chocolatey 安装 Tesseract OCR + Poppler (含 pdftoppm)".into(),
                });
            }
            if managers.contains(&PackageManager::Winget) {
                methods.push(InstallMethod {
                    package_manager: PackageManager::Winget,
                    engine: "tesseract".into(),
                    command: "winget install UB-Mannheim.TesseractOCR".into(),
                    needs_sudo: false,
                    description: "通过 winget 安装 Tesseract OCR (需另行安装 Poppler)".into(),
                });
            }
        }
    }

    if managers.contains(&PackageManager::Pip) {
        methods.push(InstallMethod {
            package_manager: PackageManager::Pip,
            engine: "paddleocr".into(),
            command: "pip3 install paddleocr paddlepaddle".into(),
            needs_sudo: false,
            description: "通过 pip 安装 PaddleOCR (中文效果优秀)".into(),
        });
    }

    let recommended = methods.first().map(|m| m.engine.clone());

    Ok(Json(OcrInstallOptions {
        platform,
        available_package_managers: managers,
        methods,
        recommended,
    }))
}

// ---------------------------------------------------------------------------
// 17.9.2  OCR install execution
// ---------------------------------------------------------------------------

#[derive(Deserialize)]
struct OcrInstallRequest {
    engine: String,
    package_manager: String,
}

#[derive(Serialize)]
struct OcrInstallResponse {
    success: bool,
    engine: String,
    package_manager: String,
    output: String,
    exit_code: Option<i32>,
    message: String,
}

async fn ocr_install(
    _auth: AuthUser,
    Json(req): Json<OcrInstallRequest>,
) -> Result<Json<OcrInstallResponse>, AppError> {
    let platform = detect_platform();
    let pm = req.package_manager.as_str();
    let engine = req.engine.as_str();

    let (program, args): (&str, Vec<&str>) = match (engine, pm, platform) {
        ("tesseract", "apt", OsPlatform::Linux) => (
            "sudo",
            vec!["apt", "install", "-y", "tesseract-ocr", "tesseract-ocr-chi-sim", "tesseract-ocr-eng", "poppler-utils"],
        ),
        ("tesseract", "brew", _) => (
            "brew",
            vec!["install", "tesseract", "tesseract-lang", "poppler"],
        ),
        ("tesseract", "choco", OsPlatform::Windows) => (
            "choco",
            vec!["install", "tesseract", "poppler", "-y", "--no-progress"],
        ),
        ("tesseract", "winget", OsPlatform::Windows) => (
            "winget",
            vec!["install", "--accept-source-agreements", "--accept-package-agreements", "UB-Mannheim.TesseractOCR"],
        ),
        ("paddleocr", "pip", _) => (
            "pip3",
            vec!["install", "paddleocr", "paddlepaddle"],
        ),
        _ => {
            return Ok(Json(OcrInstallResponse {
                success: false,
                engine: engine.into(),
                package_manager: pm.into(),
                output: String::new(),
                exit_code: None,
                message: format!("不支持的安装组合: engine={}, pm={}, platform={}", engine, pm, platform),
            }));
        }
    };

    tracing::info!(engine, package_manager = pm, %platform, "Starting OCR install");

    let install_timeout = std::time::Duration::from_secs(600); // 10 minutes

    let result = tokio::time::timeout(
        install_timeout,
        tokio::process::Command::new(program)
            .args(&args)
            .output(),
    )
    .await;

    match result {
        Ok(Ok(output)) => {
            let stdout = String::from_utf8_lossy(&output.stdout).to_string();
            let stderr = String::from_utf8_lossy(&output.stderr).to_string();
            let combined = format!("{}\n{}", stdout, stderr).trim().to_string();
            let lower = combined.to_lowercase();

            let already_installed = lower.contains("no available upgrade")
                || lower.contains("already installed")
                || lower.contains("找不到可用的升级")
                || lower.contains("已安装");
            let success = output.status.success() || already_installed;

            if success {
                tracing::info!(engine, already_installed, "OCR install completed successfully");
            } else {
                tracing::warn!(engine, exit_code = ?output.status.code(), "OCR install failed");
            }

            let message = if already_installed {
                format!("{} 已安装（最新版本），无需更新。", engine)
            } else if success {
                format!("{} 安装成功！请刷新页面确认状态。", engine)
            } else {
                let hint = if !output.status.success() && lower.contains("access") {
                    "\n提示: 可能需要管理员权限，请以管理员身份运行或手动执行安装命令。"
                } else {
                    ""
                };
                format!("{} 安装失败 (退出码: {:?})，请查看输出日志或手动安装。{}", engine, output.status.code(), hint)
            };

            Ok(Json(OcrInstallResponse {
                success,
                engine: engine.into(),
                package_manager: pm.into(),
                output: combined,
                exit_code: output.status.code(),
                message,
            }))
        }
        Ok(Err(e)) => Ok(Json(OcrInstallResponse {
            success: false,
            engine: engine.into(),
            package_manager: pm.into(),
            output: e.to_string(),
            exit_code: None,
            message: format!("执行安装命令失败: {}。请检查 {} 是否已正确安装。", e, pm),
        })),
        Err(_) => {
            tracing::warn!(engine, "OCR install timed out after 10 minutes");
            Ok(Json(OcrInstallResponse {
                success: false,
                engine: engine.into(),
                package_manager: pm.into(),
                output: "安装命令执行超时 (10 分钟)。".into(),
                exit_code: None,
                message: format!(
                    "{} 安装超时。可能原因：网络慢、包管理器锁、需要管理员权限。\n建议手动执行安装命令。",
                    engine
                ),
            }))
        }
    }
}

// ---------------------------------------------------------------------------
// 17.9.3  Async OCR install (task-based with polling)
// ---------------------------------------------------------------------------

#[derive(Serialize)]
struct OcrInstallStartResponse {
    task_id: String,
    status: OcrTaskStatus,
    log_file_path: Option<String>,
    logs_dir: Option<String>,
}

async fn ocr_preflight(_auth: AuthUser) -> Result<Json<crate::services::ocr_install::OcrPreflightResponse>, AppError> {
    Ok(Json(
        crate::services::ocr_install::run_comprehensive_preflight().await,
    ))
}

#[derive(Serialize)]
struct OcrLatestLogResponse {
    log_file_path: Option<String>,
    logs_dir: String,
}

async fn ocr_install_latest_log(
    _auth: AuthUser,
) -> Result<Json<OcrLatestLogResponse>, AppError> {
    Ok(Json(OcrLatestLogResponse {
        log_file_path: crate::services::ocr_install::read_latest_log_path(),
        logs_dir: crate::services::ocr_install::install_logs_dir()
            .display()
            .to_string(),
    }))
}

fn resolve_install_command(
    engine: &str,
    pm: &str,
    platform: OsPlatform,
) -> Result<(String, Vec<String>, OcrInstallMethod, bool), AppError> {
    use crate::services::ocr_install::OcrInstallMethod;
    let (program, args, method, needs_admin) = match (engine, pm, platform) {
        ("tesseract", "apt", OsPlatform::Linux) => (
            "sudo".into(),
            vec![
                "apt", "install", "-y", "tesseract-ocr", "tesseract-ocr-chi-sim",
                "tesseract-ocr-eng", "poppler-utils",
            ]
            .into_iter()
            .map(String::from)
            .collect(),
            OcrInstallMethod::Apt,
            true,
        ),
        ("tesseract", "brew", _) => (
            "brew".into(),
            vec!["install", "tesseract", "tesseract-lang", "poppler"]
                .into_iter()
                .map(String::from)
                .collect(),
            OcrInstallMethod::Brew,
            false,
        ),
        ("tesseract", "choco", OsPlatform::Windows) => (
            "choco".into(),
            vec!["install", "tesseract", "poppler", "-y", "--no-progress"]
                .into_iter()
                .map(String::from)
                .collect(),
            OcrInstallMethod::Choco,
            true,
        ),
        ("tesseract", "winget", OsPlatform::Windows) => (
            "winget".into(),
            vec![
                "install", "--accept-source-agreements", "--accept-package-agreements",
                "UB-Mannheim.TesseractOCR",
            ]
            .into_iter()
            .map(String::from)
            .collect(),
            OcrInstallMethod::Winget,
            true,
        ),
        ("paddleocr", "pip", _) => (
            "pip3".into(),
            vec!["install", "paddleocr", "paddlepaddle"]
                .into_iter()
                .map(String::from)
                .collect(),
            OcrInstallMethod::Pip,
            false,
        ),
        _ => {
            return Err(AppError::BadRequest(format!(
                "不支持的安装组合: engine={engine}, pm={pm}, platform={platform}"
            )));
        }
    };
    Ok((program, args, method, needs_admin))
}

async fn ocr_install_start(
    State(state): State<AppState>,
    _auth: AuthUser,
    Json(req): Json<OcrInstallRequest>,
) -> Result<Json<OcrInstallStartResponse>, AppError> {
    use crate::services::ocr_install::{
        analyze_failure_suggestions, install_logs_dir, push_log_line, task_cancel_flag_path,
        task_log_path, task_status_path, verify_installation, write_install_log_header,
        write_latest_task_pointer, write_task_status_file, OcrInstallStage, OcrTaskStatus,
        INSTALL_TIMEOUT_SECS,
    };
    use std::time::Instant;
    use tokio::io::{AsyncBufReadExt, BufReader};
    use tokio::process::Command;

    let platform = detect_platform();
    let pm = req.package_manager.as_str();
    let engine = req.engine.as_str();
    let (raw_program, raw_args, install_method, needs_admin) =
        resolve_install_command(engine, pm, platform)?;

    let is_admin = crate::services::ocr_install::is_running_as_admin().await;
    let use_elevation = needs_admin && !is_admin && cfg!(target_os = "windows") && pm != "pip";

    let task_id = uuid::Uuid::new_v4().to_string();
    let logs_dir_path = install_logs_dir();
    std::fs::create_dir_all(&logs_dir_path)
        .map_err(|e| AppError::Internal(anyhow::anyhow!("无法创建日志目录: {e}")))?;

    let log_file_path = task_log_path(&task_id);
    let status_file_path = task_status_path(&task_id);
    let cancel_flag_path = task_cancel_flag_path(&task_id);
    let logs_dir = logs_dir_path.display().to_string();

    let install_command_str = format!("{raw_program} {}", raw_args.join(" "));

    let (program, args, is_elevated, initial_status) = if use_elevation {
        #[cfg(target_os = "windows")]
        {
            let script = crate::services::ocr_install::write_windows_elevated_install_script(
                &task_id,
                &log_file_path,
                &status_file_path,
                &cancel_flag_path,
                &raw_program,
                &raw_args,
            )
            .map_err(|e| AppError::Internal(anyhow::anyhow!("无法创建提权安装脚本: {e}")))?;
            let (p, a) = crate::services::ocr_install::build_uac_launcher(&script);
            (p, a, true, OcrTaskStatus::WaitingForUac)
        }
        #[cfg(not(target_os = "windows"))]
        {
            (raw_program, raw_args, false, OcrTaskStatus::Running)
        }
    } else if is_admin && needs_admin {
        (raw_program, raw_args, true, OcrTaskStatus::Running)
    } else {
        (raw_program, raw_args, false, OcrTaskStatus::Running)
    };

    let command_str = install_command_str;

    let preflight = crate::services::ocr_install::run_comprehensive_preflight().await;
    write_install_log_header(&log_file_path, &preflight, &command_str);
    write_latest_task_pointer(&task_id);

    let now = chrono::Utc::now().to_rfc3339();
    let started_instant = Instant::now();
    let initial_stage = if initial_status == OcrTaskStatus::WaitingForUac {
        OcrInstallStage::WaitingForUac
    } else {
        OcrInstallStage::ExecutingInstall
    };

    let mut task = OcrInstallTask {
        task_id: task_id.clone(),
        engine: engine.to_string(),
        install_method,
        status: initial_status.clone(),
        stage: initial_stage,
        requires_admin: needs_admin,
        is_elevated,
        command: command_str.clone(),
        started_at: now.clone(),
        finished_at: None,
        duration_ms: None,
        exit_code: None,
        log_lines: vec![],
        message: None,
        error_message: None,
        pid: None,
        log_file: Some(log_file_path.display().to_string()),
        status_file: Some(status_file_path.display().to_string()),
        cancel_flag_file: Some(cancel_flag_path.display().to_string()),
        logs_dir: Some(logs_dir.clone()),
        last_output_at: Some(chrono::Utc::now().to_rfc3339()),
        stall_warning: false,
        suggestions: vec![],
        verification: None,
        residual_pids: vec![],
        residual_command_lines: vec![],
        windows_helper_log: Some(log_file_path.display().to_string()),
    };
    push_log_line(
        &mut task,
        format!("[info] 开始时间: {now}"),
        Some(&log_file_path),
    );
    push_log_line(
        &mut task,
        format!("[info] 执行命令: {command_str}"),
        Some(&log_file_path),
    );
    if use_elevation {
        push_log_line(
            &mut task,
            "[info] 等待 UAC 管理员授权...".into(),
            Some(&log_file_path),
        );
    } else if needs_admin && !is_admin {
        push_log_line(
            &mut task,
            "[warn] 当前非管理员，自动安装可能失败。建议以管理员身份运行 TrustRAG 或使用自定义路径。".into(),
            Some(&log_file_path),
        );
    }
    write_task_status_file(&task);

    {
        let mut tasks = state.ocr_tasks.lock().await;
        tasks.insert(task_id.clone(), task);
    }

    let child_slot = Arc::new(Mutex::new(None::<Child>));
    {
        let mut children = state.ocr_install_children.lock().await;
        children.insert(task_id.clone(), child_slot.clone());
    }

    let store = state.ocr_tasks.clone();
    let children_store = state.ocr_install_children.clone();
    let tid = task_id.clone();
    let prog = program;
    let cmd_args = args;
    let eng = engine.to_string();
    let pm_owned = pm.to_string();
    let log_file_for_task = log_file_path.clone();
    let poll_log = log_file_path.display().to_string();
    let initial_status_spawn = initial_status.clone();

    let poll_store = store.clone();
    let poll_tid = tid.clone();
    tokio::spawn(async move {
        crate::services::ocr_install::poll_log_file(poll_store, poll_tid, poll_log, 0).await;
    });

    tokio::spawn(async move {
        if initial_status_spawn == OcrTaskStatus::WaitingForUac {
            let mut tasks = store.lock().await;
            if let Some(t) = tasks.get_mut(&tid) {
                t.stage = OcrInstallStage::WaitingForUac;
                write_task_status_file(t);
            }
        }

        let child_result = Command::new(&prog)
            .args(&cmd_args)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn();

        let child = match child_result {
            Ok(c) => c,
            Err(e) => {
                let mut tasks = store.lock().await;
                if let Some(t) = tasks.get_mut(&tid) {
                    t.status = OcrTaskStatus::Failed;
                    t.stage = OcrInstallStage::Done;
                    t.finished_at = Some(chrono::Utc::now().to_rfc3339());
                    t.duration_ms = Some(started_instant.elapsed().as_millis() as u64);
                    push_log_line(
                        t,
                        format!("[error] 无法启动进程: {e}"),
                        Some(&log_file_for_task),
                    );
                    t.message = Some(format!("执行安装命令失败: {e}"));
                    t.error_message = Some(e.to_string());
                    t.suggestions = analyze_failure_suggestions(&e.to_string(), None, &pm_owned);
                    write_task_status_file(t);
                }
                children_store.lock().await.remove(&tid);
                return;
            }
        };

        let pid = child.id();
        {
            let mut slot = child_slot.lock().await;
            *slot = Some(child);
        }
        {
            let mut tasks = store.lock().await;
            if let Some(t) = tasks.get_mut(&tid) {
                t.pid = pid;
                t.status = OcrTaskStatus::Running;
                t.stage = OcrInstallStage::ExecutingInstall;
                if let Some(p) = pid {
                    push_log_line(
                        t,
                        format!("[info] 进程 PID: {p}"),
                        Some(&log_file_for_task),
                    );
                }
                write_task_status_file(t);
            }
        }

        let mut child = child_slot.lock().await.take().expect("child in slot");
        let stdout = child.stdout.take();
        let stderr = child.stderr.take();

        let stdout_handle = tokio::spawn({
            let store2 = store.clone();
            let tid2 = tid.clone();
            let log2 = log_file_for_task.clone();
            async move {
                if let Some(out) = stdout {
                    let mut reader = BufReader::new(out).lines();
                    while let Ok(Some(line)) = reader.next_line().await {
                        let mut tasks = store2.lock().await;
                        if let Some(t) = tasks.get_mut(&tid2) {
                            if matches!(
                                t.status,
                                OcrTaskStatus::Cancelled | OcrTaskStatus::Cancelling
                            ) {
                                break;
                            }
                            push_log_line(t, format!("[stdout] {line}"), Some(&log2));
                        }
                    }
                }
            }
        });

        let stderr_handle = tokio::spawn({
            let store3 = store.clone();
            let tid3 = tid.clone();
            let log3 = log_file_for_task.clone();
            async move {
                if let Some(err) = stderr {
                    let mut reader = BufReader::new(err).lines();
                    while let Ok(Some(line)) = reader.next_line().await {
                        let mut tasks = store3.lock().await;
                        if let Some(t) = tasks.get_mut(&tid3) {
                            if matches!(
                                t.status,
                                OcrTaskStatus::Cancelled | OcrTaskStatus::Cancelling
                            ) {
                                break;
                            }
                            push_log_line(t, format!("[stderr] {line}"), Some(&log3));
                        }
                    }
                }
            }
        });

        let timeout_result = tokio::time::timeout(
            std::time::Duration::from_secs(INSTALL_TIMEOUT_SECS),
            child.wait(),
        )
        .await;

        let _ = stdout_handle.await;
        let _ = stderr_handle.await;

        if timeout_result.is_err() {
            if let Some(p) = pid {
                crate::services::ocr_install::kill_process_tree(p).await;
            }
        }
        children_store.lock().await.remove(&tid);

        let mut tasks = store.lock().await;
        if let Some(t) = tasks.get_mut(&tid) {
            if matches!(
                t.status,
                OcrTaskStatus::Cancelled | OcrTaskStatus::Cancelling | OcrTaskStatus::CancelFailed
            ) {
                return;
            }
            t.finished_at = Some(chrono::Utc::now().to_rfc3339());
            t.duration_ms = Some(started_instant.elapsed().as_millis() as u64);

            match timeout_result {
                Ok(Ok(exit_status)) => {
                    let code = exit_status.code();
                    t.exit_code = code;
                    push_log_line(
                        t,
                        format!("[info] 退出码: {code:?}"),
                        Some(&log_file_for_task),
                    );
                    if code == Some(1223) {
                        t.status = OcrTaskStatus::ElevationCancelled;
                        t.stage = OcrInstallStage::Done;
                        t.message = Some("用户取消了 UAC 管理员授权。".into());
                        t.error_message = Some("elevation_cancelled".into());
                        t.suggestions = analyze_failure_suggestions("", Some(1223), &pm_owned);
                    } else {
                        let log_lower = t.log_lines.join("\n").to_lowercase();
                        let already_installed = log_lower.contains("already installed")
                            || log_lower.contains("no available upgrade")
                            || log_lower.contains("已安装");
                        let cmd_success = exit_status.success() || already_installed;
                        if !cmd_success {
                            t.status = OcrTaskStatus::Failed;
                            t.stage = OcrInstallStage::Done;
                            t.suggestions =
                                analyze_failure_suggestions(&log_lower, code, &pm_owned);
                            t.message = Some(format!(
                                "{eng} 安装失败 (退出码: {code:?})。"
                            ));
                        } else {
                            push_log_line(
                                t,
                                "[info] 安装命令执行完成，开始验证...".into(),
                                Some(&log_file_for_task),
                            );
                        }
                    }
                }
                Ok(Err(e)) => {
                    t.status = OcrTaskStatus::Failed;
                    t.stage = OcrInstallStage::Done;
                    push_log_line(
                        t,
                        format!("[error] 进程异常: {e}"),
                        Some(&log_file_for_task),
                    );
                    t.message = Some(format!("安装进程异常: {e}"));
                    t.error_message = Some(e.to_string());
                    t.suggestions = analyze_failure_suggestions(&e.to_string(), None, &pm_owned);
                }
                Err(_) => {
                    t.status = OcrTaskStatus::Timeout;
                    t.stage = OcrInstallStage::Done;
                    push_log_line(
                        t,
                        format!("[error] 安装超时 ({INSTALL_TIMEOUT_SECS} 秒)"),
                        Some(&log_file_for_task),
                    );
                    t.message = Some(format!("{eng} 安装超时。"));
                    t.suggestions = vec![
                        "安装长时间无响应。可能正在等待 UAC、网络下载或 Chocolatey 锁。".into(),
                    ];
                }
            }
            write_task_status_file(t);
        }
        drop(tasks);

        let should_verify = {
            let tasks = store.lock().await;
            tasks.get(&tid).map(|t| {
                !matches!(
                    t.status,
                    OcrTaskStatus::Failed
                        | OcrTaskStatus::Cancelled
                        | OcrTaskStatus::ElevationCancelled
                        | OcrTaskStatus::Timeout
                ) && t.exit_code.map(|c| c == 0).unwrap_or(false)
            }).unwrap_or(false)
        };

        if should_verify {
            {
                let mut tasks = store.lock().await;
                if let Some(t) = tasks.get_mut(&tid) {
                    t.stage = OcrInstallStage::VerifyingTesseract;
                    write_task_status_file(t);
                }
            }
            let verification = verify_installation(&eng).await;
            let mut tasks = store.lock().await;
            if let Some(t) = tasks.get_mut(&tid) {
                t.verification = Some(verification.clone());
                t.stage = OcrInstallStage::RefreshingConfig;
                for item in &verification.items {
                    let tag = if item.passed { "OK" } else { "FAIL" };
                    push_log_line(
                        t,
                        format!("[verify:{tag}] {} — {}", item.name, item.detail),
                        Some(&log_file_for_task),
                    );
                }
                if verification.all_passed {
                    t.status = OcrTaskStatus::Success;
                    t.stage = OcrInstallStage::Done;
                    t.message = Some(format!("{eng} 安装并验证成功！"));
                } else {
                    t.status = OcrTaskStatus::Failed;
                    t.stage = OcrInstallStage::Done;
                    t.message = Some(format!(
                        "{eng} 安装命令已结束，但验证未全部通过。{}",
                        if verification.path_refresh_needed {
                            "请重启 TrustRAG 或手动配置路径。"
                        } else {
                            "请查看验证详情。"
                        }
                    ));
                    if verification.path_refresh_needed {
                        t.suggestions.push(
                            "PATH 可能未刷新。请重启 TrustRAG 或手动配置 Tesseract/Poppler 路径。".into(),
                        );
                    }
                }
                push_log_line(
                    t,
                    format!("[info] 耗时: {} ms", t.duration_ms.unwrap_or(0)),
                    Some(&log_file_for_task),
                );
                write_task_status_file(t);
            }
        }
    });

    Ok(Json(OcrInstallStartResponse {
        task_id,
        status: initial_status.clone(),
        log_file_path: Some(log_file_path.display().to_string()),
        logs_dir: Some(logs_dir),
    }))
}

#[derive(Deserialize)]
struct OcrStatusQuery {
    since_line: Option<usize>,
}

#[derive(Serialize)]
struct OcrInstallStatusResponse {
    task_id: String,
    status: OcrTaskStatus,
    stage: OcrInstallStage,
    engine: String,
    install_method: OcrInstallMethod,
    requires_admin: bool,
    is_elevated: bool,
    command: String,
    started_at: String,
    finished_at: Option<String>,
    duration_ms: Option<u64>,
    exit_code: Option<i32>,
    message: Option<String>,
    error_message: Option<String>,
    log_file_path: Option<String>,
    status_file_path: Option<String>,
    logs_dir: Option<String>,
    last_log_at: Option<String>,
    stall_warning: bool,
    suggestions: Vec<String>,
    verification: Option<crate::services::ocr_install::OcrVerificationResult>,
    residual_pids: Vec<u32>,
    residual_command_lines: Vec<String>,
    new_lines: Vec<String>,
    total_lines: usize,
}

async fn ocr_install_status(
    State(state): State<AppState>,
    _auth: AuthUser,
    Path(task_id): Path<String>,
    Query(query): Query<OcrStatusQuery>,
) -> Result<Json<OcrInstallStatusResponse>, AppError> {
    crate::services::ocr_install::update_stall_warning(&state.ocr_tasks, &task_id).await;

    let tasks = state.ocr_tasks.lock().await;
    let task = tasks.get(&task_id).ok_or_else(|| {
        AppError::NotFound(format!("OCR install task not found: {}", task_id))
    })?;

    let since = query.since_line.unwrap_or(0);
    let new_lines = if since < task.log_lines.len() {
        task.log_lines[since..].to_vec()
    } else {
        vec![]
    };

    Ok(Json(OcrInstallStatusResponse {
        task_id: task.task_id.clone(),
        status: task.status.clone(),
        stage: task.stage.clone(),
        engine: task.engine.clone(),
        install_method: task.install_method.clone(),
        requires_admin: task.requires_admin,
        is_elevated: task.is_elevated,
        command: task.command.clone(),
        started_at: task.started_at.clone(),
        finished_at: task.finished_at.clone(),
        duration_ms: task.duration_ms,
        exit_code: task.exit_code,
        message: task.message.clone(),
        error_message: task.error_message.clone(),
        log_file_path: task.log_file.clone(),
        status_file_path: task.status_file.clone(),
        logs_dir: task.logs_dir.clone(),
        last_log_at: task.last_output_at.clone(),
        stall_warning: task.stall_warning,
        suggestions: task.suggestions.clone(),
        verification: task.verification.clone(),
        residual_pids: task.residual_pids.clone(),
        residual_command_lines: task.residual_command_lines.clone(),
        new_lines,
        total_lines: task.log_lines.len(),
    }))
}

async fn ocr_install_task_logs(
    _auth: AuthUser,
    Path(task_id): Path<String>,
    Query(query): Query<OcrStatusQuery>,
) -> Result<Json<serde_json::Value>, AppError> {
    let since = query.since_line.unwrap_or(0);
    let (new_lines, total) = crate::services::ocr_install::read_task_logs(&task_id, since);
    Ok(Json(serde_json::json!({
        "task_id": task_id,
        "new_lines": new_lines,
        "total_lines": total,
        "log_file_path": crate::services::ocr_install::task_log_path(&task_id).display().to_string(),
    })))
}

async fn ocr_config_get(
    _auth: AuthUser,
) -> Result<Json<crate::services::ocr_install::OcrConfig>, AppError> {
    Ok(Json(crate::services::ocr_install::load_ocr_config()))
}

#[derive(Deserialize)]
struct OcrConfigSaveRequest {
    tesseract_path: Option<String>,
    tessdata_dir: Option<String>,
    poppler_bin_dir: Option<String>,
    default_language: Option<String>,
    ocr_enabled: Option<bool>,
    prefer_custom_paths: Option<bool>,
    allow_auto_install: Option<bool>,
    portable_runtime_dir: Option<String>,
}

#[derive(Serialize)]
struct OcrConfigSaveResponse {
    success: bool,
    config: crate::services::ocr_install::OcrConfig,
    verification: crate::services::ocr_install::OcrVerificationResult,
    message: String,
}

async fn ocr_config_save(
    _auth: AuthUser,
    Json(req): Json<OcrConfigSaveRequest>,
) -> Result<Json<OcrConfigSaveResponse>, AppError> {
    let mut config = crate::services::ocr_install::load_ocr_config();
    if let Some(v) = req.tesseract_path {
        config.tesseract_path = if v.is_empty() { None } else { Some(v) };
    }
    if let Some(v) = req.tessdata_dir {
        config.tessdata_dir = if v.is_empty() { None } else { Some(v) };
    }
    if let Some(v) = req.poppler_bin_dir {
        config.poppler_bin_dir = if v.is_empty() { None } else { Some(v) };
    }
    if let Some(v) = req.default_language {
        config.default_language = v;
    }
    if let Some(v) = req.ocr_enabled {
        config.ocr_enabled = v;
    }
    if let Some(v) = req.prefer_custom_paths {
        config.prefer_custom_paths = v;
    }
    if let Some(v) = req.allow_auto_install {
        config.allow_auto_install = v;
    }
    if let Some(v) = req.portable_runtime_dir {
        config.portable_runtime_dir = if v.is_empty() { None } else { Some(v) };
    }

    crate::services::ocr_install::save_ocr_config(&config)
        .map_err(|e| AppError::Internal(anyhow::anyhow!("保存 OCR 配置失败: {e}")))?;

    let verification = crate::services::ocr_install::verify_with_config("tesseract", &config).await;
    let message = if verification.all_passed {
        "OCR 路径配置已保存并验证通过。".into()
    } else {
        "OCR 路径配置已保存，但验证未全部通过。请检查路径。".into()
    };

    Ok(Json(OcrConfigSaveResponse {
        success: verification.all_passed,
        config,
        verification,
        message,
    }))
}

#[derive(Serialize)]
struct OcrVerifyResponse {
    verification: crate::services::ocr_install::OcrVerificationResult,
    overall: crate::services::ocr_install::OcrOverallStatus,
}

async fn ocr_verify(
    _auth: AuthUser,
) -> Result<Json<OcrVerifyResponse>, AppError> {
    let config = crate::services::ocr_install::load_ocr_config();
    let verification = crate::services::ocr_install::verify_with_config("tesseract", &config).await;
    let overall = crate::services::ocr_install::compute_overall_status(&config).await;
    Ok(Json(OcrVerifyResponse {
        verification,
        overall,
    }))
}

#[derive(Serialize)]
struct OcrCancelResponse {
    success: bool,
    message: String,
}

async fn ocr_install_cancel(
    State(state): State<AppState>,
    _auth: AuthUser,
    Path(task_id): Path<String>,
) -> Result<Json<OcrCancelResponse>, AppError> {
    use crate::services::ocr_install::{push_log_line, write_task_status_file, OcrTaskStatus};

    let can_cancel = {
        let tasks = state.ocr_tasks.lock().await;
        let task = tasks.get(&task_id).ok_or_else(|| {
            AppError::NotFound(format!("OCR install task not found: {task_id}"))
        })?;
        matches!(
            task.status,
            OcrTaskStatus::Running
                | OcrTaskStatus::WaitingForUac
                | OcrTaskStatus::Pending
        )
    };

    if !can_cancel {
        return Ok(Json(OcrCancelResponse {
            success: false,
            message: "任务已不在可取消状态".into(),
        }));
    }

    {
        let mut tasks = state.ocr_tasks.lock().await;
        if let Some(task) = tasks.get_mut(&task_id) {
            let log_path_buf = task.log_file.clone();
            let log_path = log_path_buf.as_deref().map(std::path::Path::new);
            task.status = OcrTaskStatus::Cancelling;
            task.message = Some("正在取消安装...".into());
            push_log_line(task, "[info] 用户请求取消安装".into(), log_path);
            push_log_line(task, "[info] 正在终止安装进程...".into(), log_path);
            write_task_status_file(task);
        }
    }

    let store = state.ocr_tasks.clone();
    let children_store = state.ocr_install_children.clone();
    let tid = task_id.clone();
    tokio::spawn(async move {
        crate::services::ocr_install::perform_async_cancel(store, children_store, tid).await;
    });

    Ok(Json(OcrCancelResponse {
        success: true,
        message: "取消请求已接受，正在终止安装进程".into(),
    }))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_detect_platform() {
        let p = detect_platform();
        if cfg!(target_os = "macos") {
            assert_eq!(p, OsPlatform::MacOs);
        } else if cfg!(target_os = "windows") {
            assert_eq!(p, OsPlatform::Windows);
        } else {
            assert_eq!(p, OsPlatform::Linux);
        }
    }

    #[test]
    fn test_os_platform_display() {
        assert_eq!(OsPlatform::Linux.to_string(), "linux");
        assert_eq!(OsPlatform::MacOs.to_string(), "macos");
        assert_eq!(OsPlatform::Windows.to_string(), "windows");
    }

    #[test]
    fn test_package_manager_display() {
        assert_eq!(PackageManager::Apt.to_string(), "apt");
        assert_eq!(PackageManager::Brew.to_string(), "brew");
        assert_eq!(PackageManager::Choco.to_string(), "choco");
        assert_eq!(PackageManager::Winget.to_string(), "winget");
        assert_eq!(PackageManager::Pip.to_string(), "pip");
        assert_eq!(PackageManager::None.to_string(), "none");
    }

    #[tokio::test]
    async fn test_detect_package_managers() {
        let managers = detect_package_managers().await;
        // Should not contain duplicates
        let mut deduped = managers.clone();
        deduped.dedup();
        assert_eq!(managers.len(), deduped.len());
    }

    #[test]
    fn test_ocr_install_request_deser() {
        let json = r#"{"engine":"tesseract","package_manager":"apt"}"#;
        let req: OcrInstallRequest = serde_json::from_str(json).unwrap();
        assert_eq!(req.engine, "tesseract");
        assert_eq!(req.package_manager, "apt");
    }

    #[test]
    fn test_ocr_install_options_serialization() {
        let opts = OcrInstallOptions {
            platform: OsPlatform::Linux,
            available_package_managers: vec![PackageManager::Apt, PackageManager::Pip],
            methods: vec![InstallMethod {
                package_manager: PackageManager::Apt,
                engine: "tesseract".into(),
                command: "sudo apt install -y tesseract-ocr".into(),
                needs_sudo: true,
                description: "Install via apt".into(),
            }],
            recommended: Some("tesseract".into()),
        };
        let json = serde_json::to_value(&opts).unwrap();
        assert_eq!(json["platform"], "linux");
        assert!(json["methods"].is_array());
        assert_eq!(json["methods"][0]["engine"], "tesseract");
        assert_eq!(json["methods"][0]["needs_sudo"], true);
        assert_eq!(json["recommended"], "tesseract");
    }

    #[test]
    fn test_ocr_task_status_serde() {
        let status = OcrTaskStatus::Running;
        let json = serde_json::to_string(&status).unwrap();
        assert_eq!(json, "\"running\"");

        let success: OcrTaskStatus = serde_json::from_str("\"success\"").unwrap();
        assert_eq!(success, OcrTaskStatus::Success);

        let cancelled: OcrTaskStatus = serde_json::from_str("\"cancelled\"").unwrap();
        assert_eq!(cancelled, OcrTaskStatus::Cancelled);

        let elevation: OcrTaskStatus = serde_json::from_str("\"elevation_cancelled\"").unwrap();
        assert_eq!(elevation, OcrTaskStatus::ElevationCancelled);
    }

    #[test]
    fn test_resolve_install_command_choco() {
        let (prog, args, method, admin) =
            resolve_install_command("tesseract", "choco", OsPlatform::Windows).unwrap();
        assert_eq!(prog, "choco");
        assert!(args.contains(&"tesseract".to_string()));
        assert_eq!(method, OcrInstallMethod::Choco);
        assert!(admin);
    }
}
