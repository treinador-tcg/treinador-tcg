# Arruma a pasta das versoes ate a 1.1.x, que guardavam tudo solto ao lado
# dos atalhos, no formato novo: so "INICIAR TREINADOR TCG" e a pasta oculta
# "programa". Tambem apaga o "ATUALIZAR" das versoes ate a 1.7.x (agora o
# programa se atualiza sozinho quando abre). Os dados (partidas, senhas,
# chave) sao MOVIDOS para programa\dados, nunca apagados. So apaga arquivos
# do proprio programa, por nome, e nunca mexe numa copia de desenvolvimento
# (pasta com .git).
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

$app = Split-Path -Parent $PSScriptRoot
$topo = Split-Path -Parent $app
if ((Split-Path -Leaf $app) -ne 'programa' -or -not (Test-Path -LiteralPath (Join-Path $app 'painel.mjs'))) {
  Write-Host '  Pasta em formato inesperado; nada foi mexido.'
  exit 0
}
if (Test-Path -LiteralPath (Join-Path $topo '.git')) {
  Write-Host '  Copia de desenvolvimento (com .git); nada foi mexido.'
  exit 0
}

# O painel antigo nao pode estar aberto enquanto os dados mudam de lugar.
$aberto = $false
try {
  $c = New-Object System.Net.Sockets.TcpClient
  $c.Connect('127.0.0.1', 4610)
  $aberto = $c.Connected
  $c.Close()
} catch {}
if ($aberto) {
  Write-Host '  O painel antigo ainda esta aberto. Feche a janela preta dele e abra de novo.'
  exit 1
}

Write-Host '  Organizando a pasta do programa (so desta vez)...'
$carimbo = Get-Date -Format 'yyyyMMdd-HHmmss'

# 1) Dados e convite: movidos. Se ja houver um no lugar novo, o antigo fica
#    guardado ao lado, com a data no nome.
foreach ($nome in @('dados', 'convite.json')) {
  $de = Join-Path $topo $nome
  if (-not (Test-Path -LiteralPath $de)) { continue }
  $para = Join-Path $app $nome
  if (Test-Path -LiteralPath $para) { $para = Join-Path $app ($nome + '-antigo-' + $carimbo) }
  try {
    Move-Item -LiteralPath $de -Destination $para
  } catch {
    Write-Host ('  Nao consegui mover ' + $nome + ': ' + $_.Exception.Message)
    Write-Host '  Feche outros programas que estejam usando essa pasta e abra de novo.'
    exit 1
  }
}

# 2) Node.js baixado: movido (ou apagado, se o lugar novo ja tiver um).
$deRuntime = Join-Path $topo 'runtime'
if (Test-Path -LiteralPath $deRuntime) {
  $paraRuntime = Join-Path $app 'runtime'
  try {
    if (Test-Path -LiteralPath $paraRuntime) { Remove-Item -LiteralPath $deRuntime -Recurse -Force }
    else { Move-Item -LiteralPath $deRuntime -Destination $paraRuntime }
  } catch {}
}

# 3) Arquivos soltos da versao antiga: apagados, so os que sao do programa.
$arquivos = @('painel.mjs', 'painel.html', 'package.json', 'CHANGELOG.md', 'COMECE-AQUI.md', 'README.md', 'VERSAO.txt', 'CONECTAR-CLAUDE.bat', 'INICIAR-PAINEL.bat', 'ATUALIZAR.bat', '.gitattributes', '.gitignore')
$pastas = @('src', 'cartas', 'ferramentas', 'testes', 'versao-anterior', '.github')
$sobrou = @()
foreach ($nome in ($arquivos + $pastas)) {
  $alvo = Join-Path $topo $nome
  if (-not (Test-Path -LiteralPath $alvo)) { continue }
  try { Remove-Item -LiteralPath $alvo -Recurse -Force } catch { $sobrou += $nome }
}
# Testes que o atualizador antigo copiou para dentro do programa.
$testes = Join-Path $app 'testes'
if (Test-Path -LiteralPath $testes) { try { Remove-Item -LiteralPath $testes -Recurse -Force } catch {} }
if ($sobrou.Count -gt 0) {
  Write-Host ('  Nao consegui apagar: ' + ($sobrou -join ', ') + '. Tento de novo na proxima vez.')
}
Write-Host '  Pronto: agora aparece so o INICIAR TREINADOR TCG.'
Write-Host ''
exit 0
