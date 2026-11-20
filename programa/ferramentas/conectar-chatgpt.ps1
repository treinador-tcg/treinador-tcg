# Conecta a conta do ChatGPT ao Treinador TCG, pelo Codex.
# 1) Instala o Codex, o programa oficial da OpenAI, se ainda nao estiver
#    instalado (instalador oficial: https://chatgpt.com/codex/install.ps1),
#    sem perguntas (CODEX_NON_INTERACTIVE=1).
# 2) Abre o login da OpenAI no navegador para a pessoa entrar com a propria
#    conta do ChatGPT. O painel nunca ve a senha nem o token.
$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
. (Join-Path $PSScriptRoot 'janela-comum.ps1')
try { $Host.UI.RawUI.WindowTitle = 'Conectar a conta do ChatGPT' } catch {}
Desligar-Selecao
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}
# Sem chave de API: o login tem de ser o da conta do ChatGPT.
Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue
Remove-Item Env:CODEX_API_KEY -ErrorAction SilentlyContinue
$env:CODEX_NON_INTERACTIVE = '1'
# Pedido "Trocar de conta" do painel: sai da conta atual antes de entrar.
$trocar = ($env:TTCG_TROCAR_CONTA -eq '1')
Iniciar-Registro 'conectar-chatgpt'
$ajuda = 'conectar-chatgpt.log'

function Achar-Codex {
  $codexHome = $env:CODEX_HOME
  if (-not $codexHome) { $codexHome = Join-Path $env:USERPROFILE '.codex' }
  $candidatos = @()
  if ($env:LOCALAPPDATA) { $candidatos += (Join-Path $env:LOCALAPPDATA 'Programs\OpenAI\Codex\bin\codex.exe') }
  $candidatos += (Join-Path $codexHome 'packages\standalone\current\bin\codex.exe')
  $candidatos += (Join-Path $codexHome 'packages\standalone\current\codex.exe')
  foreach ($c in $candidatos) {
    if (Test-Path -LiteralPath $c) { return $c }
  }
  # O instalador muda o PATH do usuario; esta janela ainda tem o antigo.
  $env:Path = [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $cmd = Get-Command codex.exe -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  return $null
}

if ($trocar) { Titulo 'Trocar a conta do ChatGPT do Treinador TCG' } else { Titulo 'Conectar a sua conta do ChatGPT ao Treinador TCG' }
Write-Host '  Sao 2 passos. Nao precisa digitar nada nesta janela.'

$exe = Achar-Codex
if (-not $exe) {
  Passo 'Passo 1 de 2: instalando o Codex, o programa oficial da OpenAI.'
  Write-Host '  Leva de 1 a 3 minutos. Os pontinhos mostram que esta andando.'
  $comando = '[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12; irm https://chatgpt.com/codex/install.ps1 | iex'
  [void](Instalar-Com-Pontos $comando 'instalar-codex')
  $exe = Achar-Codex
  if (-not $exe) {
    Write-Host '  Nao consegui instalar o Codex. Confira a internet e tente de novo pelo painel.' -ForegroundColor Red
    Write-Host '  Os detalhes ficam em instalar-codex.log, na pasta de dados.'
    Fechar 1 $ajuda
  }
  Write-Host '  Codex instalado.' -ForegroundColor Green
} else {
  Passo 'Passo 1 de 2: o Codex ja esta instalado.'
}
Write-Host ('  Programa: ' + $exe + ' (versao ' + ((& $exe --version) -join ' ') + ')')
# Guarda o caminho para o painel achar o Codex mesmo fora do PATH.
try { [System.IO.File]::WriteAllText((Join-Path $script:pastaDados 'codex-caminho.txt'), $exe) } catch {}

& $exe login status *> $null
$conectado = ($LASTEXITCODE -eq 0)
if ($conectado -and $trocar) {
  Write-Host '  Saindo da conta atual neste computador...'
  & $exe logout *> $null
  $conectado = $false
}
if ($conectado) {
  Passo 'Passo 2 de 2: este computador ja esta conectado a uma conta.'
} else {
  Passo 'Passo 2 de 2: entrar na sua conta do ChatGPT.'
  Write-Host '  O navegador vai abrir na pagina da OpenAI. Entre com a sua conta do ChatGPT'
  Write-Host '  e confirme. Quando o navegador disser que deu certo, volte ao painel.'
  if ($trocar) {
    Write-Host '  Se o navegador entrar direto na conta antiga, saia dela no chatgpt.com'
    Write-Host '  e clique de novo em Trocar de conta no painel.'
  }
  Write-Host '  Se o navegador nao abrir, copie o endereco https://auth.openai.com que'
  Write-Host '  aparece abaixo e cole no navegador.'
  Write-Host ''
  & $exe login
  & $exe login status *> $null
  if ($LASTEXITCODE -ne 0) {
    Write-Host ''
    Write-Host '  A conexao nao foi concluida. Tente de novo pelo painel.' -ForegroundColor Red
    Fechar 1 $ajuda
  }
}
Fechar 0 $ajuda
