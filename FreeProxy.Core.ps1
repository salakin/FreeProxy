# Shared functions for FreeProxy.ps1 (command line) and FreeProxyGui.ps1 (window).
# Dot-source this file; it does nothing on its own.

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$RegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$TestUrl = 'https://api.ipify.org'
$CacheFile = Join-Path $PSScriptRoot 'working-proxies.txt'
$BackupFile = Join-Path $PSScriptRoot 'proxy-backup.json'
$ProxyKeys = 'ProxyEnable', 'ProxyServer', 'ProxyOverride'
$ProxyPattern = '^\d{1,3}(\.\d{1,3}){3}:\d{2,5}$'
$BypassList = '<local>;localhost;127.*;10.*;192.168.*'

$Sources = @(
    'https://api.proxyscrape.com/v2/?request=displayproxies&protocol=http&timeout=5000&country=all&ssl=yes&anonymity=all',
    'https://raw.githubusercontent.com/TheSpeedX/PROXY-List/master/http.txt',
    'https://raw.githubusercontent.com/monosans/proxy-list/main/proxies/http.txt'
)

# Types are per-process, and the GUI dot-sources this file into several runspaces.
if (-not ('Win32.WinInet' -as [type])) {
    Add-Type -Namespace Win32 -Name WinInet -MemberDefinition @'
[DllImport("wininet.dll", SetLastError = true)]
public static extern bool InternetSetOption(System.IntPtr hInternet, int dwOption, System.IntPtr lpBuffer, int dwBufferLength);
'@
}

function Update-SystemProxy {
    # INTERNET_OPTION_SETTINGS_CHANGED (39) + INTERNET_OPTION_REFRESH (37)
    [void][Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)
    [void][Win32.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)
}

# Public IP as seen through the current system proxy settings (re-read on every call).
function Get-PublicIp {
    try {
        $req = [Net.HttpWebRequest]::Create($TestUrl)
        $req.Proxy = [Net.WebRequest]::GetSystemWebProxy()
        $req.Timeout = 10000
        $req.ReadWriteTimeout = 10000
        $resp = $req.GetResponse()
        try { (New-Object IO.StreamReader($resp.GetResponseStream())).ReadToEnd().Trim() }
        finally { $resp.Close() }
    } catch { '?' }
}

# A backup file means the active proxy is one we set (and may be dead), so go direct.
function New-WebClient {
    $wc = New-Object Net.WebClient
    if (Test-Path $BackupFile) { $wc.Proxy = $null }
    $wc
}

function Get-ProxySettings {
    $item = Get-ItemProperty $RegPath
    $h = [ordered]@{}
    foreach ($k in $ProxyKeys) { $h[$k] = $item.$k }
    [pscustomobject]$h
}

# Saved only once, so repeated runs / -Next keep the user's original settings.
function Save-ProxyBackup {
    if (-not (Test-Path $BackupFile)) {
        Get-ProxySettings | ConvertTo-Json | Set-Content $BackupFile
    }
}

function Set-SystemProxy([string]$Proxy) {
    Save-ProxyBackup
    Set-ItemProperty $RegPath -Name ProxyServer -Value $Proxy
    Set-ItemProperty $RegPath -Name ProxyOverride -Value $BypassList
    Set-ItemProperty $RegPath -Name ProxyEnable -Value 1
    Update-SystemProxy
}

function Restore-ProxySettings {
    if (Test-Path $BackupFile) {
        $b = Get-Content $BackupFile -Raw | ConvertFrom-Json
        foreach ($k in $ProxyKeys) {
            if ($null -eq $b.$k) { Remove-ItemProperty $RegPath -Name $k -ErrorAction SilentlyContinue }
            else { Set-ItemProperty $RegPath -Name $k -Value $b.$k }
        }
        Remove-Item $BackupFile
    } else {
        Set-ItemProperty $RegPath -Name ProxyEnable -Value 0
    }
    Update-SystemProxy
}

# Cache lines are "ip:port<TAB>country<TAB>ms<TAB>exit ip"; plain "ip:port" lines also work.
function Get-CachedProxyInfo {
    if (-not (Test-Path $CacheFile)) { return }
    foreach ($line in Get-Content $CacheFile) {
        $f = $line -split "`t"
        if ($f[0] -match $ProxyPattern) {
            [pscustomobject]@{ Proxy = $f[0]; Country = $f[1]; Ms = $f[2]; ExitIp = $f[3] }
        }
    }
}

function Get-CachedProxies { Get-CachedProxyInfo | ForEach-Object { $_.Proxy } }

# Keeps the previous list when nothing worked, so a bad scan doesn't wipe it.
function Save-CachedProxies($Working) {
    $lines = @($Working | ForEach-Object { "$($_.Proxy)`t$($_.Country)`t$($_.Ms)`t$($_.ExitIp)" })
    if ($lines.Count -gt 0) { $lines | Set-Content $CacheFile }
}

# Country of each proxy's exit IP via ip-api.com (free, no key, max 100 IPs per request).
# Lookup failures leave Country empty.
function Add-ProxyCountry($Working) {
    $items = @($Working | Where-Object { $_ })
    $ips = @($items | ForEach-Object { $_.ExitIp } | Where-Object { $_ } | Select-Object -Unique)
    $map = @{}
    for ($i = 0; $i -lt $ips.Count; $i += 100) {
        $chunk = $ips[$i..([Math]::Min($i + 99, $ips.Count - 1))]
        try {
            $wc = New-WebClient
            $wc.Headers['Content-Type'] = 'application/json'
            $json = ConvertTo-Json -InputObject @($chunk) -Compress
            $res = $wc.UploadString('http://ip-api.com/batch?fields=status,country,query', $json) | ConvertFrom-Json
            foreach ($r in $res) { if ($r.status -eq 'success') { $map[$r.query] = $r.country } }
        } catch { }
    }
    foreach ($w in $items) {
        $country = if ($w.ExitIp) { [string]$map[$w.ExitIp] } else { '' }
        $w | Add-Member -NotePropertyName Country -NotePropertyValue $country -Force
    }
    $items
}

function Get-IpCountry([string]$Ip) {
    try { ((New-WebClient).DownloadString("http://ip-api.com/json/$Ip`?fields=country") | ConvertFrom-Json).country }
    catch { '' }
}

function Get-ProxyCandidates {
    Write-Host 'Downloading proxy lists...' -ForegroundColor Cyan
    $all = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($src in $Sources) {
        try {
            $text = (New-WebClient).DownloadString($src)
            $n = 0
            foreach ($line in $text -split "`r?`n") {
                $p = $line.Trim()
                if ($p -match $ProxyPattern -and $all.Add($p)) { $n++ }
            }
            Write-Host "  $n from $src"
        } catch {
            Write-Host "  failed: $src" -ForegroundColor DarkYellow
        }
    }
    if ($all.Count -eq 0) { throw 'No proxies downloaded.' }
    $all
}

# Returns the proxies that work, fastest first. $State (a synchronized hashtable)
# receives Total/Done/Working so a GUI thread can show progress.
function Test-Proxies {
    param([string[]]$List, [int]$TimeoutMs = 6000, [int]$Threads = 64, [hashtable]$State)

    $test = {
        param($proxy, $url, $timeout)
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $sw = [Diagnostics.Stopwatch]::StartNew()
        try {
            $req = [Net.HttpWebRequest]::Create($url)
            $req.Proxy = New-Object Net.WebProxy("http://$proxy")
            $req.Timeout = $timeout
            $req.ReadWriteTimeout = $timeout
            $resp = $req.GetResponse()
            $body = (New-Object IO.StreamReader($resp.GetResponseStream())).ReadToEnd().Trim()
            $resp.Close()
            if ($body -match '^\d{1,3}(\.\d{1,3}){3}$') {
                [pscustomobject]@{ Proxy = $proxy; Ms = $sw.ElapsedMilliseconds; ExitIp = $body }
            }
        } catch { }
    }

    if ($State) { $State.Total = $List.Count; $State.Done = 0; $State.Working = 0 }
    $pool = [RunspaceFactory]::CreateRunspacePool(1, $Threads)
    $pool.Open()
    $working = @()
    try {
        $jobs = foreach ($p in $List) {
            $ps = [PowerShell]::Create().AddScript($test).AddArgument($p).AddArgument($TestUrl).AddArgument($TimeoutMs)
            $ps.RunspacePool = $pool
            [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
        }
        $done = 0
        foreach ($j in $jobs) {
            $working += $j.PS.EndInvoke($j.Handle)
            $j.PS.Dispose()
            $done++
            if ($State) { $State.Done = $done; $State.Working = $working.Count }
            Write-Progress -Activity 'Testing proxies' -Status "$done / $($List.Count)  working: $($working.Count)" -PercentComplete ($done * 100 / $List.Count)
        }
    } finally {
        Write-Progress -Activity 'Testing proxies' -Completed
        $pool.Close()
        $pool.Dispose()
    }
    @($working | Sort-Object Ms)
}
