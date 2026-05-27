## Limpeza Avancada do Windows v2.2.1

### Correcoes

- **Auto-atualizacao**: ao pressionar [S], o executavel em `C:\Windows\LimpezaWindows.exe` passa a ser substituido de forma confiavel (rename + copy + verificacao de versao) antes de reiniciar
- Modulo **`LimpezaUpdate.ps1`** isolado, copiado para `%ProgramData%\LimpezaWindows\` e para `C:\Windows\` na instalacao
- Verificacao de atualizacao ocorre **antes** da copia de instalacao, evitando sobrescrever uma versao nova com arquivos antigos
- Log de falhas em `%ProgramData%\LimpezaWindows\logs\update-*.log`

### Testes

- `tests/Test-LimpezaUpdate.ps1` (12 cenarios) executado automaticamente no build

### Novidades da v2.2.0

- 11 etapas de limpeza (Windows Update, navegadores, lixeira, DNS, etc.)
- Tela final com relatorio e espaco ganho alinhado aos valores exibidos

### Como usar

1. Baixe `LimpezaWindows.exe` desta release
2. Execute `bin\limpeza.bat` ou o executavel como **Administrador**

Repositorio: https://github.com/luizfilipeschaeffer/limpeza-windows
