@echo off
setlocal EnableExtensions
chcp 65001 >nul
cd /d "%~dp0"
title Treinador TCG
set "APP=%~dp0programa"
echo.
echo   ==================================================
echo     Treinador TCG
echo     Deixe esta janela aberta enquanto usar o painel.
echo     Pode minimizar. Fechar a janela encerra o programa.
echo   ==================================================
echo.

if not exist "%APP%\painel.mjs" goto sem_programa

rem Versoes ate a 1.1.x guardavam tudo solto nesta pasta: arruma uma vez.
set "MIGRAR="
if exist "%~dp0painel.mjs" set "MIGRAR=1"
if exist "%~dp0dados\" set "MIGRAR=1"
if exist "%~dp0runtime\" set "MIGRAR=1"
if exist "%~dp0INICIAR-PAINEL.bat" set "MIGRAR=1"
if exist "%~dp0VERSAO.txt" set "MIGRAR=1"
if not defined MIGRAR goto esconder
powershell -NoProfile -ExecutionPolicy Bypass -File "%APP%\ferramentas\migrar.ps1"
if errorlevel 1 goto parou_migrar

:esconder
rem Deixa a pasta do programa oculta: aparecem so os dois atalhos.
attrib +h "%APP%" >nul 2>nul

set "NODE_EXE="
if exist "%APP%\runtime\node\node.exe" set "NODE_EXE=%APP%\runtime\node\node.exe"
if defined NODE_EXE goto iniciar

where node >nul 2>nul
if errorlevel 1 goto baixar
node -e "process.exit(Number(process.versions.node.split('.')[0])>=20?0:1)" >nul 2>nul
if errorlevel 1 goto baixar
set "NODE_EXE=node"
goto iniciar

:baixar
echo   Primeira vez neste computador: vou baixar o motor do programa, o Node.js.
echo   Leva de 1 a 3 minutos e so acontece uma vez. Nao feche esta janela.
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%APP%\ferramentas\instalar-node.ps1"
if errorlevel 1 goto falhou_node
if not exist "%APP%\runtime\node\node.exe" goto falhou_node
set "NODE_EXE=%APP%\runtime\node\node.exe"
echo.

:iniciar
"%NODE_EXE%" "%APP%\painel.mjs"
if errorlevel 1 goto parou
goto fim

:sem_programa
echo   A pasta "programa" nao esta aqui ao lado deste arquivo.
echo   Extraia o ZIP inteiro (botao direito, Extrair Tudo) e abra de novo.
echo.
pause
goto fim

:parou_migrar
echo.
echo   Nao consegui arrumar a pasta da versao antiga. Veja a mensagem acima.
echo.
pause
goto fim

:falhou_node
echo.
echo   Nao consegui baixar o Node.js automaticamente.
echo   Confira a internet e abra este arquivo de novo.
echo   Se continuar, instale o Node.js LTS pelo site nodejs.org
echo   e depois abra este arquivo de novo.
echo.
pause
goto fim

:parou
echo.
echo   O painel parou com um erro. Veja a mensagem acima.
echo   Os detalhes ficam no arquivo programa\dados\diagnostico.log.
echo.
pause

:fim
endlocal
