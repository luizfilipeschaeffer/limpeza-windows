## Limpeza Avancada do Windows v2.1.0

### Novidades

- Etapa **[4/7] Caches de desenvolvimento**: npm, pnpm, Yarn, pip, Poetry, uv e `docker system prune -f` (ativado por padrao)
- **Relatorio final** com todos os locais processados (Windows + dev) e status (Limpo, Ignorado, Parcial, Erro, Pulado)
- Tela final manual: `cls` → relatorio → espaco em disco → menu de agendamento
- Execucao agendada: relatorio gravado em `%ProgramData%\LimpezaWindows\logs\`
- Parametros opt-out: `-SkipDevCaches`, `-SkipNode`, `-SkipPython`, `-SkipDocker` e variaveis `LIMPEZA_SKIP_*`

### Correcoes recentes

- v2.0.9: menu de agendamento com **[S] Sair**
- v2.0.8: criacao de tarefa agendada sem erro `/B` no schtasks

### Atualizacoes

https://github.com/luizfilipeschaeffer/limpeza-windows/releases
