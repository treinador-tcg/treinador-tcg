# Pecas comuns das janelas "Conectar" (Claude e ChatGPT). Carregado com:
#   . (Join-Path $PSScriptRoot 'janela-comum.ps1')

# Desliga a "selecao rapida" do console: um clique na janela nao congela mais
# a instalacao (o Windows pausa o programa enquanto ha texto selecionado).
function Desligar-Selecao {
  try {
    Add-Type -Namespace TreinadorTCG -Name Console -ErrorAction Stop -MemberDefinition '
[DllImport("kernel32.dll")] public static extern System.IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll")] public static extern bool GetConsoleMode(System.IntPtr h, out uint m);
[DllImport("kernel32.dll")] public static extern bool SetConsoleMode(System.IntPtr h, uint m);'
    $h = [TreinadorTCG.Console]::GetStdHandle(-10)
    $m = [uint32]0
    if ([TreinadorTCG.Console]::GetConsoleMode($h, [ref]$m)) {
      $novo = [uint32](((([int64]$m) -bor 0x80) -band 0xFFBF))
      [void][TreinadorTCG.Console]::SetConsoleMode($h, $novo)
    }
  } catch {}
}

# Registro da janela em programa\dados\<nome>.log, para diagnostico.
function Iniciar-Registro($nome) {
  $script:pastaDados = Join-Path (Split-Path -Parent $PSScriptRoot) 'dados'
  $script:gravando = $false
  try {
    if (-not (Test-Path -LiteralPath $script:pastaDados)) { New-Item -ItemType Directory -Path $script:pastaDados | Out-Null }
    Start-Transcript -Path (Join-Path $script:pastaDados ($nome + '.log')) -Force | Out-Null
    $script:gravando = $true
  } catch {}
}

function Titulo($texto) {
  Write-Host ''
  Write-Host ('  ' + $texto) -ForegroundColor Yellow
  Write-Host ('  ' + ('-' * $texto.Length)) -ForegroundColor Yellow
}

function Passo($texto) {
  Write-Host ''
  Write-Host ('  ' + $texto) -ForegroundColor Cyan
}

# Roda um instalador oficial sem perguntas, com a saida num arquivo de
# registro e pontinhos na tela enquanto trabalha. Devolve o codigo de saida.
function Instalar-Com-Pontos($comando, $nomeRegistro) {
  $registro = Join-Path $script:pastaDados ($nomeRegistro + '.log')
  $erros = Join-Path $script:pastaDados ($nomeRegistro + '-erros.log')
  $vazio = Join-Path $script:pastaDados 'entrada-vazia.txt'
  try { [System.IO.File]::WriteAllText($vazio, '') } catch {}
  $cod = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($comando))
  Write-Host -NoNewline '  '
  try {
    $p = Start-Process -FilePath 'powershell.exe' -ArgumentList ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + $cod) -NoNewWindow -PassThru -RedirectStandardInput $vazio -RedirectStandardOutput $registro -RedirectStandardError $erros
    $null = $p.Handle
    $inicio = Get-Date
    while (-not $p.HasExited) {
      Write-Host -NoNewline '.'
      Start-Sleep -Seconds 2
      if (((Get-Date) - $inicio).TotalMinutes -gt 10) { try { $p.Kill() } catch {}; break }
    }
    $p.WaitForExit()
    Write-Host ''
    return $p.ExitCode
  } catch {
    Write-Host ''
    Write-Host ('  ' + $_.Exception.Message)
    return 1
  }
}

# Sucesso: avisa e fecha sozinha. Falha: espera a pessoa ler.
function Fechar($codigo, $arquivoAjuda) {
  Write-Host ''
  if ($script:gravando) { try { Stop-Transcript | Out-Null } catch {} }
  if ($codigo -eq 0) {
    Write-Host '  Pronto! O painel ja percebe sozinho que a conta foi conectada.' -ForegroundColor Green
    Write-Host '  Esta janela fecha sozinha em 15 segundos.'
    Start-Sleep -Seconds 15
    exit 0
  }
  Write-Host ('  Se precisar de ajuda, mande o arquivo ' + $arquivoAjuda + ' (no painel: Ajuda, Abrir a pasta de dados).')
  Read-Host '  Aperte Enter para fechar esta janela' | Out-Null
  exit 0
}
