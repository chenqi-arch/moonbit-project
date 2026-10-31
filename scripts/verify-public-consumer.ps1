param(
    [string]$Version = '',
    [string]$ArchivePath = '',
    [switch]$BaselineOnly
)

# Compile the README and independent security assertions against a public or
# unpacked candidate package. Archive mode never counts as a public publish.
# Generated files stay under ignored _build, never replacing user projects.
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$manifest = [IO.File]::ReadAllText((Join-Path $repoRoot 'moon.mod'))
if (-not $Version) {
    $versionMatch = [regex]::Match($manifest, '(?m)^version\s*=\s*"([^"]+)"')
    if (-not $versionMatch.Success) { throw 'Module version not found' }
    $Version = $versionMatch.Groups[1].Value
}
if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw 'Invalid package version' }
$readme = [IO.File]::ReadAllText((Join-Path $repoRoot 'README.md'))
$sample = [regex]::Match(
    $readme,
    '(?s)```text\r?\n(import \{.*?pkgtype\(kind: "executable"\).*?)```.*?```mbt\r?\n(fn main \{.*?)```'
)
if (-not $sample.Success) { throw 'README consumer code blocks not found' }
$proofId = [Guid]::NewGuid().ToString('N').Substring(0, 8)
$proofRoot = Join-Path $repoRoot ('_build/c-' + $proofId)
$buildPath = Join-Path $repoRoot ('_build/t-' + $proofId)
$consumerPath = Join-Path $proofRoot 'consumer'
$utf8 = New-Object Text.UTF8Encoding($false)

function Invoke-MoonChecked {
    param([string[]]$Arguments)
    # Windows PowerShell treats even successful native stderr as ErrorRecords.
    # Judge native processes by exit code, not by stderr presence.
    $ErrorActionPreference = 'Continue'
    $output = & moon --target-dir $buildPath @Arguments 2>&1
    $commandExit = $LASTEXITCODE
    if ($commandExit -ne 0) {
        $output | ForEach-Object { Write-Output $_.ToString() }
        throw "moon command failed with exit ${commandExit}: $Arguments"
    }
    $output | Select-Object -Last 3 | ForEach-Object { Write-Output $_.ToString() }
}

Invoke-MoonChecked -Arguments @('new', $consumerPath, '--user', 'acceptance', '--name', 'moonvcr-consumer')
if ($ArchivePath) {
    $archive = (Resolve-Path -LiteralPath $ArchivePath).Path
    $candidatePath = Join-Path $proofRoot 'candidate'
    Expand-Archive -LiteralPath $archive -DestinationPath $candidatePath
    $candidateManifest = [IO.File]::ReadAllText((Join-Path $candidatePath 'moon.mod'))
    if ($candidateManifest -notmatch ('(?m)^version\s*=\s*"' + [regex]::Escape($Version) + '"')) {
        throw 'Candidate archive version mismatch'
    }
    [IO.File]::WriteAllText((Join-Path $proofRoot 'moon.work'), 'members = ["./candidate", "./consumer"]', $utf8)
    [IO.File]::AppendAllText((Join-Path $consumerPath 'moon.mod'), "`nimport { `"chenqi-arch/moonbit-project@$Version`", }`n", $utf8)
} else {
    Invoke-MoonChecked -Arguments @('-C', $consumerPath, 'add', "chenqi-arch/moonbit-project@$Version")
}
[IO.File]::WriteAllText((Join-Path $consumerPath 'cmd/main/moon.pkg'), $sample.Groups[1].Value, $utf8)
[IO.File]::WriteAllText((Join-Path $consumerPath 'cmd/main/main.mbt'), $sample.Groups[2].Value, $utf8)
Invoke-MoonChecked -Arguments @('-C', $consumerPath, 'check')
Invoke-MoonChecked -Arguments @('-C', $consumerPath, 'build')
Invoke-MoonChecked -Arguments @('-C', $consumerPath, 'run', 'cmd/main')
if (-not $BaselineOnly) {
    $securityPath = Join-Path $consumerPath 'cmd/security'
    New-Item -ItemType Directory -Path $securityPath | Out-Null
    Copy-Item -LiteralPath (Join-Path $repoRoot 'cmd/moonvcr-security-acceptance/main.mbt') -Destination (Join-Path $securityPath 'main.mbt')
    Copy-Item -LiteralPath (Join-Path $repoRoot 'cmd/moonvcr-security-acceptance/moon.pkg') -Destination (Join-Path $securityPath 'moon.pkg')
    Invoke-MoonChecked -Arguments @('-C', $consumerPath, 'run', 'cmd/security')
    # Prove that consumers cannot modify the private cassette through fields.
    $invalidPath = Join-Path $consumerPath 'cmd/invalid-access'
    New-Item -ItemType Directory -Path $invalidPath | Out-Null
    Copy-Item -LiteralPath (Join-Path $securityPath 'moon.pkg') -Destination (Join-Path $invalidPath 'moon.pkg')
    [IO.File]::WriteAllText((Join-Path $invalidPath 'main.mbt'), 'fn main { let session = @moonvcr.Session::with_defaults(@moonvcr.Cassette::empty(), @moonvcr.Record); session.cassette.interactions.clear() }', $utf8)
    $ErrorActionPreference = 'Continue'
    $diagnostics = & moon --target-dir $buildPath -C $consumerPath check cmd/invalid-access 2>&1
    $exitCode = $LASTEXITCODE
    $ErrorActionPreference = 'Stop'
    $diagnosticText = $diagnostics | Out-String
    if ($exitCode -eq 0 -or $diagnosticText -notmatch 'has no field.*cassette|field.*cassette.*private') { throw 'Session private field boundary did not reject access for the expected reason' }
    Write-Output 'Consumer private Session field access rejected as expected'
}
$origin = if ($ArchivePath) { 'candidate-archive' } else { 'public-registry' }
if ($BaselineOnly) { $origin += '-API-baseline-only-NOT-security-proof' }
Write-Output "README consumer acceptance passed package=$Version origin=$origin"
# The negative compiler test intentionally exits nonzero. Do not let that
# expected child-process code become the successful script's CI exit code.
exit 0
