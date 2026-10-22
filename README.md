# terminal-setup (Ubuntu 24.04 LTS `amd64`)

Projeto modular em Bash para instalação de ferramentas de terminal e configuração conservadora de ambiente de usuário no **Ubuntu 24.04 LTS (`amd64`)**, com separação estrita entre pacotes de sistema (APT) e configuração de usuário no `HOME`.

---

## Status atual do repositório (Fase 3 concluída)

Este repositório é desenvolvido em etapas com portões de revisão:

- **Fase 0 (Levantamento):** concluída.
- **Fase 1 (Contrato, argumentos, perfis e planejamento `--dry-run`):** implementada e testada localmente.
- **Fase 2 (Estado XDG, backups, manifesto JSON via `jq`, configuração de usuário Zsh/Starship/tmux/Git, `doctor.sh` e `uninstall-terminal.sh`):** implementada e testada localmente em sandbox isolado (`/tmp`).
- **Fase 3 (Helper APT `scripts/install-system-packages.sh`, locks JSON e instaladores de ferramentas externas Starship/Superfile e plugins Zsh via Git):** **implementada e testada localmente com mocks em sandbox isolado (`/tmp`)**.
  - Verificação de artefatos e metadados em diretório temporário: hashes SHA-256 de Starship `v1.27.0` e Superfile `v1.6.0` conferidos contra downloads reais (`sha256sum --check --strict`), caminhos internos listados via `tar -tzf` (sem extração), e tags dos 4 plugins Zsh resolvidas até os commits registrados via API do GitHub.
  - Pendência registrada: execução de `ts_validate_tar_gz_archive` sobre os tarballs reais, extração, localização efetiva e execução dos binários, fetch Git real dos plugins e execução integrada em container Ubuntu 24.04 permanecem pendentes de execução na Fase 4.
- **Fase 4 (`docker/Dockerfile`, `docker/compose.yaml`, `.dockerignore`, `docs/docker.md` e suíte de integração Ubuntu 24.04):** **arquivos preparados; execução de `docker build` / containers aguarda autorização explícita**.
- **Fase 5 (CI e documentação final completa):** planejada (ainda não implementada).

---

## Escopo e plataforma suportada na v1

- **Suporte alvo da v1:** Ubuntu 24.04 LTS (`noble`), arquitetura `amd64` (`x86_64`).
- **Fora do suporte garantido da v1:** Ubuntu `arm64` (até validação completa de artefatos e testes), outras versões do Ubuntu, Debian e distribuições baseadas em RPM/ostree (como Fedora/Aurora, que podem ser usadas apenas como ambiente de desenvolvimento com `--dry-run` ou containers).
- **Fora do escopo da v1:** configuração de SSH, UFW, Fail2ban, `unattended-upgrades`, alteração de `sudoers`, armazenamento de senhas/tokens/chaves privadas e remoção de pacotes APT.

---

## Perfis de ferramentas

| Componente | `minimal` | `developer` | `server` | Origem no Ubuntu 24.04 |
|---|---|---|---|---|
| `zsh`, `git`, `nano`, `ca-certificates`, `curl`, `jq` | sim | sim | sim | APT (`main`) |
| `starship` (modo texto `plain` por padrão) | sim | sim | sim | Release oficial GitHub + SHA-256 (`versions/tools.lock.json`) |
| `fzf`, `ripgrep` (`rg`), `bat` (`batcat`) | sim | sim | sim | APT (`universe`) |
| `fd` (`fd-find`/`fdfind`), `tmux`, `zoxide` | não | sim | sim | APT (`main`/`universe`) |
| `eza` | não | sim | opcional | APT (`universe`) |
| `superfile` (`spf`) | não | sim | opcional | Release oficial GitHub + SHA-256 (`versions/tools.lock.json`) |
| `btop` | não | opcional | sim | APT (`universe`) |
| `zsh-autosuggestions`, `zsh-history-substring-search` | não | sim | sim | Git com commit fixado (`versions/plugins.lock.json`) |
| `zsh-syntax-highlighting` | não | sim | opcional | Git com commit fixado (`versions/plugins.lock.json`) |
| `zsh-vi-mode` | opcional | opcional | opcional | Git com commit fixado (`--vi-mode`) |

---

## Como usar os recursos disponíveis (Fases 1 a 3)

Execute o instalador principal, o `doctor.sh` e o `uninstall-terminal.sh` sempre como **usuário comum** (nunca como `root`). O helper `scripts/install-system-packages.sh` é exclusivo para `root` (ou chamado via `sudo` pelo instalador em máquina Ubuntu 24.04):

```bash
# Usuário comum: inspecionar o plano do perfil developer em modo dry-run (sem escrita e sem rede)
bash ./install-terminal.sh --profile developer --dry-run

# Usuário comum: planejar somente Superfile e suas dependências obrigatórias
bash ./install-terminal.sh --only superfile --dry-run

# Administrador (root) em Ubuntu 24.04: validar pacotes APT do perfil server em modo dry-run
sudo bash ./scripts/install-system-packages.sh --profile server --dry-run

# Usuário comum: diagnóstico somente leitura (texto humano ou JSON via jq)
bash ./doctor.sh --profile developer
bash ./doctor.sh --profile minimal --json

# Usuário comum: simular ou executar restauração/desinstalação baseada em manifesto
bash ./uninstall-terminal.sh --dry-run
```

---

## Documentação e testes (Fases 1 a 3)

- Contrato de parâmetros e arquivo de configuração: [`docs/parametros.md`](docs/parametros.md)
- Perfis e seleção de componentes: [`docs/perfis.md`](docs/perfis.md)
- Fontes oficiais, versões, checksums e limites: [`docs/fontes-e-versoes.md`](docs/fontes-e-versoes.md)
- Guia do Superfile (`spf`): [`docs/superfile.md`](docs/superfile.md)
- Estado XDG, backups, manifesto, diagnóstico e restauração: [`docs/backup-restauracao.md`](docs/backup-restauracao.md)
- Exemplo de arquivo de preferências: [`examples/terminal.conf.example`](examples/terminal.conf.example)
- Suítes de testes automatizados (executam exclusivamente em diretórios temporários isolados em `/tmp`, sem tocar no `HOME` real, sem rede e sem `sudo` real):

```bash
# Usuário comum: executar as 3 suítes de testes (Fases 1, 2 e 3)
bash ./tests/unit/test_phase1_contract.sh
bash ./tests/unit/test_phase2_state_and_reversibility.sh
bash ./tests/unit/test_phase3_packages_tools_plugins.sh
```
