# OST vendored patch — Azure DevOps PR description on Windows (#501)

This directory holds a locally-vendored build of `no-mistakes` that carries a
one-file bug fix for issue **#501**, plus the scripts to build and deploy it to
Windows colleagues.

## The bug (#501)

On **Windows only**, PR descriptions created/updated against Azure DevOps were
silently truncated to their first line (e.g. just `## Intent`).

Root cause: the Azure DevOps connector
(`internal/scm/azuredevops/azuredevops.go`) passed the PR body inline as
`--description <body>`. On Windows, Go runs the `az` CLI as `az.cmd` through
`cmd.exe`, and `cmd.exe` terminates each argument at the first newline. A
multi-line description therefore lost everything after line one — real data
loss, invisible until you looked at the PR in the browser.

## The fix

The (clamped) body is written to a temp file and passed as
`--description @<tempfile>`. `az repos pr create`/`update` read the description
from the file via the `@` convention. This:

- survives `cmd.exe` — the argument is a single newline-free token;
- avoids Python `argparse` misreading body lines that start with `-`/`--`/`---`
  (markdown horizontal rules, diff `--- a/file` hunks) as new options, which a
  naive per-line split would break on;
- keeps the 4000-char Azure DevOps clamp (`clampDescription`) applied before the
  file is written;
- fails closed: a temp-file write error returns a wrapped error rather than
  falling back to the broken inline form.

The change is isolated to a single source file
(`internal/scm/azuredevops/azuredevops.go`, helper `runWithDescription`) plus its
test file. The `scm.Host` interface is unchanged.

## Why vendored

The upstream fix is still `needs-decision` (the maintainer endorsed the
temp-file approach in triage but has not merged a release). Rather than wait, we
build our own binary from this branch so Windows colleagues stop losing PR
descriptions today.

## The version pin (and why it disables self-update)

`build-patched.sh` pins `internal/buildinfo.Version = ost-nm-501`. That string
is intentionally **not** semver. The self-updater
(`internal/update.isDevVersion`) treats any version it cannot parse as a
development build, so:

- the background upgrade-nag never fires, and
- `no-mistakes update` prints `self-update unavailable for development builds
  (ost-nm-501)` and does nothing.

This is what stops an upstream auto-update from silently overwriting the patched
binary and reintroducing the bug. Verified locally:

```
$ dist/no-mistakes.exe --version
no-mistakes version ost-nm-501 (<commit>) <date>
$ dist/no-mistakes.exe update
self-update unavailable for development builds (ost-nm-501)
```

## How to build

From the repo root, with Go on PATH:

```bash
./ost-patch/build-patched.sh
```

Produces `dist/no-mistakes.exe` (windows/amd64, `CGO_ENABLED=0`). The script
mirrors the Makefile LDFLAGS (`Version`, `Commit`, `Date`, and the default
telemetry host/website id) and only overrides `Version` with the pin.

## How the build is distributed

The patched binary is published as an asset on a **GitHub Release** of the OST
fork (`SaschaGschwind/no-mistakes`), tagged `ost-nm-501` on the `deploy` branch.
Colleagues do not build it themselves — `deploy-nm.ps1` pulls the asset by URL:

```
https://github.com/SaschaGschwind/no-mistakes/releases/download/ost-nm-501/no-mistakes.exe
```

To cut a release (maintainer, after building `dist/no-mistakes.exe`):

```bash
gh release create ost-nm-501 dist/no-mistakes.exe \
  --repo SaschaGschwind/no-mistakes --target deploy \
  --title "ost-nm-501 — #501 ADO PR-description fix" \
  --notes "Windows-only vendored build; see ost-patch/README.md."
```

## How to deploy

On the target Windows machine (PowerShell) — **no build required**:

```powershell
powershell -ExecutionPolicy Bypass -File ost-patch/deploy-nm.ps1
```

The script downloads the `no-mistakes.exe` asset from the `ost-nm-501` release,
resolves the installed path via `where.exe no-mistakes` (it does NOT hardcode a
location — the shared/per-user install path is unconfirmed), stops the daemon,
backs up the existing exe (timestamped `.bak-<stamp>` alongside it), copies the
downloaded exe over it, restarts the daemon, and prints `no-mistakes --version`
(expect `ost-nm-501`). It aborts if the download fails or `where` finds nothing,
and restores the backup if the copy fails. Pass `-PatchedExe <path>` to install
a locally-built binary instead of downloading (skips the download).

## Ongoing maintenance

- The fix is a single-file patch. When a new upstream tag ships, rebase the
  `deploy` branch onto it, rebuild with a fresh pin (bump `VERSION` in
  `build-patched.sh`, e.g. `ost-nm-501-2`), and cut a new release under the
  matching tag. Point colleagues at `deploy-nm.ps1 -Tag <new-tag>` (or bump the
  script's default `Tag`).
- Retire this vendored build once upstream ships the fix in a real release —
  then colleagues manually install that upstream SemVer release (which
  re-arms the auto-updater) and leave the hook removed. Do NOT run
  `no-mistakes update` on the pinned build — it is a no-op on a dev-version
  build.

## Scope

Only **Windows** colleagues need this build; the truncation is Windows-only
(`cmd.exe` argument handling). macOS/Linux users are unaffected and should stay
on the normal upstream releases.

## Verified end-to-end (2026-07-16)

The fix was exercised end-to-end against a real Azure DevOps organization: a
throwaway PR created through the full no-mistakes gate (running the pinned
`ost-nm-501` binary) against
`dev.azure.com/ost-it-ba-dev/Entwicklermeetings/TestReact`. The resulting PR
description stored the complete multi-line body (all of `## Intent`,
`## What Changed`, `## Risk Assessment`, `## Testing`, `## Pipeline`) instead of
collapsing to just `## Intent`, confirming `az repos pr create` with
`--description @<file>` reads the description from the file. Clamping, temp-file
lifecycle, no-newline-in-args, and cleanup are additionally covered by unit
tests.

Gotcha: on Windows, `az repos pr show` re-encodes its output as cp1252 and
silently drops characters it cannot represent (e.g. umlauts). To inspect a
stored PR body faithfully, read it through the Azure DevOps REST API
(`_apis/git/repositories/<repo>/pullRequests/<id>`), which returns UTF-8 — not
`az ... show`. This only affects reading the body back; the write path
(`--description @<file>`) preserves UTF-8 correctly.
