# Estado XDG, backups, manifesto, diagnóstico e restauração (`terminal-setup`)

Este documento descreve como o `terminal-setup` armazena seu estado, protege configurações preexistentes do usuário, realiza diagnóstico somente leitura (`doctor.sh`) e permite restaurar ou desinstalar configurações de forma segura (`uninstall-terminal.sh`).

> **Onde executar:** todos os comandos abaixo devem ser executados como **usuário comum** (nunca como `root`).

---

## 1. Estrutura de diretórios no perfil do usuário (XDG)

O projeto nunca grava logs, backups ou manifestos dentro do diretório do repositório. Todo o estado pertence exclusivamente ao usuário efetivo:

```text
${XDG_CONFIG_HOME:-$HOME/.config}/terminal-setup/
├── zsh/
│   ├── options.zsh
│   ├── aliases.zsh
│   ├── bindings.zsh
│   ├── containers.zsh
│   ├── database.zsh
│   ├── fzf.zsh
│   ├── git.zsh
│   ├── plugins.zsh
│   └── prompt.zsh
└── local.zsh                      (opcional, pertencente ao usuário; nunca sobrescrito)

${XDG_STATE_HOME:-$HOME/.local/state}/terminal-setup/
├── lock/                          (lock de concorrência durante execução efetiva)
├── logs/
│   └── <install-id>.log           (permissão 0600, sem dados pessoais Git ou segredos)
├── backups/
│   └── <install-id>/
│       └── files/<caminho-original>
└── manifests/
    └── <install-id>.json          (permissão 0600, gerado e validado via jq)
```

### Arquivos do projeto vs. arquivos do usuário

- **Gerenciados pelo projeto (registrados no manifesto):**
  - `${ZDOTDIR:-$HOME}/.zshenv` e `${ZDOTDIR:-$HOME}/.zshrc` (respeitando `--on-conflict`);
  - `${XDG_CONFIG_HOME:-$HOME/.config}/terminal-setup/zsh/options.zsh` (gerado de forma determinística na instalação com `TS_ICONS_MODE` e `TS_VI_MODE_ENABLED`, registrado no manifesto e sujeito às mesmas regras de conflito, backup, idempotência, validação individual `zsh -n` e restauração);
  - `${XDG_CONFIG_HOME:-$HOME/.config}/terminal-setup/zsh/*.zsh` (`aliases.zsh`, `bindings.zsh`, `containers.zsh`, `database.zsh`, `fzf.zsh`, `git.zsh`, `plugins.zsh`, `prompt.zsh`);
  - `${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml` (quando Starship está selecionado);
  - `${XDG_CONFIG_HOME:-$HOME/.config}/tmux/tmux.conf` (quando tmux está selecionado);
  - `${XDG_DATA_HOME:-$HOME/.local/share}/terminal-setup/tools/<ferramenta>/<versao>/<binario>` (binários externos verificados como `starship` e `spf`);
  - `${XDG_DATA_HOME:-$HOME/.local/share}/terminal-setup/plugins/<plugin>` (repositórios Git de plugins Zsh em commit fixado);
  - `${HOME}/.local/bin/{starship,spf,bat,fd}` (links controlados criados apenas se não colidirem com arquivos/links existentes);
  - `${GIT_CONFIG_GLOBAL:-$HOME/.gitconfig}` (somente quando o usuário autoriza configurar identidade ou defaults Git).
- **Intocados / exclusivos do usuário:**
  - `${XDG_CONFIG_HOME:-$HOME/.config}/terminal-setup/local.zsh`;
  - `${XDG_CONFIG_HOME:-$HOME/.config}/superfile/*` (o projeto não instala `config.toml` fictício para o Superfile);
  - Chaves SSH (`~/.ssh`), credenciais, histórico de comandos e quaisquer arquivos fora do manifesto.

---

## 2. Política de conflitos, idempotência e proteção de symlinks

Ao instalar um arquivo de configuração em um caminho de destino:

1. **Destino ausente (`absent`):** o arquivo é criado de forma atômica (arquivo temporário no mesmo diretório seguido de `mv -Tf`) e registrado no manifesto como `created`.
2. **Destino existente e idêntico (`unchanged`):** se o destino já é um arquivo regular com o mesmo hash SHA-256 do conteúdo a instalar, **nenhuma escrita é feita e nenhum backup redundante é criado** (idempotência).
3. **Destino existente e divergente (arquivo modificado ou symlink):**
   - `--on-conflict keep` (padrão em `--non-interactive`): preserva o arquivo ou symlink atual sem alterá-lo e registra `kept_existing` no manifesto. Se `~/.zshrc` for preservado por `keep`, o instalador avisa que a ativação automática do perfil Zsh não ocorrerá até que o usuário substitua o arquivo (`--on-conflict backup-replace`) ou faça o carregamento manual.
   - `--on-conflict backup-replace`: copia o arquivo original (ou recria textualmente o symlink original sem seguir seu alvo) em `backups/<install-id>/files/...` antes de substituir o destino, registrando `replaced`, `backup_path` e o hash/link anterior no manifesto.
   - `--on-conflict ask` (padrão interativo): pergunta ao usuário antes de decidir entre `keep` e `backup-replace`. **Nota:** `--yes` nunca aprova substituir arquivos em conflito.
4. **Symlinks nunca são seguidos inadvertidamente:** se `~/.zshrc` for um link simbólico apontando para um arquivo externo, a substituição com `backup-replace` faz backup do próprio link simbólico e substitui a entrada do link, **sem jamais sobrescrever o arquivo-alvo apontado pelo link**.

---

## 3. Manifesto JSON e proteção contra path traversal

Cada execução efetiva gera um arquivo `${XDG_STATE_HOME}/terminal-setup/manifests/<install-id>.json` com `umask 077`, construído exclusivamente via `jq`.

Antes de usar qualquer manifesto na restauração (`uninstall-terminal.sh`) ou no diagnóstico (`doctor.sh`), o módulo `lib/manifest.sh` valida:

- Que o arquivo não é um symlink e pertence ao `UID` efetivo do usuário atual;
- Que o JSON obedece ao `schema_version == 1` e contém apenas tipos e ações válidas;
- Que nenhum caminho (`path` ou `backup_path`) contém `..`, `.`, barras duplas, caracteres de controle ou aponta para fora das árvores permitidas do usuário (`HOME`, `ZDOTDIR`, `XDG_*`), e que nenhum diretório pai intermediário é um symlink escapando da árvore do usuário.

---

## 4. Diagnóstico somente leitura (`doctor.sh`)

O script `doctor.sh` inspeciona o ambiente sem modificar arquivos, sem criar logs, sem chamar `sudo` e sem acessar a rede:

```bash
# Usuário comum: diagnóstico humano em português para o perfil developer
bash ./doctor.sh --profile developer

# Usuário comum: saída estruturada em JSON limpo (gerada via jq)
bash ./doctor.sh --profile minimal --json

# Usuário comum: modo estrito (converte avisos em código de saída 1)
bash ./doctor.sh --profile server --strict
```

### Códigos de saída do `doctor.sh`
- `0`: nenhum erro obrigatório encontrado (e nenhum aviso quando `--strict` está ativo).
- `1`: requisito obrigatório ausente, erro de sintaxe em arquivo Zsh (`zsh -n`) ou falha de integridade no manifesto (ou aviso quando `--strict` está ativo).
- `2`: parâmetro inválido.

---

## 5. Desinstalação e restauração segura (`uninstall-terminal.sh`)

O script `uninstall-terminal.sh` reverte apenas as alterações registradas no manifesto selecionado:

```bash
# Usuário comum: simular o que seria removido ou restaurado (sem tocar no disco)
bash ./uninstall-terminal.sh --dry-run

# Usuário comum: restaurar/remover de forma não interativa usando o manifesto mais recente
bash ./uninstall-terminal.sh --non-interactive

# Usuário comum: restaurar um manifesto específico pelo seu INSTALL_ID
bash ./uninstall-terminal.sh --restore 20261022T120000Z-12345-a1b2c3d4 --non-interactive
```

### Garantias de segurança na restauração
1. **Proteção de edições posteriores (`--on-modified keep`):** se você editou `~/.zshrc` ou `~/.config/starship.toml` manualmente **depois** da instalação, o `sha256sum` atual será diferente do `installed_checksum` registrado no manifesto. O `uninstall-terminal.sh` detecta essa divergência, **preserva o arquivo editado** e exibe um aviso de conflito.
2. **Restauração verificada de backups:** quando um arquivo tinha backup (`previous_state` igual a `file` ou `symlink`), o script verifica o hash SHA-256 (ou o alvo do symlink) do backup antes de restaurá-lo.
3. **Preservação dos backups e idempotência:** os arquivos dentro de `${XDG_STATE_HOME}/terminal-setup/backups/<install-id>/` são preservados por padrão. Se você executar `uninstall-terminal.sh` uma segunda vez seguida para o mesmo manifesto, ele reconhece que os arquivos já voltaram ao estado pré-instalação (`[JA RESTAURADO]`) e termina com código `0` sem erros.
4. **Preservação de conteúdo desconhecido e pacotes:** diretórios só são removidos se estiverem completamente vazios (`rmdir`), e pacotes APT nunca são desinstalados na v1.

