## Limpeza Avancada do Windows v2.4.0

### Novidades

- **Duas edições com versão independente**: Standard (`LimpezaWindows.exe`) e Clean Code (`LimpezaWindows-CleanCode.exe`)
- **Canais de atualização separados**: cada executável busca releases que contenham apenas o seu asset
- **ProgramData separado**: `%ProgramData%\LimpezaWindows` vs `%ProgramData%\LimpezaWindows-CleanCode`
- **Fluxo linear** (Clean Code): atualizar → limpar → relatório, sem menu, instalação ou agendamento

### Removido

- Instalacao automatica em `C:\Windows\LimpezaWindows.exe`
- Menu inicial (continuar / atualizar / desinstalar)
- Agendamento automatico (`schtasks`) e modo `-ScheduledRun`
- Animacao de introducao

### Como usar

1. Baixe `LimpezaWindows.exe` (Standard) ou `LimpezaWindows-CleanCode.exe` (Clean Code)
2. Execute como **Administrador** (UAC) ou use `bin\limpeza.bat` / `bin\limpeza-clean-code.bat`
3. O app atualiza (se necessario), limpa e exibe o relatorio — pressione uma tecla para sair

Para pular a verificacao de atualizacao: `$env:LIMPEZA_SKIP_UPDATE = '1'`

Repositorio: https://github.com/luizfilipeschaeffer/limpeza-windows
