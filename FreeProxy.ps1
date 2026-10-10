<#
.SYNOPSIS
  Finds a working free public proxy and routes Windows traffic through it.

.EXAMPLE
  .\FreeProxy.ps1              # find fastest proxy and enable it system-wide
  .\FreeProxy.ps1 -Quick       # re-test saved proxies first, full scan only if none work
  .\FreeProxy.ps1 -Next        # switch to a different proxy (current one is skipped)
  .\FreeProxy.ps1 -Status      # show whether the proxy is on and your public IP
  .\FreeProxy.ps1 -NoApply     # only find/test proxies, don't change settings
  .\FreeProxy.ps1 -Off         # turn the proxy off and restore your previous settings

  For a window instead of the command line, run FreeProxyGui.ps1 (or FreeProxyGui.cmd).

.NOTES
  This is NOT a real VPN: traffic between you and the proxy is not encrypted
  by the proxy, and only apps that honour the Windows proxy setting use it.
  Public proxies are run by unknown people - stick to HTTPS sites and don't
  log in to anything important while it is on.
#>
param(
    [switch]$Off,
    [switch]$Status,
    [switch]$Next,
    [switch]$Quick,
    [switch]$NoApply,
    [int]$MaxToTest = 400,
    [int]$TimeoutMs = 6000,
    [int]$Threads = 64
)

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'FreeProxy.Core.ps1')

# --- Status / Off ---------------------------------------------------------------
if ($Status) {
    $s = Get-ProxySettings
    if ($s.ProxyEnable -eq 1) { Write-Host "Proxy ON: $($s.ProxyServer)" -ForegroundColor Green }
    else { Write-Host 'Proxy OFF' -ForegroundColor Yellow }
    $ip = Get-PublicIp
    $country = if ($ip -ne '?') { Get-IpCountry $ip }
    Write-Host 'Your public IP:' $ip $(if ($country) { "($country)" })
    if ($ip -eq '?' -and $s.ProxyEnable -eq 1) {
        Write-Host 'The proxy is not responding. Run  .\FreeProxy.ps1 -Next  or  -Off.' -ForegroundColor DarkYellow
    }
    return
}

if ($Off) {
    Restore-ProxySettings
    Write-Host 'Proxy disabled. Your public IP:' (Get-PublicIp) -ForegroundColor Green
    return
}

# --- 1. Find working proxies ----------------------------------------------------
$exclude = if ($Next) { (Get-ProxySettings).ProxyServer }
$working = @()

if ($Quick -or $Next) {
    $cached = @(Get-CachedProxies | Where-Object { $_ -ne $exclude })
    if ($cached.Count -gt 0) {
        Write-Host "Re-testing $($cached.Count) saved proxies..." -ForegroundColor Cyan
        $working = Test-Proxies $cached -TimeoutMs $TimeoutMs -Threads $Threads
    }
    if ($working.Count -eq 0) { Write-Host 'No saved proxies work any more; doing a full scan.' -ForegroundColor DarkYellow }
}

if ($working.Count -eq 0) {
    $all = @(Get-ProxyCandidates | Where-Object { $_ -ne $exclude })
    $candidates = @($all | Get-Random -Count ([Math]::Min($MaxToTest, $all.Count)))
    Write-Host "Testing $($candidates.Count) of $($all.Count) proxies (HTTPS through each)..." -ForegroundColor Cyan
    $working = Test-Proxies $candidates -TimeoutMs $TimeoutMs -Threads $Threads
}

if ($working.Count -eq 0) { throw 'No working proxies found. Try again or raise -MaxToTest.' }

$working = Add-ProxyCountry $working
Write-Host "`n$($working.Count) working proxies. Fastest:" -ForegroundColor Green
$working | Select-Object -First 10 Proxy, Country, Ms, ExitIp | Format-Table -AutoSize | Out-Host
Save-CachedProxies $working

if ($NoApply) { return }

# --- 2. Apply system-wide -------------------------------------------------------
$best = $working[0]
Set-SystemProxy $best.Proxy

Write-Host "Proxy ON: $($best.Proxy)  (exit IP $($best.ExitIp) $($best.Country))" -ForegroundColor Green
Write-Host 'Run  .\FreeProxy.ps1 -Next  to switch proxy,  -Off  to turn it off.'
