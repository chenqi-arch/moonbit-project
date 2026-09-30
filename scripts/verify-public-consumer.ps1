# Compile and run the exact README quick start against the public package.
# Generated files stay under ignored _build, never replacing user projects.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$readme = [IO.File]::ReadAllText((Join-Path $repoRoot 'README.md'))
$sample = [regex]::Match(
    $readme,
    '(?s)```text\r?\n(import \{.*?pkgtype\(kind: "executable"\).*?)```.*?```mbt\r?\n(fn main \{.*?)```'
)
if (-not $sample.Success) { throw 'README consumer code blocks not found' }
$consumerPath = Join-Path $repoRoot ('_build/guide-consumer-' + [Guid]::NewGuid().ToString('N'))

function Invoke-MoonChecked {
    param([string[]]$Arguments)
    # Windows PowerShell treats even successful native stderr as ErrorRecords.
    # Judge native processes by exit code, not by stderr presence.
    $ErrorActionPreference = 'Continue'
    & moon @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "moon command failed with exit ${LASTEXITCODE}: $Arguments"
    }
}

Invoke-MoonChecked -Arguments @('new', $consumerPath, '--user', 'acceptance', '--name', 'moonvcr-consumer')
Invoke-MoonChecked -Arguments @('-C', $consumerPath, 'add', 'chenqi-arch/moonbit-project@0.3.0')
$utf8 = New-Object Text.UTF8Encoding($false)
[IO.File]::WriteAllText((Join-Path $consumerPath 'cmd/main/moon.pkg'), $sample.Groups[1].Value, $utf8)
[IO.File]::WriteAllText((Join-Path $consumerPath 'cmd/main/main.mbt'), $sample.Groups[2].Value, $utf8)
Invoke-MoonChecked -Arguments @('-C', $consumerPath, 'check')
Invoke-MoonChecked -Arguments @('-C', $consumerPath, 'build')
Invoke-MoonChecked -Arguments @('-C', $consumerPath, 'run', 'cmd/main')
Write-Output 'README public consumer acceptance passed package=0.3.0'
