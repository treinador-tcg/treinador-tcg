# Abre o Treinador TCG. Chamado de dois jeitos:
#  - pelo atalho "Treinador TCG" (programa\Treinador TCG.exe, que o instalador
#    poe na Area de Trabalho e no menu Iniciar), com -Bandeja: sem janela
#    preta. O programa fica num icone ao lado do relogio, os avisos aparecem
#    em caixas de mensagem e o painel abre numa janela propria. -SemJanela
#    (quando abre junto com o Windows) nao abre o painel, so o icone.
#  - pelo "INICIAR TREINADOR TCG.bat" (pacote ZIP): janela preta, como antes.
# Passos:
#  1) Arruma a pasta de versoes antigas, se precisar.
#  2) Baixa o Node.js na primeira vez (o atualizador usa o Node para conferir
#     a assinatura das versoes novas).
#  3) Confere se ha versao nova e instala sozinho (sem internet, abre a
#     versao que ja esta aqui e tenta de novo na proxima vez).
#  4) Abre o painel. Se o painel pedir (botao "Atualizar agora"), atualiza e
#     abre de novo, sem abrir outra janela. Se o painel avisar que os arquivos
#     foram alterados ou estao danificados (codigo 76), baixa de novo a versao
#     oficial e abre de novo.
# Codigos de saida: 0 = fechou normalmente; 3 = erro ja explicado (com pausa
# ou caixa de mensagem). Qualquer outro (1, 2) e inesperado: quem chamou (o
# INICIAR .bat ou o Treinador TCG.exe) procura uma versao corrigida.
param([switch]$JaAtualizou, [switch]$Bandeja, [switch]$SemJanela)
$ProgressPreference = 'SilentlyContinue'

$ferramentas = $PSScriptRoot
$app = Split-Path -Parent $ferramentas
$topo = Split-Path -Parent $app
$desenvolvimento = (Test-Path -LiteralPath (Join-Path $topo '.git')) -or (Test-Path -LiteralPath (Join-Path $app '.git'))
# Codigo de saida do painel que quer dizer "atualize e me abra de novo".
$PEDIU_ATUALIZAR = 75
$ARQUIVOS_ALTERADOS = 76
$ERRO_AVISADO = 3
$PORTA = 4610
if ($env:TTCG_PORTA) { $PORTA = $env:TTCG_PORTA }
$lancador = Join-Path $app 'Treinador TCG.exe'
$CHAVE_LIGAR = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
$NOME_LIGAR = 'Treinador TCG'
$CHAVE_INSTALADOR = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\TreinadorTCG'

try { $Host.UI.RawUI.WindowTitle = 'Treinador TCG' } catch {}

# Texto com acentos: o arquivo fica so com ASCII (o PowerShell 5.1 le errado
# sem BOM), entao os acentos vao escritos como \u00e3 (a com til) etc.
function T([string]$s) { return [regex]::Unescape($s) }

# ---- Icone ao lado do relogio (so com -Bandeja) ----------------------------
$script:icone = $null
$script:menu = $null
$script:itemLigar = $null
$script:mutex = $null
$script:painelProc = $null
$script:sair = $false
$script:inicioPainel = Get-Date

function Preparar-Bandeja {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  [System.Windows.Forms.Application]::EnableVisualStyles()
  # Um Treinador so por vez: se ja esta aberto, so mostra a janela dele.
  $criado = $false
  $script:mutex = New-Object System.Threading.Mutex($true, 'Local\TreinadorTCG-Bandeja', [ref]$criado)
  if (-not $criado) {
    $script:mutex.Dispose()
    $script:mutex = $null
    if (-not $SemJanela) { Abrir-Janela '' }
    exit 0
  }
  $script:icone = New-Object System.Windows.Forms.NotifyIcon
  try {
    $script:icone.Icon = New-Object System.Drawing.Icon((Join-Path $ferramentas 'treinador.ico'), [System.Windows.Forms.SystemInformation]::SmallIconSize)
  } catch {
    $script:icone.Icon = [System.Drawing.SystemIcons]::Application
  }
  Mostrar-Estado 'abrindo...'
  $script:icone.add_MouseDoubleClick({ if ($script:menu -and $script:icone.ContextMenuStrip) { Abrir-Janela '' } })
  $script:icone.add_BalloonTipClicked({ if ($script:icone.ContextMenuStrip) { Abrir-Janela '' } })

  $m = New-Object System.Windows.Forms.ContextMenuStrip
  $abrir = New-Object System.Windows.Forms.ToolStripMenuItem((T 'Abrir o Treinador TCG'))
  $abrir.Font = New-Object System.Drawing.Font($abrir.Font, [System.Drawing.FontStyle]::Bold)
  $abrir.add_Click({ Abrir-Janela '' })
  [void]$m.Items.Add($abrir)
  $procurar = New-Object System.Windows.Forms.ToolStripMenuItem((T 'Procurar vers\u00e3o nova'))
  $procurar.add_Click({ Abrir-Janela '#/ajuda/procurar' })
  [void]$m.Items.Add($procurar)
  if (Test-Path -LiteralPath $lancador) {
    [void]$m.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
    $ligar = New-Object System.Windows.Forms.ToolStripMenuItem((T 'Abrir junto com o Windows'))
    $ligar.Checked = Liga-Com-Windows
    $script:itemLigar = $ligar
    # Vale o que esta no registro (a pessoa pode ter mudado nas configuracoes
    # do Windows): o clique inverte o estado real e a marquinha acompanha.
    $ligar.add_Click({
      Mudar-Ligar (-not (Liga-Com-Windows))
      $script:itemLigar.Checked = Liga-Com-Windows
    })
    $m.add_Opening({ if ($script:itemLigar) { $script:itemLigar.Checked = Liga-Com-Windows } })
    [void]$m.Items.Add($ligar)
  }
  [void]$m.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator))
  $sairItem = New-Object System.Windows.Forms.ToolStripMenuItem('Sair')
  $sairItem.add_Click({ Pedir-Para-Sair })
  [void]$m.Items.Add($sairItem)
  $script:menu = $m
  $script:icone.Visible = $true
}

# Dica que aparece ao passar o mouse no icone (o Windows aceita ate 63 letras).
function Mostrar-Estado($texto) {
  if (-not $script:icone) { return }
  $t = 'Treinador TCG'
  if ($texto) { $t = $t + ': ' + (T $texto) }
  if ($t.Length -gt 63) { $t = $t.Substring(0, 63) }
  $script:icone.Text = $t
}

function Avisar-Balao($texto) {
  if (-not $script:icone) { return }
  try { $script:icone.ShowBalloonTip(10000, 'Treinador TCG', (T $texto), [System.Windows.Forms.ToolTipIcon]::Info) } catch {}
}

# Caixa de mensagem na frente das outras janelas (o programa nao tem janela).
function Caixa($texto, $botoes, $simbolo) {
  $dono = New-Object System.Windows.Forms.Form
  $dono.TopMost = $true
  try {
    return [System.Windows.Forms.MessageBox]::Show($dono, $texto, 'Treinador TCG', $botoes, $simbolo)
  } finally {
    $dono.Dispose()
  }
}

function Fechar-Bandeja {
  if ($script:icone) {
    $script:icone.Visible = $false
    $script:icone.Dispose()
    $script:icone = $null
  }
  if ($script:mutex) {
    try { $script:mutex.ReleaseMutex() } catch {}
    $script:mutex.Dispose()
    $script:mutex = $null
  }
}

function Liga-Com-Windows {
  try {
    $v = (Get-ItemProperty -Path $CHAVE_LIGAR -Name $NOME_LIGAR -ErrorAction Stop).$NOME_LIGAR
    return [bool]$v
  } catch {
    return $false
  }
}

function Mudar-Ligar($ligar) {
  try {
    if ($ligar) {
      # Num usuario novo a chave Run pode nao existir ainda.
      if (-not (Test-Path -LiteralPath $CHAVE_LIGAR)) { New-Item -Path $CHAVE_LIGAR -Force -ErrorAction Stop | Out-Null }
      New-ItemProperty -Path $CHAVE_LIGAR -Name $NOME_LIGAR -Value ('"' + $lancador + '" --ao-ligar') -PropertyType String -Force -ErrorAction Stop | Out-Null
    } else {
      Remove-ItemProperty -Path $CHAVE_LIGAR -Name $NOME_LIGAR -ErrorAction SilentlyContinue
    }
  } catch {
    Registrar-Erro ('Abrir junto com o Windows: ' + $_.Exception.Message)
    Avisar-Balao 'N\u00e3o consegui mudar o "Abrir junto com o Windows" agora. Tente de novo pelo menu do \u00edcone.'
  }
}

# Mesma forma das linhas do painel no diagnostico.log (UTF-8 sem BOM).
function Registrar-Erro($texto) {
  try {
    $pasta = Join-Path $app 'dados'
    if (-not (Test-Path -LiteralPath $pasta)) { New-Item -ItemType Directory -Path $pasta -Force | Out-Null }
    $linha = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffZ') + ' [erro] ' + $texto + "`n"
    [System.IO.File]::AppendAllText((Join-Path $pasta 'diagnostico.log'), $linha, (New-Object System.Text.UTF8Encoding($false)))
  } catch {}
}

# Painel numa janela propria (modo aplicativo do Edge, que vem com o
# Windows): sem barra de endereco nem abas. Sem o Edge, o navegador padrao.
function Achar-Edge {
  $c = @()
  if (${env:ProgramFiles(x86)}) { $c += (Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe') }
  if ($env:ProgramFiles) { $c += (Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe') }
  if ($env:LOCALAPPDATA) { $c += (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\Application\msedge.exe') }
  foreach ($x in $c) { if (Test-Path -LiteralPath $x) { return $x } }
  return $null
}

function Abrir-Janela($ancora) {
  $url = 'http://127.0.0.1:' + $PORTA + '/' + $ancora
  $edge = Achar-Edge
  try {
    if ($edge) {
      Start-Process -FilePath $edge -ArgumentList @(('--app=' + $url), '--no-first-run', '--no-default-browser-check')
    } else {
      Start-Process $url
    }
  } catch {
    try { Start-Process $url } catch {}
  }
}

function Pedir-Para-Sair {
  $r = Caixa (T 'Fechar o Treinador TCG?\r\n\r\nEle para de acompanhar as suas partidas at\u00e9 voc\u00ea abrir de novo pelo atalho Treinador TCG.') 'YesNo' 'Question'
  if ($r -ne 'Yes') { return }
  $script:sair = $true
  Parar-Painel
}

# Fecha o painel e o que ele abriu (uma analise no meio, por exemplo).
function Parar-Painel {
  $p = $script:painelProc
  if (-not $p -or $p.HasExited) { return }
  try { & taskkill.exe /PID $p.Id /T /F *> $null } catch {}
  try { if (-not $p.HasExited) { $p.Kill() } } catch {}
}

# Ultimo erro que o painel registrou nesta abertura (para a caixa de aviso).
function Ultimo-Erro {
  try {
    $linhas = Get-Content -LiteralPath (Join-Path $app 'dados\diagnostico.log') -Tail 60 -Encoding UTF8 -ErrorAction Stop
    $erro = $linhas | Where-Object { $_ -match '^\S+ \[erro\] ' } | Select-Object -Last 1
    if ($erro -and $erro -match '^(\S+) \[erro\] (.*)$') {
      $quando = [datetime]::Parse($Matches[1])
      if ($quando -ge $script:inicioPainel.AddSeconds(-5)) { return $Matches[2] }
    }
  } catch {}
  return $null
}

# Roda o painel escondido e fica com o icone ate ele fechar. Devolve o codigo
# de saida dele (0 se a pessoa pediu Sair).
function Rodar-Painel-Na-Bandeja {
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $node
  $psi.Arguments = '"' + $painel + '"'
  $psi.WorkingDirectory = $app
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $script:sair = $false
  $script:inicioPainel = Get-Date
  $script:painelProc = [System.Diagnostics.Process]::Start($psi)
  Mostrar-Estado 'acompanhando as partidas'
  $script:icone.ContextMenuStrip = $script:menu
  $script:contexto = New-Object System.Windows.Forms.ApplicationContext
  $relogio = New-Object System.Windows.Forms.Timer
  $relogio.Interval = 500
  $relogio.add_Tick({
    if ($script:painelProc.HasExited) {
      $this.Stop()
      $script:contexto.ExitThread()
    }
  })
  $relogio.Start()
  [System.Windows.Forms.Application]::Run($script:contexto)
  $relogio.Dispose()
  $script:icone.ContextMenuStrip = $null
  $script:painelProc.WaitForExit()
  if ($script:sair) { return 0 }
  return [int]$script:painelProc.ExitCode
}

# A versao que aparece em "Aplicativos instalados" acompanha as atualizacoes.
function Anotar-Versao-Instalada {
  try {
    if (-not (Test-Path -LiteralPath $CHAVE_INSTALADOR)) { return }
    $v = (Get-Content -LiteralPath (Join-Path $app 'VERSAO.txt') -Raw).Trim([char]0xFEFF).Trim()
    Set-ItemProperty -Path $CHAVE_INSTALADOR -Name 'DisplayVersion' -Value $v
    # Abrir junto com o Windows: aponta para o lugar atual do atalho.
    if (Liga-Com-Windows) { Mudar-Ligar $true }
  } catch {}
}

# Na primeira vez, explica onde o Treinador fica.
function Apresentar-Bandeja {
  $marca = Join-Path $app 'dados\bandeja-apresentada.txt'
  if (Test-Path -LiteralPath $marca) { return }
  Avisar-Balao 'O Treinador TCG fica aqui, ao lado do rel\u00f3gio (\u00e0s vezes dentro da setinha ^). Pode fechar a janela: ele continua acompanhando as partidas. Para fechar de vez: bot\u00e3o direito no \u00edcone > Sair.'
  try {
    New-Item -ItemType Directory -Path (Join-Path $app 'dados') -Force | Out-Null
    Set-Content -LiteralPath $marca -Value (Get-Date -Format s)
  } catch {}
}

# ---- Comum aos dois jeitos ---------------------------------------------------

# Espera a pessoa ler a mensagem (sem programa externo, para o aviso
# aparecer na hora).
function Esperar {
  Write-Host ''
  Write-Host '  Aperte qualquer tecla para fechar esta janela.'
  try { $null = $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown') } catch { $null = Read-Host }
}

# Erro ja explicado: na janela preta (com pausa) ou numa caixa de mensagem.
function Falhar($linhas) {
  $textos = @($linhas | ForEach-Object { T $_ })
  if ($Bandeja) {
    try { [void](Caixa ($textos -join "`r`n`r`n") 'OK' 'Warning') } catch {}
    Fechar-Bandeja
  } else {
    Write-Host ''
    foreach ($l in $textos) { Write-Host ('  ' + $l) }
    Esperar
  }
  exit $ERRO_AVISADO
}

# Roda outro script do PowerShell nesta mesma janela (sem capturar o que ele
# escreve) e devolve o codigo de saida dele. Com o icone, mantem o icone
# respondendo e, se demorar, avisa num balao.
function Rodar-Script($arquivo, $extras, $avisoSeDemorar) {
  $argumentos = '-NoProfile -ExecutionPolicy Bypass -File "' + $arquivo + '"'
  if ($extras) { $argumentos = $argumentos + ' ' + $extras }
  try {
    $p = Start-Process -FilePath (Join-Path $PSHOME 'powershell.exe') -ArgumentList $argumentos -NoNewWindow -PassThru
    $null = $p.Handle
    $inicio = Get-Date
    $avisou = $false
    while (-not $p.WaitForExit(100)) {
      if ($script:icone) {
        [System.Windows.Forms.Application]::DoEvents()
        if ($avisoSeDemorar -and -not $avisou -and ((Get-Date) - $inicio).TotalSeconds -gt 4) {
          Avisar-Balao $avisoSeDemorar
          $avisou = $true
        }
      }
    }
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
  Mostrar-Estado 'procurando vers\u00e3o nova...'
  return ((Rodar-Script $atualizador '-Automatico' 'Procurando vers\u00e3o nova do Treinador TCG. Ele abre em instantes.') -eq 10)
}

# Roda o iniciar.ps1 novo (o que acabou de chegar) nesta mesma janela.
function Abrir-De-Novo {
  $extras = '-JaAtualizou'
  if ($Bandeja) {
    $extras = $extras + ' -Bandeja'
    # O iniciar novo poe o proprio icone.
    Fechar-Bandeja
  }
  if ($SemJanela) { $extras = $extras + ' -SemJanela' }
  $codigo = Rodar-Script (Join-Path $ferramentas 'iniciar.ps1') $extras
  exit $codigo
}

if ($Bandeja) {
  Preparar-Bandeja
} elseif (-not $JaAtualizou) {
  Write-Host ''
  Write-Host '  =================================================='
  Write-Host '    Treinador TCG'
  Write-Host '    Deixe esta janela aberta enquanto usar o painel.'
  Write-Host '    Pode minimizar. Fechar a janela encerra o programa.'
  Write-Host '  =================================================='
  Write-Host ''
}
if ($SemJanela) { $env:TTCG_NAO_ABRIR = '1' }

if (-not (Test-Path -LiteralPath (Join-Path $app 'painel.mjs'))) {
  if ($Bandeja) {
    Falhar @('A pasta do programa est\u00e1 incompleta.', 'Instale o Treinador TCG de novo (suas partidas continuam).')
  }
  Falhar @('A pasta "programa" esta incompleta. Extraia o ZIP inteiro de novo.')
}

# Versoes ate a 1.1.x guardavam tudo solto na pasta de cima: arruma uma vez.
$legado = @('painel.mjs', 'dados', 'runtime', 'INICIAR-PAINEL.bat', 'VERSAO.txt') | Where-Object { Test-Path -LiteralPath (Join-Path $topo $_) }
if ($legado -and -not $desenvolvimento) {
  if ((Rodar-Script (Join-Path $ferramentas 'migrar.ps1') '') -ne 0) {
    Falhar @('N\u00e3o consegui arrumar a pasta da vers\u00e3o antiga.', 'Abra de novo pelo INICIAR TREINADOR TCG para ver os detalhes.')
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
  # Atalho antigo que estava aberto durante a atualizacao (atualizar.ps1).
  Get-ChildItem -LiteralPath $app -Filter '*.antigo' -Force -ErrorAction SilentlyContinue | ForEach-Object {
    try { Remove-Item -LiteralPath $_.FullName -Force -ErrorAction Stop } catch {}
  }
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
  Mostrar-Estado 'baixando o motor do programa...'
  Avisar-Balao 'Primeira vez neste computador: baixando o motor do programa. Leva de 1 a 3 minutos e s\u00f3 acontece uma vez.'
  $instalou = Rodar-Script (Join-Path $ferramentas 'instalar-node.ps1') ''
  $baixado = Join-Path $app 'runtime\node\node.exe'
  if ($instalou -ne 0 -or -not (Test-Path -LiteralPath $baixado)) {
    Falhar @('N\u00e3o consegui baixar o motor do programa (Node.js).', 'Confira a internet e abra o Treinador TCG de novo. Se continuar, instale o Node.js LTS pelo site nodejs.org e abra de novo.')
  }
  $node = $baixado
  Write-Host ''
}

if (-not $JaAtualizou) {
  if (Atualizar-Agora) { Abrir-De-Novo }
}

# O painel recusa abrir com estas variaveis (depuracao, codigo injetado,
# certificados de terceiros). Quem abre pelo atalho nunca e afetado.
foreach ($v in @('NODE_OPTIONS', 'NODE_EXTRA_CA_CERTS', 'NODE_TLS_REJECT_UNAUTHORIZED', 'NODE_DEBUG', 'NODE_V8_COVERAGE')) {
  Remove-Item -Path ('Env:' + $v) -ErrorAction SilentlyContinue
}

# Avisa o painel que ele pode pedir "atualize e me abra de novo".
# (Na janela preta, o painel roda direto nesta janela, fora de funcao, para
# nada capturar a saida dele.)
$env:TTCG_LANCADOR = '1'
if ($Bandeja) {
  $env:TTCG_BANDEJA = '1'
  Anotar-Versao-Instalada
  if (-not $SemJanela) { Apresentar-Bandeja }
}
$painel = Join-Path $app 'painel.mjs'
$jaReparou = $false
while ($true) {
  if ($Bandeja) {
    $codigo = Rodar-Painel-Na-Bandeja
  } else {
    & $node $painel
    $codigo = $LASTEXITCODE
  }
  if ($codigo -eq $PEDIU_ATUALIZAR) {
    Write-Host ''
    Write-Host '  Atualizando o Treinador TCG. O painel volta sozinho em instantes.'
    Mostrar-Estado 'atualizando...'
    Avisar-Balao 'Atualizando o Treinador TCG. A janela volta sozinha em instantes.'
    # A janela que pediu a atualizacao recarrega sozinha.
    $env:TTCG_NAO_ABRIR = '1'
    if (Atualizar-Agora) { Abrir-De-Novo }
    continue
  }
  if ($codigo -eq $ARQUIVOS_ALTERADOS) {
    if (-not $jaReparou -and -not $desenvolvimento) {
      $jaReparou = $true
      Write-Host '  Vou baixar de novo a versao oficial do Treinador TCG...'
      Mostrar-Estado 'reparando os arquivos...'
      Avisar-Balao 'Alguns arquivos do Treinador TCG est\u00e3o diferentes do oficial. Baixando de novo a vers\u00e3o oficial...'
      if ((Rodar-Script (Join-Path $ferramentas 'atualizar.ps1') '-Automatico -Reparar') -eq 10) { Abrir-De-Novo }
    }
    Falhar @('N\u00e3o consegui reparar os arquivos do Treinador TCG agora.', 'Conecte o computador \u00e0 internet e abra de novo. Se continuar, instale o Treinador TCG de novo (partidas e senhas continuam).')
  }
  if ($codigo -ne 0) {
    if ($Bandeja) {
      $detalhe = Ultimo-Erro
      $linhas = @('O Treinador TCG parou com um erro.')
      if ($detalhe) { $linhas += $detalhe.Replace('\', '\\') }
      $linhas += 'Abra de novo pelo atalho Treinador TCG. Os detalhes ficam em programa\\dados\\diagnostico.log, na pasta do Treinador.'
      Falhar $linhas
    }
    Falhar @('O painel parou com um erro. Veja a mensagem acima.', 'Os detalhes ficam no arquivo programa\\dados\\diagnostico.log.')
  }
  Fechar-Bandeja
  exit 0
}
