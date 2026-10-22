# Guia de Desenvolvimento, Qualidade e Manutenção (`terminal-setup`)

Este documento orienta contribuidores e mantenedores sobre as convenções de código, formatação, análise estática, execução de testes, ambiente Docker de qualidade e atualização dos arquivos de lock do projeto `terminal-setup`.

---

## 1. Convenções de código e arquivos

1. **Padrão de formatação ([`.editorconfig`](../.editorconfig) e [`.gitattributes`](../.gitattributes)):**
   - Codificação `UTF-8`, fim de linha `LF`, indentação de **2 espaços** para scripts `.sh`, `.zsh`, `.bats`, `.yaml` e `.json`.
   - Em partições compartilhadas Windows/Linux (NTFS com `core.filemode=false`), execute sempre scripts com `bash ./script.sh` sem depender de `chmod +x` recursivo no host.
2. **Separação entre Bash e Zsh:**
   - Scripts executáveis e bibliotecas (`install-terminal.sh`, `doctor.sh`, `uninstall-terminal.sh`, `scripts/*.sh`, `lib/*.sh`, `tests/**/*.sh`) são escritos em **Bash** (`#!/usr/bin/env bash` com `set -Eeuo pipefail` nos pontos de entrada).
   - Os arquivos em `config/zsh/` (`zshenv.template`, `zshrc`, `*.zsh`) são escritos para **Zsh** e **não devem ser analisados como Bash pelo ShellCheck**; sua validação sintática individual é feita exclusivamente com `zsh -n`.
3. **Manipulação de JSON:**
   - Qualquer leitura ou geração de JSON (`versions/*.lock.json`, manifestos em `manifests/<id>.json` e saída de `doctor.sh --json`) utiliza **`jq`**. Nunca implemente parsers JSON artesanais com `grep`, `sed` ou concatenação manual de strings.

---

## 2. Validação sintática e suítes unitárias locais (sem instalar nada no host)

Como **usuário comum**, a partir da raiz do repositório:

```bash
# [Executar como USUÁRIO COMUM no host ou em container]
# 1. Validar sintaxe individual de cada script Bash (bash -n)
for f in install-terminal.sh doctor.sh uninstall-terminal.sh scripts/install-system-packages.sh lib/*.sh tests/unit/*.sh tests/integration/*.sh; do
  bash -n "${f}"
done

# 2. Validar sintaxe individual de cada arquivo Zsh (zsh -n)
for zf in config/zsh/zshenv.template config/zsh/zshrc config/zsh/*.zsh; do
  zsh -n "${zf}"
done

# 3. Executar as 4 suítes unitárias isoladas em /tmp (sem rede e sem sudo)
bash ./tests/unit/test_phase1_contract.sh
bash ./tests/unit/test_phase2_state_and_reversibility.sh
bash ./tests/unit/test_phase3_packages_tools_plugins.sh
bash ./tests/unit/test_phase4_docker_contract.sh
```

---

## 3. Ambiente Docker de Qualidade (`ShellCheck`, `shfmt` e `Bats-core`)

Para não instalar ferramentas no host Aurora/Fedora e não adicionar pacotes de teste à imagem normal do usuário ([`docker/Dockerfile`](../docker/Dockerfile)), o projeto disponibiliza um Dockerfile dedicado: [`docker/Dockerfile.quality`](../docker/Dockerfile.quality).

### Ferramentas incluídas em `docker/Dockerfile.quality` (Ubuntu 24.04 `noble`)

| Ferramenta | Pacote APT (`noble`) | Versão | Uso no projeto |
|---|---|---|---|
| **ShellCheck** | `shellcheck` (`universe`) | `0.9.0-1` | Análise estática dos scripts Bash (`shellcheck -x`) |
| **shfmt** | `shfmt` (`universe`) | `3.8.0-1` | Verificação de formatação (`shfmt -d -i 2 -ci -bn`) |
| **Bats-core** | `bats` (`universe`) | `1.10.0-1` | Execução dos adaptadores em `tests/bats/*.bats` |
| **Zsh / jq / Git** | `zsh`, `jq`, `git` (`main`) | Versões Ubuntu 24.04 | Suporte às suítes unitárias executadas sob `bats` |

### Comandos para construir e executar o container de qualidade

```bash
# [Executar no HOST, na raiz do repositório]
# 1. Construir a imagem de qualidade separada:
docker build -f docker/Dockerfile.quality -t terminal-setup-quality:local .

# [Executar no HOST — roda dentro do container sem rede (--network none)]
# 2. Verificar formatação com shfmt em modo diff (sem alterar arquivos):
docker run --rm --network none terminal-setup-quality:local \
  shfmt -d -i 2 -ci -bn \
    install-terminal.sh doctor.sh uninstall-terminal.sh \
    scripts/install-system-packages.sh lib/*.sh tests/unit/*.sh tests/integration/*.sh

# 3. Executar ShellCheck nos scripts Bash (com resolução de source -x):
docker run --rm --network none terminal-setup-quality:local \
  shellcheck -x \
    install-terminal.sh doctor.sh uninstall-terminal.sh \
    scripts/install-system-packages.sh lib/*.sh tests/unit/*.sh tests/integration/*.sh

# 4. Executar as suítes unitárias pelo runner Bats-core:
docker run --rm --network none terminal-setup-quality:local \
  bats tests/bats/

# 5. Limpeza seletiva da imagem de qualidade após o uso:
docker rmi terminal-setup-quality:local
```

---

## 4. Integração Contínua (`.github/workflows/ci.yaml`)

O arquivo [`.github/workflows/ci.yaml`](../.github/workflows/ci.yaml) define dois jobs para runners `ubuntu-24.04`:

1. **`static-and-unit`** (`timeout-minutes: 15`, `permissions: contents: read`):
   - Faz checkout com `actions/checkout@11bd71901bbe5b1630ceea73d27597364c9af683` (`v4.2.2` fixado por SHA de 40 caracteres);
   - Instala `bats`, `shellcheck`, `shfmt`, `jq` e `zsh` via APT;
   - Executa `bash -n`, `zsh -n`, `shfmt -d -i 2 -ci -bn`, `shellcheck -x` e `bats tests/bats/`.
2. **`container-integration`** (`timeout-minutes: 20`, matriz `developer`, `minimal`, `server`):
   - Constrói a imagem `docker/Dockerfile` para cada perfil;
   - Executa `doctor.sh --profile <perfil>` com `--network none`;
   - Executa `tests/integration/test_ubuntu2404_container.sh` com `--network none` para o perfil `developer`;
   - Executa inspeção read-only de `/root` com `--network none --read-only --user 0:0`.

> **Importante:** a existência do arquivo `.github/workflows/ci.yaml` no repositório local não significa que o workflow já tenha sido executado nos servidores do GitHub Actions (pois não houve `git push` nem publicação em repositório remoto).

---

## 5. Procedimento seguro para atualizar `versions/*.lock.json`

1. **Ferramentas externas ([`versions/tools.lock.json`](../versions/tools.lock.json)):**
   - Consulte a release oficial do projeto (`starship/starship` ou `yorukot/superfile`);
   - Baixe o arquivo `.tar.gz` e o arquivo oficial de checksums em um diretório temporário criado com `mktemp -d`;
   - Confirme o hash com `sha256sum --check --strict`;
   - Inspecione a listagem de entradas com `tar -tzf` para confirmar o caminho interno do binário e ausência de `..` ou caminhos absolutos;
   - Atualize `version`, `release_tag`, `commit_sha`, `url`, `sha256` e `size_bytes` em `versions/tools.lock.json` e documente em [`docs/fontes-e-versoes.md`](fontes-e-versoes.md).
2. **Plugins Zsh ([`versions/plugins.lock.json`](../versions/plugins.lock.json)):**
   - Resolva a tag oficial até o objeto `commit` de 40 caracteres (desreferenciando tags anotadas quando necessário);
   - Atualize `tag` e `commit` em `versions/plugins.lock.json` e execute a suíte de integração em container Ubuntu 24.04.

