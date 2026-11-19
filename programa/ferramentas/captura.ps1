param([int]$Pai = 0)
# Vigia da area de transferencia do Treinador TCG.
# So envia ao painel textos com 8 linhas ou mais (Battle Log e listas de deck).
# Textos curtos, como senhas copiadas, nunca saem deste script.
$ErrorActionPreference = 'SilentlyContinue'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Numero de sequencia da area de transferencia: muda a cada copia, mesmo que
# o texto copiado seja igual ao anterior (ex.: exportar o mesmo deck de novo).
$temSequencia = $false
try {
  Add-Type -Namespace TreinadorTCG -Name AreaTransf -MemberDefinition '[DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();' -ErrorAction Stop
  $temSequencia = $true
} catch {}

function Ler-Area {
  try { return (Get-Clipboard -Raw -Format Text) } catch {}
  try {
    Add-Type -AssemblyName System.Windows.Forms
    return [System.Windows.Forms.Clipboard]::GetText()
  } catch {}
  return $null
}

$ultimo = ''
$ultimaSeq = [uint32]0
$voltas = 0
while ($true) {
  $mudou = $true
  $seq = [uint32]0
  if ($temSequencia) {
    $seq = [TreinadorTCG.AreaTransf]::GetClipboardSequenceNumber()
    $mudou = ($seq -ne $ultimaSeq)
  }
  if ($mudou) {
    $t = Ler-Area
    # So marca a copia como lida quando conseguiu ler o texto (o jogo pode
    # ainda estar escrevendo na area de transferencia).
    if ($t -and $temSequencia) { $ultimaSeq = $seq }
    # Sem o numero de sequencia, compara o texto para nao repetir.
    if ($t -and ($temSequencia -or ($t -cne $ultimo))) {
      $ultimo = $t
      # Conta linhas com qualquer quebra: CRLF, LF ou so CR.
      $linhas = ($t -split '\r\n|\r|\n').Count
      if ($linhas -ge 8) {
        $b = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($t))
        [Console]::Out.WriteLine('CLIP ' + $b)
        [Console]::Out.Flush()
      }
    }
  }
  $voltas++
  if ($Pai -gt 0 -and ($voltas % 10) -eq 0) {
    if (-not (Get-Process -Id $Pai -ErrorAction SilentlyContinue)) { exit 0 }
  }
  Start-Sleep -Milliseconds 700
}
