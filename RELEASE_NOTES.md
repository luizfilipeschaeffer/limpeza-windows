## Limpeza Avancada do Windows v2.3.0

### Novidades

- **Menu inicial** antes de qualquer limpeza: escolha continuar, atualizar ou sair
- **[3] Desinstalar**: remove `C:\Windows\LimpezaWindows.exe`, modulo de update, atalho, tarefa agendada e `%ProgramData%\LimpezaWindows\`
- Facilita **reinstalar do zero**: desinstale, depois execute novamente `dist\LimpezaWindows.exe` ou baixe do GitHub

### Correcoes (v2.2.x)

- Auto-atualizacao confiavel com modulo `LimpezaUpdate.ps1` isolado
- Substituicao do executavel com validacao de versao e log em `%ProgramData%\LimpezaWindows\logs\`

### Como usar

1. Baixe `LimpezaWindows.exe` desta release (recomendado copiar tambem `LimpezaUpdate.ps1` para `C:\Windows\` na primeira instalacao manual)
2. Execute `bin\limpeza.bat` ou o executavel como **Administrador**
3. No menu inicial: **1** limpar, **2** atualizar, **3** desinstalar, **0** sair

Repositorio: https://github.com/luizfilipeschaeffer/limpeza-windows
