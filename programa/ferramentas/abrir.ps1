# Abre o Treinador TCG sem janela preta: e o que os atalhos (Area de Trabalho,
# menu Iniciar) e o "Abrir junto com o Windows" rodam (ver atalhos.ps1):
#   conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File abrir.ps1 [-AoLigar]
# Faz o mesmo que o Treinador TCG.exe: roda o iniciar.ps1 -Bandeja e, se ele
# sair de um jeito inesperado (codigo diferente de 0 e 3), procura uma versao
# corrigida (atualizar.ps1 -Automatico) e tenta de novo.
# -AoLigar (junto com o Windows) = so o icone ao lado do relogio, sem o painel.
param([switch]$AoLigar)
$ProgressPreference = 'SilentlyContinue'
$ferramentas = $PSScriptRoot
$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$iniciar = Join-Path $ferramentas 'iniciar.ps1'
$extra = ''
if ($AoLigar) { $extra = ' -SemJanela' }

function T([string]$s) { return [regex]::Unescape($s) }

function Avisar($texto) {
  try {
    Add-Type -AssemblyName System.Windows.Forms
    $dono = New-Object System.Windows.Forms.Form
    $dono.TopMost = $true
    try { [void][System.Windows.Forms.MessageBox]::Show($dono, (T $texto), 'Treinador TCG', 'OK', 'Warning') } finally { $dono.Dispose() }
  } catch {}
}

# Roda um script do PowerShell no mesmo console (escondido) e devolve o codigo.
function Rodar($script, $parametros) {
  try {
    $p = Start-Process -FilePath $ps -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -File "' + $script + '"' + $parametros) -NoNewWindow -PassThru
    $null = $p.Handle
    $p.WaitForExit()
    return [int]$p.ExitCode
  } catch {
    return -1
  }
}

if (-not (Test-Path -LiteralPath $iniciar)) {
  Avisar 'Faltam arquivos do Treinador TCG.\r\n\r\nInstale de novo pelo instalador (suas partidas e a ativa\u00e7\u00e3o continuam).'
  exit 1
}

# Quem clicou no atalho foi a pessoa: a janela do painel pode vir para a frente.
try {
  Add-Type -Namespace TreinadorTCG -Name Frente -MemberDefinition '[DllImport("user32.dll")] public static extern bool AllowSetForegroundWindow(int id);'
  [void][TreinadorTCG.Frente]::AllowSetForegroundWindow(-1)
} catch {}

$codigo = Rodar $iniciar (' -Bandeja' + $extra)
if ($codigo -eq 0 -or $codigo -eq 3) { exit $codigo }

# Saida inesperada: procura uma versao corrigida (como o INICIAR .bat).
$atualizar = Join-Path $ferramentas 'atualizar.ps1'
if (Test-Path -LiteralPath $atualizar) {
  if ((Rodar $atualizar ' -Automatico') -eq 10) {
    $codigo = Rodar $iniciar (' -Bandeja -JaAtualizou' + $extra)
    if ($codigo -eq 0 -or $codigo -eq 3) { exit $codigo }
  }
}
Avisar 'O Treinador TCG n\u00e3o abriu direito.\r\n\r\nConfira a internet e abra de novo. Se continuar, instale de novo pelo instalador (suas partidas e a ativa\u00e7\u00e3o continuam).'
exit 1
