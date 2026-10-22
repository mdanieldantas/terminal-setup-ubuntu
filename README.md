# terminal-setup (Ubuntu 24.04 LTS `amd64`)

Automação modular em Bash para instalação de ferramentas de terminal e configuração conservadora de ambiente de usuário no **Ubuntu 24.04 LTS (`amd64`)**, com separação estrita entre pacotes de sistema (APT via helper administrativo) e configuração de espaço do usuário (`$HOME` / diretórios XDG).

---

## 1. Escopo e matriz de suporte na v1

| Item | Status na v1 |
|---|---|
| **Plataforma alvo suportada** | **Ubuntu 24.04 LTS (`noble`), arquitetura `amd64` (`x86_64`)** |
| **Validação integrada executada** | **Em containers Docker `ubuntu:24.04` (`amd64`)** (não em VM ou servidor real com boot, `systemd` e serviços reais):<br>- **`developer`:** suíte completa de integração (`57` verificações) + suítes unitárias (`161`) + inspeção `/root` (`14`);<br>- **`minimal` e `server`:** verificações enxutas por perfil (`6` blocos por perfil) + inspeção `/root` (`14`);<br>- **Bats-core:** `4` adaptadores `@test` invocando `161` verificações internas (`shfmt=0`, `shellcheck=0`, `bats=0`) |
| **Pipeline CI (`.github/workflows/ci.yaml`)** | Criado e validado estaticamente no repositório local; **ainda não executado no GitHub Actions** (sem push remoto) |
| **Fora do suporte garantido da v1** | Ubuntu `arm64` (`aarch64`), outras versões do Ubuntu, Debian e distribuições RPM/ostree (como Fedora/Aurora Linux, usadas apenas como host de desenvolvimento/Docker ou com `--dry-run`) |
| **Fora do escopo da v1** | Configuração de SSH, UFW, Fail2ban, `unattended-upgrades`, alteração de `sudoers`, armazenamento de senhas/tokens/chaves privadas e desinstalação de pacotes APT |

> **Nota:** este projeto não anuncia uso irrestrito em produção nem suporte a plataformas ou perfis além do que foi efetivamente verificado em [`docs/matriz-de-testes.md`](docs/matriz-de-testes.md).

---

## 2. Perfis e ferramentas

| Componente | `minimal` | `developer` | `server` | Origem no Ubuntu 24.04 (`amd64`) |
|---|---|---|---|---|
| `zsh`, `git`*, `nano`, `ca-certificates`, `curl`, `jq` | **sim** | **sim** | **sim** | APT (`main`) |
| `starship` (modo `plain` por padrão) | **sim** | **sim** | **sim** | Release oficial GitHub + SHA-256 (`versions/tools.lock.json`) |
| `fzf`, `ripgrep` (`rg`), `bat` (`batcat`) | **sim** | **sim** | **sim** | APT (`universe`) |
| `fd` (`fd-find`/`fdfind`), `tmux`, `zoxide` | não | **sim** | **sim** | APT (`main` / `universe`) |
| `eza` | não | **sim** | opcional | APT (`universe`) |
| `superfile` (`spf`) | não | **sim** | opcional | Release oficial GitHub + SHA-256 (`versions/tools.lock.json`) |
| `btop` | não | opcional | **sim** | APT (`universe`) |
| `zsh-autosuggestions`, `zsh-history-substring-search` | não | **sim** | **sim** | Git com commit fixado (`versions/plugins.lock.json`) |
| `zsh-syntax-highlighting` | não | **sim** | opcional | Git com commit fixado (`versions/plugins.lock.json`) |
| `zsh-vi-mode` | opcional | opcional | opcional | Git com commit fixado (`--vi-mode`) |

*\*`git` e os plugins Zsh são omitidos com aviso claro quando `--skip-git` é informado.*

---

## 3. Comandos principais e onde executar cada um

Execute sempre `install-terminal.sh`, `doctor.sh` e `uninstall-terminal.sh` como **usuário comum** (`UID != 0`). O helper `scripts/install-system-packages.sh` é exclusivo para `root`/`sudo` no Ubuntu 24.04:

```bash
# [USUÁRIO COMUM no Ubuntu 24.04 ou host de dev]: ver plano sem modificar nada
bash ./install-terminal.sh --profile developer --dry-run

# [USUÁRIO COMUM no Ubuntu 24.04]: instalação interativa com preservação por padrão
bash ./install-terminal.sh --profile developer

# [USUÁRIO COMUM no Ubuntu 24.04]: servidor com ferramentas extras, sem alterar serviços
bash ./install-terminal.sh --profile server --include superfile

# [USUÁRIO COMUM no Ubuntu 24.04]: somente Superfile (spf) e suas dependências necessárias
bash ./install-terminal.sh --only superfile

# [USUÁRIO COMUM no Ubuntu 24.04]: diagnóstico somente leitura (texto humano ou --json)
bash ./doctor.sh --profile server

# [USUÁRIO COMUM no Ubuntu 24.04]: simular ou executar restauração baseada em manifesto
bash ./uninstall-terminal.sh --dry-run

# [HOST com Docker, na raiz do projeto]: construir imagem de trabalho Ubuntu 24.04
docker build -f docker/Dockerfile -t terminal-setup:dev .

# [HOST com Docker]: iniciar ambiente descartável como usuário 'dev', sem volume nem socket Docker
docker run --rm -it terminal-setup:dev

# [HOST com Docker]: usar o Compose localizado na subpasta docker/
docker compose -f docker/compose.yaml run --rm terminal
```

---

## 4. Documentação completa (`docs/`)

- **Manual completo do usuário (passo a passo operacional):** [`docs/manual-do-usuario.md`](docs/manual-do-usuario.md)
- **Arquitetura e fluxo interno:** [`docs/arquitetura.md`](docs/arquitetura.md)
- **Guia de instalação (interativa, não interativa, 2 etapas, Git opcional):** [`docs/instalacao.md`](docs/instalacao.md)
- **Perfis e seleção de componentes:** [`docs/perfis.md`](docs/perfis.md)
- **Parâmetros de CLI e formato `terminal.conf`:** [`docs/parametros.md`](docs/parametros.md)
- **Ambiente Docker e Docker Compose:** [`docs/docker.md`](docs/docker.md)
- **Guia do Superfile (`spf`):** [`docs/superfile.md`](docs/superfile.md)
- **Modelo de segurança, limites e hooks `TS_TEST_*`:** [`docs/seguranca.md`](docs/seguranca.md)
- **Estado XDG, backups, manifesto, `doctor.sh` e restauração:** [`docs/backup-restauracao.md`](docs/backup-restauracao.md)
- **Guia de desenvolvimento, qualidade (`ShellCheck`/`shfmt`/`Bats`) e CI:** [`docs/desenvolvimento.md`](docs/desenvolvimento.md)
- **Matriz de testes e cobertura real:** [`docs/matriz-de-testes.md`](docs/matriz-de-testes.md)
- **Fontes oficiais, versões e checksums verificados:** [`docs/fontes-e-versoes.md`](docs/fontes-e-versoes.md)
- **Solução de problemas (`troubleshooting`):** [`docs/solucao-de-problemas.md`](docs/solucao-de-problemas.md)
- **Suítes de testes (`tests/`):** [`tests/README.md`](tests/README.md)
- **Histórico de alterações:** [`CHANGELOG.md`](CHANGELOG.md)

---

## 5. Licença

A definição do titular de direitos autorais e a confirmação final da licença (proposta no guia: **MIT** para o código original do projeto, mantendo as licenças próprias de cada ferramenta e plugin de terceiros) aguardam confirmação do responsável antes da geração do arquivo `LICENSE`.
