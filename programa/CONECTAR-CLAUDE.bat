@echo off
setlocal EnableExtensions
cd /d "%~dp0"
title Conectar o plano do Claude
rem Instala o Claude Code (se faltar) e conecta a conta do Claude deste PC.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0ferramentas\conectar-claude.ps1"
if errorlevel 1 pause
