@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"
title Treinador TCG
rem Tudo fica dentro dos parenteses: o cmd le o bloco inteiro antes de rodar,
rem entao a atualizacao automatica pode trocar este arquivo sem atrapalhar.
rem Quem faz o trabalho e o programa\ferramentas\iniciar.ps1. Se ele falhar
rem de um jeito inesperado (codigo 1 ou 2), procura uma versao corrigida.
(
  if exist "%~dp0programa\ferramentas\iniciar.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0programa\ferramentas\iniciar.ps1"
    if errorlevel 1 if not errorlevel 3 (
      echo.
      echo   O Treinador TCG nao abriu direito. Vou procurar uma versao corrigida...
      powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0programa\ferramentas\atualizar.ps1" -Automatico
      if errorlevel 10 (
        powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0programa\ferramentas\iniciar.ps1" -JaAtualizou
      ) else (
        echo.
        pause
      )
    )
  ) else (
    echo.
    echo   A pasta "programa" nao esta aqui ao lado deste arquivo.
    echo   Extraia o ZIP inteiro ^(botao direito, Extrair Tudo^) e abra de novo.
    echo.
    pause
  )
  exit /b
)
