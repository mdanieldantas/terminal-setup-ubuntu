# Superfile (`spf`) no `terminal-setup`

O **Superfile** (<https://superfile.dev/>) é um gerenciador de arquivos TUI moderno para terminal, cujo binário e comando oficial é **`spf`**.

> **Onde executar:** a instalação e o uso do `spf` ocorrem sempre como **usuário comum** (sem `sudo`).

---

## 1. Presença nos perfis e instalação avulsa

Na matriz de perfis do `terminal-setup` (Ubuntu 24.04 LTS `amd64`):

- **Perfil `developer`:** incluído por padrão.
- **Perfil `server`:** opcional. Nunca pressupomos que uma ferramenta TUI é incompatível com servidores apenas por ser visual; você pode incluí-lo explicitamente sem alterar nenhum serviço do servidor:
  ```bash
  # Usuário comum no Ubuntu 24.04: planejar servidor com Superfile
  bash ./install-terminal.sh --profile server --include superfile --dry-run
  ```
- **Perfil `minimal`:** não incluído por padrão, mas pode ser adicionado com `--include superfile`.
- **Instalação somente do Superfile (`--only`):** instala apenas o Superfile e suas dependências obrigatórias (`ca-certificates`, `curl`, `jq`), sem instalar Zsh, Starship, tmux ou plugins:
  ```bash
  # Usuário comum no Ubuntu 24.04: planejar somente Superfile e dependências
  bash ./install-terminal.sh --only superfile --dry-run
  ```

---

## 2. Método de instalação seguro (sem `curl | bash` e sem `sudo`)

Em vez de executar o script remoto `https://superfile.dev/install.sh` (que tenta escrever em `/usr/local/bin` com `sudo`), o módulo `lib/tools.sh`:

1. Lê a versão (`1.6.0`), a URL oficial do tarball (`superfile-linux-v1.6.0-amd64.tar.gz`) e o checksum SHA-256 registrado em `versions/tools.lock.json`;
2. Faz o download via HTTPS para um diretório temporário seguro em `/tmp`;
3. Verifica o hash SHA-256 (`sha256sum`) e inspeciona o arquivo `.tar.gz` contra caminhos inseguros antes de extrair;
4. Instala o binário `spf` em `${XDG_DATA_HOME:-$HOME/.local/share}/terminal-setup/tools/superfile/1.6.0/spf` e cria um link simbólico controlado em `${HOME}/.local/bin/spf` (registrados no manifesto JSON para permitir desinstalação limpa);
5. Verifica a execução de `spf --version` com `~/.local/bin` no `PATH`.

---

## 3. Caminhos de configuração e política conservadora

Conforme a documentação oficial (<https://superfile.dev/configure/config-file-path/>) e a seção 10 do guia de implementação:

- Este projeto **não cria um arquivo `config.toml` fictício** para o Superfile.
- Na primeira vez que você executar `spf` interativamente, o próprio Superfile criará sua estrutura padrão nos diretórios XDG do usuário:
  - Configuração principal: `${XDG_CONFIG_HOME:-$HOME/.config}/superfile/config.toml`
  - Atalhos de teclado: `${XDG_CONFIG_HOME:-$HOME/.config}/superfile/hotkeys.toml`
  - Temas: `${XDG_CONFIG_HOME:-$HOME/.config}/superfile/theme/`
- Para consultar os caminhos exatos usados pela sua versão do `spf`:
  ```bash
  # Usuário comum: listar caminhos de configuração e estado do Superfile
  spf path-list
  ```

---

## 4. Fontes (Nerd Font) e renderização via SSH

Conforme a página de solução de problemas oficial (<https://superfile.dev/troubleshooting/>):

1. **Onde configurar a Nerd Font:** a fonte visual é processada pelo **emulador de terminal do computador cliente** (por exemplo, Konsole no Aurora Linux ou Windows Terminal no Windows/WSL), e **não** no servidor Ubuntu acessado por SSH.
2. **Uso sem Nerd Font:** se o seu terminal cliente não estiver configurado com uma Nerd Font e você observar símbolos substituídos por quadrados (`□` ou `?`), abra o arquivo `${XDG_CONFIG_HOME:-$HOME/.config}/superfile/config.toml` (gerado após a primeira execução do `spf`) e ajuste:
   ```toml
   nerdfont = false
   ```
3. **Alinhamento de bordas em sessões SSH/UTF-8:** caso as bordas da interface fiquem desalinhadas em determinados terminais, defina antes de abrir o `spf`:
   ```bash
   export RUNEWIDTH_EASTASIAN=0
   ```
