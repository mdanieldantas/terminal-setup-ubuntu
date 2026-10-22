# Matriz de Testes e Status de Validação (`terminal-setup`)

Este documento registra com precisão quais plataformas, perfis, suítes e requisitos obrigatórios do guia foram efetivamente testados, quais possuem plano preparado aguardando aprovação pontual de execução e quais estão fora do escopo da v1.

---

## 1. Matriz de plataformas e arquiteturas

| Plataforma / Arquitetura | Status de Suporte na v1 | O que foi efetivamente testado | Limitações / Observações |
|---|---|---|---|
| **Ubuntu 24.04 LTS (`noble`) `amd64` (Container Docker)** | **Suportado e validado em container** | Build completo e testes isolados (`--network none`) na revisão final da Fase 5 (`ts-p5-r2-20261022-7eb4ba03`): suíte completa de integração para `developer`, verificações enxutas por perfil para `minimal` e `server`, imagem de qualidade (`shfmt 3.8.0`, `shellcheck 0.9.0`, `bats 1.10.0`), inspeção read-only de `/root` (`14/14` caminhos em cada perfil) e smoke test via Docker Compose na Fase 4 (`ts-p4-r2-20261022-7eb4ba03`). | Ambiente de container não possui boot real, `systemd`, serviços reais de sistema nem sessão de login PAM completa (`chsh` interativo). |
| **Ubuntu 24.04 LTS (`noble`) `amd64` (VM / Bare-metal / WSL2)** | **Alvo suportado da v1** | Contrato de argumentos, `--dry-run`, detecção de WSL/OS e validação integrada em containers `ubuntu:24.04` (`developer`, `minimal` e `server`). | **Não validado em VM ou servidor real com boot e serviços reais nesta sessão** (validação integrada realizada exclusivamente em containers Ubuntu 24.04 `amd64`). |
| **Host Fedora / Aurora Linux (`x86_64`)** | **Apenas ambiente de desenvolvimento e host Docker** | Validação sintática (`bash -n`, `zsh -n`), modo `--dry-run`, `--help`, `--version` e as 4 suítes unitárias isoladas em `/tmp` (`161 PASS`). | **Não suportado como alvo de instalação efetiva** (bloqueado por `ts_require_supported_execution_environment` com código `3`). |
| **Ubuntu 24.04 `arm64` (`aarch64`)** | **Não suportado na v1** | Testada a **rejeição segura** (`código 3`) via simulação de arquitetura em `test_phase1_contract.sh` e `test_phase3_packages_tools_plugins.sh`. | Sem artefatos `arm64` registrados em `versions/tools.lock.json` na v1. |
| **Debian / Ubuntu 22.04 / Outras distros** | **Não suportado na v1** | Testada a **rejeição segura** (`código 3`) em `install-terminal.sh` e `scripts/install-system-packages.sh`. | Fora do escopo da v1. |

---

## 2. Cobertura real por perfil (`minimal`, `developer`, `server` e `--only superfile`)

| Perfil / Modo | Planejamento `--dry-run` e Contrato CLI | Testes Unitários Isolados (`/tmp`) | Build e Integração em Container Ubuntu 24.04 (`amd64`) | Nível de Cobertura em Container |
|---|---|---|---|---|
| **`developer`** | **Testado e aprovado** | **Testado e aprovado** (`test_phase1`, `test_phase2`, `test_phase3`) | **Suíte completa de integração** (`terminal-setup:ts-p5-developer-20261022-7eb4ba03`, ID `sha256:0ede7db25b22...`: `57 PASS, 0 FAIL` em `test_ubuntu2404_container.sh`, `161 PASS` nas suítes unitárias dentro do container e `14/14` caminhos limpos em `/root`) e revisão anterior da Fase 4 (`terminal-setup:ts-p4-r2-20261022-7eb4ba03`) | **Suíte completa de integração (`57` verificações) + suítes unitárias (`161`) + inspeção `/root` (`14`)** |
| **`minimal`** | **Testado e aprovado** | **Testado e aprovado** (`test_phase1`, `test_phase2`, `test_phase3`) | **Verificações enxutas por perfil** (`terminal-setup:ts-p5-minimal-20261022-7eb4ba03`, ID `sha256:ee9ed8e8b5d5...`: `UID 1001` sem `sudo`, 10 ferramentas obrigatórias presentes, ferramentas/plugins opcionais ausentes, `zsh -i -c` limpo sem aliases invasivos, `doctor.sh --profile minimal --json` com `0` erros, 2ª execução sem reescrita com entradas registradas como `action=unchanged` no manifesto e `14/14` caminhos limpos em `/root`) | **Verificações enxutas por perfil (`6` blocos) + inspeção `/root` (`14`)** |
| **`server`** | **Testado e aprovado** | **Testado e aprovado** (`test_phase1`, `test_phase3`) | **Verificações enxutas por perfil** (`terminal-setup:ts-p5-server-20261022-7eb4ba03`, ID `sha256:52425398348b...`: `UID 1001` sem `sudo`, 15 ferramentas obrigatórias presentes incluindo `fdfind`/`tmux`/`zoxide`/`btop`, `spf`/`eza`/`zsh-syntax-highlighting`/`zsh-vi-mode` ausentes por padrão, 2 plugins `zsh-autosuggestions` e `zsh-history-substring-search` carregados em `zsh -i -c`, `doctor.sh --profile server --json` com `0` erros, 2ª execução sem reescrita com entradas registradas como `action=unchanged` no manifesto e `14/14` caminhos limpos em `/root`) | **Verificações enxutas por perfil (`6` blocos) + inspeção `/root` (`14`)** |
| **`--only superfile`** | **Testado e aprovado** | **Testado e aprovado** (`test_phase1`, `test_phase3`) | **Testado e aprovado** (validado em `test_phase3_packages_tools_plugins.sh` executado dentro do container `terminal-setup:ts-p5-developer-20261022-7eb4ba03` com `--network none`) | **Coberto via suíte Fase 3 em container Ubuntu 24.04 `amd64`** |

---

## 3. Resumo das suítes de testes e ferramentas de qualidade (Revisão Final Fase 5 vs. Revisão Fase 4)

| Suíte / Ferramenta | Tipo | Testes Bats (`@test`) | Verificações Internas | Ambiente onde foi executado (Revisão Final `ts-p5-r2-20261022-7eb4ba03`) | Resultado |
|---|---|---:|---:|---|---|
| `tests/unit/test_phase1_contract.sh` | Unitário (Bash) | — | `57` | Container de qualidade (`UID 1001`) e Container `developer` (`UID 1001`, `--network none`) | **57 PASS, 0 FAIL** |
| `tests/unit/test_phase2_state_and_reversibility.sh` | Unitário (Bash) | — | `56` | Container de qualidade (`UID 1001`) e Container `developer` (`UID 1001`, `--network none`) *(na revisão anterior da Fase 4 continha `54 PASS`, antes da adição dos testes `12f` e `12g`)* | **56 PASS, 0 FAIL** |
| `tests/unit/test_phase3_packages_tools_plugins.sh` | Unitário (Bash) | — | `29` | Container de qualidade (`UID 1001`) e Container `developer` (`UID 1001`, `--network none`) | **29 PASS, 0 FAIL** |
| `tests/unit/test_phase4_docker_contract.sh` | Unitário (Bash) | — | `19` | Container de qualidade (`UID 1001`) e Container `developer` (`UID 1001`, `--network none`) | **19 PASS, 0 FAIL** |
| `tests/integration/test_ubuntu2404_container.sh` | Integração em Container (`developer`) | — | `57` | Container `terminal-setup:ts-p5-developer-20261022-7eb4ba03` (`UID 1001`, `--network none`) | **57 PASS, 0 FAIL** |
| Integração dedicada dos perfis `minimal` e `server` | Integração em Container (`minimal` / `server`) | — | `6` blocos por perfil | Containers `terminal-setup:ts-p5-minimal-20261022-7eb4ba03` e `terminal-setup:ts-p5-server-20261022-7eb4ba03` (`UID 1001`, `--network none`) | **6/6 PASS em `minimal` e 6/6 PASS em `server`** |
| Inspeção `/root` (`UID 0`, `--read-only`) | Isolamento de `/root` nos 3 perfis | — | `14` caminhos por perfil | Containers efêmeros `--user 0:0 --read-only --network none` sobre as imagens `developer`, `minimal` e `server` | **14/14 limpos nos 3 perfis (`0 FAIL`)** |
| `tests/bats/*.bats` (`Bats 1.10.0`) | Adaptadores Bats-core | `4` | `161` *(soma `57+56+29+19`)* | Container `terminal-setup-quality:ts-p5-qa-r2-20261022-7eb4ba03` (`UID 1001`, `--network none`) | **4/4 `@test` PASS (`BATS_EXIT_CODE=0`, 161 verificações internas)** |
| `shfmt -d -i 2 -ci -bn` (`shfmt 3.8.0`) | Formatação Bash (22 scripts `.sh`) | — | `22` arquivos Bash | Container `terminal-setup-quality:ts-p5-qa-r2-20261022-7eb4ba03` (`UID 1001`, `--network none`; reprovou com `exit 1` na Rodada 1 `ts-p5-qa-20261022-7eb4ba03` antes da formatação e aprovou com `exit 0` na Rodada 2) | **Aprovado (`SHFMT_EXIT_CODE=0`)** |
| `shellcheck -x` (`ShellCheck 0.9.0`) | Análise Estática Bash (22 scripts `.sh`) | — | `22` arquivos Bash | Container `terminal-setup-quality:ts-p5-qa-r2-20261022-7eb4ba03` (`UID 1001`, `--network none`; reprovou com `exit 1` na Rodada 1 em 12 arquivos antes dos ajustes e aprovou com `exit 0` na Rodada 2) | **Aprovado (`SHELLCHECK_EXIT_CODE=0`)** |
| `.github/workflows/ci.yaml` | Pipeline GitHub Actions | — | — | Criado localmente no repositório | **Criado localmente; ainda não executado no GitHub Actions** (sem push remoto) |

---

## 4. Rastreabilidade dos 18 testes obrigatórios da Seção 15 do guia

| # | Requisito obrigatório (Seção 15 do guia) | Onde está implementado | Status de execução |
|---:|---|---|---|
| 1 | Parser: flags válidas/inválidas, conflitos, precedência e dados maliciosos em `terminal.conf` não executados | `tests/unit/test_phase1_contract.sh` (Seções 6 e 7) | **Executado e aprovado** |
| 2 | `--help` / `--version` em ambiente somente leitura, sem `mkdir`/log/`sudo` | `tests/unit/test_phase1_contract.sh` (Seção 3) | **Executado e aprovado** |
| 3 | `--dry-run` com mocks de comandos administrativos e snapshot antes/depois; nenhuma escrita ou rede | `tests/unit/test_phase1_contract.sh` (Seção 5) e `test_ubuntu2404_container.sh` (Seção 10) | **Executado e aprovado** |
| 4 | `--non-interactive` com `stdin` fechado e timeout: não trava nem pede senha | `tests/unit/test_phase1_contract.sh` (Seção 6) e `test_phase3_packages_tools_plugins.sh` (Seção 4) | **Executado e aprovado** |
| 5 | `--yes` não altera identidade nem shell nem sobrescreve conflitos | `tests/unit/test_phase1_contract.sh` (Seção 6) | **Executado e aprovado** |
| 6 | Instalação limpa em Ubuntu suportado | `docker/Dockerfile` + `tests/integration/test_ubuntu2404_container.sh` (Seções 1–6) | **Executado e aprovado** (perfil `developer`) |
| 7 | Segunda instalação idempotente | `tests/unit/test_phase2_state_and_reversibility.sh` (Seção 3) e `test_ubuntu2404_container.sh` (Seção 8) | **Executado e aprovado** |
| 8 | Configuração existente, `ZDOTDIR` customizado, espaços em caminhos e symlinks | `tests/unit/test_phase2_state_and_reversibility.sh` (Seções 5, 6 e 7) | **Executado e aprovado** |
| 9 | Backup/restore e recusa de remoção de arquivo posteriormente editado | `tests/unit/test_phase2_state_and_reversibility.sh` (Seção 11) e `test_ubuntu2404_container.sh` (Seção 11) | **Executado e aprovado** |
| 10 | Downloads com falha, checksum incorreto, anti-*tar-slip* (`../evil.txt`) e arquitetura não suportada | `tests/unit/test_phase3_packages_tools_plugins.sh` (Seção 6) e `test_ubuntu2404_container.sh` (Seção 5) | **Executado e aprovado** |
| 11 | Git ausente / `--skip-git` e plugins dependentes | `tests/unit/test_phase1_contract.sh` (Seção 6) e `test_phase3_packages_tools_plugins.sh` (Seção 6) | **Executado e aprovado** |
| 12 | `bash -n` em cada script Bash e `zsh -n` em cada arquivo Zsh separadamente | `tests/unit/test_phase2_state_and_reversibility.sh` (Seção 1) e `test_ubuntu2404_container.sh` (Seção 6) | **Executado e aprovado** |
| 13 | Shell interativo de smoke test sem mensagens de erro e sem chamadas de rede | `tests/unit/test_phase2_state_and_reversibility.sh` (Seção 4) e `test_ubuntu2404_container.sh` (Seção 7, `--network none`) | **Executado e aprovado** |
| 14 | Docker build sem `stdin`/senha e execução final com `UID != 0` | `docker/Dockerfile` + `test_ubuntu2404_container.sh` (Seção 1: `dev`, `UID 1001`) | **Executado e aprovado** |
| 15 | Isolamento: arquivos do usuário `dev` não ficam em `/root` | `test_ubuntu2404_container.sh` (Seção 2) + container `--user 0:0 --read-only` (`13 PASS`) | **Executado e aprovado** |
| 16 | Verificar que segredos e `terminal.conf` locais não entram no contexto/camadas da imagem | `tests/unit/test_phase4_docker_contract.sh` + `test_ubuntu2404_container.sh` (Seção 3) | **Executado e aprovado** |
| 17 | Manifesto malformado / com path traversal ou symlink escapando não consegue remover arquivos externos | `tests/unit/test_phase2_state_and_reversibility.sh` (Seção 12: `12a`–`12f`) | **Executado e aprovado** |
| 18 | Falha de uma instalação não remove arquivos anteriores nem mascara o status de saída | `tests/unit/test_phase3_packages_tools_plugins.sh` (Seção 6) e trap `ts_on_exit` em `install-terminal.sh` | **Executado e aprovado** |

