# Conecta o plano do Claude (Pro ou Max) ao Treinador TCG.
# 1) Instala o Claude Code, o programa oficial da Anthropic, se ainda nao
#    estiver instalado (instalador oficial: https://claude.ai/install.ps1).
# 2) Abre o login da Anthropic no navegador para a pessoa entrar com a
#    propria conta. O painel nunca ve a senha nem o token.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'janela-comum.ps1')
try { $Host.UI.RawUI.WindowTitle = 'Conectar o plano do Claude' } catch {}
Desligar-Selecao
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}
# Sem chave de API: o login tem de ser o da conta do plano.
Remove-Item Env:ANTHROPIC_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:ANTHROPIC_AUTH_TOKEN -ErrorAction SilentlyContinue
# Pedido "Trocar de conta" do painel: sai da conta atual antes de entrar.
$trocar = ($env:TTCG_TROCAR_CONTA -eq '1')
Iniciar-Registro 'conectar-claude'
$ajuda = 'conectar-claude.log'

function Achar-Claude {
  $candidatos = @(
    (Join-Path $env:USERPROFILE '.local\bin\claude.exe')
  )
  if ($env:LOCALAPPDATA) { $candidatos += (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links\claude.exe') }
  foreach ($c in $candidatos) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $cmd = Get-Command claude.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

Titulo 'Conectar o seu plano do Claude ao Treinador TCG'
Write-Host '  Sao 2 passos. Nao precisa digitar nada nesta janela.'

$exe = Achar-Claude
if (-not $exe) {
  Passo 'Passo 1 de 2: instalando o Claude Code, o programa oficial da Anthropic.'
  Write-Host '  Leva de 1 a 3 minutos. Os pontinhos mostram que esta andando.'
  $comando = '[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; irm https://claude.ai/install.ps1 | iex'
  [void](Instalar-Com-Pontos $comando 'instalar-claude')
  $exe = Achar-Claude
  if (-not $exe) {
    Write-Host '  Nao consegui instalar o Claude Code. Confira a internet e tente de novo pelo painel.' -ForegroundColor Red
    Write-Host '  Se continuar, instale pelo site https://claude.com/download e clique em Conectar de novo.'
    Write-Host '  Os detalhes ficam em instalar-claude.log, na pasta de dados.'
    Fechar 1 $ajuda
  }
  Write-Host '  Claude Code instalado.' -ForegroundColor Green
} else {
  Passo 'Passo 1 de 2: o Claude Code ja esta instalado. Conferindo se tem versao nova...'
  [void](Instalar-Com-Pontos ('& "' + $exe + '" update') 'atualizar-claude')
}
Write-Host ('  Programa: ' + $exe + ' (versao ' + ((& $exe --version) -join ' ') + ')')

& $exe auth status *> $null
$conectado = ($LASTEXITCODE -eq 0)
if ($conectado -and $trocar) {
  Write-Host '  Saindo da conta atual neste computador...'
  & $exe auth logout *> $null
  $conectado = $false
}
if ($conectado) {
  Passo 'Passo 2 de 2: este computador ja esta conectado a uma conta do Claude.'
} else {
  Passo 'Passo 2 de 2: entrar na sua conta do Claude.'
  Write-Host '  O navegador vai abrir na pagina da Anthropic. Entre com a sua conta do Claude'
  Write-Host '  (a mesma do claude.ai, com plano Pro ou Max) e clique em Autorizar.'
  Write-Host '  Quando o navegador disser que deu certo, volte ao painel.'
  if ($trocar) {
    Write-Host '  Se o navegador entrar direto na conta antiga, saia dela no claude.ai'
    Write-Host '  e clique de novo em Trocar de conta no painel.'
  }
  Write-Host ''
  & $exe auth login
  & $exe auth status *> $null
  if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host '  A conexao nao foi concluida. Tente de novo pelo painel.' -ForegroundColor Red
    Fechar 1 $ajuda
  }
}
Fechar 0 $ajuda
