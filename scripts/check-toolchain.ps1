# The competition requires the compiler (moonc), not the build driver (moon),
# to be at least 0.10.14. Run on Windows or Ubuntu with PowerShell.
$ErrorActionPreference = 'Stop'
moon version --all
if ($LASTEXITCODE -ne 0) { throw 'Cannot read MoonBit toolchain version' }
$compilerOutput = (& moonc -v | Out-String).Trim()
if ($LASTEXITCODE -ne 0) { throw 'Cannot read moonc version' }
if ($compilerOutput -notmatch '^v?(\d+\.\d+\.\d+)(?:\+|\s|$)') {
    throw "Unsupported compiler version format: $compilerOutput"
}
$compilerVersion = [version]$Matches[1]
$minimumVersion = [version]'0.10.14'
if ($compilerVersion -lt $minimumVersion) {
    throw "Compiler $compilerVersion is below required $minimumVersion. Upgrade the MoonBit toolchain."
}
Write-Output "Compiler requirement passed: $compilerVersion >= $minimumVersion"
