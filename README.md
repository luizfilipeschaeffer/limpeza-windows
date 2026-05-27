# Limpeza Avançada do Windows

Ferramenta de manutenção e liberação de espaço no disco C: (TEMP, Prefetch, Windows Installer, DISM, cleanmgr).

**Repositório:** [github.com/luizfilipeschaeffer/limpeza-windows](https://github.com/luizfilipeschaeffer/limpeza-windows)  
**Atualizações (releases):** [github.com/luizfilipeschaeffer/limpeza-windows/releases](https://github.com/luizfilipeschaeffer/limpeza-windows/releases)

## Uso rápido

| Arquivo | Função |
|---------|--------|
| `limpeza.bat` | Executa a limpeza (`.exe` ou script PowerShell) |
| `atualizar.bat` | Baixa a última versão do executável no GitHub |
| `build.bat` | Compila `dist\LimpezaWindows.exe` |

Requer **Administrador** (UAC).

Ao iniciar, o app verifica atualizações no GitHub. Se houver versão mais nova, pergunta se deseja baixar e reiniciar; caso contrário, segue com a limpeza. Para pular a verificação: `$env:LIMPEZA_SKIP_UPDATE = '1'`.

## Baixar a última versão

1. Abra [Releases](https://github.com/luizfilipeschaeffer/limpeza-windows/releases/latest).
2. Baixe `LimpezaWindows.exe`.
3. Execute `limpeza.bat` ou o `.exe` diretamente.

Ou, com o repositório clonado:

```powershell
.\scripts\get-latest-release.ps1
```

## Estrutura do projeto

```
limpeza-windows/
├── limpeza.bat          # executar
├── atualizar.bat        # baixar release do GitHub
├── build.bat            # compilar
├── VERSION              # versão atual (ex.: 2.0.0)
├── src/limpeza.ps1      # código-fonte
├── dist/                # executável gerado
├── assets/              # ícones
├── scripts/             # build, release, ícone
└── tools/ps2exe-build/  # compilador PS → EXE
```

## Publicar uma nova release

1. Atualize `VERSION` (ex.: `2.0.1`).
2. Atualize `$AppVersion` em `src/limpeza.ps1`.
3. Compile e publique:

```powershell
.\scripts\publish-release.ps1
```

Ou crie a tag no Git — o workflow `.github/workflows/release.yml` compila e publica automaticamente:

```bash
git tag v2.0.1
git push origin v2.0.1
```

## Autor

Luiz Filipe Schaeffer
