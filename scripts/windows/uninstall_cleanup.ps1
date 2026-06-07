# TrustRAG Windows uninstall helper — stop processes and delete local data.
# Called from Inno Setup uninstaller (installer.iss).

[CmdletBinding()]
param(
    [switch]$StopProcessesOnly,
    [switch]$DeleteLocalData,
    [string]$InstallDir = '',
    [int]$GraceSeconds = 5,
    [int]$ForceWaitSeconds = 15
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir 'trustrag_paths.ps1')

function Wait-TrustRagPortsReleased {
    param([int]$TimeoutSeconds = 10)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    $ports = @(8080)

    while ((Get-Date) -lt $deadline) {
        $busy = $false
        foreach ($port in $ports) {
            $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
            if ($conn) {
                $owner = $conn | Select-Object -ExpandProperty OwningProcess -Unique
                foreach ($pid in $owner) {
                    $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
                    if ($proc -and (Test-TrustRagProcessName $proc.ProcessName)) {
                        $busy = $true
                    }
                }
            }
        }
        if (-not $busy) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Stop-TrustRagProcesses {
    $processes = @(Get-TrustRagRunningProcesses)
    if ($processes.Count -eq 0) {
        Write-Host 'No TrustRAG processes running.'
        return 0
    }

    Write-Host "Found $($processes.Count) TrustRAG-related process(es). Attempting graceful shutdown..."
    foreach ($proc in $processes) {
        try {
            if ($proc.MainWindowHandle -ne 0) {
                $null = $proc.CloseMainWindow()
            }
        } catch {
            Write-Warning "Graceful close failed for PID $($proc.Id): $_"
        }
    }

    Start-Sleep -Seconds $GraceSeconds

    $remaining = @(Get-TrustRagRunningProcesses)
    if ($remaining.Count -gt 0) {
        Write-Host 'Forcing termination of remaining processes...'
        foreach ($proc in $remaining) {
            try {
                Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            } catch {
                Write-Error "Failed to force-stop PID $($proc.Id) ($($proc.ProcessName)): $_"
                return 2
            }
        }
        Start-Sleep -Seconds 2
    }

    $stillRunning = @(Get-TrustRagRunningProcesses)
    if ($stillRunning.Count -gt 0) {
        $names = ($stillRunning | ForEach-Object { "$($_.ProcessName) (PID $($_.Id))" }) -join ', '
        Write-Error "TrustRAG processes still running after forced stop: $names"
        return 3
    }

    $portsReleased = Wait-TrustRagPortsReleased -TimeoutSeconds $ForceWaitSeconds
    if (-not $portsReleased) {
        Write-Error 'TrustRAG backend port (8080) is still in use after process stop.'
        return 4
    }

    Write-Host 'All TrustRAG processes stopped.'
    return 0
}

function Remove-TrustRagDirectory {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return $true
    }

    for ($i = 0; $i -lt 4; $i++) {
        try {
            Remove-Item -LiteralPath $Path -Recurse -Force -ErrorAction Stop
            return $true
        } catch {
            if ($i -lt 3) {
                Start-Sleep -Milliseconds (300 * ($i + 1))
            } else {
                Write-Warning "Failed to delete: $Path — $_"
                return $false
            }
        }
    }
    return $false
}

function Clear-TrustRagLocalData {
    param([string]$InstallDirectory = '')

    $failures = New-Object System.Collections.Generic.List[string]

    foreach ($dir in Get-TrustRagKnownDataDirectories) {
        if (-not (Remove-TrustRagDirectory -Path $dir)) {
            $failures.Add($dir)
        }
    }

    foreach ($item in Get-TrustRagTempResidueItems) {
        if (-not (Remove-TrustRagDirectory -Path $item)) {
            $failures.Add($item)
        }
    }

    foreach ($shortcut in Get-TrustRagShortcutPaths) {
        if (Test-Path -LiteralPath $shortcut) {
            try {
                Remove-Item -LiteralPath $shortcut -Force -ErrorAction Stop
            } catch {
                $failures.Add($shortcut)
            }
        }
    }

    if ($InstallDirectory -and (Test-Path -LiteralPath $InstallDirectory)) {
        if (-not (Remove-TrustRagDirectory -Path $InstallDirectory)) {
            $failures.Add($InstallDirectory)
        }
    }

    if ($failures.Count -gt 0) {
        Write-Error ("Failed to delete the following paths:`n" + ($failures -join "`n"))
        return 5
    }

    Write-Host 'TrustRAG local data cleanup completed.'
    return 0
}

try {
    if ($StopProcessesOnly) {
        exit (Stop-TrustRagProcesses)
    }

    if ($DeleteLocalData) {
        $stopCode = Stop-TrustRagProcesses
        if ($stopCode -ne 0) {
            exit $stopCode
        }
        exit (Clear-TrustRagLocalData -InstallDirectory $InstallDir)
    }

    Write-Error 'Specify -StopProcessesOnly or -DeleteLocalData.'
    exit 1
} catch {
    Write-Error $_
    exit 99
}