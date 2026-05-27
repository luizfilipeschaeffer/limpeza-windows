# Limpeza Avançada do Windows

Ferramenta de manutenção e liberação de espaço no disco C: (TEMP, Prefetch, Windows Installer, DISM, cleanmgr).

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

Ao terminar (execução manual), é possível agendar a limpeza (1x ao dia, 1x na semana ou 1x no mês) e escolher o horário em intervalos de 3 horas (00:00 a 21:00). Na execução agendada, atualizações são aplicadas automaticamente, sem prompt.

## Baixar a última versão

1. Abra [Releases](https://github.com/luizfilipeschaeffer/limpeza-windows/releases/latest).
2. Baixe `LimpezaWindows.exe`.
3. Execute `bin\limpeza.bat` ou o `.exe` diretamente.

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
