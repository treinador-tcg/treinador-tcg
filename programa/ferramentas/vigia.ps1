# Vigia de fim de partida do Treinador TCG (Windows). O painel inicia este
# script escondido e conversa com ele pela entrada e pela saida (uma linha por
# mensagem). Toda a logica fica em ferramentas/vigia.cs, compilado aqui na hora
# (o arquivo faz parte do pacote conferido pelo manifesto).
# -Pai: processo do painel (o vigia fecha junto). -Barreira 0/1: barreira
# sobre o CONTINUAR. -Depurar: escreve cada deteccao (testes). -SemEntrada:
# nao le a entrada (diagnostico rodado a mao).
param([int]$Pai = 0, [int]$Barreira = 1, [switch]$Depurar, [switch]$SemEntrada)
$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding($false) } catch {}

try {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing
  Add-Type -Path (Join-Path $PSScriptRoot 'vigia.cs') -ReferencedAssemblies System.Windows.Forms, System.Drawing
} catch {
  $m = ($_.Exception.Message -replace '[\r\n"\\]', ' ')
  [Console]::Out.WriteLine('{"evento":"erro","mensagem":"nao consegui preparar o vigia: ' + $m + '"}')
  exit 2
}

# Coordenadas em pixels reais (escala do Windows em 125%, 150%...): antes de
# criar qualquer janela.
[TreinadorTCG.Nativo]::PrepararDpi()
$argumentos = @('-pai', [string]$Pai, '-barreira', [string]$Barreira)
if ($Depurar) { $argumentos += '-depurar' }
if ($SemEntrada) { $argumentos += '-sementrada' }
exit ([TreinadorTCG.Vigia]::Rodar([string[]]$argumentos))
