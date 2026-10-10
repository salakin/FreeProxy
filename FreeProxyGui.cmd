@echo off
rem Double-click to open the FreeProxy window.
start "" powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0FreeProxyGui.ps1"
