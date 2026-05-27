## Limpeza Avancada do Windows v2.2.0

### Novidades

- **11 etapas de limpeza** (antes eram 7), incluindo:
  - Cache do **Windows Update** (`SoftwareDistribution\Download`)
  - **Miniaturas**, logs do Windows (`C:\Windows\Logs`) e relatorios de erro (**WER**)
  - Caches de **Edge**, **Chrome** e **Firefox**
  - **Lixeira** e limpeza de **cache DNS**
- Tela final apos `cls`: cabecalho com autor/versao/inicio/termino, relatorio completo, resultado em disco e menu de agendamento
- **Espaco ganho** calculado a partir dos valores exibidos em GB (Antes/Depois), alinhado ao relatorio na tela

### Mantido da v2.1.0

- Caches de desenvolvimento (Node, Python, Docker)
- Relatorio por categoria com status (Limpo, Ignorado, Parcial, Erro, Pulado)
- Agendamento automatico no Agendador de Tarefas
- Logs em execucao agendada: `%ProgramData%\LimpezaWindows\logs\`

### Como usar

1. Baixe `LimpezaWindows.exe` desta release
2. Execute `bin\limpeza.bat` ou o executavel como **Administrador**

Repositorio: https://github.com/luizfilipeschaeffer/limpeza-windows
