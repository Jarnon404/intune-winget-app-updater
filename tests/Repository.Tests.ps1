Describe 'Repository structure' {
    It 'Has a README' {
        Test-Path '.\README.md' | Should -BeTrue
    }

    It 'Has a LICENSE file' {
        Test-Path '.\LICENSE' | Should -BeTrue
    }

    It 'Has documentation folder' {
        Test-Path '.\docs' | Should -BeTrue
    }

    It 'Has script folders' {
        Test-Path '.\scripts' | Should -BeTrue
        Test-Path '.\tools' | Should -BeTrue
    }
}

Describe 'PowerShell scripts' {
    $Scripts = Get-ChildItem -Path '.\scripts', '.\tools' -Filter '*.ps1' -Recurse -File

    It 'Contains PowerShell scripts' {
        $Scripts.Count | Should -BeGreaterThan 0
    }

    It 'PowerShell script <_.Name> parses successfully' -ForEach $Scripts {
        $Tokens = $null
        $ParseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$Tokens, [ref]$ParseErrors) | Out-Null
        $ParseErrors.Count | Should -Be 0
    }

    It 'PowerShell script <_.Name> has comment-based header or comments' -ForEach $Scripts {
        $Content = Get-Content -Path $_.FullName -Raw
        $Content | Should -Match '#'
    }
}

Describe 'Repository hygiene' {
    It 'Does not contain generated report files in tracked project areas' {
        $GeneratedExtensions = @('.csv', '.xlsx', '.html', '.json', '.log', '.zip', '.7z', '.bak', '.tmp')
        $ExcludedDirs = @('.git', '.github', 'tests', 'docs', 'examples')

        $Files = Get-ChildItem -Path . -Recurse -File | Where-Object {
            $FullName = $_.FullName
            -not ($ExcludedDirs | Where-Object { $FullName -match "[\\/]$($_)([\\/]|$)" })
        }

        $Generated = $Files | Where-Object { $GeneratedExtensions -contains $_.Extension.ToLowerInvariant() }
        $Generated.Count | Should -Be 0
    }
}
