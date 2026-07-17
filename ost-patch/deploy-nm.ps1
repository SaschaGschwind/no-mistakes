<#
.SYNOPSIS
    Deploy the OST-patched no-mistakes.exe (#501 fix) over the installed binary.

.DESCRIPTION
    For Windows colleagues. Downloads the patched no-mistakes.exe from the OST
    fork's GitHub Release asset URL, locates the currently installed
    `no-mistakes` executable via `where.exe` (the shared/per-user install
    location is NOT hardcoded because it is unconfirmed), stops the daemon, backs
    up and replaces the binary with the downloaded one, restarts the daemon, and
    prints the version to confirm.

    No build step and no Go toolchain are required on the target machine: the
    binary is pulled straight from the release asset. To deploy a locally-built
    binary instead (e.g. when iterating on the patch), pass -PatchedExe pointing
    at the dist/no-mistakes.exe produced by ost-patch/build-patched.sh; the
    download is then skipped.

.PARAMETER Tag
    Release tag to pull the asset from. Defaults to the pinned OST build tag.
    Ignored when -PatchedExe is supplied.

.PARAMETER Repo
    owner/name of the fork hosting the release. Defaults to the OST fork.

.PARAMETER PatchedExe
    Optional path to a locally-built patched binary. When set, the script skips
    the download and installs this file instead.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ost-patch/deploy-nm.ps1

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ost-patch/deploy-nm.ps1 -PatchedExe ..\dist\no-mistakes.exe
#>

[CmdletBinding()]
param(
    [string]$Tag = "ost-nm-501",
    [string]$Repo = "SaschaGschwind/no-mistakes",
    [string]$PatchedExe
)

$ErrorActionPreference = "Stop"

function Fail([string]$msg) {
    Write-Error $msg
    exit 1
}

# 1. Obtain the patched binary: a caller-supplied local build, or the release
#    asset downloaded by URL from the fork.
$tempDownload = $null
if ($PatchedExe) {
    if (-not (Test-Path -LiteralPath $PatchedExe)) {
        Fail "Patched binary not found at '$PatchedExe'."
    }
    $source = (Resolve-Path -LiteralPath $PatchedExe).Path
    Write-Host "Using local patched binary: $source"
}
else {
    $url = "https://github.com/$Repo/releases/download/$Tag/no-mistakes.exe"
    $tempDownload = Join-Path ([System.IO.Path]::GetTempPath()) "no-mistakes-$Tag.exe"
    Write-Host "Downloading patched binary from: $url"
    try {
        Invoke-WebRequest -Uri $url -OutFile $tempDownload -UseBasicParsing
    }
    catch {
        Fail "Download failed from '$url': $_"
    }
    $source = $tempDownload
}

try {
    # 2. Resolve the installed no-mistakes path (do NOT hardcode it).
    $resolved = & where.exe no-mistakes 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $resolved) {
        Fail "'where.exe no-mistakes' found nothing on PATH. Is no-mistakes installed? Aborting."
    }
    # where.exe may return multiple matches (one per line); take the first.
    $installed = ($resolved -split "`r?`n" | Where-Object { $_ -ne "" } | Select-Object -First 1)
    Write-Host "Installed no-mistakes: $installed"

    # 3. Stop the daemon before swapping the binary (a running exe cannot be
    #    overwritten on Windows).
    Write-Host "Stopping daemon..."
    & no-mistakes daemon stop --force
    # Do not hard-fail if stop reports non-zero (daemon may already be stopped).

    # 4. Back up the existing binary next to it, timestamped.
    $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backup = "$installed.bak-$stamp"
    Write-Host "Backing up existing binary to: $backup"
    Copy-Item -LiteralPath $installed -Destination $backup -Force

    # 5. Copy the patched binary over the installed location.
    Write-Host "Copying patched binary into place..."
    try {
        Copy-Item -LiteralPath $source -Destination $installed -Force
    }
    catch {
        Write-Warning "Copy failed; restoring backup."
        Copy-Item -LiteralPath $backup -Destination $installed -Force
        Fail "Failed to install patched binary: $_"
    }

    # 6. Restart the daemon.
    Write-Host "Starting daemon..."
    & no-mistakes daemon start

    # 7. Confirm the deployed version.
    Write-Host "Deployed version:"
    & no-mistakes --version
    Write-Host "Done. (Expect: ost-nm-501)"
}
finally {
    if ($tempDownload -and (Test-Path -LiteralPath $tempDownload)) {
        Remove-Item -LiteralPath $tempDownload -Force -ErrorAction SilentlyContinue
    }
}
