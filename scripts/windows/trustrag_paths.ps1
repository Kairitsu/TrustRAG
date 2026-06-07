# TrustRAG Windows local data / residue path registry.
# Dot-source this file from uninstall_cleanup.ps1 and check_trustrag_residue.ps1.

function Get-TrustRagKnownDataDirectories {
    <#
    .SYNOPSIS
    Returns absolute directories that may contain TrustRAG user data.
    Only TrustRAG-specific paths are listed — never broad vendor roots.
    #>
    $appData = [Environment]::GetFolderPath('ApplicationData')
    $localAppData = [Environment]::GetFolderPath('LocalApplicationData')
    $temp = [IO.Path]::GetTempPath().TrimEnd('\')

    $relative = @(
        # Current Flutter path_provider (CompanyName=XimilalaXiang, ProductName=TrustRAG)
        'XimilalaXiang\TrustRAG'
        'XimilalaXiang\TrustRAG\TrustRAG'

        # Legacy / alternate Flutter bundle ids
        'com.example\client'
        'com.example\client\TrustRAG'
        'com.example\TrustRAG'
        'com.trustrag'
        'com.trustrag\TrustRAG'
        'com.trustrag.client'
        'com.trustrag.client\TrustRAG'
        'com.trustrag.app'

        # Generic product folders
        'TrustRAG'
        'trustrag'

        # Tester / historical vendor names
        'Kairitsu\TrustRAG'
    )

    $roots = @($appData, $localAppData)
    $dirs = New-Object System.Collections.Generic.List[string]

    foreach ($root in $roots) {
        foreach ($rel in $relative) {
            $dirs.Add((Join-Path $root $rel))
        }
    }

    # Rust directories crate default (TRUSTRAG__DATA_DIR unset standalone backend)
    $dirs.Add((Join-Path $localAppData 'trustrag\TrustRAG'))
    $dirs.Add((Join-Path $localAppData 'trustrag\TrustRAG\data'))
    $dirs.Add((Join-Path $localAppData 'trustrag\TrustRAG\config'))
    $dirs.Add((Join-Path $localAppData 'trustrag\TrustRAG\cache'))
    $dirs.Add((Join-Path $localAppData 'com.trustrag\TrustRAG'))
    $dirs.Add((Join-Path $localAppData 'com.trustrag\TrustRAG\data'))

    # Duplicate-safe return
    return $dirs | Sort-Object -Unique
}

function Get-TrustRagTempResidueItems {
    $temp = [IO.Path]::GetTempPath().TrimEnd('\')
    $items = @()

    foreach ($pattern in @('trustrag*', 'TrustRAG*')) {
        $matches = Get-ChildItem -Path $temp -Filter $pattern -ErrorAction SilentlyContinue
        foreach ($m in $matches) {
            $items += $m.FullName
        }
    }

    return $items | Sort-Object -Unique
}

function Get-TrustRagDefaultInstallDirectory {
    $pf = ${env:ProgramFiles}
    if ($pf) {
        return Join-Path $pf 'TrustRAG'
    }
    return $null
}

function Get-TrustRagShortcutPaths {
    $items = New-Object System.Collections.Generic.List[string]

    $desktop = [Environment]::GetFolderPath('Desktop')
    $commonDesktop = [Environment]::GetFolderPath('CommonDesktopDirectory')
    $startMenu = [Environment]::GetFolderPath('Programs')
    $commonStartMenu = [Environment]::GetFolderPath('CommonPrograms')

    foreach ($base in @($desktop, $commonDesktop, $startMenu, $commonStartMenu)) {
        if (-not $base) { continue }
        $lnk = Join-Path $base 'TrustRAG.lnk'
        $items.Add($lnk)
    }

    return $items | Sort-Object -Unique
}

function Get-TrustRagUninstallRegistryHints {
    # Inno Setup AppId from installer.iss — used only for residue detection.
    return @(
        'HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{B2F8A9E1-7C3D-4F5A-9E1B-2D4F6A8C0E3F}_is1'
        'HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\{B2F8A9E1-7C3D-4F5A-9E1B-2D4F6A8C0E3F}_is1'
        'HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{B2F8A9E1-7C3D-4F5A-9E1B-2D4F6A8C0E3F}_is1'
    )
}

function Test-TrustRagProcessName {
    param([string]$Name)
    return $Name -match '(?i)^(TrustRAG|trustrag-backend|trustrag)(\.exe)?$'
}

function Get-TrustRagRunningProcesses {
    $found = @{}

    Get-Process -ErrorAction SilentlyContinue | ForEach-Object {
        if (Test-TrustRagProcessName $_.ProcessName) {
            $found[$_.Id] = $_
        }
    }

    try {
        Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | ForEach-Object {
            $name = $_.Name
            $cmd = $_.CommandLine
            if ((Test-TrustRagProcessName $name) -or ($cmd -and $cmd -match '(?i)trustrag')) {
                $proc = Get-Process -Id $_.ProcessId -ErrorAction SilentlyContinue
                if ($proc) { $found[$proc.Id] = $proc }
            }
        }
    } catch {
        # CIM may be unavailable in constrained environments.
    }

    return $found.Values | Sort-Object Id -Unique
}