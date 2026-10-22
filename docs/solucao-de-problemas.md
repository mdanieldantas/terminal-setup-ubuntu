# Solução de Problemas (`troubleshooting`)

Este documento reúne diagnósticos e soluções para os problemas mais comuns ao utilizar o `terminal-setup` no **Ubuntu 24.04 LTS (`amd64`)** ou via container Docker.

---

## 1. Diagnóstico inicial com `doctor.sh`

Sempre que notar algum comportamento inesperado, comece executando o diagnóstico somente leitura como **usuário comum**:

```bash
# [Executar como USUÁRIO COMUM]
bash ./doctor.sh --profile developer
```

Para inspecionar o resultado detalhado em JSON (requer `jq`):

```bash
# [Executar como USUÁRIO COMUM]
bash ./doctor.sh --profile developer --json
```

---

## 2. Problemas comuns e soluções

### 2.1. O perfil Zsh do projeto não foi ativado após a instalação (`kept_existing`)

- **Sintoma:** você abriu o Zsh, mas o prompt Starship, os plugins ou os atalhos não apareceram.
- **Causa provável:** já existia um arquivo `~/.zshrc` (ou `~/.zshenv`) diferente no seu `HOME` e a instalação usou a política conservadora `--on-conflict keep` (padrão do modo `--non-interactive` ou quando você escolheu `[k]` no prompt interativo).
- **Solução:** execute o instalador novamente autorizando o backup e a substituição dos arquivos em conflito:
  ```bash
  # [Executar como USUÁRIO COMUM no Ubuntu 24.04 amd64]
  bash ./install-terminal.sh --profile developer --on-conflict backup-replace
  ```
  O seu `~/.zshrc` antigo ficará salvo em `${XDG_STATE_HOME:-$HOME/.local/state}/terminal-setup/backups/<install-id>/files/...`.

---

### 2.2. Erro de plataforma não suportada (`código 3`)

- **Sintoma:**
  ```text
  [ERRO] Execucao efetiva bloqueada: Ambiente atual (...) fora do alvo de instalacao da v1 (Ubuntu 24.04 LTS amd64).
  ```
- **Causa:** você tentou executar a instalação real em outra distribuição (como Fedora/Aurora Linux ou Debian), em outra versão do Ubuntu ou em arquitetura `arm64`.
- **Solução:**
  - Se você está no host de desenvolvimento (como Aurora Linux) e quer apenas inspecionar o plano, adicione `--dry-run`:
    ```bash
    # [Executar como USUÁRIO COMUM]
    bash ./install-terminal.sh --profile developer --dry-run
    ```
  - Se você quer usar o ambiente completo a partir de outro Linux, construa e execute o container Ubuntu 24.04 conforme [`docs/docker.md`](docker.md).

---

### 2.3. Erro ao executar como `root` (`código 4`)

- **Sintoma:**
  ```text
  [ERRO] O instalador principal nao deve ser executado como root (UID 0).
  ```
- **Causa:** você executou `sudo bash ./install-terminal.sh` ou estava logado diretamente como `root`.
- **Solução:** execute `install-terminal.sh`, `doctor.sh` e `uninstall-terminal.sh` **sem `sudo`**, usando sua conta de usuário comum. Se precisar instalar os pacotes APT separadamente como `root`, use apenas o helper administrativo:
  ```bash
  # [Executar como ROOT ou via SUDO no Ubuntu 24.04 amd64]
  sudo bash ./scripts/install-system-packages.sh --profile developer
  ```

---

### 2.4. Falha em `--non-interactive` porque `sudo -n` exige senha (`código 4`)

- **Sintoma:**
  ```text
  [ERRO] Modo --non-interactive ativo e ha pacotes APT ausentes (...), mas 'sudo -n' exige senha.
  ```
- **Causa:** o modo `--non-interactive` nunca trava aguardando digitação de senha de `sudo`.
- **Solução:** instale os pacotes APT previamente como administrador e depois execute o instalador de usuário com `--skip-system-packages`:
  ```bash
  # 1. [Executar como ROOT / SUDO interativo]
  sudo bash ./scripts/install-system-packages.sh --profile developer

  # 2. [Executar como USUÁRIO COMUM]
  bash ./install-terminal.sh --profile developer --skip-system-packages --non-interactive
  ```

---

### 2.5. Caracteres estranhos ou quadrados (`□` / `?`) no Starship ou no Superfile (`spf`)

- **Sintoma:** ícones aparecem quebrados no terminal, especialmente em sessões SSH.
- **Causa:** o emulador de terminal da sua **máquina cliente** (por exemplo, Konsole no Aurora Linux ou Windows Terminal) não está configurado com uma Nerd Font, e você ativou `--icons nerd` ou abriu o Superfile (`spf`) com `nerdfont = true`.
- **Importante:** instalar fontes no servidor SSH remoto **não** corrige a renderização de fontes do terminal local.
- **Solução:**
  1. Para o Starship, use o modo padrão em texto puro (`--icons plain`):
     ```bash
     # [Executar como USUÁRIO COMUM no Ubuntu 24.04 amd64]
     bash ./install-terminal.sh --profile developer --icons plain --on-conflict backup-replace
     ```
  2. Para o Superfile (`spf`), consulte [`docs/superfile.md`](superfile.md) para definir `nerdfont = false` em `${XDG_CONFIG_HOME:-$HOME/.config}/superfile/config.toml` ou instale uma Nerd Font no emulador de terminal do computador cliente.

---

### 2.6. `docker exec -it <container> bash` não carrega o prompt nem os plugins Zsh

- **Sintoma:** ao rodar `docker exec -it <container> bash`, o terminal abre em Bash simples em vez do Zsh configurado.
- **Causa:** `docker exec` inicia exatamente o comando informado (`bash`), ignorando o shell de login registrado em `/etc/passwd`.
- **Solução:** especifique `/usr/bin/zsh -l` ao usar `docker exec`:
  ```bash
  # [Executar no HOST contra um container em execução]
  docker exec -it <nome-ou-id-do-container> /usr/bin/zsh -l
  ```

---

### 2.7. Lock de execução concorrente preso após interrupção abrupta (`SIGKILL`)

- **Sintoma:**
  ```text
  [ERRO] Outra execucao do terminal-setup parece estar ativa (lock em '.../.local/state/terminal-setup/lock', PID '...').
  ```
- **Causa:** uma execução anterior foi encerrada com `kill -9` (`SIGKILL`) ou queda de energia antes que o `trap EXIT` pudesse remover o diretório de lock.
- **Solução:** verifique com `ps -p <PID>` que não há processo `install-terminal.sh` ou `uninstall-terminal.sh` ativo e remova apenas o diretório de lock:
  ```bash
  # [Executar como USUÁRIO COMUM após confirmar que não há processo ativo]
  rm -f "${XDG_STATE_HOME:-$HOME/.local/state}/terminal-setup/lock/pid"
  rmdir "${XDG_STATE_HOME:-$HOME/.local/state}/terminal-setup/lock"
  ```

