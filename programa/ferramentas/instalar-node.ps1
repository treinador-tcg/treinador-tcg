# Baixa o Node.js portatil (versao LTS oficial) para a pasta runtime\node.
# Nao precisa de administrador e nao mexe no resto do computador.
# Confere a assinatura SHA-256 oficial antes de extrair.
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try {
  [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {}

function Ler-Texto($resposta) {
  $c = $resposta.Content
  if ($c -is [byte[]]) { $c = [System.Text.Encoding]::UTF8.GetString($c) }
  return [string]$c
}

$raiz = Split-Path -Parent $PSScriptRoot
$destino = Join-Path $raiz 'runtime'
$arq = 'x64'
if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { $arq = 'arm64' }

try {
  Write-Host '  Consultando a versao estavel mais nova do Node.js...'
  $indice = Invoke-RestMethod -Uri 'https://nodejs.org/dist/index.json' -UseBasicParsing
  $rel = $null
  foreach ($r in $indice) {
    if ($r.lts -and ($r.files -contains "win-$arq-zip")) { $rel = $r; break }
  }
  if (-not $rel) { throw 'Nenhuma versao LTS encontrada para este Windows.' }
  $ver = $rel.version
  $nome = "node-$ver-win-$arq"
  $zip = Join-Path $env:TEMP "$nome.zip"

  Write-Host "  Baixando Node.js $ver ..."
  Invoke-WebRequest -Uri "https://nodejs.org/dist/$ver/$nome.zip" -OutFile $zip -UseBasicParsing

  Write-Host '  Conferindo a assinatura do arquivo...'
  $somas = Ler-Texto (Invoke-WebRequest -Uri "https://nodejs.org/dist/$ver/SHASUMS256.txt" -UseBasicParsing)
  $linha = ($somas -split "`n") | Where-Object { $_ -match [regex]::Escape("$nome.zip") } | Select-Object -First 1
  if (-not $linha) { throw 'Nao encontrei a assinatura oficial do arquivo.' }
  $esperado = ($linha.Trim() -split '\s+')[0].ToLower()
  $obtido = (Get-FileHash -Algorithm SHA256 -Path $zip).Hash.ToLower()
  if ($esperado -ne $obtido) { throw 'O arquivo baixado nao confere com a assinatura oficial.' }

  Write-Host '  Extraindo...'
  if (Test-Path $destino) { Remove-Item $destino -Recurse -Force }
  New-Item -ItemType Directory -Path $destino | Out-Null
  Expand-Archive -Path $zip -DestinationPath $destino -Force
  Rename-Item -Path (Join-Path $destino $nome) -NewName 'node'
  Remove-Item $zip -Force
  Write-Host '  Pronto.'
  exit 0
} catch {
  Write-Host ('  Erro: ' + $_.Exception.Message)
  exit 1
}
