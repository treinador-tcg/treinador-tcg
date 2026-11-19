# Atualiza o Treinador TCG a partir do GitHub.
# Troca so os dois atalhos e a pasta programa. Nunca mexe em programa\dados
# (partidas, senhas, chave), programa\runtime (Node baixado) nem no convite.
# Guarda a versao atual em programa\versao-anterior.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

$app = Split-Path -Parent $PSScriptRoot
$topo = Split-Path -Parent $app
$preservar = @('dados', 'runtime', 'versao-anterior', 'convite.json', 'testes', 'node_modules', '.git')
$atalhos = @('INICIAR TREINADOR TCG.bat', 'ATUALIZAR.bat')

function Ler-Texto($resposta) {
  $c = $resposta.Content
  if ($c -is [byte[]]) { $c = [System.Text.Encoding]::UTF8.GetString($c) }
  return [string]$c
}

function Copiar-Arvore($de, $para) {
  Get-ChildItem -LiteralPath $de -Recurse -File -Force | ForEach-Object {
    $rel = $_.FullName.Substring($de.Length).TrimStart('\', '/')
    $primeiro = ($rel -split '[\\/]')[0]
    if ($preservar -contains $primeiro) { return }
    $alvo = Join-Path $para $rel
    $pasta = Split-Path -Parent $alvo
    if (-not (Test-Path -LiteralPath $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
    Copy-Item -LiteralPath $_.FullName -Destination $alvo -Force
  }
}

try {
  $repo = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'repositorio.txt') -Raw).Trim()
  $local = '0'
  $arqVersao = Join-Path $app 'VERSAO.txt'
  if (Test-Path -LiteralPath $arqVersao) { $local = (Get-Content -LiteralPath $arqVersao -Raw).Trim() }

  $aberto = $false
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $c.Connect('127.0.0.1', 4610)
    $aberto = $c.Connected
    $c.Close()
  } catch {}
  if ($aberto) {
    Write-Host '  O Treinador esta aberto. Feche a janela preta dele e rode o ATUALIZAR de novo.'
    exit 1
  }

  Write-Host '  Procurando versao nova...'
  $remota = (Ler-Texto (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$repo/main/programa/VERSAO.txt" -UseBasicParsing -Headers @{ 'Cache-Control' = 'no-cache' })).Trim()
  if ($remota -eq $local) {
    Write-Host "  Voce ja esta na versao mais nova ($local)."
    exit 0
  }
  Write-Host "  Atualizando da versao $local para $remota ..."

  $tmp = Join-Path $env:TEMP ('ttcg-' + [guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $tmp | Out-Null
  $zip = Join-Path $tmp 'novo.zip'
  Invoke-WebRequest -Uri "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing
  $extraido = Join-Path $tmp 'x'
  Expand-Archive -Path $zip -DestinationPath $extraido -Force
  $novo = Get-ChildItem -LiteralPath $extraido -Directory | Select-Object -First 1
  $novoApp = if ($novo) { Join-Path $novo.FullName 'programa' } else { $null }
  if (-not $novoApp -or -not (Test-Path -LiteralPath (Join-Path $novoApp 'painel.mjs'))) {
    throw 'O pacote baixado veio incompleto.'
  }

  $backup = Join-Path $app 'versao-anterior'
  if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
  New-Item -ItemType Directory -Path $backup | Out-Null
  Copiar-Arvore $app $backup
  Copiar-Arvore $novoApp $app
  foreach ($a in $atalhos) {
    $origem = Join-Path $novo.FullName $a
    if (Test-Path -LiteralPath $origem) { Copy-Item -LiteralPath $origem -Destination (Join-Path $topo $a) -Force }
  }
  Remove-Item -LiteralPath $tmp -Recurse -Force

  # Arruma restos de versoes antigas, se houver.
  & (Join-Path $PSScriptRoot 'migrar.ps1') | Out-Null
  try { (Get-Item -LiteralPath $app -Force).Attributes = 'Directory, Hidden' } catch {}

  Write-Host "  Pronto! Versao $remota instalada. Partidas, senhas e chave continuam iguais."
  Write-Host '  Agora abra de novo pelo INICIAR TREINADOR TCG.'
  exit 0
} catch {
  if ($_.Exception.Message -match '404') {
    Write-Host "  Ainda nao ha versao publicada em github.com/$repo."
  } else {
    Write-Host ('  Nao consegui atualizar: ' + $_.Exception.Message)
  }
  Write-Host '  Seus dados nao foram alterados.'
  exit 1
}
