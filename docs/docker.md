# Ambiente em Container — Docker e Docker Compose (`Ubuntu 24.04 LTS amd64`)

Este documento descreve a arquitetura, as garantias de isolamento e os comandos de uso do ambiente em container do projeto `terminal-setup`, em conformidade com as Seções 12, 14, 15 e 17 do guia de implementação.

---

## 1. Visão geral e arquitetura da imagem

Os arquivos de container do projeto estão organizados em:

- [`.dockerignore`](../.dockerignore) (na raiz do repositório): controla o contexto enviado ao daemon Docker.
- [`docker/Dockerfile`](../docker/Dockerfile): definição reprodutível da imagem baseada em `ubuntu:24.04`.
- [`docker/compose.yaml`](../docker/compose.yaml): especificação moderna do Docker Compose (sem campo legado `version`) com o serviço `terminal`.

### Etapas do build (`docker/Dockerfile`)

1. **Base oficial (`FROM ubuntu:24.04`)**:
   - Utiliza a imagem oficial do Ubuntu 24.04 LTS (`noble`).
   - Caso um digest SHA-256 específico da imagem base seja adotado em ambiente corporativo ou CI, ele deve ser obtido de uma inspeção real (`docker buildx imagetools inspect` ou `docker image inspect`) e nunca inventado.
2. **Etapa administrativa (`root`, única camada `RUN`)**:
   - Executa `bash /opt/terminal-setup/scripts/install-system-packages.sh --profile "${PROFILE}"`, que combina `apt-get update -y` e `apt-get install -y --no-install-recommends` apenas para os pacotes da allowlist do perfil selecionado (`developer` por padrão).
   - Remove imediatamente `/var/lib/apt/lists/*` e arquivos `.deb` em cache na mesma camada `RUN`.
   - **Não instala `sudo`** e **não configura `NOPASSWD:ALL`**.
   - Cria o grupo e o usuário não-root `dev` (`ARG USERNAME=dev`) validando colisões de UID/GID (`getent group` e `getent passwd`), pois a imagem oficial `ubuntu:24.04` já possui o usuário `ubuntu` no UID/GID `1000`. Quando o UID/GID `1000` está ocupado, o `groupadd`/`useradd` aloca automaticamente o próximo UID/GID livre de usuário comum (por exemplo, `1001`).
   - Bloqueia a autenticação por senha da conta `dev` (`passwd -l` / `usermod -L`), sem definir senhas fracas de exemplo.
   - Define `/usr/bin/zsh` como shell de login no `useradd` (evitando `chsh` durante o build) e transfere a propriedade de `/home/dev` e `/opt/terminal-setup` para `dev:dev`.
3. **Transição para usuário não-root (`USER dev`)**:
   - Define `USER dev`, `WORKDIR /home/dev`, `HOME=/home/dev`, `USER=dev`, `SHELL=/usr/bin/zsh` e inclui `/home/dev/.local/bin` no `PATH`.
   - Executa o instalador de usuário sem privilégios administrativos e sem interação:
     ```bash
     bash /opt/terminal-setup/install-terminal.sh \
       --profile "${PROFILE}" \
       --non-interactive \
       --skip-system-packages \
       --git-identity skip \
       --change-shell no
     ```
   - Todas as ferramentas de espaço do usuário (`starship` e `spf` em `/home/dev/.local/bin`), plugins Zsh (`/home/dev/.local/share/terminal-setup/plugins`), dotfiles (`/home/dev/.zshenv`, `/home/dev/.zshrc`, `/home/dev/.config/...`) e manifestos (`/home/dev/.local/state/terminal-setup/manifests`) são gravados exclusivamente em `/home/dev`, nunca em `/root`.
4. **Comando padrão (`CMD ["/usr/bin/zsh", "-l"]`)**:
   - Inicia o Zsh como shell de login do usuário `dev`.

---

## 2. Segurança, privacidade e `.dockerignore`

- **Sem identidade pessoal na imagem**: o build executa `--git-identity skip`, garantindo que `user.name`, `user.email`, tokens ou chaves SSH privadas nunca sejam gravados nas camadas da imagem. A configuração global do Git reside no perfil de cada usuário e uma alteração feita dentro de um container descartável não configura automaticamente o Git do host.
- **Proteção de contexto (`.dockerignore`)**:
  - Exclui `.git/`, `.github/`, `terminal.conf` local da raiz, `*.log`, `*.bak`, `backups/`, `manifests/`, `tmp/`, `.env*`, `*.pem`, `*.key`, `*.secret`, `*id_rsa*` e `*id_ed25519*`.
  - Preserva explicitamente os arquivos necessários ao funcionamento do instalador (`!examples/terminal.conf.example`, `!profiles/*.conf` e `!config/tmux/tmux.conf`).
- **Isolamento do container em execução (`docker/compose.yaml`)**:
  - Não usa `privileged: true`.
  - Não usa `network_mode: host` nem publica portas (`ports`).
  - Não monta `/var/run/docker.sock`.
  - Não monta volumes do host por padrão.
- **Reprodutibilidade vs. `docker commit`**:
  - Não utilize `docker commit` como método principal de distribuição ou atualização do ambiente. Qualquer ajuste permanente deve ser refletido no [`docker/Dockerfile`](../docker/Dockerfile), nos perfis em `profiles/*.conf` e nos arquivos de lock em `versions/*.lock.json`.

---

## 3. Comandos de build e execução

> **Nota sobre onde executar**: todos os comandos `docker build`, `docker run` e `docker compose` abaixo devem ser executados **no terminal do sistema host** (a partir da raiz do repositório `terminal-setup-ubuntu`), utilizando uma conta que já possua acesso ao daemon Docker.

### 3.1. Construir a imagem (`host`)

Na raiz do repositório:

```bash
# [Executar no HOST, na raiz do projeto]
# Constrói a imagem terminal-setup:dev com o perfil padrão (developer).
docker build -f docker/Dockerfile -t terminal-setup:dev .
```

Para construir com outro perfil (`minimal` ou `server`):

```bash
# [Executar no HOST, na raiz do projeto]
# Constrói a imagem usando o perfil server.
docker build -f docker/Dockerfile --build-arg PROFILE=server -t terminal-setup:server .
```

### 3.2. Iniciar container interativo descartável (`host`)

```bash
# [Executar no HOST]
# Inicia um container interativo descartável (--rm) como usuário 'dev',
# sem montar volumes do host e sem expor o socket Docker.
docker run --rm -it terminal-setup:dev
```

### 3.3. Usar via Docker Compose (`host`)

O arquivo [`docker/compose.yaml`](../docker/compose.yaml) fica no subdiretório `docker/` e define `build.context: ..` (raiz do repositório) e o serviço `terminal`:

```bash
# [Executar no HOST, na raiz do projeto]
# Constrói a imagem (se necessário) via Docker Compose.
docker compose -f docker/compose.yaml build

# [Executar no HOST, na raiz do projeto]
# Inicia uma sessão interativa descartável do serviço 'terminal' como usuário 'dev'.
docker compose -f docker/compose.yaml run --rm terminal
```

### 3.4. Executar diagnóstico ou suíte de integração dentro do container (`usuário dev no container`)

Dentro do container (ou disparado a partir do host com `docker run --rm`):

```bash
# [Executar no HOST para rodar como usuário 'dev' dentro do container]
# Executa o diagnóstico somente leitura do perfil developer.
docker run --rm terminal-setup:dev bash /opt/terminal-setup/doctor.sh --profile developer

# [Executar no HOST para rodar como usuário 'dev' dentro do container]
# Executa a suíte automatizada de integração para Ubuntu 24.04 amd64.
docker run --rm terminal-setup:dev bash /opt/terminal-setup/tests/integration/test_ubuntu2404_container.sh
```

---

## 4. Volumes opt-in do host

Por segurança, nenhum diretório do host (como `/home`, `/root` ou o `$HOME` do usuário no Aurora Linux) é montado automaticamente.

Se você desejar trabalhar sobre um diretório de código específico do host dentro do container, monte **somente a subpasta do projeto desejado** de forma explícita:

```bash
# [Executar no HOST]
# Monta apenas uma pasta de trabalho específica em /home/dev/workspace.
docker run --rm -it \
  --mount type=bind,source="$(pwd)/meu-projeto",target=/home/dev/workspace \
  terminal-setup:dev
```

Nunca monte seu `$HOME` inteiro do host em `/home/dev`, pois isso ocultaria os dotfiles e plugins instalados na imagem dentro de `/home/dev` e exporia seus arquivos pessoais do host ao container.

---

## 5. Diferença entre shell de login, shell interativo e `docker exec ... bash`

1. **Shell de login padrão do container (`CMD ["/usr/bin/zsh", "-l"]`)**:
   - Quando você inicia o container com `docker run --rm -it terminal-setup:dev` ou `docker compose -f docker/compose.yaml run --rm terminal` sem sobrescrever o comando, o processo principal executa `/usr/bin/zsh -l`.
   - O Zsh lê `~/.zshenv` (configurando `PATH` com `~/.local/bin` e variáveis XDG) e, por ser interativo, lê `~/.zshrc` (carregando histórico privado, `compinit`, `options.zsh`, módulos de funções/aliases, plugins Zsh, Starship e `zoxide`).
2. **Shell interativo sem login (`zsh -i`)**:
   - Lê `~/.zshenv` e `~/.zshrc`, ativando igualmente todos os módulos interativos e plugins do projeto.
3. **Execução direta de outro interpretador (`docker exec -it <container> bash` ou `docker run ... bash`)**:
   - O comando `docker exec` (ou `docker run` com comando explícito) **não consulta o shell de login de `/etc/passwd` para decidir qual binário iniciar** — ele executa exatamente o binário solicitado na linha de comando (`bash`).
   - Portanto, `docker exec -it <container> bash` abrirá uma sessão **Bash** (que não carrega `~/.zshrc`), mesmo que o shell de login registrado para `dev` em `/etc/passwd` seja `/usr/bin/zsh`.
   - Para abrir uma nova sessão Zsh em um container em execução, execute:
     ```bash
     # [Executar no HOST contra um container em execução]
     docker exec -it <nome-ou-id-do-container> /usr/bin/zsh -l
     ```

---

## 6. Limpeza seletiva de recursos

Para remover exclusivamente a imagem gerada por este projeto sem afetar outros containers, volumes ou imagens do host:

```bash
# [Executar no HOST]
# Remove apenas a imagem terminal-setup:dev (quando não estiver em uso).
docker rmi terminal-setup:dev
```

> **Importante**: não é necessário (nem recomendado) executar `docker system prune` ou `docker volume prune`, pois esses comandos removem recursos globais do host fora do escopo deste projeto.

