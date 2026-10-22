# Fontes oficiais, versões, checksums e limites de reprodutibilidade (`terminal-setup`)

- **Data de consulta às fontes oficiais:** 2026-10-22
- **Plataforma alvo da v1:** Ubuntu 24.04 LTS (`noble`), arquitetura `amd64` (`x86_64`)

Este documento registra as versões observadas nos repositórios oficiais do Ubuntu 24.04 LTS, os metadados e checksums publicados pelos projetos upstream para as ferramentas externas (`versions/tools.lock.json`), os commits fixados para os plugins Zsh (`versions/plugins.lock.json`) e a distinção rigorosa entre o que foi consultado nas fontes oficiais e o que ainda aguarda verificação por download/execução em container Ubuntu 24.04.

---

## 1. Pacotes APT do Ubuntu 24.04 LTS (`noble`)

Conforme a seção 9 do guia e a **Decisão P1**, ferramentas disponíveis nos repositórios oficiais do Ubuntu 24.04 que atendem aos requisitos do projeto são instaladas via APT pelo helper administrativo `scripts/install-system-packages.sh`.

> **Limite de reprodutibilidade (Seção 9 do guia):** as versões APT abaixo são **versões observadas** na série `noble` (`Release`, `Updates` e `Security`) via API oficial do Launchpad (`https://api.launchpad.net/1.0/ubuntu/+archive/primary`) em **2026-10-22**. Como repositórios APT recebem atualizações de segurança e correções pontuais ao longo do ciclo LTS, o ambiente APT não é congelado bit a bit.

| Componente do projeto | Pacote binário APT | Pacote fonte (`noble`) | Repositório | Versão em `Release` | Versão em `Updates`/`Security` (em 2026-10-22) | Comando no Ubuntu |
|---|---|---|---|---|---|---|
| `zsh` | `zsh` | `zsh` | `main` | `5.9-6ubuntu2` | — | `zsh` |
| `git` | `git` | `git` | `main` | `1:2.43.0-1ubuntu7` | `1:2.43.0-1ubuntu7.4` | `git` |
| `nano` | `nano` | `nano` | `main` | `7.2-2build1` | `7.2-2ubuntu0.2` | `nano` |
| `ca-certificates` | `ca-certificates` | `ca-certificates` | `main` | `20240203` | `20260816ubuntu0.24.04.1` | *(certificados TLS)* |
| `curl` | `curl` | `curl` | `main` | `8.5.0-2ubuntu10` | `8.5.0-2ubuntu10.16` | `curl` |
| `jq` *(base — Decisão P3)* | `jq` | `jq` | `main` | `1.7.1-3build1` | `1.7.1-3ubuntu0.24.04.2` | `jq` |
| `fzf` | `fzf` | `fzf` | `universe` | `0.44.1-1` | `0.44.1-1ubuntu0.3` | `fzf` |
| `ripgrep` | `ripgrep` | `rust-ripgrep` | `universe` | `14.1.0-1` | — | `rg` |
| `bat` | `bat` | `rust-bat` | `universe` | `0.24.0-1build1` | — | `batcat` (link opcional `~/.local/bin/bat`) |
| `fd` | `fd-find` | `rust-fd-find` | `universe` | `9.0.0-1` | — | `fdfind` (link opcional `~/.local/bin/fd`) |
| `tmux` | `tmux` | `tmux` | `main` | `3.4-1build1` | `3.4-1ubuntu0.2` | `tmux` |
| `zoxide` *(APT — Decisão P1)* | `zoxide` | `rust-zoxide` | `universe` | `0.9.3-1` | — | `zoxide` |
| `eza` *(APT — Decisão P1)* | `eza` | `rust-eza` | `universe` | `0.18.2-1` | — | `eza` |
| `btop` | `btop` | `btop` | `universe` | `1.3.0-1` | — | `btop` |

### Observações técnicas importantes sobre os pacotes do Ubuntu 24.04

1. **Ausência de `starship` no APT do Ubuntu 24.04:** a consulta à API oficial do Launchpad para `starship` e `rust-starship` na série `noble` retornou lista vazia (`[]`). Por isso, o Starship é gerenciado em `versions/tools.lock.json`.
2. **Versão do `fzf` (`0.44.1`):** a flag `fzf --zsh` só foi introduzida no `fzf 0.48.0`. No Ubuntu 24.04 (`0.44.1`), a integração com Zsh deve carregar `/usr/share/doc/fzf/examples/key-bindings.zsh` e `/usr/share/doc/fzf/examples/completion.zsh` (implementado em `config/zsh/fzf.zsh`).
3. **Mapeamento `batcat` e `fdfind`:** os pacotes `bat` e `fd-find` instalam `/usr/bin/batcat` e `/usr/bin/fdfind`. O instalador cria symlinks em `~/.local/bin/bat` e `~/.local/bin/fd` apenas se não houver arquivo ou link preexistente nesses caminhos, registrando-os no manifesto.

---

## 2. Ferramentas externas (`versions/tools.lock.json`)

As ferramentas abaixo não possuem pacote APT no Ubuntu 24.04 e são instaladas no diretório do usuário (`~/.local/share/terminal-setup/tools/<nome>/<versao>/` com symlink em `~/.local/bin/`) a partir de releases oficiais versionadas:

| Ferramenta | Versão fixada | Data da release | Licença | Artefato (`amd64`) | URL oficial do artefato |
|---|---|---|---|---|---|
| **Starship** (`starship`) | `1.27.0` (`v1.27.0`, commit `f8e4e2155542cc84f49b342122d371f74e0ad253`) | 2026-10-17 | ISC | `starship-x86_64-unknown-linux-musl.tar.gz` (5.215.016 bytes) | `https://github.com/starship/starship/releases/download/v1.27.0/starship-x86_64-unknown-linux-musl.tar.gz` |
| **Superfile** (`spf`) | `1.6.0` (`v1.6.0`, commit `865dba26c1d8d35b95bd7b7501ebdeac66ce2618`) | 2026-06-07 | MIT | `superfile-linux-v1.6.0-amd64.tar.gz` (13.490.110 bytes) | `https://github.com/yorukot/superfile/releases/download/v1.6.0/superfile-linux-v1.6.0-amd64.tar.gz` |

### Status dos checksums SHA-256 e inspeção dos tarballs

| Ferramenta | SHA-256 publicado pelo upstream | Origem do valor publicado | SHA-256 conferido contra download real (`sha256sum --check --strict`) | Caminhos internos listados por `tar -tzf` (sem extração) | Anti-tar-slip real, extração, localização efetiva e execução |
|---|---|---|---|---|---|
| **Starship `v1.27.0`** | `10c8eb4cb3b761d9bf59ea828444c2dab36c900b7d69a69e08814b286969df89` | `starship-x86_64-unknown-linux-musl.tar.gz.sha256` e `assets[].digest` da API GitHub Releases | `10c8eb4cb3b761d9bf59ea828444c2dab36c900b7d69a69e08814b286969df89` — **SUCESSO** (`5215016` bytes em `/tmp/ts-phase3-verify.7pYvCu`, removido após verificação) | `starship` | **Ainda não testadas** sobre o arquivo real (função `ts_validate_tar_gz_archive`, extração `tar -xzf`, localização pós-extração e execução `--version` pendentes de integração no Ubuntu 24.04) |
| **Superfile `v1.6.0`** | `d45b0e95072629a6aa7983a84eedca9cd7a98861e67ef91be1415496e3dda309` | `superfile-v1.6.0-checksums.txt` (`browser_download_url` confirmado na API) e `assets[].digest` | `d45b0e95072629a6aa7983a84eedca9cd7a98861e67ef91be1415496e3dda309` — **SUCESSO** (`13490110` bytes em `/tmp/ts-phase3-verify.7pYvCu`, removido após verificação) | `./dist/superfile-linux-v1.6.0-amd64/` e `./dist/superfile-linux-v1.6.0-amd64/spf` | **Ainda não testadas** sobre o arquivo real (função `ts_validate_tar_gz_archive`, extração `tar -xzf`, localização pós-extração e execução `--version` pendentes de integração no Ubuntu 24.04) |

> **Nota técnica sobre papéis distintos no código:**
> - A proteção anti-*tar-slip* reside exclusivamente em `ts_validate_tar_gz_archive` (`lib/downloads.sh`), que inspeciona a saída de `tar -tzf` **antes** de qualquer extração para rejeitar caminhos absolutos (`/*`) ou segmentos `..`. Essa função foi testada localmente sobre pacotes `.tar.gz` sintéticos, mas ainda não foi executada sobre os tarballs reais baixados.
> - O comando `find` em `lib/tools.sh` **não** é mecanismo de proteção anti-*tar-slip*; serve apenas para localizar o binário já extraído dentro do diretório temporário (como `./dist/superfile-linux-v1.6.0-amd64/spf`), cuja extração e localização efetiva nos artefatos reais permanecem pendentes dos testes de integração na Fase 4.

> **Aviso de segurança sobre checksums (Seção 9 do guia):** validar o SHA-256 contra um hash publicado na mesma origem (GitHub Releases) protege contra corrupção de tráfego ou truncamento de download, mas não constitui autenticação criptográfica independente caso a própria conta ou release upstream seja comprometida.

---

## 3. Plugins Zsh (`versions/plugins.lock.json`)

Conforme a **Decisão P2**, todos os plugins Zsh são gerenciados via Git no diretório do usuário (`${XDG_DATA_HOME:-$HOME/.local/share}/terminal-setup/plugins/<plugin>`), apontando para commits específicos de 40 caracteres resolvidos a partir das referências de tags (`refs/tags/<tag>`) e confirmados no endpoint `/commits/<sha>` da API oficial do GitHub em **2026-10-22**:

| Plugin | Repositório oficial | Licença | Tag de referência | Tipo da ref (`refs/tags/<tag>`) | Commit SHA fixado (`versions/plugins.lock.json`) | Arquivo de entrada | Ordem de carga |
|---|---|---|---|---|---|---|---|
| `zsh-vi-mode` *(opcional)* | `https://github.com/jeffreytse/zsh-vi-mode.git` | MIT | `v0.12.0` | `commit` (tag leve) | `80f78d9a3cc06843c776f60e4535b20bb857b1d4` | `zsh-vi-mode.plugin.zsh` | 1º (com `ZVM_INIT_MODE=sourcing`) |
| `zsh-autosuggestions` | `https://github.com/zsh-users/zsh-autosuggestions.git` | MIT | `v0.7.1` | `commit` (tag leve) | `e52ee8ca55bcc56a17c828767a3f98f22a68d4eb` | `zsh-autosuggestions.zsh` | 2º |
| `zsh-syntax-highlighting` | `https://github.com/zsh-users/zsh-syntax-highlighting.git` | BSD-3-Clause | `0.8.0` | `tag` anotada (`b1379f1ee96b1fe25701c9418c75f81eaabdab56`) | `db085e4661f6aafd24e5acb5b2e17e4dd5dddf3e` | `zsh-syntax-highlighting.zsh` | 3º |
| `zsh-history-substring-search` | `https://github.com/zsh-users/zsh-history-substring-search.git` | BSD-3-Clause | `v1.1.0` | `commit` (tag leve) | `400e58a87f72ecec14f783fbd29bc6be4ff1641c` | `zsh-history-substring-search.zsh` | 4º (último) |

> **Nota sobre clonagem e execução real:** na Fase 3, a lógica de obtenção (`git init` + `git fetch --depth 1 origin <commit>` + `git checkout --detach FETCH_HEAD` + validação `git rev-parse HEAD == <commit>`) foi implementada em `lib/plugins.sh` e testada localmente contra repositórios Git criados na sandbox `/tmp`. As tags foram resolvidas e confirmadas contra os commits na API do GitHub, mas o fetch Git real e a carga dos plugins em sessão Zsh no Ubuntu 24.04 permanecem pendentes para os testes de integração em container (Fase 4).

---

## 4. Ferramentas de qualidade e testes (referência para CI / Fase 5)

| Ferramenta | Pacote APT no Ubuntu 24.04 (`universe`) | Última release upstream (em 2026-10-22) | Licença |
|---|---|---|---|
| **ShellCheck** (`koalaman/shellcheck`) | `0.9.0-1` | `v0.11.0` (`8c3be12b05d5c177a04c29e3c78ce89ac86f1595681cab149b65b97c4e227198` para `.linux.x86_64.tar.xz`) | GPL-3.0 |
| **shfmt** (`mvdan/sh`) | `3.8.0-1` (`golang-mvdan-sh`) | `v3.14.1` (`76e77641faa025814b77f153b29796b8e6fa2fca03e0c76a691608b86c7ea7bf` para `shfmt_v3.14.1_linux_amd64`) | BSD-3-Clause |
| **Bats-core** (`bats-core/bats-core`) | `1.10.0-1` (`bats`) | `v1.14.0` (commit `eb7f42f8d608ac693d7a4b67474f6714ea68cfc5`) | MIT |

---

## 5. Política de atualização dos locks

Os arquivos `versions/tools.lock.json` e `versions/plugins.lock.json` nunca são atualizados automaticamente em segundo plano nem na abertura do terminal:

1. Para atualizar uma ferramenta externa, consulte a release oficial no GitHub, obtenha a URL do artefato para `amd64`, verifique o SHA-256 publicado, baixe o artefato em diretório temporário para confirmar o `sha256sum` e a estrutura interna com `tar -tzf`, e atualize `versions/tools.lock.json` e este documento em commit revisado.
2. Para atualizar um plugin Zsh, verifique o novo commit de 40 caracteres no repositório oficial, confirme a compatibilidade de ordem de carga e atualize `versions/plugins.lock.json` em commit revisado.
