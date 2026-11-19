@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"
title Atualizar o Treinador TCG
rem O bloco entre parenteses e lido inteiro antes de rodar: assim a
rem atualizacao pode trocar este proprio arquivo sem atrapalhar.
(
  echo.
  if exist "%~dp0programa\ferramentas\atualizar.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0programa\ferramentas\atualizar.ps1"
  ) else (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0ferramentas\atualizar.ps1"
  )
  echo.
  pause
  exit /b
)
