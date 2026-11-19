@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Conectar a conta do ChatGPT
rem Instala o Codex (se faltar) e conecta a conta do ChatGPT deste PC.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ferramentas\conectar-chatgpt.ps1"
if errorlevel 1 pause
