# ============================================================
# Winget Log Summary - Detection Only v10
#
# Purpose:
# - Reads local Winget update logs from:
#   C:\ProgramData\IntuneWingetUpdates\Logs
# - Prints a compact summary to Intune script output
# - Final output line contains the useful summary because
#   Intune export often shows only the last output line.
# - Supports Approved App Updates v10 output markers:
#   WINGET_DETECTION_V10
#   WINGET_REMEDIATION_V10
# - Does not modify the device
# - Always exits 0
#
# Recommended Intune package:
# Name: Winget - Log Summary
# Run as logged-on user: No
# Run script in 64-bit PowerShell: Yes
# Schedule: Daily, or Hourly while testing
# ============================================================

$ErrorActionPreference = "Continue"

$LogRoot = "C:\ProgramData\IntuneWingetUpdates\Logs"
$TailLinesToRead = 300
$MaxDetailLines = 22
$FinalMaxLength = 1900

function ConvertTo-SafeSingleLine {
    param(
        [AllowNull()][string]$Text,
        [int]$MaxLength = 600
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return "None"
    }

    $OneLine = $Text -replace "`r", " " -replace "`n", " "
    $OneLine = $OneLine -replace "\s+", " "
    $OneLine = $OneLine.Trim()

    if ($OneLine.Length -gt $MaxLength) {
        return $OneLine.Substring(0, $MaxLength) + "..."
    }

    return $OneLine
}

function Join-Safe {
    param(
        [string[]]$Lines,
        [int]$MaxLength = 700
    )

    if (-not $Lines -or $Lines.Count -eq 0) {
        return "None"
    }

    $Text = ($Lines | ForEach-Object { ConvertTo-SafeSingleLine -Text $_ -MaxLength 300 }) -join " || "
    return ConvertTo-SafeSingleLine -Text $Text -MaxLength $MaxLength
}

function Get-LogLines {
    param(
        [string]$Path,
        [int]$TailLines = 300
    )

    if (-not (Test-Path $Path)) {
        return @()
    }

    $Lines = Get-Content -Path $Path -Tail $TailLines -ErrorAction SilentlyContinue
    if (-not $Lines) {
        return @()
    }

    return @($Lines)
}

function Get-LastMatchingLine {
    param(
        [string[]]$Lines,
        [string[]]$Patterns
    )

    if (-not $Lines -or $Lines.Count -eq 0) {
        return $null
    }

    for ($i = $Lines.Count - 1; $i -ge 0; $i--) {
        foreach ($Pattern in $Patterns) {
            if ($Lines[$i] -match $Pattern) {
                return $Lines[$i]
            }
        }
    }

    return $null
}

function Get-MatchingLines {
    param(
        [string[]]$Lines,
        [string[]]$Patterns,
        [int]$Last = 10
    )

    if (-not $Lines -or $Lines.Count -eq 0) {
        return @()
    }

    $Matched = New-Object System.Collections.Generic.List[string]

    foreach ($Line in $Lines) {
        foreach ($Pattern in $Patterns) {
            if ($Line -match $Pattern) {
                $Matched.Add($Line)
                break
            }
        }
    }

    if ($Matched.Count -eq 0) {
        return @()
    }

    return @($Matched | Select-Object -Last $Last)
}

function Get-KeyValue {
    param(
        [string]$Line,
        [string]$Key
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return "None"
    }

    # Matches "Key=value" until next " | " or end of line.
    $Pattern = [regex]::Escape($Key) + "=(.*?)( \| |$)"
    $Match = [regex]::Match($Line, $Pattern)

    if ($Match.Success) {
        return ConvertTo-SafeSingleLine -Text $Match.Groups[1].Value -MaxLength 500
    }

    return "None"
}

function Get-ImportantLines {
    param(
        [string]$Path,
        [int]$TailLines = 300,
        [int]$MaxLines = 22
    )

    $Lines = Get-LogLines -Path $Path -TailLines $TailLines

    if (-not $Lines -or $Lines.Count -eq 0) {
        return @("No readable lines found.")
    }

    $Patterns = @(
        "Starting winget update detection v10",
        "Starting winget update remediation v10",
        "WINGET_DETECTION_V10",
        "WINGET_REMEDIATION_V10",
        "SourceUpdateStatus",
        "source update exit code",
        "source update explanation",
        "Reboot pending detected",
        "No reboot pending",
        "Winget installed configured apps:",
        "Registry-only configured apps:",
        "Not installed configured apps:",
        "Unknown configured app states:",
        "install state:",
        "registry match:",
        "registry detected as:",
        "Update available",
        "No update available",
        "Running winget upgrade",
        "winget exit code for",
        "winget exit code explanation",
        "upgrade command completed successfully",
        "completed successfully",
        "reboot required",
        "returned non-zero exit code",
        "Attempted apps:",
        "Updated apps:",
        "Skipped apps:",
        "Registry-only apps:",
        "Unknown apps:",
        "Warning apps:",
        "Remediation completed",
        "\[ERROR\]",
        "\[WARN\]",
        "Command timed out",
        "TechnicalFailure"
    )

    $Matched = Get-MatchingLines -Lines $Lines -Patterns $Patterns -Last $MaxLines

    if (-not $Matched -or $Matched.Count -eq 0) {
        return @("No important summary lines found in the last $TailLines lines.")
    }

    return $Matched
}

function Get-AppFailureHints {
    param(
        [string[]]$Lines
    )

    if (-not $Lines -or $Lines.Count -eq 0) {
        return "None"
    }

    $Patterns = @(
        "WINGET_REMEDIATION_V10",
        "Warning apps:",
        "Registry-only apps:",
        "Unknown apps:",
        "winget exit code for",
        "winget exit code explanation",
        "returned non-zero exit code",
        "\[ERROR\]",
        "\[WARN\]",
        "TechnicalFailure",
        "Command timed out"
    )

    $FailureLines = Get-MatchingLines -Lines $Lines -Patterns $Patterns -Last 14

    if (-not $FailureLines -or $FailureLines.Count -eq 0) {
        return "None"
    }

    return Join-Safe -Lines $FailureLines -MaxLength 900
}

function Get-LogInfo {
    param(
        [string]$Type,
        [object]$LogFile
    )

    if (-not $LogFile) {
        return [pscustomobject]@{
            Type = $Type
            File = "NoLog"
            LastWriteTime = "NoLog"
            Status = "No log found"
            FinalLine = "None"
            SourceUpdateStatus = "None"
            RebootPending = "None"
            WingetInstalledApps = "None"
            RegistryOnlyApps = "None"
            AttemptedApps = "None"
            UpdatedApps = "None"
            WarningApps = "None"
            SkippedApps = "None"
            UnknownApps = "None"
            FailureHints = "None"
        }
    }

    $Lines = Get-LogLines -Path $LogFile.FullName -TailLines $TailLinesToRead

    $FinalPatterns = @(
        "WINGET_DETECTION_V10",
        "WINGET_REMEDIATION_V10",
        "WINGET_DETECTION_V9",
        "WINGET_REMEDIATION_V9",
        "WINGET_LOG_SUMMARY_V3",
        "WINGET_LOG_SUMMARY_V2"
    )

    $StatusPatterns = @(
        "WINGET_DETECTION_V10",
        "WINGET_REMEDIATION_V10",
        "Status=",
        "Device is compliant",
        "No configured app updates available",
        "RegistryOnlyNoWingetManageableApps",
        "NoConfiguredAppsInstalled",
        "UnknownAppStates",
        "SourceUpdateTechnicalFailure",
        "UpgradeListTechnicalFailure",
        "UpdatesAvailable",
        "Remediation completed",
        "CompletedWithWarnings",
        "\[ERROR\]",
        "\[WARN\]"
    )

    $FinalLine = Get-LastMatchingLine -Lines $Lines -Patterns $FinalPatterns
    $StatusLine = Get-LastMatchingLine -Lines $Lines -Patterns $StatusPatterns

    $SourceUpdateStatus = Get-KeyValue -Line $FinalLine -Key "SourceUpdateStatus"
    $RebootPending = Get-KeyValue -Line $FinalLine -Key "RebootPending"
    $WingetInstalledApps = Get-KeyValue -Line $FinalLine -Key "WingetInstalledApps"
    $RegistryOnlyApps = Get-KeyValue -Line $FinalLine -Key "RegistryOnlyApps"
    $AttemptedApps = Get-KeyValue -Line $FinalLine -Key "AttemptedApps"
    $UpdatedApps = Get-KeyValue -Line $FinalLine -Key "UpdatedApps"
    $WarningApps = Get-KeyValue -Line $FinalLine -Key "WarningApps"
    $SkippedApps = Get-KeyValue -Line $FinalLine -Key "SkippedApps"
    $UnknownApps = Get-KeyValue -Line $FinalLine -Key "UnknownApps"

    return [pscustomobject]@{
        Type = $Type
        File = $LogFile.Name
        LastWriteTime = $LogFile.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
        Status = ConvertTo-SafeSingleLine -Text $StatusLine -MaxLength 550
        FinalLine = ConvertTo-SafeSingleLine -Text $FinalLine -MaxLength 800
        SourceUpdateStatus = $SourceUpdateStatus
        RebootPending = $RebootPending
        WingetInstalledApps = $WingetInstalledApps
        RegistryOnlyApps = $RegistryOnlyApps
        AttemptedApps = $AttemptedApps
        UpdatedApps = $UpdatedApps
        WarningApps = $WarningApps
        SkippedApps = $SkippedApps
        UnknownApps = $UnknownApps
        FailureHints = Get-AppFailureHints -Lines $Lines
    }
}

Write-Output "Winget Log Summary v10"
Write-Output "Computer: $env:COMPUTERNAME"
Write-Output "Run time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Output "Log path: $LogRoot"
Write-Output ""

if (-not (Test-Path $LogRoot)) {
    $Final = "WINGET_LOG_SUMMARY_V10 | Computer=$env:COMPUTERNAME | Status=LogPathMissing | LogPath=$LogRoot | DetectionLog=NoLog | RemediationLog=NoLog | Exit=0"
    Write-Output $Final
    exit 0
}

$DetectionLog = Get-ChildItem -Path $LogRoot -Filter "Detection_*.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

$RemediationLog = Get-ChildItem -Path $LogRoot -Filter "Remediation_*.log" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

$DetectionInfo = Get-LogInfo -Type "Detection" -LogFile $DetectionLog
$RemediationInfo = Get-LogInfo -Type "Remediation" -LogFile $RemediationLog

Write-Output "=== Overall ==="
Write-Output "DetectionLog: $($DetectionInfo.File)"
Write-Output "DetectionLastWriteTime: $($DetectionInfo.LastWriteTime)"
Write-Output "DetectionStatus: $($DetectionInfo.Status)"
Write-Output "DetectionSourceUpdateStatus: $($DetectionInfo.SourceUpdateStatus)"
Write-Output "DetectionRebootPending: $($DetectionInfo.RebootPending)"
Write-Output "DetectionWingetInstalledApps: $($DetectionInfo.WingetInstalledApps)"
Write-Output "DetectionRegistryOnlyApps: $($DetectionInfo.RegistryOnlyApps)"
Write-Output "DetectionUnknownApps: $($DetectionInfo.UnknownApps)"
Write-Output ""
Write-Output "RemediationLog: $($RemediationInfo.File)"
Write-Output "RemediationLastWriteTime: $($RemediationInfo.LastWriteTime)"
Write-Output "RemediationStatus: $($RemediationInfo.Status)"
Write-Output "RemediationSourceUpdateStatus: $($RemediationInfo.SourceUpdateStatus)"
Write-Output "RemediationAttemptedApps: $($RemediationInfo.AttemptedApps)"
Write-Output "RemediationUpdatedApps: $($RemediationInfo.UpdatedApps)"
Write-Output "RemediationWarningApps: $($RemediationInfo.WarningApps)"
Write-Output "RemediationSkippedApps: $($RemediationInfo.SkippedApps)"
Write-Output "RemediationRegistryOnlyApps: $($RemediationInfo.RegistryOnlyApps)"
Write-Output "RemediationUnknownApps: $($RemediationInfo.UnknownApps)"
Write-Output ""

Write-Output "=== Latest Detection Summary ==="
if ($DetectionLog) {
    Get-ImportantLines -Path $DetectionLog.FullName -TailLines $TailLinesToRead -MaxLines $MaxDetailLines |
        ForEach-Object { Write-Output $_ }
}
else {
    Write-Output "No detection log found."
}

Write-Output ""
Write-Output "=== Latest Remediation Summary ==="
if ($RemediationLog) {
    Get-ImportantLines -Path $RemediationLog.FullName -TailLines $TailLinesToRead -MaxLines $MaxDetailLines |
        ForEach-Object { Write-Output $_ }
}
else {
    Write-Output "No remediation log found. Normal when detection reports compliant."
}

$Final = "WINGET_LOG_SUMMARY_V10 | Computer=$env:COMPUTERNAME | DetectionLog=$($DetectionInfo.File) | DetectionTime=$($DetectionInfo.LastWriteTime) | DetectionStatus=$($DetectionInfo.Status) | DetectionSourceUpdateStatus=$($DetectionInfo.SourceUpdateStatus) | DetectionRebootPending=$($DetectionInfo.RebootPending) | DetectionWingetInstalledApps=$($DetectionInfo.WingetInstalledApps) | DetectionRegistryOnlyApps=$($DetectionInfo.RegistryOnlyApps) | DetectionUnknownApps=$($DetectionInfo.UnknownApps) | RemediationLog=$($RemediationInfo.File) | RemediationTime=$($RemediationInfo.LastWriteTime) | RemediationSourceUpdateStatus=$($RemediationInfo.SourceUpdateStatus) | RemediationAttemptedApps=$($RemediationInfo.AttemptedApps) | RemediationUpdatedApps=$($RemediationInfo.UpdatedApps) | RemediationWarningApps=$($RemediationInfo.WarningApps) | RemediationSkippedApps=$($RemediationInfo.SkippedApps) | RemediationRegistryOnlyApps=$($RemediationInfo.RegistryOnlyApps) | RemediationUnknownApps=$($RemediationInfo.UnknownApps) | Exit=0"

if ($Final.Length -gt $FinalMaxLength) {
    $Final = $Final.Substring(0, $FinalMaxLength) + "... | Exit=0"
}

Write-Output ""
Write-Output $Final

exit 0
