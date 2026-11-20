# Atualiza o Treinador TCG a partir do GitHub.
# Roda sozinho toda vez que o programa abre (iniciar.ps1 chama com
# -Automatico); sem -Automatico, e o modo manual, com mais mensagens.
# Troca so o atalho INICIAR e a pasta programa. Nunca mexe em programa\dados
# (partidas, senhas, chave), programa\runtime (Node baixado) nem no convite.
# Guarda a versao atual em programa\versao-anterior e volta para ela se a
# copia der errado no meio.
# Codigos de saida: 10 = instalou versao nova (so no -Automatico);
# 0 = nada a fazer ou sem internet; 1 = erro (so no modo manual).
param([switch]$Automatico)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

$app = Split-Path -Parent $PSScriptRoot
$topo = Split-Path -Parent $app
$preservar = @('dados', 'runtime', 'versao-anterior', 'convite.json', 'licenca.txt', 'testes', 'node_modules', '.git')
$atalhos = @('INICIAR TREINADOR TCG.bat')
$INSTALOU = 10

function Ler-Texto($resposta) {
  $c = $resposta.Content
  if ($c -is [byte[]]) { $c = [System.Text.Encoding]::UTF8.GetString($c) }
  return ([string]$c).Trim([char]0xFEFF).Trim()
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

# A versao $a e mais nova que a $b? (1.10.0 e mais nova que 1.9.3)
function Mais-Nova($a, $b) {
  try { return ([version]$a) -gt ([version]$b) } catch { return ($a -ne $b) }
}

# Mesmo conteudo? (o atalho so e trocado se mudou)
function Iguais($x, $y) {
  if (-not (Test-Path -LiteralPath $y)) { return $false }
  $bx = [System.IO.File]::ReadAllBytes($x)
  $by = [System.IO.File]::ReadAllBytes($y)
  if ($bx.Length -ne $by.Length) { return $false }
  for ($i = 0; $i -lt $bx.Length; $i++) { if ($bx[$i] -ne $by[$i]) { return $false } }
  return $true
}

function Sair-Sem-Mudar($texto) {
  if ($texto) { Write-Host $texto }
  if ($Automatico) { exit 0 }
  Write-Host '  Seus dados nao foram alterados.'
  exit 1
}

if ((Test-Path -LiteralPath (Join-Path $topo '.git')) -or (Test-Path -LiteralPath (Join-Path $app '.git'))) {
  Write-Host '  Copia de desenvolvimento (com .git): nada a atualizar.'
  exit 0
}

$repo = (Get-Content -LiteralPath (Join-Path $PSScriptRoot 'repositorio.txt') -Raw).Trim([char]0xFEFF).Trim()
$local = '0'
$arqVersao = Join-Path $app 'VERSAO.txt'
if (Test-Path -LiteralPath $arqVersao) { $local = (Get-Content -LiteralPath $arqVersao -Raw).Trim([char]0xFEFF).Trim() }

# Com o painel aberto, os arquivos estao em uso.
$aberto = $false
try {
  $c = New-Object System.Net.Sockets.TcpClient
  $c.Connect('127.0.0.1', 4610)
  $aberto = $c.Connected
  $c.Close()
} catch {}
if ($aberto) {
  if ($Automatico) { exit 0 }
  Write-Host '  O Treinador esta aberto. Feche a janela preta dele e rode de novo.'
  exit 1
}

Write-Host '  Procurando versao nova...'
try {
  $espera = 30
  if ($Automatico) { $espera = 10 }
  $remota = Ler-Texto (Invoke-WebRequest -Uri "https://raw.githubusercontent.com/$repo/main/programa/VERSAO.txt" -UseBasicParsing -TimeoutSec $espera -Headers @{ 'Cache-Control' = 'no-cache' })
} catch {
  if ($_.Exception.Message -match '404') { Sair-Sem-Mudar "  Ainda nao ha versao publicada em github.com/$repo." }
  if ($Automatico) { Sair-Sem-Mudar "  Sem conexao com a internet agora: abrindo a versao $local, que ja esta aqui." }
  Sair-Sem-Mudar ('  Nao consegui procurar a versao nova (sem internet?): ' + $_.Exception.Message)
}
if (-not (Mais-Nova $remota $local)) {
  Write-Host "  Voce ja esta na versao mais nova ($local)."
  exit 0
}

Write-Host "  Versao nova encontrada: $remota. Atualizando (leva poucos segundos)..."
$tmp = Join-Path $env:TEMP ('ttcg-' + [guid]::NewGuid().ToString('N'))
try {
  New-Item -ItemType Directory -Path $tmp | Out-Null
  $zip = Join-Path $tmp 'novo.zip'
  Invoke-WebRequest -Uri "https://github.com/$repo/archive/refs/heads/main.zip" -OutFile $zip -UseBasicParsing -TimeoutSec 300
  $extraido = Join-Path $tmp 'x'
  Expand-Archive -Path $zip -DestinationPath $extraido -Force
  $novo = Get-ChildItem -LiteralPath $extraido -Directory | Select-Object -First 1
  $novoApp = $null
  if ($novo) { $novoApp = Join-Path $novo.FullName 'programa' }
  if (-not $novoApp -or -not (Test-Path -LiteralPath (Join-Path $novoApp 'painel.mjs')) -or -not (Test-Path -LiteralPath (Join-Path $novoApp 'VERSAO.txt'))) {
    throw 'o pacote baixado veio incompleto'
  }
  $baixada = (Get-Content -LiteralPath (Join-Path $novoApp 'VERSAO.txt') -Raw).Trim([char]0xFEFF).Trim()
  if (-not (Mais-Nova $baixada $local)) {
    # O GitHub ainda estava entregando o pacote anterior; fica para a proxima.
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Voce ja esta na versao mais nova ($local)."
    exit 0
  }

  $backup = Join-Path $app 'versao-anterior'
  if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup -Recurse -Force }
  New-Item -ItemType Directory -Path $backup | Out-Null
  Copiar-Arvore $app $backup
  try {
    Copiar-Arvore $novoApp $app
  } catch {
    $motivo = $_.Exception.Message
    try { Copiar-Arvore $backup $app } catch {}
    throw ('nao consegui copiar os arquivos novos (' + $motivo + ')')
  }
  foreach ($a in $atalhos) {
    $origem = Join-Path $novo.FullName $a
    $destino = Join-Path $topo $a
    if ((Test-Path -LiteralPath $origem) -and -not (Iguais $origem $destino)) {
      try { Copy-Item -LiteralPath $origem -Destination $destino -Force } catch {}
    }
  }
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
} catch {
  Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
  if ($Automatico) {
    Sair-Sem-Mudar ('  Nao consegui atualizar agora (' + $_.Exception.Message + '). Abrindo a versao ' + $local + '; tento de novo na proxima vez.')
  }
  Sair-Sem-Mudar ('  Nao consegui atualizar: ' + $_.Exception.Message)
}

# Arruma restos de versoes antigas (inclusive o ATUALIZAR, que nao e mais preciso).
try { & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'migrar.ps1') | Out-Null } catch {}
try { (Get-Item -LiteralPath $app -Force).Attributes = 'Directory, Hidden' } catch {}

Write-Host "  Pronto! Versao $baixada instalada. Partidas, senhas e licenca continuam iguais."
if ($Automatico) { exit $INSTALOU }
Write-Host '  Agora abra de novo pelo INICIAR TREINADOR TCG.'
exit 0
