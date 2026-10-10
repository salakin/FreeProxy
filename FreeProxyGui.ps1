<#
.SYNOPSIS
  Window for finding free proxies and choosing which one Windows uses.

.DESCRIPTION
  Nothing changes until you click "Use selected", "Use" or "Turn off".
  Start it by double-clicking FreeProxyGui.cmd, or:
    powershell -ExecutionPolicy Bypass -File .\FreeProxyGui.ps1

  This is NOT a VPN - see the notes in FreeProxy.ps1.
#>

$ErrorActionPreference = 'Stop'
$CorePath = Join-Path $PSScriptRoot 'FreeProxy.Core.ps1'
. $CorePath

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

# --- Background work ------------------------------------------------------------
# Network work runs in its own runspace so the window stays responsive; a timer
# polls it, shows progress from $Sync and calls OnDone on the UI thread.
$Sync = [hashtable]::Synchronized(@{})
$script:Job = $null

$wrapper = {
    param($core, $sync, $work, $workArgs)
    $ErrorActionPreference = 'Stop'
    . $core
    & ([scriptblock]::Create($work)) @workArgs
}

function Start-Work([string]$Message, [scriptblock]$Work, [object[]]$Arguments, [scriptblock]$OnDone) {
    if ($script:Job) { return }
    $Sync.Clear()
    $ps = [PowerShell]::Create().AddScript($wrapper).AddArgument($CorePath).AddArgument($Sync).AddArgument($Work.ToString()).AddArgument($Arguments)
    $script:Job = [pscustomobject]@{ PS = $ps; Handle = $ps.BeginInvoke(); OnDone = $OnDone }
    Set-Busy $true $Message
}

function Set-Busy([bool]$Busy, [string]$Message) {
    foreach ($b in $btnScan, $btnRetest, $btnTestManual) { $b.Enabled = -not $Busy }
    $progress.Visible = $Busy
    $progress.Style = 'Marquee'
    if ($Message) { $lblMsg.Text = $Message }
}

# --- Helpers --------------------------------------------------------------------
function Show-State {
    $s = Get-ProxySettings
    if ($s.ProxyEnable -eq 1) {
        $lblState.Text = "Proxy ON:  $($s.ProxyServer)"
        $lblState.ForeColor = [Drawing.Color]::ForestGreen
    } else {
        $lblState.Text = 'Proxy OFF  (direct connection)'
        $lblState.ForeColor = [Drawing.Color]::DimGray
    }
}

function Update-PublicIp {
    if ($script:Job) { $lblIp.Text = 'Public IP: click Refresh when the scan is done'; return }
    $lblIp.Text = 'Public IP: checking...'
    Start-Work '' {
        $ip = Get-PublicIp
        $country = if ($ip -ne '?') { Get-IpCountry $ip }
        [pscustomobject]@{ Ip = $ip; Country = $country }
    } @() {
        param($r)
        $ip = [string]$r[0].Ip
        if ($ip -eq '?') {
            $lblIp.Text = 'Public IP: no response'
            if ((Get-ProxySettings).ProxyEnable -eq 1) { $lblMsg.Text = 'The current proxy is not responding. Pick another one or turn it off.' }
        } else {
            $lblIp.Text = "Public IP: $ip" + $(if ($r[0].Country) { "  ($($r[0].Country))" })
        }
    }
}

function Show-Proxies($Items) {
    $list.BeginUpdate()
    $list.Items.Clear()
    foreach ($p in $Items) {
        $it = New-Object Windows.Forms.ListViewItem([string]$p.Proxy)
        [void]$it.SubItems.Add([string]$p.Country)
        [void]$it.SubItems.Add([string]$p.Ms)
        [void]$it.SubItems.Add([string]$p.ExitIp)
        [void]$list.Items.Add($it)
    }
    $list.EndUpdate()
}

function Use-Proxy([string]$Proxy) {
    try { Set-SystemProxy $Proxy } catch { $lblMsg.Text = "Could not set proxy: $($_.Exception.Message)"; return }
    Show-State
    $lblMsg.Text = "Now using $Proxy."
    Update-PublicIp
}

# --- Layout ---------------------------------------------------------------------
$form = New-Object Windows.Forms.Form
$form.Text = 'FreeProxy'
$form.ClientSize = New-Object Drawing.Size(620, 524)
$form.MinimumSize = New-Object Drawing.Size(560, 420)
$form.StartPosition = 'CenterScreen'
$form.Font = New-Object Drawing.Font('Segoe UI', 9)

function New-Control($Type, $X, $Y, $W, $H, $Text, $Anchor = 'Top, Left') {
    $c = New-Object "Windows.Forms.$Type"
    $c.Location = New-Object Drawing.Point($X, $Y)
    $c.Size = New-Object Drawing.Size($W, $H)
    if ($Text) { $c.Text = $Text }
    $c.Anchor = $Anchor
    $c
}

$grp = New-Control GroupBox 12 8 596 84 'Current proxy' 'Top, Left, Right'
$lblState = New-Control Label 12 22 400 22 ''
$lblState.Font = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
$lblIp = New-Control Label 12 50 400 20 'Public IP:'
$btnRefresh = New-Control Button 420 22 80 28 'Refresh' 'Top, Right'
$btnOff = New-Control Button 506 22 80 28 'Turn off' 'Top, Right'
$grp.Controls.AddRange(@($lblState, $lblIp, $btnRefresh, $btnOff))

$btnScan = New-Control Button 12 102 170 28 'Scan for new proxies'
$btnRetest = New-Control Button 188 102 130 28 'Re-test saved list'
$lblMax = New-Control Label 330 108 76 20 'Max to test:'
$numMax = New-Control NumericUpDown 408 105 80 24 ''
$numMax.Minimum = 10; $numMax.Maximum = 5000; $numMax.Increment = 50; $numMax.Value = 400

$list = New-Control ListView 12 140 596 278 '' 'Top, Bottom, Left, Right'
$list.View = 'Details'
$list.FullRowSelect = $true
$list.MultiSelect = $false
$list.HideSelection = $false
[void]$list.Columns.Add('Proxy', 170)
[void]$list.Columns.Add('Country', 150)
[void]$list.Columns.Add('Speed (ms)', 90)
[void]$list.Columns.Add('Exit IP', 150)

$btnUse = New-Control Button 12 428 150 28 'Use selected' 'Bottom, Left'
$lblManual = New-Control Label 178 434 110 20 'Or enter ip:port:' 'Bottom, Left'
$txtManual = New-Control TextBox 290 431 150 24 '' 'Bottom, Left'
$btnTestManual = New-Control Button 446 428 76 28 'Test' 'Bottom, Left'
$btnUseManual = New-Control Button 528 428 80 28 'Use' 'Bottom, Left'

$progress = New-Control ProgressBar 12 468 596 16 '' 'Bottom, Left, Right'
$progress.Visible = $false
$lblMsg = New-Control Label 12 490 596 30 'Double-click a proxy to use it.' 'Bottom, Left, Right'

$form.Controls.AddRange(@($grp, $btnScan, $btnRetest, $lblMax, $numMax, $list,
    $btnUse, $lblManual, $txtManual, $btnTestManual, $btnUseManual, $progress, $lblMsg))

$tip = New-Object Windows.Forms.ToolTip
$tip.SetToolTip($btnOff, 'Turn the proxy off and restore the settings you had before')
$tip.SetToolTip($btnRetest, 'Check which proxies from the last scan still work')

# --- Events ---------------------------------------------------------------------
$timer = New-Object Windows.Forms.Timer
$timer.Interval = 200
$timer.Add_Tick({
    $job = $script:Job
    if (-not $job) { return }
    if ($Sync.Message) { $lblMsg.Text = $Sync.Message }
    elseif ($Sync.Total -gt 0) {
        $progress.Style = 'Continuous'
        $progress.Maximum = $Sync.Total
        $progress.Value = [Math]::Min([int]$Sync.Done, [int]$Sync.Total)
        $lblMsg.Text = "Testing $($Sync.Done) / $($Sync.Total)   working so far: $($Sync.Working)"
    }
    if (-not $job.Handle.IsCompleted) { return }

    $script:Job = $null
    $err = $null
    try { $result = $job.PS.EndInvoke($job.Handle) }
    catch { $err = $_.Exception; while ($err.InnerException) { $err = $err.InnerException } }
    $job.PS.Dispose()
    Set-Busy $false ''
    if ($err) { $lblMsg.Text = "Error: $($err.Message)" }
    else {
        try { & $job.OnDone $result } catch { $lblMsg.Text = "Error: $($_.Exception.Message)" }
    }
})

$btnRefresh.Add_Click({ Show-State; Update-PublicIp })

$btnOff.Add_Click({
    try { Restore-ProxySettings } catch { $lblMsg.Text = "Could not restore settings: $($_.Exception.Message)"; return }
    Show-State
    $lblMsg.Text = 'Proxy turned off; your previous settings were restored.'
    Update-PublicIp
})

$btnScan.Add_Click({
    Start-Work 'Downloading proxy lists...' {
        param($max)
        $all = @(Get-ProxyCandidates)
        $sample = @($all | Get-Random -Count ([Math]::Min($max, $all.Count)))
        $w = Test-Proxies $sample -State $sync
        $sync.Message = 'Looking up countries...'
        $w = Add-ProxyCountry $w
        Save-CachedProxies $w
        $w
    } @([int]$numMax.Value) {
        param($r)
        Show-Proxies $r
        $lblMsg.Text = if ($r.Count) { "Found $($r.Count) working proxies (fastest first). Select one and click Use." }
                       else { 'No working proxies found this time. Try again or raise "Max to test".' }
    }
})

$btnRetest.Add_Click({
    $cached = @(Get-CachedProxies)
    if ($cached.Count -eq 0) { $lblMsg.Text = 'No saved proxies yet. Click "Scan for new proxies".'; return }
    Start-Work "Re-testing $($cached.Count) saved proxies..." {
        param($proxies)
        $w = Test-Proxies $proxies -State $sync
        $sync.Message = 'Looking up countries...'
        $w = Add-ProxyCountry $w
        Save-CachedProxies $w
        $w
    } @(, [string[]]$cached) {
        param($r)
        Show-Proxies $r
        $lblMsg.Text = if ($r.Count) { "$($r.Count) saved proxies still work." }
                       else { 'None of the saved proxies work any more. Click "Scan for new proxies".' }
    }
})

$useSelected = {
    if ($list.SelectedItems.Count -eq 0) { $lblMsg.Text = 'Select a proxy in the list first.'; return }
    Use-Proxy $list.SelectedItems[0].Text
}
$btnUse.Add_Click($useSelected)
$list.Add_DoubleClick($useSelected)

$btnTestManual.Add_Click({
    $p = $txtManual.Text.Trim()
    if ($p -notmatch $ProxyPattern) { $lblMsg.Text = 'Enter the proxy as ip:port, e.g. 1.2.3.4:8080'; return }
    Start-Work "Testing $p..." {
        param($proxy)
        Add-ProxyCountry (Test-Proxies @($proxy) -State $sync)
    } @($p) {
        param($r)
        if ($r.Count) { $lblMsg.Text = "$($r[0].Proxy) works: $($r[0].Ms) ms, exit IP $($r[0].ExitIp) $(if ($r[0].Country) { "($($r[0].Country))" })." }
        else { $lblMsg.Text = 'That proxy did not work (no valid response within 6 seconds).' }
    }
})

$btnUseManual.Add_Click({
    $p = $txtManual.Text.Trim()
    if ($p -notmatch $ProxyPattern) { $lblMsg.Text = 'Enter the proxy as ip:port, e.g. 1.2.3.4:8080'; return }
    Use-Proxy $p
})

$form.Add_Shown({
    Show-Proxies (Get-CachedProxyInfo)
    Show-State
    Update-PublicIp
})

$form.Add_FormClosing({
    $timer.Stop()
    if ($script:Job) { [void]$script:Job.PS.BeginStop($null, $null) }
})

$timer.Start()
[void]$form.ShowDialog()
