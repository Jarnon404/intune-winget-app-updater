# ============================================================
# Intune Winget App Update Detection v10.4 - Hybrid Registry Discovery
# Detection script
#
# Purpose:
# - Checks selected installed apps for available winget updates
# - Does not install missing apps
# - Does not run winget upgrade --all
# - Uses winget + registry fallback to determine app state
# - Returns exit 1 when one or more winget-manageable configured apps have updates
# - Returns exit 1 when winget technical checks fail and state cannot be trusted
# - Returns exit 0 when no winget-manageable configured app updates are available
#
# v10.4 diagnostic baseline:
# - Hybrid detection: winget + uninstall registry
# - Safe log writing using File.AppendAllText
# - Command timeout handling
# - Enforces log retention and max log folder size
# - Fixes PowerShell parser issue with variable followed by colon
# - Fixes Windows PowerShell 5.1 compatibility by avoiding ProcessStartInfo.ArgumentList
# - Adds diagnostic winget --name fallback discovery
# - Adds DiscoveryHints to final Intune output
# - Writes final output line to local log for Log Summary
# - Clear final one-line Intune export output
# - Separates WingetInstalled, RegistryOnly, NotInstalled and Unknown
# - RegistryOnly apps are reported but do not trigger remediation by default
# - ASCII-only script content for Intune compatibility
#
# Logs:
# - C:\ProgramData\IntuneWingetUpdates\Logs
# ============================================================

$ErrorActionPreference = "Continue"

# --- Settings ---
$LogRoot = "C:\ProgramData\IntuneWingetUpdates\Logs"
$LogRetentionDays = 14
$MaxLogFolderSizeMB = 50
$CommandTimeoutSeconds = 300

# If true, apps found in registry but not visible to winget cause exit 1.
# Default false avoids remediation loops for apps winget cannot manage.
$TreatRegistryOnlyAsIssue = $false

$Apps = @(
    [pscustomobject]@{
        Id = "7zip.7zip"
        RegistryDisplayNamePatterns = @("7-Zip")
        NameQueryPatterns = @("7-Zip")
    },
    [pscustomobject]@{
        Id = "Notepad++.Notepad++"
        RegistryDisplayNamePatterns = @("Notepad++")
        NameQueryPatterns = @("Notepad++")
    },
    [pscustomobject]@{
        Id = "Mozilla.Firefox"
        RegistryDisplayNamePatterns = @("Mozilla Firefox")
        NameQueryPatterns = @("Mozilla Firefox", "Firefox")
    },
    [pscustomobject]@{
        Id = "Google.Chrome"
        RegistryDisplayNamePatterns = @("Google Chrome")
        NameQueryPatterns = @("Google Chrome", "Chrome")
    },
    [pscustomobject]@{
        Id = "Adobe.Acrobat.Reader.32-bit"
        RegistryDisplayNamePatterns = @("Adobe Acrobat Reader", "Adobe Acrobat")
        NameQueryPatterns = @("Adobe Acrobat Reader", "Acrobat Reader", "Adobe Acrobat")
    },
    [pscustomobject]@{
        Id = "Adobe.Acrobat.Reader.64-bit"
        RegistryDisplayNamePatterns = @("Adobe Acrobat Reader", "Adobe Acrobat")
        NameQueryPatterns = @("Adobe Acrobat Reader", "Acrobat Reader", "Adobe Acrobat")
    }
)

# --- Logging ---
if (-not (Test-Path $LogRoot)) {
    New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $LogRoot ("Detection_{0}.log" -f (Get-Date -Format "yyyyMMdd"))

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
        Write-Output "WARN: Log write failed: $($_.Exception.Message)"
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
        [int]$TimeoutSeconds = 300
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
        -1978335189 { return "Winget or installer failed during operation. App state cannot always be trusted from this result." }
        -1978335162 { return "Winget list package query failed. Common causes: pending reboot, source or index issue, corrupted package metadata, or winget cannot resolve installed package identity." }
        -1978335212 { return "No applicable package or no package found." }
        -1978335214 { return "Package source or agreement issue." }
        -1978335229 { return "Installer failed or operation cancelled." }
        -2147024891 { return "Access denied." }
        3010 { return "Success, reboot required." }
        1603 { return "Fatal MSI installer error." }
        1618 { return "Another installation is already in progress." }
        default { return "Unknown or package-specific exit code." }
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

        # 1. Remove logs older than retention.
        Get-ChildItem -Path $Path -Filter "*.log" -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-$RetentionDays) } |
            Remove-Item -Force -ErrorAction SilentlyContinue

        # 2. Enforce max folder size by keeping newest logs first.
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

function Get-WingetNameDiscovery {
    param(
        [string]$WingetPath,
        [object]$App
    )

    $AppId = $App.Id
    $Patterns = @($App.NameQueryPatterns)

    if (-not $Patterns -or $Patterns.Count -eq 0) {
        return [pscustomobject]@{
            AppId = $AppId
            Hint = "$($AppId):NameDiscoveryNotConfigured"
            Found = $false
            ExitCode = 0
            Output = ""
        }
    }

    foreach ($Pattern in $Patterns) {
        if ([string]::IsNullOrWhiteSpace($Pattern)) {
            continue
        }

        Write-Log "Running diagnostic winget name discovery for $($AppId) with name pattern: $Pattern"

        $Result = Invoke-LoggedCommand -FilePath $WingetPath -Arguments @(
            "list",
            "--name", $Pattern,
            "--disable-interactivity"
        ) -TimeoutSeconds $CommandTimeoutSeconds

        Write-Log "winget name discovery exit code for $($AppId) / $($Pattern) : $($Result.ExitCode)"
        Write-Log "winget name discovery explanation for $($AppId) / $($Pattern) : $(Get-WingetExitCodeExplanation -ExitCode $Result.ExitCode)"

        if ($Result.Output.Count -gt 0) {
            Write-CommandOutputToLog -Lines $Result.Output
        }

        $Text = ($Result.Output -join " ")

        if ($Result.ExitCode -eq 0 -and $Text -match [regex]::Escape($Pattern)) {
            return [pscustomobject]@{
                AppId = $AppId
                Hint = "$($AppId):NameFound($Pattern)"
                Found = $true
                ExitCode = $Result.ExitCode
                Output = ConvertTo-SafeSingleLine -Text $Text -MaxLength 250
            }
        }
    }

    return [pscustomobject]@{
        AppId = $AppId
        Hint = "$($AppId):NameNotFound"
        Found = $false
        ExitCode = 0
        Output = ""
    }
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
        Write-Log "winget list output for $($AppId):"
        Write-CommandOutputToLog -Lines $Result.Output
    }

    $Discovery = $null
    if ($Result.ExitCode -ne 0 -or -not ($Text -match [regex]::Escape($AppId))) {
        $Discovery = Get-WingetNameDiscovery -WingetPath $WingetPath -App $App
        Write-Log "Discovery hint for $($AppId): $($Discovery.Hint)"
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
                DiscoveryHint = if ($Discovery) { $Discovery.Hint } else { "None" }
            }
        }

        return [pscustomobject]@{
            AppId = $AppId
            State = "Unknown"
            ExitCode = $Result.ExitCode
            RegistryDisplayName = ""
            RegistryDisplayVersion = ""
            Reason = "Technical winget list failure and no registry match."
                DiscoveryHint = if ($Discovery) { $Discovery.Hint } else { "None" }
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
                DiscoveryHint = if ($Discovery) { $Discovery.Hint } else { "None" }
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
                DiscoveryHint = if ($Discovery) { $Discovery.Hint } else { "None" }
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
                DiscoveryHint = if ($Discovery) { $Discovery.Hint } else { "None" }
        }
    }

    return [pscustomobject]@{
        AppId = $AppId
        State = "NotInstalled"
        ExitCode = $Result.ExitCode
        RegistryDisplayName = ""
        RegistryDisplayVersion = ""
        Reason = "No winget match and no registry match."
                DiscoveryHint = if ($Discovery) { $Discovery.Hint } else { "None" }
    }
}

function Write-FinalOutput {
    param(
        [string]$Line,
        [int]$ExitCode
    )

    Write-Log $Line
    Write-Output $Line
    exit $ExitCode
}

Write-Log "============================================================"
Write-Log "Starting winget update detection v10.4 hybrid registry discovery"
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "User context: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file: $LogFile"
Write-Log "Configured apps: $(($Apps | ForEach-Object { $_.Id }) -join ', ')"
Write-Log "Treat registry-only apps as issue: $TreatRegistryOnlyAsIssue"
Write-Log "Command timeout seconds: $CommandTimeoutSeconds"
Write-Log "Log retention days: $LogRetentionDays"
Write-Log "Max log folder size MB: $MaxLogFolderSizeMB"
Write-Log "Script version: Detection v10.4"

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
    Write-Log "winget.exe was not found. Detection cannot continue." "ERROR"
    Write-FinalOutput -Line "WINGET_DETECTION_V10_4 | Computer=$env:COMPUTERNAME | Status=WingetMissing | SourceUpdateStatus=NotRun | RebootPending=$RebootPending | Exit=1" -ExitCode 1
}

Write-Log "winget path: $WingetPath"

Write-Log "Updating winget sources"
$SourceUpdate = Invoke-LoggedCommand -FilePath $WingetPath -Arguments @(
    "source",
    "update",
    "--disable-interactivity"
) -TimeoutSeconds $CommandTimeoutSeconds

Write-CommandOutputToLog -Lines $SourceUpdate.Output
Write-Log "winget source update exit code: $($SourceUpdate.ExitCode)"
$SourceExplanation = Get-WingetExitCodeExplanation -ExitCode $SourceUpdate.ExitCode
Write-Log "winget source update explanation: $SourceExplanation"

$SourceUpdateStatus = "OK"
if ($SourceUpdate.TechnicalFailure -eq $true -or $SourceUpdate.ExitCode -eq 9998 -or $SourceUpdate.ExitCode -eq 9999) {
    $SourceUpdateStatus = "TechnicalFailure_$($SourceUpdate.ExitCode)"
}
elseif ($SourceUpdate.ExitCode -ne 0) {
    $SourceUpdateStatus = "Warning_$($SourceUpdate.ExitCode)"
}

if ($SourceUpdateStatus -like "TechnicalFailure*") {
    Write-Log "winget source update had a technical failure. Detection result cannot be trusted." "ERROR"
    Write-FinalOutput -Line "WINGET_DETECTION_V10_4 | Computer=$env:COMPUTERNAME | Status=SourceUpdateTechnicalFailure | SourceUpdateStatus=$SourceUpdateStatus | RebootPending=$RebootPending | Exit=1" -ExitCode 1
}

$WingetInstalledApps = @()
$RegistryOnlyApps = @()
$UnknownApps = @()
$NotInstalledApps = @()
$DiscoveryHints = @()
$WingetListFailedApps = @()

foreach ($App in $Apps) {
    Write-Log "------------------------------------------------------------"
    Write-Log "Checking installed state for $($App.Id)"

    $State = Get-AppInstallState -WingetPath $WingetPath -App $App

    Write-Log "$($App.Id) install state: $($State.State). Reason: $($State.Reason)"

    if ($State.RegistryDisplayName) {
        Write-Log "$($App.Id) registry detected as: $($State.RegistryDisplayName) $($State.RegistryDisplayVersion)"
    }

    if ($State.DiscoveryHint -and $State.DiscoveryHint -ne "None") {
        $DiscoveryHints += $State.DiscoveryHint
    }

    if ($State.ExitCode -eq -1978335162) {
        $WingetListFailedApps += "$($App.Id) (-1978335162)"
    }

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

Write-Log "Winget installed configured apps: $($WingetInstalledApps -join ', ')"
Write-Log "Registry-only configured apps: $($RegistryOnlyApps -join ', ')"
Write-Log "Not installed configured apps: $($NotInstalledApps -join ', ')"
Write-Log "Unknown configured app states: $($UnknownApps -join ', ')"
Write-Log "Winget list failed apps: $($WingetListFailedApps -join ', ')"
Write-Log "Discovery hints: $($DiscoveryHints -join ', ')"

if ($UnknownApps.Count -gt 0) {
    Write-Log "One or more configured app states are unknown due to technical failures. Detection cannot be trusted." "ERROR"
    Write-FinalOutput -Line "WINGET_DETECTION_V10_4 | Computer=$env:COMPUTERNAME | Status=UnknownAppStates | SourceUpdateStatus=$SourceUpdateStatus | UnknownApps=$(Join-Safe -Items $UnknownApps -MaxLength 500) | DiscoveryHints=$(Join-Safe -Items $DiscoveryHints -MaxLength 500) | WingetListFailedApps=$(Join-Safe -Items $WingetListFailedApps -MaxLength 500) | RebootPending=$RebootPending | Exit=1" -ExitCode 1
}

if ($TreatRegistryOnlyAsIssue -and $RegistryOnlyApps.Count -gt 0) {
    Write-Log "Registry-only apps are configured to be reported as issues." "WARN"
    Write-FinalOutput -Line "WINGET_DETECTION_V10_4 | Computer=$env:COMPUTERNAME | Status=RegistryOnlyAppsFound | SourceUpdateStatus=$SourceUpdateStatus | RegistryOnlyApps=$(Join-Safe -Items $RegistryOnlyApps -MaxLength 600) | DiscoveryHints=$(Join-Safe -Items $DiscoveryHints -MaxLength 500) | WingetListFailedApps=$(Join-Safe -Items $WingetListFailedApps -MaxLength 500) | RebootPending=$RebootPending | Exit=1" -ExitCode 1
}

if ($WingetInstalledApps.Count -eq 0) {
    if ($RegistryOnlyApps.Count -gt 0) {
        Write-Log "Configured apps exist in registry but are not visible to winget. No winget-manageable configured apps found." "WARN"
        Write-FinalOutput -Line "WINGET_DETECTION_V10_4 | Computer=$env:COMPUTERNAME | Status=RegistryOnlyNoWingetManageableApps | SourceUpdateStatus=$SourceUpdateStatus | RegistryOnlyApps=$(Join-Safe -Items $RegistryOnlyApps -MaxLength 700) | DiscoveryHints=$(Join-Safe -Items $DiscoveryHints -MaxLength 500) | WingetListFailedApps=$(Join-Safe -Items $WingetListFailedApps -MaxLength 500) | RebootPending=$RebootPending | Exit=0" -ExitCode 0
    }

    Write-Log "No configured apps are installed. Device is compliant."
    Write-FinalOutput -Line "WINGET_DETECTION_V10_4 | Computer=$env:COMPUTERNAME | Status=NoConfiguredAppsInstalled | SourceUpdateStatus=$SourceUpdateStatus | RebootPending=$RebootPending | Exit=0" -ExitCode 0
}

Write-Log "Checking available upgrades using winget upgrade"
$UpgradeResult = Invoke-LoggedCommand -FilePath $WingetPath -Arguments @(
    "upgrade",
    "--disable-interactivity",
    "--accept-source-agreements"
) -TimeoutSeconds $CommandTimeoutSeconds

Write-Log "winget upgrade list exit code: $($UpgradeResult.ExitCode)"
Write-Log "winget upgrade list explanation: $(Get-WingetExitCodeExplanation -ExitCode $UpgradeResult.ExitCode)"
Write-CommandOutputToLog -Lines $UpgradeResult.Output

if ($UpgradeResult.TechnicalFailure -eq $true -or $UpgradeResult.ExitCode -eq 9998 -or $UpgradeResult.ExitCode -eq 9999) {
    Write-Log "winget upgrade list had a technical failure. Detection cannot be trusted." "ERROR"
    Write-FinalOutput -Line "WINGET_DETECTION_V10_4 | Computer=$env:COMPUTERNAME | Status=UpgradeListTechnicalFailure | SourceUpdateStatus=$SourceUpdateStatus | WingetInstalledApps=$(Join-Safe -Items $WingetInstalledApps -MaxLength 500) | DiscoveryHints=$(Join-Safe -Items $DiscoveryHints -MaxLength 500) | WingetListFailedApps=$(Join-Safe -Items $WingetListFailedApps -MaxLength 500) | RebootPending=$RebootPending | Exit=1" -ExitCode 1
}

$UpgradeText = ($UpgradeResult.Output -join "`n")
$UpdatesAvailable = @()

foreach ($AppId in $WingetInstalledApps) {
    if ($UpgradeText -match [regex]::Escape($AppId)) {
        Write-Log "Update available for $AppId"
        $UpdatesAvailable += $AppId
    }
    else {
        Write-Log "No update available for $AppId"
    }
}

if ($UpdatesAvailable.Count -gt 0) {
    Write-Log "Configured winget-manageable app updates available: $($UpdatesAvailable -join ', ')" "WARN"
    Write-FinalOutput -Line "WINGET_DETECTION_V10_4 | Computer=$env:COMPUTERNAME | Status=UpdatesAvailable | SourceUpdateStatus=$SourceUpdateStatus | Updates=$(Join-Safe -Items $UpdatesAvailable -MaxLength 500) | WingetInstalledApps=$(Join-Safe -Items $WingetInstalledApps -MaxLength 500) | RegistryOnlyApps=$(Join-Safe -Items $RegistryOnlyApps -MaxLength 500) | DiscoveryHints=$(Join-Safe -Items $DiscoveryHints -MaxLength 500) | WingetListFailedApps=$(Join-Safe -Items $WingetListFailedApps -MaxLength 500) | RebootPending=$RebootPending | Exit=1" -ExitCode 1
}

Write-Log "No configured winget-manageable app updates available. Device is compliant."
Write-FinalOutput -Line "WINGET_DETECTION_V10_4 | Computer=$env:COMPUTERNAME | Status=Compliant | SourceUpdateStatus=$SourceUpdateStatus | WingetInstalledApps=$(Join-Safe -Items $WingetInstalledApps -MaxLength 500) | RegistryOnlyApps=$(Join-Safe -Items $RegistryOnlyApps -MaxLength 500) | DiscoveryHints=$(Join-Safe -Items $DiscoveryHints -MaxLength 500) | WingetListFailedApps=$(Join-Safe -Items $WingetListFailedApps -MaxLength 500) | RebootPending=$RebootPending | Exit=0" -ExitCode 0
