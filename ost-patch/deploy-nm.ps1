<#
.SYNOPSIS
    Deploy the OST-patched no-mistakes.exe (#501 fix) over the installed binary.

.DESCRIPTION
    For Windows colleagues. Locates the currently installed `no-mistakes`
    executable via `where.exe` (the shared/per-user install location is NOT
    hardcoded because it is unconfirmed), stops the daemon, backs up and replaces
    the binary with the freshly built patched one, restarts the daemon, and
    prints the version to confirm.

    Build the patched binary first with ost-patch/build-patched.sh, which writes
    dist/no-mistakes.exe.

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File ost-patch/deploy-nm.ps1
#>

[CmdletBinding()]
param(
    # Path to the patched binary produced by build-patched.sh.
    [string]$PatchedExe = (Join-Path $PSScriptRoot "..\dist\no-mistakes.exe")
)

$ErrorActionPreference = "Stop"

function Fail([string]$msg) {
    Write-Error $msg
    exit 1
}

# 1. Confirm the patched binary exists.
if (-not (Test-Path -LiteralPath $PatchedExe)) {
    Fail "Patched binary not found at '$PatchedExe'. Build it first: ost-patch/build-patched.sh"
}
$PatchedExe = (Resolve-Path -LiteralPath $PatchedExe).Path

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
    Copy-Item -LiteralPath $PatchedExe -Destination $installed -Force
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
