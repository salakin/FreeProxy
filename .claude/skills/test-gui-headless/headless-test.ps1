# Runs FreeProxyGui.ps1 invisibly with scripted clicks. Never changes the system proxy:
# Set-SystemProxy / Restore-ProxySettings are replaced with functions that throw.
param([string]$ProjectDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path)

$ErrorActionPreference = 'Stop'
$reg = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$before = Get-ItemProperty $reg | Select-Object ProxyEnable, ProxyServer, ProxyOverride

$work = Join-Path $env:TEMP "freeproxy-gui-test-$PID"
New-Item -ItemType Directory -Force $work | Out-Null
Copy-Item (Join-Path $ProjectDir 'FreeProxy.Core.ps1') $work
$cache = Join-Path $ProjectDir 'working-proxies.txt'
if (Test-Path $cache) { Copy-Item $cache $work }

$marker = '[void]$form.ShowDialog()'
$src = Get-Content (Join-Path $ProjectDir 'FreeProxyGui.ps1') -Raw
if (-not $src.Contains($marker)) { throw "'$marker' not found in FreeProxyGui.ps1 - update headless-test.ps1" }

$scenarios = @'
# ---- headless scenarios (replaces ShowDialog) ----
function Set-SystemProxy { throw 'blocked by headless test' }
function Restore-ProxySettings { throw 'blocked by headless test' }
$log = Join-Path $PSScriptRoot 'headless.log'
'' | Set-Content $log
function Pump([int]$Seconds) {
    $end = (Get-Date).AddSeconds($Seconds)
    do { [Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 50 } while ($script:Job -and (Get-Date) -lt $end)
    [Windows.Forms.Application]::DoEvents()
    if ($script:Job) { "!! timed out after $Seconds s" | Add-Content $log }
}
function Fire($ctl) { [Windows.Forms.Control].GetMethod('OnClick', [Reflection.BindingFlags]'NonPublic,Instance').Invoke($ctl, @([EventArgs]::Empty)) }
function Dump($what) {
    "== $what" | Add-Content $log
    "  state: $($lblState.Text) | $($lblIp.Text)" | Add-Content $log
    "  msg:   $($lblMsg.Text)" | Add-Content $log
    foreach ($it in $list.Items) { '    ' + (($it.SubItems | ForEach-Object { $_.Text }) -join ' | ') | Add-Content $log }
}

$form.CreateControl()
Show-Proxies (Get-CachedProxyInfo); Show-State; Update-PublicIp
Pump 30; Dump 'startup'

Fire $btnRetest; Pump 180; Dump 're-test saved list'

$first = if ($list.Items.Count) { $list.Items[0].Text } else { '1.1.1.1:80' }
$txtManual.Text = $first; Fire $btnTestManual; Pump 30; Dump "manual test $first"
$txtManual.Text = 'not-a-proxy'; Fire $btnTestManual; Pump 2; Dump 'manual test bad input'

$list.SelectedItems.Clear(); Fire $btnUse; Dump 'use with nothing selected'
if ($list.Items.Count) { $list.Items[0].Selected = $true; Fire $btnUse; Dump 'use selected (blocked)' }
Fire $btnOff; Dump 'turn off (blocked)'
'== done' | Add-Content $log
'@

Set-Content (Join-Path $work 'FreeProxyGui.ps1') $src.Replace($marker, $scenarios)
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $work 'FreeProxyGui.ps1')
Get-Content (Join-Path $work 'headless.log')

$after = Get-ItemProperty $reg | Select-Object ProxyEnable, ProxyServer, ProxyOverride
$same = ($before | ConvertTo-Json) -eq ($after | ConvertTo-Json)
"== registry unchanged: $same"
Remove-Item $work -Recurse -Force
if (-not $same) { exit 1 }
