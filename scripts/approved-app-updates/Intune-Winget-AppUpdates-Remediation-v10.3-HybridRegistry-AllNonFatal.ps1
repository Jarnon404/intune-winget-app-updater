# ============================================================
# Intune Winget App Update Remediation v10.3 - Hybrid Registry
# Remediation script
#
# Purpose:
# - Updates selected apps only
# - Does not run winget upgrade --all
# - Does not install missing apps
# - Uses winget + registry fallback to determine app state
# - Treats all app update failures as non-fatal warnings
# - Returns exit 0 even if one or more app updates fail
# - Skips update attempts if winget source update has a technical failure
#
# v10.3 hotfix baseline:
# - Hybrid remediation: winget + uninstall registry
# - Safe log writing using File.AppendAllText
# - Command timeout handling
# - Enforces log retention and max log folder size
# - Fixes PowerShell parser issue with variable followed by colon
# - Fixes Windows PowerShell 5.1 compatibility by avoiding ProcessStartInfo.ArgumentList
# - Clear final one-line Intune export output
# - Separates Attempted, Updated, Warning, Skipped, RegistryOnly and Unknown
# - RegistryOnly apps are skipped by default
# - All app-level failures are non-fatal
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
$CommandTimeoutSeconds = 600

# Default false:
# If app is found in registry but not by winget list, log and skip.
# Set true only if you explicitly want to try winget upgrade anyway.
$AttemptRegistryOnlyApps = $false

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

# --- Logging ---
if (-not (Test-Path $LogRoot)) {
    New-Item -Path $LogRoot -ItemType Directory -Force | Out-Null
}

$LogFile = Join-Path $LogRoot ("Remediation_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

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

Write-Log "============================================================"
Write-Log "Starting winget update remediation v10.3 hybrid registry"
Write-Log "Computer: $env:COMPUTERNAME"
Write-Log "User context: $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)"
Write-Log "Log file: $LogFile"
Write-Log "Configured apps: $(($Apps | ForEach-Object { $_.Id }) -join ', ')"
Write-Log "Attempt registry-only apps: $AttemptRegistryOnlyApps"
Write-Log "Command timeout seconds: $CommandTimeoutSeconds"
Write-Log "All app update failures are treated as warnings in v10.3."
Write-Log "Log retention days: $LogRetentionDays"
Write-Log "Max log folder size MB: $MaxLogFolderSizeMB"
Write-Log "Script version: Remediation v10.3"

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
    Write-Log "winget.exe was not found. Cannot run app updates." "WARN"
    Write-Output "WINGET_REMEDIATION_V10_3 | Computer=$env:COMPUTERNAME | Status=WingetMissing | SourceUpdateStatus=NotRun | AttemptedApps=None | UpdatedApps=None | WarningApps=WingetMissing | SkippedApps=None | RegistryOnlyApps=None | UnknownApps=None | RebootPending=$RebootPending | Exit=0"
    exit 0
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

$UpdatedApps = @()
$WarningApps = @()
$SkippedApps = @()
$RegistryOnlyApps = @()
$UnknownApps = @()
$AttemptedApps = @()

if ($SourceUpdateStatus -like "TechnicalFailure*") {
    Write-Log "winget source update did not complete cleanly. Skipping app update attempts to avoid unreliable results." "WARN"
    $WarningApps += "winget source update $SourceUpdateStatus"

    $FinalSource = "WINGET_REMEDIATION_V10_3 | Computer=$env:COMPUTERNAME | Status=SourceUpdateWarning | SourceUpdateStatus=$SourceUpdateStatus | AttemptedApps=None | UpdatedApps=None | WarningApps=$(Join-Safe -Items $WarningApps -MaxLength 450) | SkippedApps=None | RegistryOnlyApps=None | UnknownApps=None | RebootPending=$RebootPending | Exit=0"
    if ($FinalSource.Length -gt 1900) {
        $FinalSource = $FinalSource.Substring(0, 1900) + "... | Exit=0"
    }

    Write-Output $FinalSource
    exit 0
}

foreach ($App in $Apps) {
    $AppId = $App.Id

    Write-Log "------------------------------------------------------------"
    Write-Log "Processing $AppId"

    $State = Get-AppInstallState -WingetPath $WingetPath -App $App

    Write-Log "$AppId install state: $($State.State). Reason: $($State.Reason)"

    if ($State.RegistryDisplayName) {
        Write-Log "$AppId registry detected as: $($State.RegistryDisplayName) $($State.RegistryDisplayVersion)"
    }

    if ($State.State -eq "NotInstalled") {
        Write-Log "$AppId is not installed. Skipping."
        $SkippedApps += $AppId
        continue
    }

    if ($State.State -eq "Unknown") {
        Write-Log "$AppId state is unknown. Skipping update attempt to avoid unreliable remediation." "WARN"
        $UnknownApps += "$AppId ($($State.ExitCode))"
        $WarningApps += "$AppId (unknown state)"
        continue
    }

    if ($State.State -eq "RegistryOnly" -and -not $AttemptRegistryOnlyApps) {
        Write-Log "$AppId is installed according to registry but not visible to winget. Skipping because AttemptRegistryOnlyApps is false." "WARN"
        $RegistryOnlyApps += "$AppId [$($State.RegistryDisplayName) $($State.RegistryDisplayVersion)]"
        $WarningApps += "$AppId (registry-only)"
        continue
    }

    if ($State.State -eq "RegistryOnly" -and $AttemptRegistryOnlyApps) {
        Write-Log "$AppId is registry-only, but AttemptRegistryOnlyApps is true. Attempting winget upgrade anyway." "WARN"
        $RegistryOnlyApps += "$AppId [$($State.RegistryDisplayName) $($State.RegistryDisplayVersion)]"
    }

    $RunningHint = Get-RunningProcessHint -App $App
    if ($RunningHint) {
        Write-Log "$AppId related process is running: $RunningHint. Installer may fail if files are locked." "WARN"
    }

    try {
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
            Write-Log "$AppId has no applicable update or winget reported no matching upgrade. Treating as skipped." "WARN"
            $SkippedApps += "$AppId (no applicable update)"
        }
        else {
            Write-Log "$AppId upgrade returned non-zero exit code: $ExitCode. Treating as non-fatal warning." "WARN"
            Write-Log "$AppId failure explanation: $Explanation" "WARN"
            $WarningApps += "$AppId ($ExitCode)"
        }
    }
    catch {
        Write-Log "$AppId update failed: $($_.Exception.Message). Treating as non-fatal warning." "WARN"
        $WarningApps += "$AppId (exception)"
    }
}

Write-Log "============================================================"
Write-Log "Remediation summary"
Write-Log "Attempted apps: $($AttemptedApps -join ', ')"
Write-Log "Updated apps: $($UpdatedApps -join ', ')"
Write-Log "Skipped apps: $($SkippedApps -join ', ')"
Write-Log "Registry-only apps: $($RegistryOnlyApps -join ', ')"
Write-Log "Unknown apps: $($UnknownApps -join ', ')"
Write-Log "Warning apps: $($WarningApps -join ', ')"

$Status = "Completed"
if ($WarningApps.Count -gt 0 -or $RegistryOnlyApps.Count -gt 0 -or $UnknownApps.Count -gt 0) {
    $Status = "CompletedWithWarnings"
    Write-Log "Remediation completed with non-fatal warnings: $($WarningApps -join ', ')" "WARN"
}
else {
    Write-Log "Remediation completed without failed apps."
}

$Final = "WINGET_REMEDIATION_V10_3 | Computer=$env:COMPUTERNAME | Status=$Status | SourceUpdateStatus=$SourceUpdateStatus | AttemptedApps=$(Join-Safe -Items $AttemptedApps -MaxLength 350) | UpdatedApps=$(Join-Safe -Items $UpdatedApps -MaxLength 350) | WarningApps=$(Join-Safe -Items $WarningApps -MaxLength 450) | SkippedApps=$(Join-Safe -Items $SkippedApps -MaxLength 350) | RegistryOnlyApps=$(Join-Safe -Items $RegistryOnlyApps -MaxLength 450) | UnknownApps=$(Join-Safe -Items $UnknownApps -MaxLength 350) | RebootPending=$RebootPending | Exit=0"

if ($Final.Length -gt 1900) {
    $Final = $Final.Substring(0, 1900) + "... | Exit=0"
}

Write-Output $Final
exit 0
