# Suítes de Testes Automatizados (`tests/`)

Este diretório contém as suítes de testes unitários, adaptadores Bats-core e testes de integração em container do projeto `terminal-setup` para **Ubuntu 24.04 LTS (`amd64`)**.

---

## 1. Estrutura do diretório `tests/`

```text
tests/
├── README.md                                       (este documento)
├── bats/
│   ├── test_phase1_contract.bats                   (adaptador Bats -> Fase 1)
│   ├── test_phase2_state_and_reversibility.bats    (adaptador Bats -> Fase 2)
│   ├── test_phase3_packages_tools_plugins.bats     (adaptador Bats -> Fase 3)
│   └── test_phase4_docker_contract.bats            (adaptador Bats -> Fase 4)
├── unit/
│   ├── test_phase1_contract.sh                     (57 verificações internas)
│   ├── test_phase2_state_and_reversibility.sh      (56 verificações internas)
│   ├── test_phase3_packages_tools_plugins.sh       (29 verificações internas)
│   └── test_phase4_docker_contract.sh              (19 verificações internas)
└── integration/
    └── test_ubuntu2404_container.sh                (57 verificações internas em container)
```

> **Nota sobre `tests/fixtures/`:** as fixtures de teste (como arquivos `terminal.conf` válidos e maliciosos, manifestos JSON com tentativa de path traversal, symlinks com alvo literal `__NULL__`, repositórios Git locais e pacotes `.tar.gz` sintéticos com `../evil.txt` e `/etc/evil.txt`) são geradas dinamicamente dentro do diretório temporário exclusivo de cada execução (`mktemp -d` em `/tmp`) e removidas automaticamente via `trap cleanup EXIT`. Isso evita deixar artefatos malformados permanentes na árvore do repositório.

---

## 2. Distinção entre testes Bats e verificações internas dos scripts

Os arquivos em `tests/bats/*.bats` são adaptadores para o runner **Bats-core**, permitindo integrar as suítes existentes em pipelines e relatórios TAP/Bats sem renomear scripts `.sh` para `.bats`:

| Arquivo `.bats` | Testes Bats (`@test`) | Script `.sh` invocado | Verificações internas (`[PASS]`/`[FAIL]`) |
|---|---:|---|---:|
| `tests/bats/test_phase1_contract.bats` | `1` | `tests/unit/test_phase1_contract.sh` | `57` |
| `tests/bats/test_phase2_state_and_reversibility.bats` | `1` | `tests/unit/test_phase2_state_and_reversibility.sh` | `56` |
| `tests/bats/test_phase3_packages_tools_plugins.bats` | `1` | `tests/unit/test_phase3_packages_tools_plugins.sh` | `29` |
| `tests/bats/test_phase4_docker_contract.bats` | `1` | `tests/unit/test_phase4_docker_contract.sh` | `19` |
| **Total unitário** | **4 testes Bats** | **4 scripts `.sh`** | **161 verificações internas** |

Além dos `4` adaptadores Bats (que invocam `161` verificações internas), a validação em containers Ubuntu 24.04 `amd64` (`--network none`) diferencia:
- **Perfil `developer`:** suíte completa de integração [`tests/integration/test_ubuntu2404_container.sh`](integration/test_ubuntu2404_container.sh) com **57 verificações internas**, execução das 4 suítes unitárias (**161 verificações internas**) e inspeção separada de `/root` (`--user 0:0 --read-only`, **14 caminhos verificados**);
- **Perfis `minimal` e `server`:** verificações enxutas específicas por perfil (**6 blocos de verificação** cada: usuário não-root `dev` sem `sudo`, comandos obrigatórios do perfil presentes, ferramentas/plugins fora do perfil ausentes, inicialização de `zsh -i -c` sem erros em `stderr` nem aliases invasivos, `doctor.sh --profile <perfil>` humano e `--json` com `0` erros, e segunda execução registrando entradas como `action=unchanged` no manifesto) mais inspeção separada de `/root` (**14 caminhos verificados** em cada perfil).

---

## 3. Onde e como executar cada suíte

### 3.1. Suítes unitárias em Bash puro (host ou container, sem rede e sem `sudo`)

Podem ser executadas como **usuário comum** tanto no host Linux de desenvolvimento quanto dentro do container Ubuntu 24.04. Elas operam exclusivamente em diretórios temporários sob `/tmp` e não alteram o `$HOME` real:

```bash
# [Executar como USUÁRIO COMUM no host ou no container]
bash ./tests/unit/test_phase1_contract.sh
bash ./tests/unit/test_phase2_state_and_reversibility.sh
bash ./tests/unit/test_phase3_packages_tools_plugins.sh
bash ./tests/unit/test_phase4_docker_contract.sh
```

### 3.2. Execução via runner Bats-core (em container de qualidade ou Ubuntu 24.04 com `bats`)

```bash
# [Executar como USUÁRIO COMUM em ambiente onde 'bats' esteja disponível]
bats tests/bats/
```

### 3.3. Suíte de integração real (somente dentro de container Ubuntu 24.04 `amd64`)

A suíte `tests/integration/test_ubuntu2404_container.sh` modifica `/home/dev` durante os testes de idempotência, conflito, desinstalação e reinstalação. **Execute-a apenas dentro do container descartável Ubuntu 24.04** (com `--network none`):

```bash
# [Executar no HOST para rodar dentro de um container descartável sem rede]
docker run --rm --network none terminal-setup:dev \
  bash /opt/terminal-setup/tests/integration/test_ubuntu2404_container.sh
```

