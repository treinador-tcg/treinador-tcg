# Atualiza o Treinador TCG a partir do GitHub.
# Roda sozinho toda vez que o programa abre (iniciar.ps1 chama com
# -Automatico); sem -Automatico, e o modo manual, com mais mensagens.
# Troca so o atalho INICIAR e a pasta programa. Nunca mexe em programa\dados
# (partidas, senhas, chave), programa\runtime (Node baixado) nem no convite.
# Guarda a versao atual em programa\versao-anterior e volta para ela se a
# copia der errado no meio.
# Antes de instalar, o painel instalado confere o pacote baixado: o
# MANIFESTO.json dele tem de ser o que o servidor de licencas confirma para
# aquela versao (resposta assinada), e cada arquivo tem de bater com o
# manifesto. Pacote que nao e oficial ou veio alterado nao entra. -Reparar baixa de novo a versao publicada mesmo se for a mesma
# (arquivos alterados ou danificados).
# Codigos de saida: 10 = instalou (so no -Automatico);
# 0 = nada a fazer ou sem internet; 1 = erro (so no modo manual).
param([switch]$Automatico, [switch]$Reparar)
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
    if ($rel -like '*.antigo') { return }
    $alvo = Join-Path $para $rel
    $pasta = Split-Path -Parent $alvo
    if (-not (Test-Path -LiteralPath $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
    Copiar-Arquivo $_.FullName $alvo
  }
}

# Um .exe em uso (o atalho "Treinador TCG.exe" fica aberto enquanto o
# programa roda) nao pode ser sobrescrito, mas pode ser renomeado: o antigo
# vira "*.antigo" (o iniciar.ps1 apaga na proxima abertura) e o novo entra.
function Copiar-Arquivo($origem, $alvo) {
  # Igual ao que ja esta aqui: nao mexe (um arquivo em uso igual nao trava nada).
  try { if (Iguais $origem $alvo) { return } } catch {}
  try {
    Copy-Item -LiteralPath $origem -Destination $alvo -Force -ErrorAction Stop
  } catch {
    if (-not ($alvo -like '*.exe') -or -not (Test-Path -LiteralPath $alvo)) { throw }
    $velho = $alvo + '.' + [guid]::NewGuid().ToString('N') + '.antigo'
    Move-Item -LiteralPath $alvo -Destination $velho -Force -ErrorAction Stop
    Copy-Item -LiteralPath $origem -Destination $alvo -Force -ErrorAction Stop
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

# Node para a conferencia: o baixado pelo INICIAR ou o do computador.
function Achar-Node {
  $n = Join-Path $app 'runtime\node\node.exe'
  if (Test-Path -LiteralPath $n) { return $n }
  $s = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($s) { return $s.Path }
  return $null
}

# Roda "painel.mjs --verificar-pacote <pasta>" com o painel indicado e devolve
# o codigo: 0 = oficial e inteiro; 3 = recusado; 4 = sem conexao com o
# servidor de licencas; outro = nao conseguiu conferir.
function Conferir-Pacote($painel, $pastaNova) {
  $node = Achar-Node
  if (-not $node -or -not (Test-Path -LiteralPath $painel)) { return -1 }
  foreach ($v in @('NODE_OPTIONS', 'NODE_EXTRA_CA_CERTS', 'NODE_TLS_REJECT_UNAUTHORIZED', 'NODE_DEBUG', 'NODE_V8_COVERAGE')) {
    Remove-Item -Path ('Env:' + $v) -ErrorAction SilentlyContinue
  }
  $argumentos = '"' + $painel + '" --verificar-pacote "' + $pastaNova + '"'
  try {
    $p = Start-Process -FilePath $node -ArgumentList $argumentos -NoNewWindow -PassThru
    $null = $p.Handle
    if (-not $p.WaitForExit(120000)) {
      try { $p.Kill() } catch {}
      return -1
    }
    return [int]$p.ExitCode
  } catch {
    return -1
  }
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
if ($Reparar) {
  if (Mais-Nova $local $remota) { Sair-Sem-Mudar "  A versao publicada ($remota) e mais velha que a instalada ($local); nada foi mexido." }
  Write-Host "  Baixando de novo a versao oficial $remota para reparar os arquivos..."
} else {
  if (-not (Mais-Nova $remota $local)) {
    Write-Host "  Voce ja esta na versao mais nova ($local)."
    exit 0
  }
  Write-Host "  Versao nova encontrada: $remota. Atualizando (leva poucos segundos)..."
}
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
  if (-not $Reparar -and -not (Mais-Nova $baixada $local)) {
    # O GitHub ainda estava entregando o pacote anterior; fica para a proxima.
    Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "  Voce ja esta na versao mais nova ($local)."
    exit 0
  }

  # So entra pacote oficial e inteiro. Quem confere e o painel instalado
  # (perguntando ao servidor de licencas). No reparo, se o painel instalado
  # estiver danificado demais para conferir, o proprio pacote baixado confere
  # (tambem perguntando ao servidor).
  $conferencia = Conferir-Pacote (Join-Path $app 'painel.mjs') $novoApp
  if ($Reparar -and $conferencia -ne 0 -and $conferencia -ne 3) {
    $conferencia = Conferir-Pacote (Join-Path $novoApp 'painel.mjs') $novoApp
  }
  if ($conferencia -ne 0) {
    if ($conferencia -eq 4) { throw 'sem conexao com o servidor de licencas para conferir o pacote' }
    throw 'o pacote baixado nao passou na conferencia (nao e o oficial ou veio danificado)'
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
