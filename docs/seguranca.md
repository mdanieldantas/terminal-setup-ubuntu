# Modelo de Segurança, Limites e Hooks de Teste (`terminal-setup`)

Este documento descreve os controles de segurança implementados no `terminal-setup`, o tratamento de entradas não confiáveis, a distinção entre verificações reais e hooks de teste (`TS_TEST_*`) e os limites conhecidos das verificações de integridade na v1.

---

## 1. Fronteira de privilégios (`root` vs. usuário comum)

1. **Bloqueio de `root` nos scripts de usuário (`ts_require_non_root`):**
   - `install-terminal.sh` e `uninstall-terminal.sh` consultam o `EUID` real do processo fornecido pelo kernel (`${EUID:-$(/usr/bin/id -u)}`).
   - Se o processo real estiver rodando com `UID 0`, a execução é encerrada imediatamente com código `4` (`TS_EXIT_PRIVILEGE`) antes de criar qualquer diretório, arquivo ou log.
   - Esse bloqueio **não pode ser desativado** por variáveis de ambiente ou flags de linha de comando.
2. **Escopo restrito do helper administrativo (`scripts/install-system-packages.sh`):**
   - Exige `UID 0` real para executar o binário `/usr/bin/apt-get` do sistema.
   - Valida a plataforma (`ID=ubuntu`, `VERSION_ID=24.04`, arquitetura `amd64`).
   - Aceita exclusivamente pacotes presentes na allowlist estática `TS_ALLOWED_APT_PACKAGES` (`zsh`, `git`, `nano`, `ca-certificates`, `curl`, `jq`, `fzf`, `ripgrep`, `bat`, `fd-find`, `tmux`, `zoxide`, `eza`, `btop`), passando-os após `--` para `apt-get install -y --no-install-recommends --`.
   - Não lê `terminal.conf` do usuário, não aceita URLs arbitrárias, não adiciona PPAs ou chaves GPG de terceiros e não altera arquivos em `/home` ou `/root`.
3. **Sem `NOPASSWD:ALL` ou elevação oculta:**
   - Nenhum script altera `/etc/sudoers` ou `/etc/sudoers.d/`.
   - Em modo `--non-interactive`, se houver pacotes APT ausentes e `sudo -n true` indicar que uma senha é necessária, o instalador falha imediatamente com código `4` e instrui a execução em duas etapas, sem travar aguardando entrada.

---

## 2. Proteção contra execução de código em configuração (`lib/config-parser.sh`)

Arquivos de preferências passados via `--config <caminho>` nunca são interpretados com `source`, `.` ou `eval`:

- O parser lê o arquivo linha por linha com `IFS= read -r`.
- Rejeita arquivos contendo byte `NUL` (`\0`) ou caracteres de controle ASCII (`0x00–0x1F`, `0x7F`).
- Aceita somente chaves maiúsculas pertencentes à lista fechada `TS_ALLOWED_USER_CONFIG_KEYS`.
- Rejeita chaves duplicadas, aspas de shell ao redor do valor (`"..."` ou `'...'`) e qualquer sintaxe de expansão ou substituição de comandos (`$(...)`, `` `...` ``, `${...}`).
- Em `GIT_NAME`, rejeita operadores de encadeamento (`;`, `|`, `&`).

---

## 3. Downloads, checksums SHA-256 e proteção anti-*tar-slip*

1. **Proibição de `curl | bash`:**
   - Nenhuma ferramenta ou plugin é instalado canalizando scripts remotos diretamente para um interpretador shell.
2. **Transporte e verificação (`lib/downloads.sh` e `lib/tools.sh`):**
   - `curl` é invocado com `--proto '=https' --tlsv1.2 --fail --location --connect-timeout 15 --max-time 120`.
   - O arquivo baixado em diretório temporário exclusivo (`mktemp -d`) tem seu hash SHA-256 conferido contra o valor hexadecimal de 64 caracteres fixado em [`versions/tools.lock.json`](../versions/tools.lock.json) antes de qualquer inspeção ou extração.
3. **Inspeção prévia de arquivos `.tar.gz` (`ts_validate_tar_gz_archive`):**
   - Antes de executar `tar -xzf`, a função lista as entradas com `tar -tzf` e rejeita o pacote caso qualquer entrada seja vazia, comece com `/`, contenha segmentos `..` (`..`, `../`, `/../`, `/..`) ou possua caracteres de controle.
   - A extração subsequente ocorre em subdiretório temporário com `--no-same-owner --no-same-permissions`.
4. **Limites conhecidos da verificação por SHA-256:**
   - A validação de SHA-256 contra hashes publicados nas releases oficiais do GitHub garante integridade contra corrupção de rede, truncamento ou substituição acidental do arquivo, mas **não substitui verificação de assinatura criptográfica offline (PGP/Minisign/Sigstore)** caso a própria conta ou release upstream no GitHub seja comprometida no momento da atualização manual do lock.

---

## 4. Validação de propriedade, symlinks e destinos (`lib/backups.sh` e `lib/manifest.sh`)

1. **Escopo estrito de escrita (`ts_validate_managed_path`):**
   - Só permite operações dentro das raízes legítimas do usuário (`$HOME`, `$XDG_CONFIG_HOME`, `$XDG_DATA_HOME`, `$ZDOTDIR` customizado, `dirname($GIT_CONFIG_GLOBAL)` e, apenas para validação de backups, `$XDG_STATE_HOME`).
   - Rejeita caminhos relativos, caracteres de controle, barras duplas (`//`), segmentos `.` ou `..`.
   - Rejeita se a própria raiz selecionada (`matched_root`, como `HOME`, `ZDOTDIR` ou `XDG_CONFIG_HOME`) for um symlink (`-L`), se qualquer diretório intermediário entre a base (`HOME` ou `/tmp`) e o diretório pai do arquivo for um symlink, ou se o caminho canônico resolvido (`readlink -f`) do diretório pai escapar do caminho canônico da raiz.
   - **Nota de compatibilidade:** essa verificação bloqueia intencionalmente setups onde o próprio diretório raiz de `ZDOTDIR` ou `XDG_*` é um link simbólico (arquivos finais individuais como `~/.zshrc` continuam podendo ser symlinks pré-existentes, sendo preservados com `--on-conflict keep` ou copiados como link em `--on-conflict backup-replace`).
2. **Proteção de symlinks no destino:**
   - Ao fazer backup (`ts_create_backup_item`), um symlink é copiado como link simbólico (`readlink` + `ln -s`), sem seguir o arquivo-alvo.
   - Ao substituir um destino que era symlink (`ts_atomic_write_from_file`), a entrada do symlink é removida (`rm -f`) antes do `mv -Tf`, garantindo que o arquivo externo apontado pelo link jamais seja modificado.
3. **Validação de manifesto (`ts_validate_manifest_file`):**
   - Confirma que o arquivo de manifesto não é symlink, pertence ao `UID` real do usuário no sistema de arquivos (`stat -c '%u'`) e possui no JSON interno `.uid` e `.home` idênticos ao `UID` e `HOME` atuais.

---

## 5. Revisão e papel dos hooks de teste (`TS_TEST_*`)

O código distribuído contém variáveis prefixadas por `TS_TEST_*` utilizadas pelas suítes de testes unitários em `tests/unit/`.

> **Importante:** `TS_TEST_SANDBOX_MODE` e a verificação de caminhos sob `/tmp` **não são mecanismos de isolamento nem barreiras de segurança** contra processos executados pelo mesmo usuário (qualquer processo rodando com o mesmo `UID` já possui as mesmas permissões de sistema operacional daquele usuário). Eles são apenas convenções do *test harness* para evitar que variáveis de teste acidentalmente exportadas afetem uma execução normal.

### Distinção entre as três categorias no código

| Categoria | Variáveis / Funções | Papel Real e Limites |
|---|---|---|
| **1. Verificações reais de UID, propriedade e destino (Segurança Efetiva)** | `EUID` em `ts_require_non_root` e `install-system-packages.sh`; `stat -c '%u'` e `.uid`/`.home` em `ts_validate_manifest_file`; `ts_validate_managed_path` em `lib/backups.sh` | **Imutáveis por hooks em execução real:**<br>- Um processo rodando como `root` real (`EUID == 0`) **jamais** consegue contornar `ts_require_non_root`, mesmo que defina `TS_TEST_SANDBOX_MODE=1` e `TS_TEST_EUID=1000`.<br>- Um usuário comum (`EUID != 0`) **jamais** consegue falsificar outro UID não-root (`TS_EFFECTIVE_UID` é sempre `real_euid` quando `TS_TEST_EUID != 0`), mantendo intacta a checagem de propriedade do manifesto.<br>- `install-system-packages.sh` recusa executar `/usr/bin/apt-get` real se `real_euid != 0`. |
| **2. Simulação de plataforma e erro de `UID 0` em testes** | `TS_TEST_OS_RELEASE_FILE`, `TS_TEST_ARCH`, `TS_TEST_EUID=0` | Permitem que um usuário não-root teste a rejeição de `UID 0` (`exit 4`), o aviso de `UID 0` no `doctor.sh`, e a rejeição de outras distribuições (`Fedora`, `Debian`) ou arquiteturas (`arm64`, `riscv64`). `TS_TEST_OS_RELEASE_FILE` exige que `ts_is_effective_tmp_path` confirme ausência de symlinks e resolução canônica (`readlink -f`) dentro de `/tmp`. |
| **3. Mocks de artefatos e repositórios locais em testes offline** | `TS_TEST_TOOLS_LOCK_FILE`, `TS_TEST_PLUGINS_LOCK_FILE`, `TS_TEST_PLUGIN_REPO_BASE`, `TS_TEST_SKIP_EXTERNAL_DOWNLOADS` | Permitem que as suítes unitárias das Fases 2 e 3 exercitem a lógica de instalação, falha de checksum, anti-*tar-slip* e clonagem Git contra fixtures temporárias em `/tmp` sem acessar a internet. Todos os caminhos passam por `ts_is_effective_tmp_path` (rejeitando symlinks e verificando `readlink -f`). |

