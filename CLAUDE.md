# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Windows PowerShell 5.1 tool that scrapes free public HTTP proxy lists, tests them in parallel, looks up each exit IP's country, and sets a chosen proxy as the current user's system-wide (WinINet) proxy. No build, no dependencies, no test suite, not a git repo.

- [FreeProxy.Core.ps1](FreeProxy.Core.ps1): all shared logic (registry, backup/restore, list download, testing, country lookup, cache). Dot-sourced and has no side effects beyond defining things.
- [FreeProxy.ps1](FreeProxy.ps1): command-line front end (switches below).
- [FreeProxyGui.ps1](FreeProxyGui.ps1): Windows Forms front end. [FreeProxyGui.cmd](FreeProxyGui.cmd) launches it with the console hidden.

## Commands

```powershell
.\FreeProxy.ps1                      # find fastest proxy and enable it system-wide
.\FreeProxy.ps1 -NoApply             # find/test only; writes working-proxies.txt, no registry changes
.\FreeProxy.ps1 -Quick               # re-test working-proxies.txt first, full scan only if none work
.\FreeProxy.ps1 -Next                # same as -Quick but excludes the currently set ProxyServer
.\FreeProxy.ps1 -Status              # read-only: proxy state + public IP + country
.\FreeProxy.ps1 -Off                 # restore settings from proxy-backup.json (or just disable)
.\FreeProxy.ps1 -MaxToTest 100 -TimeoutMs 4000 -Threads 32   # tuning knobs (defaults 400 / 6000 / 64)
.\FreeProxyGui.ps1                   # window
```

**The user does not want their system proxy changed.** When testing, use only `-NoApply` (can combine with `-Quick`/`-Next`) and `-Status`. Never run the apply path or `-Off`, never click Use/Turn off in the GUI, and never write the Internet Settings registry keys. If execution policy blocks the script: `powershell -ExecutionPolicy Bypass -File .\FreeProxy.ps1 -NoApply`.

Test the GUI headlessly instead of opening windows on the user's desktop. In a scratch copy, replace `[void]$form.ShowDialog()` with code that calls `$form.CreateControl()`, fires handlers through reflection (`[Windows.Forms.Control].GetMethod('OnClick', 'NonPublic,Instance').Invoke($btn, @([EventArgs]::Empty))`), pumps `[Windows.Forms.Application]::DoEvents()` until `$script:Job` is `$null`, then reads label and list text. `DrawToBitmap` on a hidden form renders blank.

## How it works

1. **Collect**: with `-Quick`/`-Next`, the CLI first re-tests the cached list and skips the download if any still work. Otherwise `Get-ProxyCandidates` downloads plain-text `ip:port` lists from `$Sources`, keeps lines matching `$ProxyPattern`, and dedupes via a `HashSet`. The caller then samples up to `-MaxToTest`. A failed source is logged and skipped; zero total proxies throws.
2. **Test**: `Test-Proxies` creates a `RunspacePool` that runs the `$test` scriptblock per proxy: an HTTPS GET to `https://api.ipify.org` through the proxy. A proxy counts as working only if the body is a bare IPv4 address (this filters out captive or garbage pages). It returns `[pscustomobject]@{Proxy; Ms; ExitIp}` sorted by `Ms`. An optional synchronized `-State` hashtable receives `Total/Done/Working` for GUI progress.
3. **Country**: `Add-ProxyCountry` POSTs unique exit IPs to `http://ip-api.com/batch` (100 per request, no key; HTTPS needs a paid plan) and adds a `Country` property. Failures leave it empty. `Get-IpCountry` does a single IP for status.
4. **Cache**: `working-proxies.txt` lines are `proxy<TAB>country<TAB>ms<TAB>exitIp`. `Get-CachedProxyInfo` also accepts bare `ip:port` lines. `Save-CachedProxies` does nothing on an empty result, so a failed scan doesn't wipe the list.
5. **Apply**: `Set-SystemProxy` calls `Save-ProxyBackup`, which writes the original `ProxyEnable/ProxyServer/ProxyOverride` to `proxy-backup.json` only if that file doesn't already exist, so it keeps the true original across switches. It then writes `ProxyServer`, `ProxyOverride` (`$BypassList`) and `ProxyEnable=1` under HKCU Internet Settings and calls `wininet.dll!InternetSetOption` with 39 (SETTINGS_CHANGED) and 37 (REFRESH) so running apps pick up the change.

`Restore-ProxySettings` writes the backup back (removing values that were absent) and deletes the file. **A backup file existing means the active proxy is ours**: `New-WebClient` then bypasses the system proxy for downloads and lookups, so a dead proxy can't block rescans. `Get-PublicIp` deliberately uses `[Net.WebRequest]::GetSystemWebProxy()` per call (not the process-cached default proxy), so it reflects changes made in the same process (the GUI).

## GUI threading model

All network work runs off the UI thread. `Start-Work` runs a `$wrapper` in a fresh `[PowerShell]` runspace. The wrapper dot-sources the core file and recreates the work scriptblock from its string with `[scriptblock]::Create`, because scriptblocks are bound to their origin runspace. Inside the work block, `$sync` is the shared synchronized hashtable; setting `$sync.Message` overrides the progress text. A 200 ms `Windows.Forms.Timer` polls the job, updates the progress bar, and calls `OnDone` on the UI thread. Only one job runs at a time, and buttons that start work are disabled while one runs. Use and Turn off only touch the registry, so they stay on the UI thread and are never blocked.

## Constraints / gotchas

- Wrap pipeline results in `@()` before using `.Count`: in PS 5.1, a single `[pscustomobject]` has no `.Count`. Also `@($null)` has one element, so filter nulls (`Where-Object { $_ }`).
- Target is **Windows PowerShell 5.1** (.NET Framework). It explicitly forces TLS 1.2 in every runspace, because runspaces don't inherit `ServicePointManager` settings. Avoid PS7-only syntax (`??`, `?.`, ternary, `ForEach-Object -Parallel`).
- Runspace scriptblocks (`$test`, GUI work) can't see the caller's variables or functions. Pass everything via `AddArgument`, or dot-source the core inside the runspace.
- Passing an array as one argument through `Start-Work`'s splatted `-Arguments` needs the unary comma: `@(, [string[]]$list)`.
- `Win32.WinInet` is added only if the type doesn't exist yet. Types are per process and the GUI loads the core into several runspaces. Changing its signature requires a new process.
- `$ErrorActionPreference = 'Stop'` is set by both front ends. Network calls that are allowed to fail are wrapped in `try/catch`.
- Only affects the current user (HKCU) and only apps honouring the WinINet proxy setting. It is not a VPN. Keep the warnings in the script help and README intact.
