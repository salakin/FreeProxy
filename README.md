# FreeProxy

Finds working free proxies, shows their country, and lets you switch your Windows proxy with one click.

> ⚠️ **Not a VPN.** Proxies are run by strangers. Use HTTPS sites only and don't log in to anything important.

## Requirements

- Windows 10/11 (PowerShell 5.1 comes with Windows)
- No admin rights or installs needed

## How to use (window)

1. **Open** by double-clicking `FreeProxyGui.cmd`.
2. **Check the top box.** It shows whether a proxy is on, plus your public IP and country.
3. **Find proxies.** Click **Scan for new proxies** (about 1 minute). To check last time's list instead, click **Re-test saved list**.
4. **Pick one.** The list shows **Proxy · Country · Speed · Exit IP**, fastest first.
5. **Turn it on.** Select a proxy and click **Use selected**, or double-click it.
6. **Confirm it worked.** The top box now shows the proxy's IP and country.
7. **If a site stops loading,** pick another proxy (they die often).
8. **When you're done,** click **Turn off** to restore your original settings.

**Your own proxy:** type `ip:port` in the box at the bottom, click **Test**, then **Use**.

## How to use (command line)

Run these in PowerShell, from this folder:

| Command | What it does |
|---|---|
| `.\FreeProxy.ps1` | Find the fastest proxy and turn it on |
| `.\FreeProxy.ps1 -Next` | Switch to a different proxy |
| `.\FreeProxy.ps1 -Quick` | Re-use saved proxies (faster) |
| `.\FreeProxy.ps1 -Status` | Show proxy, IP and country |
| `.\FreeProxy.ps1 -NoApply` | Only test proxies, change nothing |
| `.\FreeProxy.ps1 -Off` | Turn off and restore your settings |

Optional: `-MaxToTest 400` · `-TimeoutMs 6000` · `-Threads 64`

**"Script is disabled" error?** Run:
`powershell -ExecutionPolicy Bypass -File .\FreeProxy.ps1`

## Good to know

- Only apps that follow the Windows proxy setting use it (browsers do; many games and tools don't).
- The proxy **stays on after a reboot** until you turn it off.
- If something goes wrong, use **Turn off**, or *Settings → Network & Internet → Proxy*.
- Countries come from ip-api.com. If a country is blank, the lookup failed. Try again later.

## Files

| File | Purpose |
|---|---|
| `FreeProxyGui.cmd` | Opens the window |
| `FreeProxyGui.ps1` | The window |
| `FreeProxy.ps1` | Command-line version |
| `FreeProxy.Core.ps1` | Shared logic |
| `working-proxies.txt` | Last working proxies (auto) |
| `proxy-backup.json` | Your original settings while a proxy is on (auto) |
