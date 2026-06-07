# TrustRAG Windows uninstall residue checker.
# Usage (PowerShell):
#   powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\windows\check_trustrag_residue.ps1

[CmdletBinding()]
param(
    [switch]$IncludeInstallDir
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'trustrag_paths.ps1')

$residue = New-Object System.Collections.Generic.List[string]

function Add-Residue {
    param([string]$Category, [string]$Path)
    if ($Path) {
        $residue.Add("[$Category] $Path")
    }
}

Write-Host '=== TrustRAG Residue Check ==='
Write-Host ''

# 1. Running processes
$procs = @(Get-TrustRagRunningProcesses)
foreach ($proc in $procs) {
    Add-Residue 'PROCESS' "$($proc.ProcessName) (PID $($proc.Id))"
}

# 2. Install directory
$installDir = Get-TrustRagDefaultInstallDirectory
if ($installDir -and (Test-Path -LiteralPath $installDir)) {
    Add-Residue 'INSTALL_DIR' $installDir
}

# 3. AppData / LocalAppData data directories
foreach ($dir in Get-TrustRagKnownDataDirectories) {
    if (Test-Path -LiteralPath $dir) {
        Add-Residue 'DATA_DIR' $dir
    }
}

# 4. Temp residue
foreach ($item in Get-TrustRagTempResidueItems) {
    if (Test-Path -LiteralPath $item) {
        Add-Residue 'TEMP' $item
    }
}

# 5. Shortcuts
foreach ($shortcut in Get-TrustRagShortcutPaths) {
    if (Test-Path -LiteralPath $shortcut) {
        Add-Residue 'SHORTCUT' $shortcut
    }
}

# 6. Uninstall registry entries (Inno Setup)
foreach ($key in Get-TrustRagUninstallRegistryHints) {
    if (Test-Path -LiteralPath "Registry::$key") {
        Add-Residue 'REGISTRY' $key
    }
}

# Optional: custom install dir from caller
if ($IncludeInstallDir -and $env:TRUSTRAG_INSTALL_DIR) {
    $custom = $env:TRUSTRAG_INSTALL_DIR
    if (Test-Path -LiteralPath $custom) {
        Add-Residue 'INSTALL_DIR' $custom
    }
}

if ($residue.Count -eq 0) {
    Write-Host 'PASS — No TrustRAG residue detected.'
    exit 0
}

Write-Host 'FAIL — TrustRAG residue found:'
Write-Host ''
foreach ($line in $residue) {
    Write-Host "  $line"
}
Write-Host ''
Write-Host "Total: $($residue.Count) item(s)"
exit 1