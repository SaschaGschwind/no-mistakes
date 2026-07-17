# Deploy the OST-patched no-mistakes.exe (#501 fix) over the installed binary.
# Downloads the release asset by default; pass -PatchedExe to install a local build.

[CmdletBinding()]
param(
    [string]$Tag = "ost-nm-501",
    [string]$Repo = "SaschaGschwind/no-mistakes",
    [string]$PatchedExe
)

$ErrorActionPreference = "Stop"

$tempDownload = $null
if ($PatchedExe) {
    if (-not (Test-Path -LiteralPath $PatchedExe)) {
        throw "Patched binary not found at '$PatchedExe'."
    }
    $source = (Resolve-Path -LiteralPath $PatchedExe).Path
    Write-Host "Using local patched binary: $source"
}
else {
    $url = "https://github.com/$Repo/releases/download/$Tag/no-mistakes.exe"
    $tempDownload = Join-Path ([System.IO.Path]::GetTempPath()) "no-mistakes-$Tag.exe"
    Write-Host "Downloading $url"
    Invoke-WebRequest -Uri $url -OutFile $tempDownload -UseBasicParsing
    $source = $tempDownload
}

try {
    # Resolve the installed path via where.exe; the install location is unconfirmed.
    $resolved = & where.exe no-mistakes 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $resolved) {
        throw "'where.exe no-mistakes' found nothing on PATH. Is no-mistakes installed?"
    }
    $installed = ($resolved -split "`r?`n" | Where-Object { $_ -ne "" } | Select-Object -First 1)
    Write-Host "Installed no-mistakes: $installed"

    # A running exe cannot be overwritten on Windows.
    & no-mistakes daemon stop --force

    $backup = "$installed.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Copy-Item -LiteralPath $installed -Destination $backup -Force
    Write-Host "Backed up to $backup"

    try {
        Copy-Item -LiteralPath $source -Destination $installed -Force
    }
    catch {
        Copy-Item -LiteralPath $backup -Destination $installed -Force
        throw "Failed to install patched binary; restored backup: $_"
    }

    & no-mistakes daemon start
    & no-mistakes --version
    Write-Host "Done. (Expect: ost-nm-501)"
}
finally {
    if ($tempDownload -and (Test-Path -LiteralPath $tempDownload)) {
        Remove-Item -LiteralPath $tempDownload -Force -ErrorAction SilentlyContinue
    }
}
