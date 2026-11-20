# Abre o Treinador TCG. Chamado pelo "INICIAR TREINADOR TCG.bat".
#  1) Arruma a pasta de versoes antigas, se precisar.
#  2) Baixa o Node.js na primeira vez (o atualizador usa o Node para conferir
#     a assinatura das versoes novas).
#  3) Confere se ha versao nova e instala sozinho (sem internet, abre a
#     versao que ja esta aqui e tenta de novo na proxima vez).
#  4) Abre o painel. Se o painel pedir (botao "Atualizar agora"), atualiza e
#     abre de novo, sem abrir outra aba no navegador. Se o painel avisar que
#     os arquivos foram alterados ou estao danificados (codigo 76), baixa de
#     novo a versao oficial e abre de novo.
# Codigos de saida: 0 = fechou normalmente; 3 = erro ja explicado na tela
# (com pausa). Qualquer outro (1, 2) e inesperado: o INICIAR .bat procura uma
# versao corrigida.
param([switch]$JaAtualizou)
$ProgressPreference = 'SilentlyContinue'

$ferramentas = $PSScriptRoot
$app = Split-Path -Parent $ferramentas
$topo = Split-Path -Parent $app
$desenvolvimento = (Test-Path -LiteralPath (Join-Path $topo '.git')) -or (Test-Path -LiteralPath (Join-Path $app '.git'))
# Codigo de saida do painel que quer dizer "atualize e me abra de novo".
$PEDIU_ATUALIZAR = 75
$ARQUIVOS_ALTERADOS = 76
$ERRO_AVISADO = 3

try { $Host.UI.RawUI.WindowTitle = 'Treinador TCG' } catch {}

# Espera a pessoa ler a mensagem (sem programa externo, para o aviso
# aparecer na hora).
function Esperar {
  Write-Host ''
  Write-Host '  Aperte qualquer tecla para fechar esta janela.'
  try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { $null = Read-Host }
}

# Roda outro script do PowerShell nesta mesma janela (sem capturar o que ele
# escreve) e devolve o codigo de saida dele.
function Rodar-Script($arquivo, $extras) {
  $argumentos = '-NoProfile -ExecutionPolicy Bypass -File "' + $arquivo + '"'
  if ($extras) { $argumentos = $argumentos + ' ' + $extras }
  try {
    $p = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $argumentos -NoNewWindow -PassThru
    $null = $p.Handle
    $p.WaitForExit()
    return [int]$p.ExitCode
  } catch {
    Write-Host ('  ' + $_.Exception.Message)
    return 1
  }
}

# Devolve $true se instalou uma versao nova.
function Atualizar-Agora {
  if ($desenvolvimento -or $env:TTCG_SEM_ATUALIZAR -eq '1') { return $false }
  $atualizador = Join-Path $ferramentas 'atualizar.ps1'
  if (-not (Test-Path -LiteralPath $atualizador)) { return $false }
  return ((Rodar-Script $atualizador '-Automatico') -eq 10)
}

# Roda o iniciar.ps1 novo (o que acabou de chegar) nesta mesma janela.
function Abrir-De-Novo {
  $codigo = Rodar-Script (Join-Path $ferramentas 'iniciar.ps1') '-JaAtualizou'
  exit $codigo
}

if (-not $JaAtualizou) {
  Write-Host ''
  Write-Host '  =================================================='
  Write-Host '    Treinador TCG'
  Write-Host '    Deixe esta janela aberta enquanto usar o painel.'
  Write-Host '    Pode minimizar. Fechar a janela encerra o programa.'
  Write-Host '  =================================================='
  Write-Host ''
}

if (-not (Test-Path -LiteralPath (Join-Path $app 'painel.mjs'))) {
  Write-Host '  A pasta "programa" esta incompleta. Extraia o ZIP inteiro de novo.'
  Esperar
  exit $ERRO_AVISADO
}

# Versoes ate a 1.1.x guardavam tudo solto na pasta de cima: arruma uma vez.
$legado = @('painel.mjs', 'dados', 'runtime', 'INICIAR-PAINEL.bat', 'VERSAO.txt') | Where-Object { Test-Path -LiteralPath (Join-Path $topo $_) }
if ($legado -and -not $desenvolvimento) {
  if ((Rodar-Script (Join-Path $ferramentas 'migrar.ps1') '') -ne 0) {
    Write-Host ''
    Write-Host '  Nao consegui arrumar a pasta da versao antiga. Veja a mensagem acima.'
    Esperar
    exit $ERRO_AVISADO
  }
}

if (-not $desenvolvimento) {
  # Pasta do programa oculta: na pasta de cima aparece so o INICIAR.
  try {
    $pasta = Get-Item -LiteralPath $app -Force
    $pasta.Attributes = $pasta.Attributes -bor [System.IO.FileAttributes]::Hidden
  } catch {}
  # O ATUALIZAR das versoes ate a 1.7.x nao e mais preciso: agora e automatico.
  $velho = Join-Path $topo 'ATUALIZAR.bat'
  if (Test-Path -LiteralPath $velho) { try { Remove-Item -LiteralPath $velho -Force } catch {} }
}

# Motor do programa: o Node.js baixado aqui ou o do computador (20 ou mais).
$node = Join-Path $app 'runtime\node\node.exe'
if (-not (Test-Path -LiteralPath $node)) {
  $node = $null
  $sistema = Get-Command node.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($sistema) {
    try {
      $v = [string](& $sistema.Path --version 2>$null)
      if ($v -match '^v(\d+)\.' -and [int]$Matches[1] -ge 20) { $node = $sistema.Path }
    } catch {}
  }
}
if (-not $node) {
  Write-Host '  Primeira vez neste computador: vou baixar o motor do programa, o Node.js.'
  Write-Host '  Leva de 1 a 3 minutos e so acontece uma vez. Nao feche esta janela.'
  Write-Host ''
  $instalou = Rodar-Script (Join-Path $ferramentas 'instalar-node.ps1') ''
  $baixado = Join-Path $app 'runtime\node\node.exe'
  if ($instalou -ne 0 -or -not (Test-Path -LiteralPath $baixado)) {
    Write-Host ''
    Write-Host '  Nao consegui baixar o Node.js automaticamente.'
    Write-Host '  Confira a internet e abra o INICIAR TREINADOR TCG de novo.'
    Write-Host '  Se continuar, instale o Node.js LTS pelo site nodejs.org'
    Write-Host '  e depois abra o INICIAR TREINADOR TCG de novo.'
    Esperar
    exit $ERRO_AVISADO
  }
  $node = $baixado
  Write-Host ''
}

if (-not $JaAtualizou) {
  if (Atualizar-Agora) { Abrir-De-Novo }
}

# O painel recusa abrir com estas variaveis (depuracao, codigo injetado,
# certificados de terceiros). Quem abre pelo INICIAR nunca e afetado.
foreach ($v in @('NODE_OPTIONS', 'NODE_EXTRA_CA_CERTS', 'NODE_TLS_REJECT_UNAUTHORIZED', 'NODE_DEBUG', 'NODE_V8_COVERAGE')) {
  Remove-Item -Path ('Env:' + $v) -ErrorAction SilentlyContinue
}

# Avisa o painel que ele pode pedir "atualize e me abra de novo".
# (O painel roda direto nesta janela, fora de funcao, para nada capturar a
# saida dele.)
$env:TTCG_LANCADOR = '1'
$painel = Join-Path $app 'painel.mjs'
$jaReparou = $false
while ($true) {
  & $node $painel
  $codigo = $LASTEXITCODE
  if ($codigo -eq $PEDIU_ATUALIZAR) {
    Write-Host ''
    Write-Host '  Atualizando o Treinador TCG. O painel volta sozinho em instantes.'
    # A aba do navegador que pediu a atualizacao recarrega sozinha.
    $env:TTCG_NAO_ABRIR = '1'
    if (Atualizar-Agora) { Abrir-De-Novo }
    continue
  }
  if ($codigo -eq $ARQUIVOS_ALTERADOS) {
    if (-not $jaReparou -and -not $desenvolvimento) {
      $jaReparou = $true
      Write-Host '  Vou baixar de novo a versao oficial do Treinador TCG...'
      if ((Rodar-Script (Join-Path $ferramentas 'atualizar.ps1') '-Automatico -Reparar') -eq 10) { Abrir-De-Novo }
    }
    Write-Host ''
    Write-Host '  Nao consegui reparar os arquivos agora. Conecte o computador a internet'
    Write-Host '  e abra de novo. Se continuar, baixe o Treinador TCG de novo e extraia'
    Write-Host '  por cima desta pasta (partidas e senhas continuam).'
    Esperar
    exit $ERRO_AVISADO
  }
  if ($codigo -ne 0) {
    Write-Host ''
    Write-Host '  O painel parou com um erro. Veja a mensagem acima.'
    Write-Host '  Os detalhes ficam no arquivo programa\dados\diagnostico.log.'
    Esperar
    exit $ERRO_AVISADO
  }
  exit 0
}
