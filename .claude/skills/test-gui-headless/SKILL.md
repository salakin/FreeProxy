---
name: test-gui-headless
description: Test FreeProxyGui.ps1 without showing a window or touching the user's proxy. Use after changing the GUI or FreeProxy.Core.ps1.
---

# Headless GUI test

Opening the window on the user's desktop is intrusive (windows got closed mid-test before). This skill runs the real GUI script invisibly instead.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .claude\skills\test-gui-headless\headless-test.ps1
```

How [headless-test.ps1](headless-test.ps1) works:
- It copies the core, GUI and `working-proxies.txt` to a temp folder, so the project's cache is not rewritten.
- It replaces `[void]$form.ShowDialog()` with a scenario script. If that line changes, the test fails loudly; update both together.
- It overrides `Set-SystemProxy` and `Restore-ProxySettings` with functions that throw, so **Use** and **Turn off** are exercised safely: they must show "Could not ..." in the status line.
- It fires button handlers through reflection (`OnClick`) and pumps `Application.DoEvents()` until `$script:Job` is `$null`.
- It prints the status labels and list rows after each scenario.

Scenarios: startup, re-test saved list, manual test (good and bad input), Use with no selection, Use selected (blocked), Turn off (blocked).

Check that the output has no unexpected `Error:` lines, that the list has Country/Speed/Exit IP filled after re-test, and that the final registry check says the proxy is unchanged. Free proxies are flaky, so 0 working is acceptable; exceptions are not.

To cover a new button or feature, add a scenario in the `$scenarios` here-string in the script.
