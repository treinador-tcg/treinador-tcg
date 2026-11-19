// Compatibilidade: o atualizador das versões até a 1.1.x confere se este
// arquivo existe na pasta principal. O programa de verdade fica em
// programa/painel.mjs; este arquivo é apagado na primeira vez que o
// Treinador arruma a pasta (programa/ferramentas/migrar.ps1).
await import('./programa/painel.mjs');
