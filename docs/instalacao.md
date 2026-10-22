# Guia de Instalação e Uso (`terminal-setup`)

Este documento explica os pré-requisitos, onde executar cada comando e como realizar instalações interativas, não interativas, em duas etapas (sem `sudo` para o usuário comum) ou apenas de componentes isolados no **Ubuntu 24.04 LTS (`amd64`)**.

---

## 1. Requisitos e plataformas suportadas

- **Plataforma suportada na v1:** Ubuntu 24.04 LTS (`noble`), arquitetura `amd64` (`x86_64`), em instalação nativa, máquina virtual, WSL2 ou container Docker/OCI.
- **Plataformas fora do suporte de instalação da v1:**
  - Ubuntu `arm64` (`aarch64`), outras versões do Ubuntu e Debian (bloqueados para execução efetiva até verificação dedicada de artefatos e testes).
  - Distribuições baseadas em RPM/ostree (como **Fedora / Aurora Linux**): o host Aurora pode ser usado para desenvolvimento, inspeção de plano (`--dry-run`), testes unitários isolados e execução do ambiente em container Docker Ubuntu 24.04, mas **nunca** deve receber execução efetiva de pacotes APT.
- **Dependências base do sistema:**
  - `bash` (`>= 5.2` no Ubuntu 24.04), utilitários GNU coreutils (`sha256sum`, `stat`, `mktemp`, `readlink`), `tar`, `awk`, `grep`.
  - Para execução efetiva com `--skip-system-packages`, o utilitário **`jq`** já deve estar instalado no sistema (conforme Decisão P3, `jq` é dependência base obrigatória em todos os perfis, inclusive `minimal`).
- **Limitação de compatibilidade com raízes XDG/`ZDOTDIR` em symlink:**
  - Por segurança (`ts_validate_managed_path` em `lib/backups.sh`), o instalador e o desinstalador exigem que os diretórios-raiz de gerenciamento (`$HOME`, `$ZDOTDIR`, `$XDG_CONFIG_HOME`, `$XDG_STATE_HOME` e `$XDG_DATA_HOME`) sejam diretórios reais e **não** links simbólicos na própria raiz, nem contenham componentes intermediários em symlink que escapem da árvore canônica do usuário (`readlink -f`). Caso você utilize um gerenciador de dotfiles que transforme `~/.config` inteiro ou `$ZDOTDIR` inteiro em symlink para outro diretório fora da raiz canônica, aponte a variável correspondente diretamente para o diretório canônico real antes de executar o instalador.

---

## 2. Onde executar cada comando

| Script / Comando | Quem deve executar | Onde executar |
|---|---|---|
| `bash ./install-terminal.sh ...` | **Usuário comum** (`UID != 0`) | Ubuntu 24.04 `amd64` (ou em qualquer Linux apenas com `--dry-run`, `--help` ou `--version`) |
| `bash ./doctor.sh ...` | **Usuário comum** (`UID != 0`) | Ubuntu 24.04 `amd64` (somente leitura) |
| `bash ./uninstall-terminal.sh ...` | **Usuário comum** (`UID != 0`) | Ubuntu 24.04 `amd64` |
| `bash ./scripts/install-system-packages.sh ...` | **Administrador (`root` / `sudo`)** | Exclusivamente em Ubuntu 24.04 `amd64` |
| `docker build ...` / `docker run ...` / `docker compose ...` | **Usuário do host** com acesso ao Docker | Host de desenvolvimento (ex.: Aurora Linux ou Ubuntu) na raiz do repositório |

> **Partições compartilhadas Windows/Linux (NTFS):** invoque sempre os scripts com `bash ./nome-do-script.sh`. Isso garante funcionamento mesmo quando o sistema de arquivos não preserva o bit de permissão executável (`chmod +x`).

---

## 3. Passo 1 recomendado: inspecionar o plano com `--dry-run`

Antes de aplicar qualquer alteração, execute o modo `--dry-run` como usuário comum. Ele valida todos os parâmetros e mostra exatamente quais pacotes APT, ferramentas externas, plugins Zsh e arquivos de configuração seriam afetados, **sem criar diretórios, logs, backups e sem usar rede ou `sudo`**:

```bash
# [Executar como USUÁRIO COMUM]
# Planeja a instalação do perfil developer sem modificar nada no sistema.
bash ./install-terminal.sh --profile developer --dry-run
```

### Limites do `--dry-run`
- O `--dry-run` **não verifica conectividade de rede**, disponibilidade remota do GitHub ou funcionamento de espelhos APT.
- Ele **não cria nem modifica arquivos**, portanto não testa permissões reais de escrita em subdiretórios específicos nem autentica `sudo`.

---

## 4. Instalação interativa (fluxo padrão para estações e servidores)

Em uma máquina Ubuntu 24.04 `amd64` onde o seu usuário comum possui permissão `sudo`:

```bash
# [Executar como USUÁRIO COMUM no Ubuntu 24.04 amd64]
# Instala o perfil developer de forma interativa (pergunta sobre conflitos, Git e shell).
bash ./install-terminal.sh --profile developer
```

Durante a execução interativa:
1. O plano completo é exibido e o instalador pede confirmação para iniciar;
2. Se faltarem pacotes APT do perfil, o instalador chama `sudo bash ./scripts/install-system-packages.sh --packages ...`;
3. Se já existirem arquivos como `~/.zshrc` com conteúdo diferente, a política padrão (`--on-conflict ask`) pergunta se você deseja preservá-los (`keep`) ou fazer backup e substituir (`backup-replace`);
4. Pergunta se você deseja configurar identidade Git global (`user.name` e `user.email`) e defaults globais do Git.

> **Importante sobre `--yes`:** passar `--yes` aceita apenas confirmações operacionais de baixo risco com padrão positivo (como iniciar a aplicação do plano). `--yes` **não** substitui arquivos em conflito, **não** altera sua identidade Git, **não** ativa `vi-mode` e **não** executa `chsh`.

---

## 5. Instalação não interativa (`--non-interactive`)

Para automação, provisionamento ou build de containers, use `--non-interactive`. Nesse modo, nenhum prompt (`read`, `chsh` ou `sudo` pedindo senha) é permitido, e opções não especificadas assumem padrões conservadores (`--on-conflict keep`, `--git-identity skip`, `--git-defaults keep`, `--change-shell no`):

```bash
# [Executar como USUÁRIO COMUM no Ubuntu 24.04 amd64, quando os pacotes APT já estão instalados]
bash ./install-terminal.sh \
  --profile developer \
  --non-interactive \
  --skip-system-packages \
  --git-identity skip \
  --change-shell no
```

Se desejar substituir configurações preexistentes do usuário criando backup automático em modo não interativo:

```bash
# [Executar como USUÁRIO COMUM no Ubuntu 24.04 amd64]
bash ./install-terminal.sh \
  --profile server \
  --non-interactive \
  --skip-system-packages \
  --on-conflict backup-replace
```

---

## 6. Instalação em duas etapas (quando o usuário comum não tem `sudo`)

Em servidores corporativos ou containers onde o usuário comum não possui `sudo` (ou onde `sudo -n` exige senha em modo não interativo), execute o fluxo em duas etapas:

### Etapa 1 — Administrador (`root`) instala os pacotes APT do perfil

```bash
# [Executar como ROOT ou via SUDO no Ubuntu 24.04 amd64]
sudo bash ./scripts/install-system-packages.sh --profile developer
```

### Etapa 2 — Usuário comum aplica as ferramentas externas, plugins e configurações no `$HOME`

```bash
# [Executar como USUÁRIO COMUM no Ubuntu 24.04 amd64]
bash ./install-terminal.sh --profile developer --skip-system-packages
```

---

## 7. Instalação isolada do Superfile (`--only superfile`)

Para instalar exclusivamente o gerenciador de arquivos TUI **Superfile** (`spf`) e suas dependências obrigatórias (`ca-certificates`, `curl`, `jq`), sem instalar Zsh, Starship, tmux ou plugins:

```bash
# [Executar como USUÁRIO COMUM no Ubuntu 24.04 amd64]
# 1. Inspecionar o plano isolado:
bash ./install-terminal.sh --only superfile --dry-run

# 2. Executar a instalação isolada:
bash ./install-terminal.sh --only superfile
```

Consulte [`docs/superfile.md`](superfile.md) para detalhes sobre caminhos XDG e renderização de fontes do `spf`.

---

## 8. Identidade Git como decisão opcional

Instalar o pacote `git` **nunca** altera sua identidade global automaticamente:

- **Manter intocada (padrão em `--non-interactive`):** `--git-identity skip` e `--git-defaults keep`.
- **Configurar explicitamente por linha de comando:**
  ```bash
  # [Executar como USUÁRIO COMUM no Ubuntu 24.04 amd64]
  bash ./install-terminal.sh \
    --profile developer \
    --git-identity configure \
    --git-name "Nome Sobrenome" \
    --git-email "usuario@exemplo.org" \
    --git-defaults apply
  ```
- **Privacidade:** o nome e o e-mail informados são gravados apenas no arquivo de configuração global do Git do usuário (`~/.gitconfig` ou `$GIT_CONFIG_GLOBAL`), com backup prévio se o arquivo já existia. Eles **nunca** são gravados nos arquivos de log, no manifesto JSON ou em imagens Docker.
- **Isolamento host vs. container:** configurar o Git dentro de um container descartável altera apenas `/home/dev/.gitconfig` daquele container e **não** configura o Git do sistema host.

---

## 9. Uso de arquivo de preferências (`--config`)

Nenhum arquivo `terminal.conf` é carregado implicitamente. Para usar um arquivo de preferências baseado em [`examples/terminal.conf.example`](../examples/terminal.conf.example):

```bash
# [Executar como USUÁRIO COMUM]
cp examples/terminal.conf.example /tmp/meu-terminal.conf
bash ./install-terminal.sh --config /tmp/meu-terminal.conf --dry-run
```

Consulte [`docs/parametros.md`](parametros.md) para todas as chaves aceitas e regras de precedência (`defaults < --config < CLI`).

