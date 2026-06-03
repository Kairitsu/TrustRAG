use std::collections::HashMap;
use std::sync::Arc;

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

pub type OcrTaskStore = Arc<Mutex<HashMap<String, OcrInstallTask>>>;

pub fn new_ocr_task_store() -> OcrTaskStore {
    Arc::new(Mutex::new(HashMap::new()))
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
        .route("/system/ocr-install/cancel/{task_id}", post(ocr_install_cancel))
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

    for table in &tables {
        let sql = format!("DELETE FROM {}", table);
        match sqlx::query(&sql).execute(&state.pool).await {
            Ok(_) => tracing::debug!(table = table, "Table cleared"),
            Err(e) => tracing::warn!(table = table, error = %e, "Failed to clear table"),
        }
    }

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
    tools: Vec<OcrToolStatus>,
    recommendation: String,
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
    let mut tools = Vec::new();

    let (tess_ok, tess_ver, tess_path) = check_binary("tesseract", &["tesseract", "--version"]).await;
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

    let recommendation = if pdf_ocr_ready {
        "OCR 工具已就绪，可处理扫描版 PDF。".into()
    } else if tess_ok && !pdftoppm_ok {
        "已检测到 Tesseract，但缺少 pdftoppm (Poppler)，无法处理扫描版 PDF。\n请安装 Poppler 后重试。".into()
    } else if !any_ocr {
        "未检测到 OCR 工具。建议安装 Tesseract + Poppler (推荐) 或 PaddleOCR。".into()
    } else {
        "OCR 基础工具已安装，建议补全依赖以支持扫描版 PDF。".into()
    };

    Ok(Json(OcrStatus { any_available: any_ocr, pdf_ocr_ready, tools, recommendation }))
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

/// On Windows, wraps choco/winget install commands in a PowerShell script
/// that requests UAC elevation via `Start-Process -Verb RunAs`.
/// Output is redirected to a temp log file which the parent reads back.
/// pip does not need elevation.
#[cfg(target_os = "windows")]
fn wrap_windows_elevated(pm: &str, program: String, args: Vec<String>) -> (String, Vec<String>) {
    if pm == "pip" {
        return (program, args);
    }

    let inner_cmd = format!("{} {}", program, args.join(" "));
    let log_file = format!(
        "{}\\trustrag_ocr_install_{}.log",
        std::env::temp_dir().display(),
        std::process::id()
    );

    let ps_script = format!(
        "$logFile = '{}'; \
         $proc = Start-Process -FilePath '{}' -ArgumentList '{}' \
         -Verb RunAs -Wait -PassThru \
         -RedirectStandardOutput $logFile \
         -RedirectStandardError ($logFile + '.err'); \
         if (Test-Path $logFile) {{ Get-Content $logFile }}; \
         if (Test-Path ($logFile + '.err')) {{ Get-Content ($logFile + '.err') }}; \
         exit $proc.ExitCode",
        log_file,
        program,
        args.join("' '"),
    );

    (
        "powershell".into(),
        vec![
            "-NoProfile".into(),
            "-ExecutionPolicy".into(),
            "Bypass".into(),
            "-Command".into(),
            ps_script,
        ],
    )
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

#[derive(Debug, Clone, Serialize)]
pub struct OcrInstallTask {
    pub task_id: String,
    pub engine: String,
    pub package_manager: String,
    pub status: OcrTaskStatus,
    pub started_at: String,
    pub finished_at: Option<String>,
    pub exit_code: Option<i32>,
    pub log_lines: Vec<String>,
    pub message: Option<String>,
    pub pid: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum OcrTaskStatus {
    Running,
    Completed,
    Failed,
    Cancelled,
}

#[derive(Serialize)]
struct OcrInstallStartResponse {
    task_id: String,
    status: OcrTaskStatus,
}

async fn ocr_install_start(
    State(state): State<AppState>,
    _auth: AuthUser,
    Json(req): Json<OcrInstallRequest>,
) -> Result<Json<OcrInstallStartResponse>, AppError> {
    let platform = detect_platform();
    let pm = req.package_manager.as_str();
    let engine = req.engine.as_str();

    let (program, args): (String, Vec<String>) = match (engine, pm, platform) {
        ("tesseract", "apt", OsPlatform::Linux) => (
            "sudo".into(),
            vec!["apt", "install", "-y", "tesseract-ocr", "tesseract-ocr-chi-sim", "tesseract-ocr-eng", "poppler-utils"]
                .into_iter().map(String::from).collect(),
        ),
        ("tesseract", "brew", _) => (
            "brew".into(),
            vec!["install", "tesseract", "tesseract-lang", "poppler"]
                .into_iter().map(String::from).collect(),
        ),
        ("tesseract", "choco", OsPlatform::Windows) => (
            "choco".into(),
            vec!["install", "tesseract", "poppler", "-y", "--no-progress"]
                .into_iter().map(String::from).collect(),
        ),
        ("tesseract", "winget", OsPlatform::Windows) => (
            "winget".into(),
            vec!["install", "--accept-source-agreements", "--accept-package-agreements", "UB-Mannheim.TesseractOCR"]
                .into_iter().map(String::from).collect(),
        ),
        ("paddleocr", "pip", _) => (
            "pip3".into(),
            vec!["install", "paddleocr", "paddlepaddle"]
                .into_iter().map(String::from).collect(),
        ),
        _ => {
            return Err(AppError::BadRequest(format!(
                "不支持的安装组合: engine={}, pm={}, platform={}", engine, pm, platform
            )));
        }
    };

    #[cfg(target_os = "windows")]
    let (program, args) = wrap_windows_elevated(pm, program, args);

    let task_id = uuid::Uuid::new_v4().to_string();
    let now = chrono::Utc::now().to_rfc3339();

    let task = OcrInstallTask {
        task_id: task_id.clone(),
        engine: engine.to_string(),
        package_manager: pm.to_string(),
        status: OcrTaskStatus::Running,
        started_at: now,
        finished_at: None,
        exit_code: None,
        log_lines: vec![format!("Starting: {} {}", program, args.join(" "))],
        message: None,
        pid: None,
    };

    {
        let mut tasks = state.ocr_tasks.lock().await;
        tasks.insert(task_id.clone(), task);
    }

    let store = state.ocr_tasks.clone();
    let tid = task_id.clone();
    let prog = program;
    let cmd_args = args;
    let eng = engine.to_string();

    tokio::spawn(async move {
        use tokio::io::{AsyncBufReadExt, BufReader};
        use tokio::process::Command;

        let child = Command::new(&prog)
            .args(&cmd_args)
            .stdout(std::process::Stdio::piped())
            .stderr(std::process::Stdio::piped())
            .spawn();

        let mut child = match child {
            Ok(c) => c,
            Err(e) => {
                let mut tasks = store.lock().await;
                if let Some(t) = tasks.get_mut(&tid) {
                    t.status = OcrTaskStatus::Failed;
                    t.finished_at = Some(chrono::Utc::now().to_rfc3339());
                    t.log_lines.push(format!("Failed to start process: {}", e));
                    t.message = Some(format!("执行安装命令失败: {}", e));
                }
                return;
            }
        };

        let pid = child.id();
        {
            let mut tasks = store.lock().await;
            if let Some(t) = tasks.get_mut(&tid) {
                t.pid = pid;
            }
        }

        let stdout = child.stdout.take();
        let stderr = child.stderr.take();
        let store2 = store.clone();
        let tid2 = tid.clone();

        let stdout_handle = tokio::spawn(async move {
            if let Some(out) = stdout {
                let mut reader = BufReader::new(out).lines();
                while let Ok(Some(line)) = reader.next_line().await {
                    let mut tasks = store2.lock().await;
                    if let Some(t) = tasks.get_mut(&tid2) {
                        if t.status == OcrTaskStatus::Cancelled {
                            break;
                        }
                        t.log_lines.push(line);
                    }
                }
            }
        });

        let store3 = store.clone();
        let tid3 = tid.clone();
        let stderr_handle = tokio::spawn(async move {
            if let Some(err) = stderr {
                let mut reader = BufReader::new(err).lines();
                while let Ok(Some(line)) = reader.next_line().await {
                    let mut tasks = store3.lock().await;
                    if let Some(t) = tasks.get_mut(&tid3) {
                        if t.status == OcrTaskStatus::Cancelled {
                            break;
                        }
                        t.log_lines.push(format!("[stderr] {}", line));
                    }
                }
            }
        });

        let timeout_result = tokio::time::timeout(
            std::time::Duration::from_secs(600),
            child.wait(),
        ).await;

        let _ = stdout_handle.await;
        let _ = stderr_handle.await;

        let mut tasks = store.lock().await;
        if let Some(t) = tasks.get_mut(&tid) {
            if t.status == OcrTaskStatus::Cancelled {
                return;
            }
            t.finished_at = Some(chrono::Utc::now().to_rfc3339());

            match timeout_result {
                Ok(Ok(exit_status)) => {
                    t.exit_code = exit_status.code();
                    let log_lower = t.log_lines.join("\n").to_lowercase();
                    let already_installed = log_lower.contains("already installed")
                        || log_lower.contains("no available upgrade")
                        || log_lower.contains("已安装");
                    let success = exit_status.success() || already_installed;

                    if success {
                        t.status = OcrTaskStatus::Completed;
                        t.log_lines.push("安装命令执行完成，正在验证...".to_string());
                    } else {
                        t.status = OcrTaskStatus::Failed;
                        t.message = Some(format!(
                            "{} 安装失败 (退出码: {:?})，请查看日志或手动安装。",
                            eng, exit_status.code()
                        ));
                    }
                }
                Ok(Err(e)) => {
                    t.status = OcrTaskStatus::Failed;
                    t.log_lines.push(format!("Process error: {}", e));
                    t.message = Some(format!("安装进程异常: {}", e));
                }
                Err(_) => {
                    t.status = OcrTaskStatus::Failed;
                    t.log_lines.push("Installation timed out after 10 minutes.".to_string());
                    t.message = Some(format!("{} 安装超时 (10 分钟)。建议手动安装。", eng));
                }
            }
        }

        // Post-install verification: re-check if the binary is now available
        {
            let should_verify = {
                let tasks = store.lock().await;
                tasks.get(&tid).map(|t| t.status == OcrTaskStatus::Completed).unwrap_or(false)
            };

            if should_verify {
                let (check_name, check_args): (&str, &[&str]) = if eng == "paddleocr" {
                    ("python3", &["python3", "-c", "import paddleocr; print(paddleocr.VERSION)"])
                } else {
                    ("tesseract", &["tesseract", "--version"])
                };

                let (ok, ver, path) = check_binary(check_name, check_args).await;

                let mut tasks = store.lock().await;
                if let Some(t) = tasks.get_mut(&tid) {
                    if ok {
                        let ver_str = ver.unwrap_or_default();
                        let path_str = path.unwrap_or_default();
                        t.log_lines.push(format!("验证成功: {} v{} ({})", check_name, ver_str, path_str));
                        t.message = Some(format!(
                            "{} 安装并验证成功！版本: {}",
                            eng, ver_str
                        ));
                    } else {
                        t.log_lines.push(format!(
                            "警告: 安装命令执行成功，但 {} 仍不可用。可能需要重启终端或将其添加到 PATH。",
                            check_name
                        ));
                        t.message = Some(format!(
                            "{} 安装命令已完成，但验证未通过。建议重启应用后重新检测。",
                            eng
                        ));
                    }
                }
            }
        }
    });

    Ok(Json(OcrInstallStartResponse {
        task_id,
        status: OcrTaskStatus::Running,
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
    engine: String,
    package_manager: String,
    started_at: String,
    finished_at: Option<String>,
    exit_code: Option<i32>,
    message: Option<String>,
    new_lines: Vec<String>,
    total_lines: usize,
}

async fn ocr_install_status(
    State(state): State<AppState>,
    _auth: AuthUser,
    Path(task_id): Path<String>,
    Query(query): Query<OcrStatusQuery>,
) -> Result<Json<OcrInstallStatusResponse>, AppError> {
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
        engine: task.engine.clone(),
        package_manager: task.package_manager.clone(),
        started_at: task.started_at.clone(),
        finished_at: task.finished_at.clone(),
        exit_code: task.exit_code,
        message: task.message.clone(),
        new_lines,
        total_lines: task.log_lines.len(),
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
    let mut tasks = state.ocr_tasks.lock().await;
    let task = tasks.get_mut(&task_id).ok_or_else(|| {
        AppError::NotFound(format!("OCR install task not found: {}", task_id))
    })?;

    if task.status != OcrTaskStatus::Running {
        return Ok(Json(OcrCancelResponse {
            success: false,
            message: format!("任务已不在运行状态 ({})", serde_json::to_string(&task.status).unwrap_or_default()),
        }));
    }

    if let Some(pid) = task.pid {
        #[cfg(unix)]
        {
            unsafe { libc::kill(pid as i32, libc::SIGTERM); }
        }
        #[cfg(windows)]
        {
            let _ = tokio::process::Command::new("taskkill")
                .args(&["/PID", &pid.to_string(), "/F"])
                .output()
                .await;
        }
    }

    task.status = OcrTaskStatus::Cancelled;
    task.finished_at = Some(chrono::Utc::now().to_rfc3339());
    task.log_lines.push("Installation cancelled by user.".to_string());
    task.message = Some("安装已被用户取消。".to_string());

    Ok(Json(OcrCancelResponse {
        success: true,
        message: "安装已取消".to_string(),
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
    #[cfg(target_os = "windows")]
    fn test_wrap_windows_elevated_choco() {
        let (prog, args) = wrap_windows_elevated(
            "choco",
            "choco".into(),
            vec!["install".into(), "tesseract".into(), "-y".into()],
        );
        assert_eq!(prog, "powershell");
        assert!(args.contains(&"-NoProfile".to_string()));
        assert!(args.contains(&"Bypass".to_string()));
        let cmd = args.last().unwrap();
        assert!(cmd.contains("Start-Process"));
        assert!(cmd.contains("Verb RunAs"));
        assert!(cmd.contains("choco"));
    }

    #[test]
    #[cfg(target_os = "windows")]
    fn test_wrap_windows_elevated_pip_no_elevation() {
        let (prog, args) = wrap_windows_elevated(
            "pip",
            "pip3".into(),
            vec!["install".into(), "paddleocr".into()],
        );
        assert_eq!(prog, "pip3");
        assert_eq!(args, vec!["install".to_string(), "paddleocr".to_string()]);
    }

    #[test]
    fn test_ocr_task_status_serde() {
        let status = OcrTaskStatus::Running;
        let json = serde_json::to_string(&status).unwrap();
        assert_eq!(json, "\"running\"");

        let completed: OcrTaskStatus = serde_json::from_str("\"completed\"").unwrap();
        assert_eq!(completed, OcrTaskStatus::Completed);

        let cancelled: OcrTaskStatus = serde_json::from_str("\"cancelled\"").unwrap();
        assert_eq!(cancelled, OcrTaskStatus::Cancelled);

        let failed: OcrTaskStatus = serde_json::from_str("\"failed\"").unwrap();
        assert_eq!(failed, OcrTaskStatus::Failed);
    }

    #[test]
    fn test_ocr_install_task_serialization() {
        let task = OcrInstallTask {
            task_id: "test-123".into(),
            engine: "tesseract".into(),
            package_manager: "choco".into(),
            status: OcrTaskStatus::Running,
            started_at: "2026-05-27T10:00:00Z".into(),
            finished_at: None,
            exit_code: None,
            log_lines: vec!["Starting install...".into()],
            message: None,
            pid: Some(1234),
        };
        let json = serde_json::to_value(&task).unwrap();
        assert_eq!(json["task_id"], "test-123");
        assert_eq!(json["status"], "running");
        assert_eq!(json["pid"], 1234);
        assert!(json["finished_at"].is_null());
    }
}
