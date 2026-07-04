# ============================================================
# Intune Winget Offline Technician Tool v10.3
#
# Purpose:
# - Standalone/offline technician tool for testing the same logic
#   used by the Intune Winget App Updates v10.1 package.
# - Can be run manually on a workstation.
# - If not elevated, relaunches itself with UAC prompt.
# - Technician can provide admin credentials at elevation.
# - Does not require Intune Management Extension.
#
# Modes:
# - All         : Detection + Remediation + Summary
# - Detection   : Detection only
# - Remediation : Remediation only
# - Summary     : Show recent logs
#
# Hotfix:
# - Fixes Windows PowerShell 5.1 compatibility by avoiding ProcessStartInfo.ArgumentList
#
# Safety:
# - Does not install missing apps
# - Does not run winget upgrade --all
# - Updates only configured allowlist apps
# - RegistryOnly apps are skipped by default
# - All app-level update failures are warnings
#
# Logs:
# - C:\ProgramData\IntuneWingetUpdates\Logs
#
# Example:
#   powershell.exe -ExecutionPolicy Bypass -File .\Intune-Winget-Offline-Technician-Tool-v10.3.ps1
#   powershell.exe -ExecutionPolicy Bypass -File .\Intune-Winget-Offline-Technician-Tool-v10.3.ps1 -Mode Detection
#   powershell.exe -ExecutionPolicy Bypass -File .\Intune-Winget-Offline-Technician-Tool-v10.3.ps1 -Mode Remediation
# ============================================================

param(
    [ValidateSet("All", "Detection", "Remediation", "Summary")]
    [string]$Mode = "All",

    [switch]$NoElevate,

    [switch]$AttemptRegistryOnlyApps,

    [switch]$TreatRegistryOnlyAsIssue,

    [string]$LogRoot = "C:\ProgramData\IntuneWingetUpdates\Logs"
)

$ErrorActionPreference = "Continue"

# --- Settings ---
$LogRetentionDays = 14
$MaxLogFolderSizeMB = 50
$CommandTimeoutSeconds = 600

$Apps = @(
    [pscustomobject]@{
        Id = "7zip.7zip"
        RegistryDisplayNamePatterns = @("7-Zip")
        ProcessNames = @("7zFM", "7zG")
    },
    [pscustomobject]@{
        Id = "Notepad++.Notepad++"
        RegistryDisplayNamePatterns = @("Notepad++")
        ProcessNames = @("notepad++")
    },
    [pscustomobject]@{
        Id = "Mozilla.Firefox"
        RegistryDisplayNamePatterns = @("Mozilla Firefox")
        ProcessNames = @("firefox")
    },
    [pscustomobject]@{
        Id = "Google.Chrome"
        RegistryDisplayNamePatterns = @("Google Chrome")
        ProcessNames = @("chrome")
    },
    [pscustomobject]@{
        Id = "Adobe.Acrobat.Reader.32-bit"
        RegistryDisplayNamePatterns = @("Adobe Acrobat Reader", "Adobe Acrobat")
        ProcessNames = @("AcroRd32", "Acrobat", "RdrCEF")
    },
    [pscustomobject]@{
        Id = "Adobe.Acrobat.Reader.64-bit"
        RegistryDisplayNamePatterns = @("Adobe Acrobat Reader", "Adobe Acrobat")
        ProcessNames = @("AcroRd32", "Acrobat", "RdrCEF")
    }
)

# --- Elevation ---
function Test-IsAdministrator {
    try {
        $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
        return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    catch {
        return $false
    }
}

function ConvertTo-ArgumentString {
    param(
        [string[]]$Arguments
    )

    $Out = New-Object System.Collections.Generic.List[string]

    foreach ($Arg in $Arguments) {
        if ($Arg -match '\s|"') {
            $Escaped = $Arg -replace '"', '\"'
            $Out.Add('"' + $Escaped + '"')
        }
        else {
            $Out.Add($Arg)
        }
    }

    return ($Out -join " ")
}

if (-not $NoElevate -and -not (Test-IsAdministrator)) {
    Write-Host ""
    Write-Host "This tool should be run elevated." -ForegroundColor Yellow
    Write-Host "Launching UAC prompt. Enter admin credentials when prompted." -ForegroundColor Yellow
    Write-Host ""

    $Args = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $PSCommandPath,
        "-Mode", $Mode,
        "-LogRoot", $LogRoot
    )

    if ($AttemptRegistryOnlyApps) {
        $Args += "-AttemptRegistryOnlyApps"
    }

    if ($TreatRegistryOnlyAsIssue) {
        $Args += "-TreatRegistryOnlyAsIssue"
    }

    $ArgString = ConvertTo-ArgumentString -Arguments $Args

    try {
        Start-Process -FilePath "powershell.exe" -ArgumentList $ArgString -Verb RunAs -Wait
        exit $LASTEXITCODE
    }
    catch {
        Write-Host "Elevation failed or was cancelled: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

# --- Logging ---
if (-not (Test-Path $LogRoot)) {
    New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
}

$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$LogFile = Join-Path $LogRoot ("OfflineTechnician_{0}.log" -f $RunStamp)

function Write-Log {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )

    $Line = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message

    try {
        [System.IO.File]::AppendAllText(
            $LogFile,
            $Line + [Environment]::NewLine,
            [System.Text.Encoding]::UTF8
        )
    }
    catch {
        Write-Host "WARN: Log write failed: $($_.Exception.Message)" -ForegroundColor Yellow
    }

    switch ($Level) {
        "ERROR" { Write-Host $Line -ForegroundColor Red }
        "WARN"  { Write-Host $Line -ForegroundColor Yellow }
        default { Write-Host $Line }
    }
}

function Invoke-LogCleanup {
    param(
        [string]$Path,
        [int]$RetentionDays,
        [int]$MaxFolderSizeMB
    )

    try {
        if (-not (Test-Path $Path)) {
            return
        }

        Get-ChildItem -Path $Path -Filter "*.log" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays) } |
            Remove-Item -Force -ErrorAction SilentlyContinue

        $Files = @(Get-ChildItem -Path $Path -Filter "*.log" -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTime -Descending)

        if (-not $Files -or $Files.Count -eq 0) {
            return
        }

        $MaxBytes = [int64]$MaxFolderSizeMB * 1MB
        $TotalBytes = [int64](($Files | Measure-Object -Property Length -Sum).Sum)

        if ($TotalBytes -le $MaxBytes) {
            return
        }

        $RunningBytes = [int64]0

        foreach ($File in $Files) {
            $RunningBytes += [int64]$File.Length

            if ($RunningBytes -gt $MaxBytes) {
                Remove-Item -Path $File.FullName -Force -ErrorAction SilentlyContinue
            }
        }
    }
    catch {
        Write-Log "Log cleanup failed: $($_.Exception.Message)" "WARN"
    }
}

function ConvertTo-SafeSingleLine {
    param(
        [AllowNull()][string]$Text,
        [int]$MaxLength = 500
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
        [string[]]$Items,
        [int]$MaxLength = 500
    )

    if (-not $Items -or $Items.Count -eq 0) {
        return "None"
    }

    $Text = (($Items | Select-Object -Unique) -join ", ")
    return ConvertTo-SafeSingleLine -Text $Text -MaxLength $MaxLength
}

function ConvertTo-ProcessArgumentString {
    param(
        [string[]]$Arguments
    )

    if (-not $Arguments -or $Arguments.Count -eq 0) {
        return ""
    }

    $Out = New-Object System.Collections.Generic.List[string]

    foreach ($Arg in $Arguments) {
        if ($null -eq $Arg) {
            continue
        }

        $Text = [string]$Arg

        if ($Text -match '[\s"]') {
            $Escaped = $Text -replace '"', '\"'
            $Out.Add('"' + $Escaped + '"')
        }
        else {
            $Out.Add($Text)
        }
    }

    return ($Out -join " ")
}

function Invoke-LoggedCommand {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [int]$TimeoutSeconds = 600
    )

    $Output = New-Object System.Collections.Generic.List[string]

    try {
        $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
        $ProcessInfo.FileName = $FilePath
        $ProcessInfo.RedirectStandardOutput = $true
        $ProcessInfo.RedirectStandardError = $true
        $ProcessInfo.UseShellExecute = $false
        $ProcessInfo.CreateNoWindow = $true

        $ProcessInfo.Arguments = ConvertTo-ProcessArgumentString -Arguments $Arguments

        Write-Log ("Running command: {0} {1}" -f $FilePath, ($Arguments -join " "))

        $Process = New-Object System.Diagnostics.Process
        $Process.StartInfo = $ProcessInfo
        [void]$Process.Start()

        $Completed = $Process.WaitForExit($TimeoutSeconds * 1000)

        if (-not $Completed) {
            try {
                $Process.Kill()
            }
            catch { }

            return [pscustomobject]@{
                ExitCode = 9998
                Output = @("Command timed out after $TimeoutSeconds seconds.")
                TechnicalFailure = $true
                ErrorMessage = "Command timeout"
            }
        }

        $StdOut = $Process.StandardOutput.ReadToEnd()
        $StdErr = $Process.StandardError.ReadToEnd()

        if ($StdOut) {
            foreach ($Line in ($StdOut -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($Line)) {
                    $Output.Add($Line)
                }
            }
        }

        if ($StdErr) {
            foreach ($Line in ($StdErr -split "`r?`n")) {
                if (-not [string]::IsNullOrWhiteSpace($Line)) {
                    $Output.Add($Line)
                }
            }
        }

        return [pscustomobject]@{
            ExitCode = [int]$Process.ExitCode
            Output = @($Output)
            TechnicalFailure = $false
            ErrorMessage = ""
        }
    }
    catch {
        return [pscustomobject]@{
            ExitCode = 9999
            Output = @("Command failed: $($_.Exception.Message)")
            TechnicalFailure = $true
            ErrorMessage = $_.Exception.Message
        }
    }
}

function Write-CommandOutputToLog {
    param(
        [string[]]$Lines
    )

    foreach ($Line in $Lines) {
        if ([string]::IsNullOrWhiteSpace($Line)) {
            continue
        }

        $Text = $Line.Trim()

        if ($Text -match "^[\\|/\-]$") {
            continue
        }

        if ($Text -match "^[#=]+$") {
            continue
        }

        if ($Text -match "MB /|KB /|bytes /") {
            continue
        }

        Write-Log $Text
    }
}

function Get-WingetExitCodeExplanation {
    param(
        [int]$ExitCode
    )

    switch ($ExitCode) {
        0 { return "Success" }
        9998 { return "Command timeout." }
        9999 { return "Script wrapper failed to start or complete the command." }
        -1978335189 { return "Winget or installer failed during operation. Common causes: app running, installer blocked, reboot pending, broken installer state, SYSTEM-context limitation." }
        -1978335212 { return "No applicable package or no package found." }
        -1978335214 { return "Package source or agreement issue." }
        -1978335229 { return "Installer failed or operation cancelled." }
        -2147024891 { return "Access denied." }
        -2147023293 { return "Fatal installer error." }
        3010 { return "Success, reboot required." }
        1603 { return "Fatal MSI installer error." }
        1618 { return "Another installation is already in progress." }
        default { return "Unknown or package-specific exit code." }
    }
}

function Test-RebootPending {
    $Checks = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired",
        "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager"
    )

    $Pending = $false

    foreach ($Path in $Checks) {
        if ($Path -like "*Session Manager") {
            try {
                $Value = (Get-ItemProperty -Path $Path -Name PendingFileRenameOperations -ErrorAction SilentlyContinue).PendingFileRenameOperations
                if ($Value) {
                    $Pending = $true
                }
            }
            catch { }
        }
        else {
            if (Test-Path $Path) {
                $Pending = $true
            }
        }
    }

    return $Pending
}

function Find-Winget {
    $Candidates = @(
        "$env:ProgramFiles\WindowsApps\Microsoft.DesktopAppInstaller_*\winget.exe",
        "$env:LOCALAPPDATA\Microsoft\WindowsApps\winget.exe"
    )

    foreach ($Candidate in $Candidates) {
        $Found = Get-ChildItem -Path $Candidate -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending |
            Select-Object -First 1

        if ($Found) {
            return $Found.FullName
        }
    }

    $Command = Get-Command winget.exe -ErrorAction SilentlyContinue
    if ($Command) {
        return $Command.Source
    }

    return $null
}

function Get-RegistryInstalledApp {
    param(
        [string[]]$DisplayNamePatterns
    )

    $RegistryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    $Matches = New-Object System.Collections.Generic.List[object]

    foreach ($Path in $RegistryPaths) {
        try {
            $Items = Get-ItemProperty -Path $Path -ErrorAction SilentlyContinue |
                Where-Object { $_.DisplayName }

            foreach ($Item in $Items) {
                foreach ($Pattern in $DisplayNamePatterns) {
                    if ($Item.DisplayName -like "*$Pattern*") {
                        $Matches.Add([pscustomobject]@{
                            DisplayName = $Item.DisplayName
                            DisplayVersion = $Item.DisplayVersion
                            Publisher = $Item.Publisher
                            InstallLocation = $Item.InstallLocation
                            RegistryPath = $Path
                        })
                        break
                    }
                }
            }
        }
        catch {
            Write-Log "Registry app lookup failed for path $Path : $($_.Exception.Message)" "WARN"
        }
    }

    if ($Matches.Count -gt 0) {
        return $Matches | Sort-Object DisplayName, DisplayVersion | Select-Object -First 1
    }

    return $null
}

function Get-AppInstallState {
    param(
        [string]$WingetPath,
        [object]$App
    )

    $AppId = $App.Id
    $RegistryMatch = Get-RegistryInstalledApp -DisplayNamePatterns $App.RegistryDisplayNamePatterns

    if ($RegistryMatch) {
        Write-Log "$AppId registry match: $($RegistryMatch.DisplayName) $($RegistryMatch.DisplayVersion)"
    }
    else {
        Write-Log "$AppId registry match: none"
    }

    $Result = Invoke-LoggedCommand -FilePath $WingetPath -Arguments @(
        "list",
        "--id", $AppId,
        "--exact",
        "--disable-interactivity"
    ) -TimeoutSeconds $CommandTimeoutSeconds

    $Text = ($Result.Output -join "`n")
    $Explanation = Get-WingetExitCodeExplanation -ExitCode $Result.ExitCode

    Write-Log "winget list exit code for $AppId : $($Result.ExitCode)"
    Write-Log "winget list explanation for $AppId : $Explanation"

    if ($Result.Output.Count -gt 0) {
        Write-CommandOutputToLog -Lines $Result.Output
    }

    if ($Result.TechnicalFailure -eq $true -or $Result.ExitCode -eq 9998 -or $Result.ExitCode -eq 9999) {
        if ($RegistryMatch) {
            return [pscustomobject]@{
                AppId = $AppId
                State = "RegistryOnly"
                ExitCode = $Result.ExitCode
                RegistryDisplayName = $RegistryMatch.DisplayName
                RegistryDisplayVersion = $RegistryMatch.DisplayVersion
                Reason = "Registry found the app but winget list had a technical failure."
            }
        }

        return [pscustomobject]@{
            AppId = $AppId
            State = "Unknown"
            ExitCode = $Result.ExitCode
            RegistryDisplayName = ""
            RegistryDisplayVersion = ""
            Reason = "Technical winget list failure and no registry match."
        }
    }

    if ($Result.ExitCode -eq 0 -and $Text -match [regex]::Escape($AppId)) {
        return [pscustomobject]@{
            AppId = $AppId
            State = "WingetInstalled"
            ExitCode = $Result.ExitCode
            RegistryDisplayName = if ($RegistryMatch) { $RegistryMatch.DisplayName } else { "" }
            RegistryDisplayVersion = if ($RegistryMatch) { $RegistryMatch.DisplayVersion } else { "" }
            Reason = "AppId found in winget list output."
        }
    }

    $TechnicalPatterns = @(
        "access denied",
        "source",
        "server",
        "0x[0-9a-fA-F]+",
        "cancelled",
        "operation failed"
    )

    $LooksTechnical = $false
    foreach ($Pattern in $TechnicalPatterns) {
        if ($Text -match $Pattern) {
            $LooksTechnical = $true
            break
        }
    }

    if ($RegistryMatch) {
        return [pscustomobject]@{
            AppId = $AppId
            State = "RegistryOnly"
            ExitCode = $Result.ExitCode
            RegistryDisplayName = $RegistryMatch.DisplayName
            RegistryDisplayVersion = $RegistryMatch.DisplayVersion
            Reason = "Registry found the app but winget list did not confirm it."
        }
    }

    if ($LooksTechnical) {
        return [pscustomobject]@{
            AppId = $AppId
            State = "Unknown"
            ExitCode = $Result.ExitCode
            RegistryDisplayName = ""
            RegistryDisplayVersion = ""
            Reason = "winget list returned technical-looking output and no registry match."
        }
    }

    return [pscustomobject]@{
        AppId = $AppId
        State = "NotInstalled"
        ExitCode = $Result.ExitCode
        RegistryDisplayName = ""
        RegistryDisplayVersion = ""
        Reason = "No winget match and no registry match."
    }
}

function Get-RunningProcessHint {
    param(
        [object]$App
    )

    if (-not $App.ProcessNames -or $App.ProcessNames.Count -eq 0) {
        return $null
    }

    $Running = New-Object System.Collections.Generic.List[string]

    foreach ($ProcessName in $App.ProcessNames) {
        $Found = Get-Process -Name $ProcessName -ErrorAction SilentlyContinue
        if ($Found) {
            $Running.Add($ProcessName)
        }
    }

    if ($Running.Count -gt 0) {
        return ($Running | Select-Object -Unique) -join ", "
    }

    return $null
}

function Invoke-WingetSourceUpdate {
    param(
        [string]$WingetPath
    )

    Write-Log "Updating winget sources"

    $SourceUpdate = Invoke-LoggedCommand -FilePath $WingetPath -Arguments @(
        "source",
        "update",
        "--disable-interactivity"
    ) -TimeoutSeconds $CommandTimeoutSeconds

    Write-CommandOutputToLog -Lines $SourceUpdate.Output
    Write-Log "winget source update exit code: $($SourceUpdate.ExitCode)"
    Write-Log "winget source update explanation: $(Get-WingetExitCodeExplanation -ExitCode $SourceUpdate.ExitCode)"

    $SourceUpdateStatus = "OK"

    if ($SourceUpdate.TechnicalFailure -eq $true -or $SourceUpdate.ExitCode -eq 9998 -or $SourceUpdate.ExitCode -eq 9999) {
        $SourceUpdateStatus = "TechnicalFailure_$($SourceUpdate.ExitCode)"
    }
    elseif ($SourceUpdate.ExitCode -ne 0) {
        $SourceUpdateStatus = "Warning_$($SourceUpdate.ExitCode)"
    }

    return $SourceUpdateStatus
}

function Invoke-OfflineDetection {
    param(
        [string]$WingetPath
    )

    $SourceUpdateStatus = Invoke-WingetSourceUpdate -WingetPath $WingetPath

    if ($SourceUpdateStatus -like "TechnicalFailure*") {
        Write-Log "Detection cannot be trusted because winget source update failed technically." "ERROR"
        Write-Host "OFFLINE_DETECTION_RESULT | Status=SourceUpdateTechnicalFailure | SourceUpdateStatus=$SourceUpdateStatus"
        return
    }

    $WingetInstalledApps = @()
    $RegistryOnlyApps = @()
    $UnknownApps = @()
    $NotInstalledApps = @()

    foreach ($App in $Apps) {
        Write-Log "------------------------------------------------------------"
        Write-Log "Detection check: $($App.Id)"

        $State = Get-AppInstallState -WingetPath $WingetPath -App $App

        Write-Log "$($App.Id) install state: $($State.State). Reason: $($State.Reason)"

        switch ($State.State) {
            "WingetInstalled" {
                $WingetInstalledApps += $App.Id
            }
            "RegistryOnly" {
                $RegistryOnlyApps += "$($App.Id) [$($State.RegistryDisplayName) $($State.RegistryDisplayVersion)]"
            }
            "NotInstalled" {
                $NotInstalledApps += $App.Id
            }
            default {
                $UnknownApps += "$($App.Id) ($($State.ExitCode))"
            }
        }
    }

    if ($UnknownApps.Count -gt 0) {
        Write-Log "Unknown app states found: $($UnknownApps -join ', ')" "WARN"
    }

    $UpdatesAvailable = @()

    if ($WingetInstalledApps.Count -gt 0) {
        Write-Log "Checking available upgrades using winget upgrade"

        $UpgradeResult = Invoke-LoggedCommand -FilePath $WingetPath -Arguments @(
            "upgrade",
            "--disable-interactivity",
            "--accept-source-agreements"
        ) -TimeoutSeconds $CommandTimeoutSeconds

        Write-Log "winget upgrade list exit code: $($UpgradeResult.ExitCode)"
        Write-Log "winget upgrade list explanation: $(Get-WingetExitCodeExplanation -ExitCode $UpgradeResult.ExitCode)"
        Write-CommandOutputToLog -Lines $UpgradeResult.Output

        $UpgradeText = ($UpgradeResult.Output -join "`n")

        foreach ($AppId in $WingetInstalledApps) {
            if ($UpgradeText -match [regex]::Escape($AppId)) {
                Write-Log "Update available for $AppId" "WARN"
                $UpdatesAvailable += $AppId
            }
            else {
                Write-Log "No update available for $AppId"
            }
        }
    }

    $Status = "Compliant"

    if ($UpdatesAvailable.Count -gt 0) {
        $Status = "UpdatesAvailable"
    }
    elseif ($UnknownApps.Count -gt 0) {
        $Status = "UnknownAppStates"
    }
    elseif ($WingetInstalledApps.Count -eq 0 -and $RegistryOnlyApps.Count -gt 0) {
        $Status = "RegistryOnlyNoWingetManageableApps"
    }
    elseif ($WingetInstalledApps.Count -eq 0 -and $RegistryOnlyApps.Count -eq 0) {
        $Status = "NoConfiguredAppsInstalled"
    }

    if ($TreatRegistryOnlyAsIssue -and $RegistryOnlyApps.Count -gt 0) {
        $Status = "RegistryOnlyAppsFound"
    }

    $Line = "OFFLINE_DETECTION_RESULT | Status=$Status | SourceUpdateStatus=$SourceUpdateStatus | WingetInstalledApps=$(Join-Safe -Items $WingetInstalledApps -MaxLength 500) | RegistryOnlyApps=$(Join-Safe -Items $RegistryOnlyApps -MaxLength 600) | NotInstalledApps=$(Join-Safe -Items $NotInstalledApps -MaxLength 500) | UnknownApps=$(Join-Safe -Items $UnknownApps -MaxLength 500) | Updates=$(Join-Safe -Items $UpdatesAvailable -MaxLength 500)"
    Write-Log $Line
    Write-Host ""
    Write-Host $Line -ForegroundColor Cyan
}

function Invoke-OfflineRemediation {
    param(
        [string]$WingetPath
    )

    $SourceUpdateStatus = Invoke-WingetSourceUpdate -WingetPath $WingetPath

    $UpdatedApps = @()
    $WarningApps = @()
    $SkippedApps = @()
    $RegistryOnlyApps = @()
    $UnknownApps = @()
    $AttemptedApps = @()

    if ($SourceUpdateStatus -like "TechnicalFailure*") {
        $WarningApps += "winget source update $SourceUpdateStatus"
        $Line = "OFFLINE_REMEDIATION_RESULT | Status=SourceUpdateWarning | SourceUpdateStatus=$SourceUpdateStatus | AttemptedApps=None | UpdatedApps=None | WarningApps=$(Join-Safe -Items $WarningApps -MaxLength 500)"
        Write-Log $Line "WARN"
        Write-Host $Line -ForegroundColor Yellow
        return
    }

    foreach ($App in $Apps) {
        $AppId = $App.Id

        Write-Log "------------------------------------------------------------"
        Write-Log "Remediation check: $AppId"

        $State = Get-AppInstallState -WingetPath $WingetPath -App $App

        Write-Log "$AppId install state: $($State.State). Reason: $($State.Reason)"

        if ($State.State -eq "NotInstalled") {
            Write-Log "$AppId is not installed. Skipping."
            $SkippedApps += $AppId
            continue
        }

        if ($State.State -eq "Unknown") {
            Write-Log "$AppId state is unknown. Skipping update attempt." "WARN"
            $UnknownApps += "$AppId ($($State.ExitCode))"
            $WarningApps += "$AppId (unknown state)"
            continue
        }

        if ($State.State -eq "RegistryOnly" -and -not $AttemptRegistryOnlyApps) {
            Write-Log "$AppId is registry-only. Skipping because AttemptRegistryOnlyApps is false." "WARN"
            $RegistryOnlyApps += "$AppId [$($State.RegistryDisplayName) $($State.RegistryDisplayVersion)]"
            $WarningApps += "$AppId (registry-only)"
            continue
        }

        if ($State.State -eq "RegistryOnly" -and $AttemptRegistryOnlyApps) {
            Write-Log "$AppId is registry-only but AttemptRegistryOnlyApps is true. Attempting winget upgrade anyway." "WARN"
            $RegistryOnlyApps += "$AppId [$($State.RegistryDisplayName) $($State.RegistryDisplayVersion)]"
        }

        $RunningHint = Get-RunningProcessHint -App $App
        if ($RunningHint) {
            Write-Log "$AppId related process is running: $RunningHint. Installer may fail if files are locked." "WARN"
        }

        Write-Log "Running winget upgrade for $AppId"
        $AttemptedApps += $AppId

        $Result = Invoke-LoggedCommand -FilePath $WingetPath -Arguments @(
            "upgrade",
            "--id", $AppId,
            "--exact",
            "--silent",
            "--accept-package-agreements",
            "--accept-source-agreements",
            "--disable-interactivity"
        ) -TimeoutSeconds $CommandTimeoutSeconds

        Write-CommandOutputToLog -Lines $Result.Output

        $ExitCode = [int]$Result.ExitCode
        $Explanation = Get-WingetExitCodeExplanation -ExitCode $ExitCode

        Write-Log "winget exit code for $AppId : $ExitCode"
        Write-Log "winget exit code explanation for $AppId : $Explanation"

        if ($ExitCode -eq 0 -or $ExitCode -eq 3010) {
            if ($ExitCode -eq 3010) {
                Write-Log "$AppId upgrade completed successfully. Reboot required." "WARN"
                $WarningApps += "$AppId (3010 reboot required)"
            }
            else {
                Write-Log "$AppId upgrade command completed successfully"
            }

            $UpdatedApps += $AppId
        }
        elseif ($ExitCode -eq -1978335212) {
            Write-Log "$AppId has no applicable update or no matching upgrade. Treating as skipped." "WARN"
            $SkippedApps += "$AppId (no applicable update)"
        }
        else {
            Write-Log "$AppId upgrade returned non-zero exit code: $ExitCode. Treating as non-fatal warning." "WARN"
            Write-Log "$AppId failure explanation: $Explanation" "WARN"
            $WarningApps += "$AppId ($ExitCode)"
        }
    }

    $Status = "Completed"
    if ($WarningApps.Count -gt 0 -or $RegistryOnlyApps.Count -gt 0 -or $UnknownApps.Count -gt 0) {
        $Status = "CompletedWithWarnings"
    }

    $Line = "OFFLINE_REMEDIATION_RESULT | Status=$Status | SourceUpdateStatus=$SourceUpdateStatus | AttemptedApps=$(Join-Safe -Items $AttemptedApps -MaxLength 350) | UpdatedApps=$(Join-Safe -Items $UpdatedApps -MaxLength 350) | WarningApps=$(Join-Safe -Items $WarningApps -MaxLength 600) | SkippedApps=$(Join-Safe -Items $SkippedApps -MaxLength 500) | RegistryOnlyApps=$(Join-Safe -Items $RegistryOnlyApps -MaxLength 600) | UnknownApps=$(Join-Safe -Items $UnknownApps -MaxLength 500)"
    Write-Log $Line

    Write-Host ""
    Write-Host $Line -ForegroundColor Cyan
}

function Show-OfflineSummary {
    Write-Host ""
    Write-Host "=== Offline Winget Technician Summary ===" -ForegroundColor Cyan
    Write-Host "Computer: $env:COMPUTERNAME"
    Write-Host "User: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
    Write-Host "Elevated: $(Test-IsAdministrator)"
    Write-Host "Log file: $LogFile"
    Write-Host "Log folder: $LogRoot"
    Write-Host ""

    $RecentLogs = Get-ChildItem -Path $LogRoot -Filter "*.log" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 8

    if ($RecentLogs) {
        Write-Host "Recent logs:" -ForegroundColor Cyan
        foreach ($File in $RecentLogs) {
            Write-Host ("- {0} | {1} KB | {2}" -f $File.Name, [math]::Round($File.Length / 1KB, 1), $File.LastWriteTime)
        }
    }
    else {
        Write-Host "No logs found."
    }

    Write-Host ""
}

# --- Main ---
Write-Log "============================================================"
Write-Log "Starting Intune Winget Offline Technician Tool v10.3"
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "User context: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Elevated: $(Test-IsAdministrator)"
Write-Log "Mode: $Mode"
Write-Log "Log file: $LogFile"
Write-Log "Log retention days: $LogRetentionDays"
Write-Log "Max log folder size MB: $MaxLogFolderSizeMB"
Write-Log "Command timeout seconds: $CommandTimeoutSeconds"
Write-Log "Attempt registry-only apps: $AttemptRegistryOnlyApps"
Write-Log "Treat registry-only as issue: $TreatRegistryOnlyAsIssue"

Invoke-LogCleanup -Path $LogRoot -RetentionDays $LogRetentionDays -MaxFolderSizeMB $MaxLogFolderSizeMB

$RebootPending = Test-RebootPending
if ($RebootPending) {
    Write-Log "Reboot pending detected. Winget or installers may fail until reboot." "WARN"
}
else {
    Write-Log "No reboot pending indicator detected."
}

$WingetPath = Find-Winget

if (-not $WingetPath) {
    Write-Log "winget.exe was not found. Cannot continue." "ERROR"
    Write-Host ""
    Write-Host "winget.exe was not found. Install or repair Microsoft App Installer first." -ForegroundColor Red
    Show-OfflineSummary
    exit 1
}

Write-Log "winget path: $WingetPath"

switch ($Mode) {
    "Detection" {
        Invoke-OfflineDetection -WingetPath $WingetPath
    }
    "Remediation" {
        Invoke-OfflineRemediation -WingetPath $WingetPath
    }
    "Summary" {
        # Summary only
    }
    default {
        Invoke-OfflineDetection -WingetPath $WingetPath
        Invoke-OfflineRemediation -WingetPath $WingetPath
    }
}

Show-OfflineSummary

Write-Log "Offline technician tool completed."
Write-Host ""
Write-Host "Done. Send the latest log file to IT/admin if needed:" -ForegroundColor Green
Write-Host $LogFile -ForegroundColor Green
Write-Host ""

exit 0
