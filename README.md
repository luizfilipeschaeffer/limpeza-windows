# Limpeza Avançada do Windows

<p align="center">
  <a href="https://github.com/luizfilipeschaeffer/limpeza-windows/releases/latest/download/LimpezaWindows.exe">
    <img src="https://img.shields.io/badge/Download-LimpezaWindows.exe-0078D4?style=for-the-badge&logo=windows&logoColor=white" alt="Baixar LimpezaWindows.exe">
  </a>
  &nbsp;
  <a href="https://github.com/luizfilipeschaeffer/limpeza-windows/releases/latest">
    <img src="https://img.shields.io/github/v/release/luizfilipeschaeffer/limpeza-windows?label=Versão&style=for-the-badge&color=107C10" alt="Última versão">
  </a>
</p>

Ferramenta de manutenção e liberação de espaço no disco C: (TEMP, Prefetch, caches de desenvolvimento, Windows Installer, DISM, cleanmgr) com relatório final detalhado.

**Repositório:** [github.com/luizfilipeschaeffer/limpeza-windows](https://github.com/luizfilipeschaeffer/limpeza-windows)  
**Atualizações (releases):** [github.com/luizfilipeschaeffer/limpeza-windows/releases](https://github.com/luizfilipeschaeffer/limpeza-windows/releases)

## Uso rápido

| Arquivo | Função |
|---------|--------|
| `bin\limpeza.bat` | Executa a limpeza (`.exe` ou script PowerShell) |
| `scripts\atualizar.bat` | Baixa a última versão do executável no GitHub |
| `scripts\build.bat` | Compila `dist\LimpezaWindows.exe` |

Requer **Administrador** (UAC).

Na primeira execução, o app copia o executável para `C:\Windows\LimpezaWindows.exe` e cria o atalho **Limpeza Avançada do Windows** na Área de Trabalho do usuário.

Ao iniciar, o app verifica atualizações no GitHub. Se houver versão mais nova, pergunta se deseja baixar e reiniciar; caso contrário, segue com a limpeza. Para pular a verificação: `$env:LIMPEZA_SKIP_UPDATE = '1'`.

Ao terminar (execução manual), o terminal é limpo (`cls`) e exibe o **relatório completo** (todos os locais processados), o **ganho de espaço em disco** e o menu de **agendamento** (1x ao dia, semana ou mês; horários de 3 em 3 h, 00:00–21:00).

Na execução agendada, a limpeza roda em **silêncio** (sem janela nem mensagens), atualiza automaticamente se houver nova versão, pula o cleanmgr e grava o relatório em `%ProgramData%\LimpezaWindows\logs\`.

### Caches de desenvolvimento (padrão ligado)

Por padrão, o app tenta limpar pastas de cache comuns e executar `docker system prune -f` (sem remover volumes):

| Ferramenta | Pastas / ação |
|------------|----------------|
| **Node** | `npm-cache`, `pnpm-store`, Yarn, Turborepo (`%LOCALAPPDATA%`) |
| **Python** | pip, Poetry, uv (`%LOCALAPPDATA%` e `%USERPROFILE%\.cache\pip`) |
| **Docker** | `docker system prune -f` (se o CLI estiver no PATH) |

Para desativar (CLI ou variáveis de ambiente):

| Opção | Efeito |
|-------|--------|
| `-SkipDevCaches` / `LIMPEZA_SKIP_DEV=1` | Pula toda a etapa de caches de dev |
| `-SkipNode` / `LIMPEZA_SKIP_NODE=1` | Pula só Node |
| `-SkipPython` / `LIMPEZA_SKIP_PYTHON=1` | Pula só Python |
| `-SkipDocker` / `LIMPEZA_SKIP_DOCKER=1` | Pula prune do Docker |

Exemplo:

```powershell
.\src\limpeza.ps1 -SkipDocker
$env:LIMPEZA_SKIP_DEV = '1'; .\src\limpeza.ps1
```

## Baixar a última versão

Use o botão **Baixar LimpezaWindows.exe** no topo desta página ou:

1. Abra [Releases](https://github.com/luizfilipeschaeffer/limpeza-windows/releases/latest).
2. Baixe `LimpezaWindows.exe`.
3. Execute o `.exe` como Administrador (UAC) ou use `bin\limpeza.bat` se clonou o repositório.

Ou, com o repositório clonado:

```powershell
.\scripts\get-latest-release.ps1
```

## Estrutura do projeto

```
limpeza-windows/
├── bin/
│   └── limpeza.bat           # executar a limpeza
├── config/
│   └── VERSION               # versão atual (ex.: 2.0.1)
├── scripts/
│   ├── build.bat             # compilar
│   ├── atualizar.bat         # baixar release do GitHub
│   ├── build-limpeza.ps1
│   ├── get-latest-release.ps1
│   └── publish-release.ps1
├── src/limpeza.ps1           # código-fonte
├── dist/                     # executável gerado
├── assets/                   # ícones
└── tools/ps2exe-build/       # compilador PS → EXE
```

## Publicar uma nova release

1. Atualize `config\VERSION` (ex.: `2.0.2`).
2. Atualize `$AppVersion` em `src\limpeza.ps1`.
3. Compile e publique:

```powershell
.\scripts\build.bat
.\scripts\publish-release.ps1 -SkipBuild
```

Ou crie a tag no Git — o workflow `.github/workflows/release.yml` compila e publica automaticamente:

```bash
git tag v2.0.2
git push origin v2.0.2
```

## Autor

Luiz Filipe Schaeffer
