# terminal-setup (Ubuntu 24.04 LTS `amd64`)

Projeto modular em Bash para instalação de ferramentas de terminal e configuração conservadora de ambiente de usuário no **Ubuntu 24.04 LTS (`amd64`)**, com separação estrita entre pacotes de sistema (APT) e configuração de usuário no `HOME`.

---

## Status atual do repositório (Fase 1 concluída)

Este repositório é desenvolvido em etapas com portões de revisão:

- **Fase 0 (Levantamento):** concluída.
- **Fase 1 (Contrato, argumentos, perfis e planejamento `--dry-run`):** **implementada e testada localmente**.
  - Disponível agora: validação completa dos 21 parâmetros de CLI, parser seguro de `terminal.conf` (sem `source`/`eval`), definição dos perfis (`minimal`, `developer`, `server`), preflight somente leitura de plataforma/privilégios e exibição detalhada do plano em modo `--dry-run`, `--help` e `--version`.
- **Fase 2 (Estado XDG, backups, manifesto, configuração de usuário, `doctor.sh` e `uninstall-terminal.sh`):** planejada (ainda não implementada).
- **Fase 3 (Helper APT `scripts/install-system-packages.sh`, downloads verificados de Starship/Superfile e clone de plugins Zsh):** planejada (ainda não implementada).
- **Fase 4 (`docker/Dockerfile` e `docker/compose.yaml`):** planejada (ainda não implementada).
- **Fase 5 (CI e documentação final completa):** planejada (ainda não implementada).

> **Importante:** na Fase 1, chamadas sem `--dry-run` validam todos os parâmetros e a plataforma, exibem o plano e encerram com código `5` informando que a escrita e instalação efetiva pertencem às Fases 2 e 3.

---

## Escopo e plataforma suportada na v1

- **Suporte alvo da v1:** Ubuntu 24.04 LTS (`noble`), arquitetura `amd64` (`x86_64`).
- **Fora do suporte garantido da v1:** Ubuntu `arm64` (até validação completa de artefatos e testes), outras versões do Ubuntu, Debian e distribuições baseadas em RPM/ostree (como Fedora/Aurora, que podem ser usadas apenas como ambiente de desenvolvimento com `--dry-run` ou containers).
- **Fora do escopo da v1:** configuração de SSH, UFW, Fail2ban, `unattended-upgrades`, alteração de `sudoers`, armazenamento de senhas/tokens/chaves privadas e remoção de pacotes APT.

---

## Perfis de ferramentas

| Componente | `minimal` | `developer` | `server` | Origem prevista no Ubuntu 24.04 |
|---|---|---|---|---|
| `zsh`, `git`, `nano`, `ca-certificates`, `curl`, `jq` | sim | sim | sim | APT (`main`) |
| `starship` (modo texto `plain` por padrão) | sim | sim | sim | Release oficial GitHub + SHA-256 |
| `fzf`, `ripgrep` (`rg`), `bat` (`batcat`) | sim | sim | sim | APT (`universe`) |
| `fd` (`fd-find`/`fdfind`), `tmux`, `zoxide` | não | sim | sim | APT (`main`/`universe`) |
| `eza` | não | sim | opcional | APT (`universe`) |
| `superfile` (`spf`) | não | sim | opcional | Release oficial GitHub + SHA-256 |
| `btop` | não | opcional | sim | APT (`universe`) |
| `zsh-autosuggestions`, `zsh-history-substring-search` | não | sim | sim | Git com commit fixado |
| `zsh-syntax-highlighting` | não | sim | opcional | Git com commit fixado |
| `zsh-vi-mode` | opcional | opcional | opcional | Git com commit fixado (`--vi-mode`) |

---

## Como usar os recursos disponíveis na Fase 1

Execute todos os comandos como **usuário comum** (nunca como `root`), invocando explicitamente o interpretador `bash`:

```bash
# Usuário comum: consultar a ajuda completa (sem escrita em disco)
bash ./install-terminal.sh --help

# Usuário comum: consultar a versão do projeto (sem escrita em disco)
bash ./install-terminal.sh --version

# Usuário comum: inspecionar o plano do perfil minimal (padrão) em modo dry-run
bash ./install-terminal.sh --dry-run

# Usuário comum: inspecionar o plano do perfil developer em modo dry-run
bash ./install-terminal.sh --profile developer --dry-run

# Usuário comum: inspecionar o plano do perfil server incluindo Superfile
bash ./install-terminal.sh --profile server --include superfile --dry-run

# Usuário comum: planejar apenas Superfile e suas dependências obrigatórias
bash ./install-terminal.sh --only superfile --dry-run

# Usuário comum: planejar usando um arquivo de preferências explícito
bash ./install-terminal.sh --config ./examples/terminal.conf.example --dry-run
```

---

## Documentação e testes da Fase 1

- Contrato detalhado de parâmetros e arquivo de configuração: [`docs/parametros.md`](docs/parametros.md)
- Exemplo de arquivo de preferências: [`examples/terminal.conf.example`](examples/terminal.conf.example)
- Suíte de testes unitários do contrato da Fase 1 (executa em diretório temporário isolado em `/tmp`, sem rede e sem `sudo`):

```bash
# Usuário comum: validar sintaxe de cada script Bash e executar testes da Fase 1
bash ./tests/unit/test_phase1_contract.sh
```

