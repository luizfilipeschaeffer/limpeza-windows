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

Ao terminar (execução manual), é possível agendar a limpeza (1x ao dia, 1x na semana ou 1x no mês) e escolher o horário em intervalos de 3 horas (00:00 a 21:00). Na execução agendada, a limpeza roda em **silêncio** (sem janela nem mensagens), atualiza automaticamente se houver nova versão e pula o cleanmgr.

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
