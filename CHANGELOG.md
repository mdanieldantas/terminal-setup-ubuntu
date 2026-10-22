# Changelog — `terminal-setup`

Todas as alterações relevantes do projeto `terminal-setup` (alvo v1: **Ubuntu 24.04 LTS `amd64`**) são registradas neste arquivo por fase de implementação.

---

## [0.5.0-phase5] — 2026-10-22 (Em revisão final)

### Adicionado
- Documentação completa em português em `docs/`:
  - [`docs/arquitetura.md`](docs/arquitetura.md)
  - [`docs/instalacao.md`](docs/instalacao.md)
  - [`docs/seguranca.md`](docs/seguranca.md)
  - [`docs/desenvolvimento.md`](docs/desenvolvimento.md)
  - [`docs/matriz-de-testes.md`](docs/matriz-de-testes.md)
  - [`docs/solucao-de-problemas.md`](docs/solucao-de-problemas.md)
- Documentação da estrutura de testes em [`tests/README.md`](tests/README.md).
- Adaptadores **Bats-core** em `tests/bats/test_phase{1,2,3,4}_*.bats` (4 testes `@test` invocando as 161 verificações internas dos scripts `.sh` originais).
- Ambiente Docker de qualidade estática separado da imagem normal do usuário em [`docker/Dockerfile.quality`](docker/Dockerfile.quality) (`ShellCheck`, `shfmt` e `Bats-core`).
- Workflow de integração contínua em [`.github/workflows/ci.yaml`](.github/workflows/ci.yaml) com permissões mínimas (`contents: read`), timeouts explícitos e `actions/checkout` fixado em commit SHA de 40 caracteres (`11bd71901bbe5b1630ceea73d27597364c9af683`).

### Corrigido / Endurecido
- Validação de caminhos efetivos e symlinks em [`lib/common.sh`](lib/common.sh) (`ts_is_effective_tmp_path` via `readlink -f` e inspeção de symlinks intermediários).
- Validação de raízes gerenciadas em [`lib/backups.sh`](lib/backups.sh) (`ts_validate_managed_path` agora rejeita quando a própria raiz selecionada, como `ZDOTDIR` ou `XDG_CONFIG_HOME`, é um symlink ou escapa canonicamente via `readlink -f`).
- Validação do cabeçalho `.uid` e `.home` em [`lib/manifest.sh`](lib/manifest.sh) (`ts_validate_manifest_file`).
- Ajustes de conformidade estática para `ShellCheck 0.9.0` (`shellcheck -x`) e formatação padronizada com `shfmt 3.8.0` (`shfmt -i 2 -ci -bn`) nos 22 scripts Bash do projeto, sem alterar nem formatar arquivos Zsh como Bash.
- Validação em container Ubuntu 24.04 (`amd64`) para os três perfis (`developer`, `minimal` e `server`) e para a imagem de qualidade (`terminal-setup-quality`).

---

## [0.4.0-phase4] — 2026-10-22

### Adicionado
- Ambiente em container Ubuntu 24.04 LTS (`amd64`): [`docker/Dockerfile`](docker/Dockerfile), [`docker/compose.yaml`](docker/compose.yaml), [`.dockerignore`](.dockerignore) e [`docs/docker.md`](docs/docker.md).
- Suíte de testes de integração real em container: [`tests/integration/test_ubuntu2404_container.sh`](tests/integration/test_ubuntu2404_container.sh) (`57 PASS, 0 FAIL` com `--network none`).
- Suíte de contrato estático Docker: [`tests/unit/test_phase4_docker_contract.sh`](tests/unit/test_phase4_docker_contract.sh) (`19 PASS, 0 FAIL`).

### Corrigido
- Remoção de aliases padrão `ls` e `grep` de [`config/zsh/aliases.zsh`](config/zsh/aliases.zsh) para preservar comandos tradicionais inalterados.
- Uso do `UID` real do processo nos testes normais e adição de teste negativo explícito de proprietário divergente no manifesto (`UID 99999 != UID real`).
- Fixture de teste negativo anti-*tar-slip* com verificação explícita de `../evil.txt` antes da rejeição.

---

## [0.3.0-phase3] — 2026-10-22

### Adicionado
- Helper administrativo [`scripts/install-system-packages.sh`](scripts/install-system-packages.sh) com allowlist fechada de pacotes APT do Ubuntu 24.04 (`noble`).
- Módulos [`lib/packages.sh`](lib/packages.sh), [`lib/downloads.sh`](lib/downloads.sh), [`lib/tools.sh`](lib/tools.sh) e [`lib/plugins.sh`](lib/plugins.sh).
- Locks verificados [`versions/tools.lock.json`](versions/tools.lock.json) (Starship `1.27.0` e Superfile `1.6.0`) e [`versions/plugins.lock.json`](versions/plugins.lock.json) (4 plugins Zsh com commits SHA-1 de 40 caracteres).
- Documentação [`docs/fontes-e-versoes.md`](docs/fontes-e-versoes.md), [`docs/superfile.md`](docs/superfile.md) e [`docs/perfis.md`](docs/perfis.md).
- Suíte [`tests/unit/test_phase3_packages_tools_plugins.sh`](tests/unit/test_phase3_packages_tools_plugins.sh) (`29 PASS, 0 FAIL`).

---

## [0.2.0-phase2] — 2026-10-22

### Adicionado
- Gerenciamento de estado XDG, backups, escrita atômica e manifesto JSON via `jq` ([`lib/backups.sh`](lib/backups.sh), [`lib/manifest.sh`](lib/manifest.sh), [`lib/user-config.sh`](lib/user-config.sh), [`lib/git-config.sh`](lib/git-config.sh)).
- Diagnóstico somente leitura [`doctor.sh`](doctor.sh) e restauração/desinstalação [`uninstall-terminal.sh`](uninstall-terminal.sh).
- Templates de configuração para Zsh (`config/zsh/`), Starship (`config/starship/{plain,nerd}.toml`) e tmux (`config/tmux/tmux.conf`).
- Documentação [`docs/backup-restauracao.md`](docs/backup-restauracao.md) e suíte [`tests/unit/test_phase2_state_and_reversibility.sh`](tests/unit/test_phase2_state_and_reversibility.sh).

---

## [0.1.0-phase1] — 2026-10-22

### Adicionado
- Contrato de linha de comando, parser restrito de `terminal.conf` (`CHAVE=valor` sem `source`/`eval`), perfis (`profiles/{minimal,developer,server}.conf`) e planejamento puro `--dry-run`.
- Documentação [`docs/parametros.md`](docs/parametros.md), [`examples/terminal.conf.example`](examples/terminal.conf.example) e suíte [`tests/unit/test_phase1_contract.sh`](tests/unit/test_phase1_contract.sh).

