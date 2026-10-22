# Perfis e seleção de componentes (`terminal-setup`)

Os perfis do `terminal-setup` são **conjuntos de ferramentas e configurações de terminal**, não níveis de segurança ou hardening de sistema. Nenhum perfil altera SSH, firewall (UFW), Fail2ban, `sudoers` ou serviços do sistema operacional.

> **Onde executar:** todos os comandos abaixo devem ser executados como **usuário comum**.

---

## 1. Matriz de componentes por perfil (Ubuntu 24.04 LTS `amd64`)

| Componente | Comando / Recurso | `minimal` | `developer` | `server` | Origem |
|---|---|---|---|---|---|
| `zsh` | `zsh` | **sim** | **sim** | **sim** | APT (`main`) |
| `git` | `git` *(salvo `--skip-git`)* | **sim** | **sim** | **sim** | APT (`main`) |
| `nano` | `nano` | **sim** | **sim** | **sim** | APT (`main`) |
| `ca-certificates` | Certificados TLS (`/etc/ssl/certs`) | **sim** | **sim** | **sim** | APT (`main`) |
| `curl` | `curl` | **sim** | **sim** | **sim** | APT (`main`) |
| `jq` | `jq` *(base obrigatória — Decisão P3)* | **sim** | **sim** | **sim** | APT (`main`) |
| `starship` | `starship` (modo `plain` por padrão) | **sim** | **sim** | **sim** | Release oficial GitHub + SHA-256 |
| `fzf` | `fzf` | **sim** | **sim** | **sim** | APT (`universe`) |
| `ripgrep` | `rg` | **sim** | **sim** | **sim** | APT (`universe`) |
| `bat` | `batcat` (+ link opcional `~/.local/bin/bat`) | **sim** | **sim** | **sim** | APT (`universe`) |
| `fd` | `fdfind` (+ link opcional `~/.local/bin/fd`) | não | **sim** | **sim** | APT (`universe`, pacote `fd-find`) |
| `tmux` | `tmux` | não | **sim** | **sim** | APT (`main`) |
| `zoxide` | `zoxide` *(Decisão P1)* | não | **sim** | **sim** | APT (`universe`) |
| `eza` | `eza` *(Decisão P1)* | não | **sim** | opcional | APT (`universe`) |
| `superfile` | `spf` | não | **sim** | opcional | Release oficial GitHub + SHA-256 |
| `btop` | `btop` | não | opcional | **sim** | APT (`universe`) |
| `zsh-autosuggestions` | Plugin Zsh | não | **sim** | **sim** | Git com commit fixado (Decisão P2) |
| `zsh-history-substring-search` | Plugin Zsh | não | **sim** | **sim** | Git com commit fixado (Decisão P2) |
| `zsh-syntax-highlighting` | Plugin Zsh | não | **sim** | opcional | Git com commit fixado (Decisão P2) |
| `zsh-vi-mode` | Plugin Zsh (`--vi-mode`) | opcional | opcional | opcional | Git com commit fixado (Decisão P2) |

---

## 2. Descrição de cada perfil

### 2.1 `minimal` (padrão)
Voltado para máquinas, containers ou ambientes onde se deseja apenas o núcleo essencial: Zsh configurado, Git, Nano, `jq`, prompt Starship em modo texto puro (`plain.toml`, sem exigir Nerd Font) e o trio básico de busca/inspeção (`fzf`, `ripgrep`, `bat`), sem clonar plugins Zsh por padrão.

```bash
# Usuário comum: inspecionar o plano do perfil minimal
bash ./install-terminal.sh --profile minimal --dry-run
```

### 2.2 `developer`
Voltado para estações de trabalho, VMs de desenvolvimento, WSL e containers de desenvolvimento interativo. Inclui todas as ferramentas do `minimal` mais `fd`, `tmux`, `zoxide`, `eza`, `superfile` (`spf`) e os três plugins Zsh de produtividade (`zsh-autosuggestions`, `zsh-syntax-highlighting`, `zsh-history-substring-search`). `btop` e `zsh-vi-mode` ficam disponíveis como opcionais.

```bash
# Usuário comum: inspecionar o plano do perfil developer
bash ./install-terminal.sh --profile developer --dry-run
```

### 2.3 `server`
Voltado para administração interativa de servidores Ubuntu. Inclui `fd`, `tmux`, `zoxide`, `btop` e os plugins `zsh-autosuggestions` e `zsh-history-substring-search`. Mantém `eza`, `superfile` (`spf`), `zsh-syntax-highlighting` e `zsh-vi-mode` como opcionais que podem ser habilitados explicitamente com `--include`.

```bash
# Usuário comum: servidor incluindo Superfile e eza explicitamente
bash ./install-terminal.sh --profile server --include superfile,eza --dry-run
```

---

## 3. Personalizando a seleção (`--include`, `--exclude`, `--only`, `--skip-git`)

1. **Incluir componentes extras (`--include`):**
   ```bash
   bash ./install-terminal.sh --profile minimal --include tmux,btop --dry-run
   ```
2. **Excluir componentes não obrigatórios do perfil (`--exclude`):**
   ```bash
   bash ./install-terminal.sh --profile developer --exclude superfile,eza --dry-run
   ```
   *(Nota: componentes base obrigatórios como `zsh`, `nano`, `ca-certificates`, `curl` e `jq` não podem ser excluídos via `--exclude`.)*
3. **Instalar apenas componentes específicos e suas dependências (`--only`):**
   Substitui o perfil inteiro pelos itens listados e resolve automaticamente as dependências obrigatórias:
   ```bash
   bash ./install-terminal.sh --only superfile --dry-run
   ```
4. **Omitir Git e plugins dependentes (`--skip-git`):**
   ```bash
   bash ./install-terminal.sh --profile developer --skip-git --dry-run
   ```
   Quando `--skip-git` é usado com um perfil, `git` e os plugins Zsh são omitidos automaticamente com um aviso claro no plano.
