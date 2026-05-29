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

## Edições

O projeto mantém **duas edições** com versão e canal de atualização independentes:

| Edição | Executável | Versão | Launcher | Atualização |
|--------|------------|--------|----------|-------------|
| **Standard** | `LimpezaWindows.exe` | `config\VERSION` | `bin\limpeza.bat` | Só releases que incluem `LimpezaWindows.exe` |
| **Clean Code** | `LimpezaWindows-CleanCode.exe` | `config\VERSION.clean-code` | `bin\limpeza-clean-code.bat` | Só releases que incluem `LimpezaWindows-CleanCode.exe` |

Cada executável baixa **apenas o asset da sua edição** — a edição Clean Code nunca atualiza para o `.exe` Standard, e vice-versa. Logs e módulo de update ficam em pastas separadas em `%ProgramData%` (`LimpezaWindows` vs `LimpezaWindows-CleanCode`).

## Uso rápido

| Arquivo | Função |
|---------|--------|
| `bin\limpeza.bat` | Executa a edição Standard |
| `bin\limpeza-clean-code.bat` | Executa a edição Clean Code |
| `scripts\atualizar.bat` | Baixa a última Standard do GitHub |
| `scripts\build.bat` | Compila `dist\LimpezaWindows.exe` |
| `scripts\build-clean-code.bat` | Compila `dist\LimpezaWindows-CleanCode.exe` |

Requer **Administrador** (UAC).

Ao iniciar, o app verifica automaticamente se há atualização no GitHub. Se houver versão mais nova, baixa, aplica no mesmo executável, reinicia e segue com a limpeza completa. Para pular a verificação: `$env:LIMPEZA_SKIP_UPDATE = '1'`.

Ao terminar, o terminal exibe o **relatório completo** (todos os locais processados) e o **ganho de espaço em disco**. Pressione qualquer tecla para sair.

Versões anteriores instalavam em `C:\Windows\` e ofereciam agendamento — na v2.4.0 isso foi removido; artefatos legados são limpos automaticamente na primeira execução.

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
2. Baixe `LimpezaWindows.exe` (Standard) ou `LimpezaWindows-CleanCode.exe` (Clean Code).
3. Execute o `.exe` como Administrador (UAC) ou use o launcher correspondente em `bin\`.

Ou, com o repositório clonado:

```powershell
.\scripts\get-latest-release.ps1
.\scripts\get-latest-release.ps1 -Edition CleanCode
```

## Estrutura do projeto

```
limpeza-windows/
├── bin/
│   ├── limpeza.bat              # Standard
│   └── limpeza-clean-code.bat   # Clean Code
├── config/
│   ├── VERSION                  # versão Standard
│   └── VERSION.clean-code       # versão Clean Code
├── scripts/
│   ├── build.bat
│   ├── build-clean-code.bat
│   ├── atualizar.bat
│   ├── build-limpeza.ps1        # -Edition Standard | CleanCode
│   ├── get-latest-release.ps1
│   └── publish-release.ps1
```

## Publicar uma nova release

1. Atualize `config\VERSION` (Standard) e/ou `config\VERSION.clean-code` (Clean Code).
2. Atualize `$AppVersion` em `src\limpeza.ps1` (valor base usado pelo build).
3. Compile e publique:

```powershell
.\scripts\build.bat
.\scripts\build-clean-code.bat
.\scripts\publish-release.ps1 -SkipBuild
.\scripts\publish-release.ps1 -Edition CleanCode -SkipBuild
```

Uma mesma tag (ex.: `v2.4.1`) pode conter **ambos** os executáveis. Cada edição só se atualiza quando a release incluir o seu asset.

## Autor

Luiz Filipe Schaeffer
