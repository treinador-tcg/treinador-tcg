# Atalhos do Treinador TCG sem programa proprio (lido pelo iniciar.ps1 com ".").
# O atalho da Area de Trabalho, o do menu Iniciar e o "Abrir junto com o
# Windows" rodam so programas do proprio Windows:
#   conhost.exe --headless powershell.exe ... -File abrir.ps1 [-AoLigar]
# O "Controle inteligente de aplicativos" do Windows 11 bloqueia programas sem
# assinatura digital, como o Treinador TCG.exe; o conhost e o PowerShell sao
# assinados pela Microsoft. O --headless roda sem janela nenhuma (Windows 10
# 1809 ou mais novo; antes disso, o PowerShell se esconde sozinho).
# O Treinador TCG.exe continua na pasta (o instalador e atalhos antigos ainda
# apontam para ele) e os atalhos que apontam para ele viram atalhos novos na
# proxima abertura (Atualizar-Atalhos).

$script:ATALHO_NOME = 'Treinador TCG.lnk'

# Caminhos montados com texto (iguais em qualquer computador, e testaveis).
function Sob([string]$pasta, [string]$resto) { return ($pasta.TrimEnd('\') + '\' + $resto) }
function Caminho-PowerShell { return (Sob $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe') }
function Caminho-Conhost { return (Sob $env:SystemRoot 'System32\conhost.exe') }
function Tem-Headless {
  try { return ([Environment]::OSVersion.Version.Build -ge 17763) -and (Test-Path -LiteralPath (Caminho-Conhost)) } catch { return $false }
}

# Programa e argumentos que abrem o Treinador desta pasta.
function Comando-Abrir([string]$pastaApp, [switch]$AoLigar) {
  $abrir = Sob $pastaApp 'ferramentas\abrir.ps1'
  $ps = '-NoProfile -ExecutionPolicy Bypass -File "' + $abrir + '"'
  if ($AoLigar) { $ps += ' -AoLigar' }
  if (Tem-Headless) {
    return @{ Programa = (Caminho-Conhost); Argumentos = ('--headless "' + (Caminho-PowerShell) + '" ' + $ps) }
  }
  return @{ Programa = (Caminho-PowerShell); Argumentos = ('-WindowStyle Hidden ' + $ps) }
}

# Linha do "Abrir junto com o Windows" (registro, chave Run).
function Linha-Abrir([string]$pastaApp, [switch]$AoLigar) {
  $c = Comando-Abrir $pastaApp -AoLigar:$AoLigar
  return ('"' + $c.Programa + '" ' + $c.Argumentos)
}

function Criar-Atalho([string]$arquivo, [string]$pastaApp) {
  $c = Comando-Abrir $pastaApp
  $shell = New-Object -ComObject WScript.Shell
  $lnk = $shell.CreateShortcut($arquivo)
  $lnk.TargetPath = $c.Programa
  $lnk.Arguments = $c.Argumentos
  $lnk.WorkingDirectory = $pastaApp
  $lnk.IconLocation = (Sob $pastaApp 'ferramentas\treinador.ico') + ',0'
  $lnk.Description = 'Abre o Treinador TCG'
  # Minimizado: se um dia o conhost mostrar alguma coisa, nao aparece na frente.
  $lnk.WindowStyle = 7
  $lnk.Save()
}

# Lugares onde ficam os atalhos do Treinador (inclusive os fixados).
function Lugares-Atalhos {
  $lugares = @()
  try { $lugares += [Environment]::GetFolderPath('Desktop') } catch {}
  try { $lugares += [Environment]::GetFolderPath('Programs') } catch {}
  if ($env:APPDATA) {
    $lugares += (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar')
    $lugares += (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\StartMenu')
  }
  return @($lugares | Where-Object { $_ -and (Test-Path -LiteralPath $_) })
}

# Troca os atalhos que abrem o Treinador TCG.exe desta pasta pelo atalho novo
# e faz o mesmo com o "Abrir junto com o Windows". Atalhos de outras pastas
# (outra copia do Treinador) e de outros programas nao sao tocados.
# Devolve quantos trocou. Nunca da erro: se algo falhar, fica como estava.
function Atualizar-Atalhos([string]$pastaApp, [string]$chaveLigar, [string]$nomeLigar) {
  $exe = Sob $pastaApp 'Treinador TCG.exe'
  $trocados = 0
  $shell = $null
  try { $shell = New-Object -ComObject WScript.Shell } catch { return 0 }
  foreach ($lugar in (Lugares-Atalhos)) {
    foreach ($arq in @(Get-ChildItem -LiteralPath $lugar -Filter '*.lnk' -File -ErrorAction SilentlyContinue)) {
      try {
        $lnk = $shell.CreateShortcut($arq.FullName)
        if ([string]::Equals([string]$lnk.TargetPath, $exe, [StringComparison]::OrdinalIgnoreCase)) {
          Criar-Atalho $arq.FullName $pastaApp
          $trocados++
        }
      } catch {}
    }
  }
  try {
    $v = [string](Get-ItemProperty -Path $chaveLigar -Name $nomeLigar -ErrorAction Stop).$nomeLigar
    if ($v -and $v.IndexOf($exe, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
      Set-ItemProperty -Path $chaveLigar -Name $nomeLigar -Value (Linha-Abrir $pastaApp -AoLigar) -ErrorAction Stop
      $trocados++
    }
  } catch {}
  return $trocados
}
