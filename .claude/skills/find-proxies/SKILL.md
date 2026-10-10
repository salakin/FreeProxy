---
name: find-proxies
description: Find working free proxies for the user and show them with country and speed, without changing their system proxy. Use when the user asks to find/scan/list proxies or asks what their current proxy is.
---

# Find proxies (read-only)

Never apply a proxy or turn it off. The user switches proxies themselves in the GUI.

1. Current state:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\FreeProxy.ps1 -Status
   ```
2. Scan (up to ~5 min; use a 600000 ms timeout):
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\FreeProxy.ps1 -NoApply
   ```
   Pass the user's request through when they want a quick re-check of the saved list (`-Quick`), more proxies (`-MaxToTest 1000`) or fewer.
3. The console shows only the top 10. Read `working-proxies.txt` for the full list (`proxy<TAB>country<TAB>ms<TAB>exitIp`).

## Reply format

- One line: current state (proxy on/off, public IP, country).
- A table: `# | Proxy | Country | Speed (ms)`, fastest first.
- One line on how to use one: open `FreeProxyGui.cmd`, double-click a proxy, and click **Turn off** when done.
- If zero proxies worked, say so and suggest a rerun or a larger `-MaxToTest`.

The scan rewrites `working-proxies.txt`, which is tracked in git, so mention that it changed. Don't commit unless asked.
