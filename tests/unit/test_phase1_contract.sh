#!/usr/bin/env bash
# ==============================================================================
# tests/unit/test_phase1_contract.sh — Suite de testes da Fase 1
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
#
# NOTA SOBRE O EXECUTOR:
#   Este script e um executor de testes em Bash puro (provisorio para ambientes
#   onde 'bats' nao esta instalado no host). Ele executa exclusivamente em um
#   diretorio temporario isolado em /tmp, com HOME e caminhos XDG falsos,
#   sem acessar o HOME real do usuario, sem usar rede e sem chamar sudo.
# ==============================================================================

set -Eeuo pipefail

# Resolver raiz do repositorio
TEST_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -P "${TEST_DIR}/../.." >/dev/null 2>&1 && pwd)"
INSTALLER="${REPO_ROOT}/install-terminal.sh"

# Criar sandbox temporario exclusivo em /tmp
SANDBOX_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/terminal-setup-phase1-tests.XXXXXX")"
cleanup() {
  if [[ -n "${SANDBOX_ROOT:-}" ]] && [[ -d "${SANDBOX_ROOT}" ]]; then
    chmod -R u+w "${SANDBOX_ROOT}" 2>/dev/null || true
    rm -rf "${SANDBOX_ROOT}"
  fi
}
trap cleanup EXIT

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[PASS] %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[FAIL] %s\n' "$1" >&2
  if [[ $# -gt 1 ]]; then
    printf '       Detalhe: %s\n' "$2" >&2
  fi
}

# Prepara um ambiente HOME/XDG limpo e mocks de comandos externos proibidos em dry-run
setup_isolated_env() {
  local case_id="$1"
  CASE_DIR="${SANDBOX_ROOT}/${case_id}"
  FAKE_HOME="${CASE_DIR}/home"
  FAKE_XDG_CONFIG="${FAKE_HOME}/.config"
  FAKE_XDG_STATE="${FAKE_HOME}/.local/state"
  FAKE_XDG_DATA="${FAKE_HOME}/.local/share"
  MOCK_BIN="${CASE_DIR}/mock-bin"
  SIDE_EFFECT_LOG="${CASE_DIR}/side-effects.log"

  mkdir -p "${FAKE_HOME}" "${MOCK_BIN}"

  # Criar mocks que registram caso sudo, apt-get, curl, git ou chsh sejam chamados
  local cmd
  for cmd in sudo apt-get apt curl wget git chsh; do
    cat > "${MOCK_BIN}/${cmd}" << EOF
#!/usr/bin/env bash
printf 'FORBIDDEN_CALL:%s %s\n' "${cmd}" "\$*" >> "${SIDE_EFFECT_LOG}"
exit 99
EOF
    chmod +x "${MOCK_BIN}/${cmd}"
  done
}

# Executa o instalador dentro do ambiente isolado capturando stdout, stderr e exit code
run_installer() {
  local extra_env_path="${1:-}"
  shift
  local effective_path="${MOCK_BIN}:/usr/bin:/bin"
  if [[ -n "${extra_env_path}" ]]; then
    effective_path="${extra_env_path}"
  fi

  OUT_STDOUT="${CASE_DIR}/stdout.txt"
  OUT_STDERR="${CASE_DIR}/stderr.txt"
  set +e
  env -i \
    HOME="${FAKE_HOME}" \
    USER="testuser" \
    PATH="${effective_path}" \
    TERM="dumb" \
    NO_COLOR="1" \
    XDG_CONFIG_HOME="${FAKE_XDG_CONFIG}" \
    XDG_STATE_HOME="${FAKE_XDG_STATE}" \
    XDG_DATA_HOME="${FAKE_XDG_DATA}" \
    TS_TEST_EUID="${TEST_EUID_OVERRIDE:-1000}" \
    TS_OS_RELEASE_FILE="${TEST_OS_RELEASE_OVERRIDE:-/etc/os-release}" \
    TS_TEST_ARCH="${TEST_ARCH_OVERRIDE:-x86_64}" \
    bash "${INSTALLER}" "$@" </dev/null >"${OUT_STDOUT}" 2>"${OUT_STDERR}"
  RUN_EXIT=$?
  set -e
}

printf '======================================================================\n'
printf 'Suite de testes da Fase 1 — terminal-setup (executor Bash isolado)\n'
printf 'Sandbox temporario: %s\n' "${SANDBOX_ROOT}"
printf '======================================================================\n\n'

# ------------------------------------------------------------------------------
# 1. Validacao individual de sintaxe (bash -n) em cada script Bash
# ------------------------------------------------------------------------------
readonly -a BASH_SCRIPTS=(
  "${REPO_ROOT}/install-terminal.sh"
  "${REPO_ROOT}/lib/common.sh"
  "${REPO_ROOT}/lib/platform.sh"
  "${REPO_ROOT}/lib/config-parser.sh"
  "${REPO_ROOT}/lib/arguments.sh"
  "${REPO_ROOT}/lib/plan.sh"
  "${REPO_ROOT}/tests/unit/test_phase1_contract.sh"
)

for script_file in "${BASH_SCRIPTS[@]}"; do
  rel_name="${script_file#"${REPO_ROOT}/"}"
  if bash -n "${script_file}"; then
    pass "bash -n individual aprovado: ${rel_name}"
  else
    fail "bash -n falhou em: ${rel_name}"
  fi
done

# ------------------------------------------------------------------------------
# 2. Recusar execucao via 'source ./install-terminal.sh'
# ------------------------------------------------------------------------------
setup_isolated_env "source-guard"
set +e
(
  # shellcheck disable=SC1090
  source "${INSTALLER}" --help
) >/dev/null 2>&1
source_rc=$?
set -e
if [[ "${source_rc}" -eq 2 ]]; then
  pass "Recusa ser carregado via 'source' com codigo 2"
else
  fail "Deveria recusar 'source' com codigo 2, mas retornou ${source_rc}"
fi

# ------------------------------------------------------------------------------
# 3. --help, -h e --version em ambiente somente leitura (sem mkdir/log/sudo)
# ------------------------------------------------------------------------------
for flag in "--help" "-h" "--version"; do
  safe_name="${flag//-/}"
  setup_isolated_env "ro-${safe_name}"
  chmod 500 "${FAKE_HOME}"
  before_snapshot="$(find "${FAKE_HOME}" -maxdepth 3 | sort)"
  run_installer "" "${flag}"
  after_snapshot="$(find "${FAKE_HOME}" -maxdepth 3 | sort)"
  chmod 700 "${FAKE_HOME}"

  if [[ "${RUN_EXIT}" -eq 0 ]] && [[ "${before_snapshot}" == "${after_snapshot}" ]] && [[ ! -e "${SIDE_EFFECT_LOG}" ]]; then
    pass "${flag} executa com codigo 0 em HOME somente leitura sem criar arquivos"
  else
    fail "${flag} falhou ou modificou estado (exit=${RUN_EXIT})" "$(cat "${OUT_STDERR}" 2>/dev/null)"
  fi
done

# ------------------------------------------------------------------------------
# 4. Recusa de execucao como root (UID 0) sem criar arquivos
# ------------------------------------------------------------------------------
setup_isolated_env "root-refusal"
TEST_EUID_OVERRIDE=0
before_snapshot="$(find "${FAKE_HOME}" -maxdepth 3 | sort)"
run_installer "" --profile minimal --dry-run
after_snapshot="$(find "${FAKE_HOME}" -maxdepth 3 | sort)"
unset TEST_EUID_OVERRIDE

if [[ "${RUN_EXIT}" -eq 4 ]] && [[ "${before_snapshot}" == "${after_snapshot}" ]] && [[ ! -e "${SIDE_EFFECT_LOG}" ]]; then
  pass "Recusa execucao como root (UID 0) com codigo 4 e sem tocar no HOME"
else
  fail "Falha no teste de recusa de root (exit=${RUN_EXIT})"
fi

# ------------------------------------------------------------------------------
# 5. --dry-run nos 3 perfis: sem escrita, sem rede/sudo e com matriz P1/P2/P3
# ------------------------------------------------------------------------------
for prof in minimal developer server; do
  setup_isolated_env "dryrun-${prof}"
  before_snapshot="$(find "${FAKE_HOME}" -maxdepth 3 | sort)"
  run_installer "" --profile "${prof}" --dry-run
  after_snapshot="$(find "${FAKE_HOME}" -maxdepth 3 | sort)"

  if [[ "${RUN_EXIT}" -eq 0 ]] && [[ "${before_snapshot}" == "${after_snapshot}" ]] && [[ ! -e "${SIDE_EFFECT_LOG}" ]]; then
    pass "--dry-run do perfil '${prof}' nao cria arquivos, logs, backups nem chama rede/sudo"
  else
    fail "--dry-run do perfil '${prof}' falhou ou teve efeito colateral (exit=${RUN_EXIT})" "$(cat "${OUT_STDERR}" 2>/dev/null)"
  fi

  # Decisao P3: jq deve estar presente em todos os perfis, inclusive minimal
  if grep -qE 'zsh.*git.*nano.*ca-certificates.*curl.*jq' "${OUT_STDOUT}"; then
    pass "Perfil '${prof}' inclui 'jq' como pacote APT base (Decisao P3)"
  else
    fail "Perfil '${prof}' nao listou 'jq' entre os pacotes APT previstos"
  fi
done

# Verificar decisoes P1 e P2 especificamente no plano do perfil developer
setup_isolated_env "dryrun-dev-matrix"
run_installer "" --profile developer --dry-run
if grep -q "fd-find tmux zoxide eza" "${OUT_STDOUT}" &&
   grep -q "starship (artefato oficial" "${OUT_STDOUT}" &&
   grep -q "superfile (artefato oficial" "${OUT_STDOUT}" &&
   grep -q "zsh-syntax-highlighting" "${OUT_STDOUT}" &&
   ! grep -q "fast-syntax-highlighting" "${OUT_STDOUT}"; then
  pass "Perfil 'developer' reflete P1 (eza/zoxide via APT; starship/superfile externos) e P2 (zsh-syntax-highlighting)"
else
  fail "Plano do perfil 'developer' divergiu das decisoes P1/P2"
fi

# ------------------------------------------------------------------------------
# 6. --dry-run funciona mesmo sem 'jq' instalado no PATH (Decisao P3)
# ------------------------------------------------------------------------------
setup_isolated_env "dryrun-without-jq"
NO_JQ_BIN="${CASE_DIR}/no-jq-bin"
mkdir -p "${NO_JQ_BIN}"
for tool_cmd in bash id uname grep wc tr sort cat mkdir rm chmod readlink dirname pwd; do
  if command -v "${tool_cmd}" >/dev/null 2>&1; then
    ln -s "$(command -v "${tool_cmd}")" "${NO_JQ_BIN}/${tool_cmd}"
  fi
done
run_installer "${NO_JQ_BIN}" --profile minimal --dry-run
if [[ "${RUN_EXIT}" -eq 0 ]] && grep -q "jq disponivel agora  : false" "${OUT_STDOUT}"; then
  pass "--dry-run funciona mesmo quando 'jq' nao esta pre-instalado no PATH (Decisao P3)"
else
  fail "--dry-run falhou sem 'jq' no PATH (exit=${RUN_EXIT})" "$(cat "${OUT_STDERR}" 2>/dev/null)"
fi

# ------------------------------------------------------------------------------
# 7. --only resolve dependencias obrigatorias e nao carrega o perfil inteiro
# ------------------------------------------------------------------------------
setup_isolated_env "only-superfile"
run_installer "" --only superfile --dry-run
if [[ "${RUN_EXIT}" -eq 0 ]] &&
   grep -q "superfile" "${OUT_STDOUT}" &&
   grep -q "ca-certificates curl jq" "${OUT_STDOUT}" &&
   ! grep -q "ripgrep" "${OUT_STDOUT}" &&
   ! grep -q "tmux" "${OUT_STDOUT}"; then
  pass "--only superfile resolve apenas superfile e suas dependencias (ca-certificates, curl, jq)"
else
  fail "--only superfile falhou na resolucao de dependencias (exit=${RUN_EXIT})"
fi

# ------------------------------------------------------------------------------
# 8. Conflitos de argumentos devem falhar com codigo 2 antes de efeitos colaterais
# ------------------------------------------------------------------------------
assert_usage_failure() {
  local label="$1"
  shift
  setup_isolated_env "conflict-${PASS_COUNT}-${FAIL_COUNT}"
  before_snapshot="$(find "${FAKE_HOME}" -maxdepth 3 | sort)"
  run_installer "" "$@"
  after_snapshot="$(find "${FAKE_HOME}" -maxdepth 3 | sort)"
  if [[ "${RUN_EXIT}" -eq 2 ]] && [[ "${before_snapshot}" == "${after_snapshot}" ]] && [[ ! -e "${SIDE_EFFECT_LOG}" ]]; then
    pass "Rejeita com codigo 2 e sem efeito colateral: ${label}"
  else
    fail "Esperava codigo 2 sem efeitos para '${label}', mas obteve exit=${RUN_EXIT}" "$(cat "${OUT_STDERR}" 2>/dev/null)"
  fi
}

assert_usage_failure "flag desconhecida" --flag-inexistente --dry-run
assert_usage_failure "argumento posicional solto" developer --dry-run
assert_usage_failure "flag booleana com valor (--dry-run=true)" --dry-run=true
assert_usage_failure "--profile sem valor" --profile
assert_usage_failure "--profile invalido" --profile inexistente --dry-run
assert_usage_failure "--only combinado com --profile" --profile developer --only superfile --dry-run
assert_usage_failure "--only combinado com --include" --only superfile --include btop --dry-run
assert_usage_failure "--only combinado com --exclude" --only superfile --exclude btop --dry-run
assert_usage_failure "mesmo componente em --include e --exclude" --profile server --include superfile --exclude superfile --dry-run
assert_usage_failure "componente desconhecido em --include" --include htop --dry-run
assert_usage_failure "lista vazia em --include" --include "" --dry-run
assert_usage_failure "item vazio em CSV (a,,b)" --include "eza,,btop" --dry-run
assert_usage_failure "excluir componente obrigatorio base (zsh)" --profile developer --exclude zsh --dry-run
assert_usage_failure "excluir componente obrigatorio base (jq)" --profile minimal --exclude jq --dry-run
assert_usage_failure "excluir git sem --skip-git" --profile minimal --exclude git --dry-run
assert_usage_failure "--vi-mode combinado com --exclude zsh-vi-mode" --vi-mode --exclude zsh-vi-mode --dry-run
assert_usage_failure "--git-name sem --git-identity configure" --git-name "Fulano" --dry-run
assert_usage_failure "--git-email invalido" --git-identity configure --git-name "Fulano" --git-email "email-invalido" --dry-run

# ------------------------------------------------------------------------------
# 9. Regras de --skip-git
# ------------------------------------------------------------------------------
setup_isolated_env "skip-git-profile"
run_installer "" --profile developer --skip-git --dry-run
if [[ "${RUN_EXIT}" -eq 0 ]] &&
   grep -q "Plugins Zsh via Git com commit fixado (0):" "${OUT_STDOUT}" &&
   grep -q "foram omitidos: git zsh-autosuggestions zsh-history-substring-search zsh-syntax-highlighting" "${OUT_STDERR}"; then
  pass "--skip-git no perfil 'developer' omite Git e plugins Zsh com aviso claro"
else
  fail "--skip-git no perfil 'developer' nao se comportou como esperado (exit=${RUN_EXIT})"
fi

assert_usage_failure "--skip-git com plugin exigido em --include" --skip-git --include zsh-autosuggestions --dry-run
assert_usage_failure "--skip-git com plugin exigido em --only" --skip-git --only zsh-autosuggestions --dry-run
assert_usage_failure "--skip-git com --vi-mode" --skip-git --vi-mode --dry-run
assert_usage_failure "--skip-git com --git-identity configure" --skip-git --git-identity configure --git-name "A" --git-email "a@b.com" --dry-run

# ------------------------------------------------------------------------------
# 10. --non-interactive vs --yes
# ------------------------------------------------------------------------------
setup_isolated_env "non-interactive-defaults"
run_installer "" --profile minimal --non-interactive --dry-run
if [[ "${RUN_EXIT}" -eq 0 ]] &&
   grep -q "Identidade Git       : skip" "${OUT_STDOUT}" &&
   grep -q "Defaults globais Git : keep" "${OUT_STDOUT}" &&
   grep -q "Troca de shell       : no" "${OUT_STDOUT}" &&
   grep -q "Politica de conflito : keep" "${OUT_STDOUT}"; then
  pass "--non-interactive converte 'ask' padrao em skip/keep/no/keep sem travar com stdin fechado"
else
  fail "--non-interactive nao converteu politicas 'ask' corretamente (exit=${RUN_EXIT})"
fi

assert_usage_failure "--non-interactive com --change-shell yes" --non-interactive --change-shell yes --dry-run
assert_usage_failure "--non-interactive com --on-conflict ask explicito" --non-interactive --on-conflict ask --dry-run
assert_usage_failure "--non-interactive com --git-identity configure sem dados" --non-interactive --git-identity configure --dry-run

setup_isolated_env "yes-preserves-decisions"
run_installer "" --profile minimal --yes --dry-run
if [[ "${RUN_EXIT}" -eq 0 ]] &&
   grep -q "Confirmacao (--yes)  : true" "${OUT_STDOUT}" &&
   grep -q "Identidade Git       : ask" "${OUT_STDOUT}" &&
   grep -q "Defaults globais Git : ask" "${OUT_STDOUT}" &&
   grep -q "Troca de shell       : ask" "${OUT_STDOUT}" &&
   grep -q "Politica de conflito : ask" "${OUT_STDOUT}" &&
   grep -q "Modo Vi (Zsh)        : false" "${OUT_STDOUT}"; then
  pass "--yes preserva decisoes pessoais/conflitos em 'ask' e vi-mode em 'false'"
else
  fail "--yes alterou indevidamente politicas pessoais ou de conflito"
fi

# ------------------------------------------------------------------------------
# 11. Parser seguro de terminal.conf (--config): precedencia e ataques
# ------------------------------------------------------------------------------
setup_isolated_env "config-precedence"
VALID_CONF="${CASE_DIR}/terminal.conf"
cat > "${VALID_CONF}" << 'EOF'
# Comentario valido
PROFILE=server
ICONS=nerd
VI_MODE=true
INCLUDE=superfile,eza
GIT_IDENTITY=configure
GIT_NAME=Maria da Silva
GIT_EMAIL=maria@example.invalid
ON_CONFLICT=backup-replace
EOF

run_installer "" --config "${VALID_CONF}" --icons plain --on-conflict keep --dry-run
if [[ "${RUN_EXIT}" -eq 0 ]] &&
   grep -q "perfil 'server'" "${OUT_STDOUT}" &&
   grep -q "Modo de icones       : plain" "${OUT_STDOUT}" &&
   grep -q "Politica de conflito : keep" "${OUT_STDOUT}" &&
   grep -q "Modo Vi (Zsh)        : true" "${OUT_STDOUT}" &&
   grep -q "superfile" "${OUT_STDOUT}"; then
  pass "Parser de --config aplica valores corretamente e respeita precedencia (defaults < --config < CLI)"
else
  fail "Falha na precedencia ou leitura de --config valido (exit=${RUN_EXIT})"
fi

# Teste de injecao maliciosa em terminal.conf: NUNCA deve executar comandos
setup_isolated_env "config-malicious"
PWN_MARKER="${CASE_DIR}/pwned.txt"
MALICIOUS_CONF="${CASE_DIR}/malicious.conf"
cat > "${MALICIOUS_CONF}" << EOF
PROFILE=minimal
GIT_IDENTITY=configure
GIT_NAME=\$(touch ${PWN_MARKER})
GIT_EMAIL=teste@example.invalid
EOF

run_installer "" --config "${MALICIOUS_CONF}" --dry-run
if [[ "${RUN_EXIT}" -eq 2 ]] && [[ ! -e "${PWN_MARKER}" ]]; then
  pass "Rejeita substituicao de comando \$(...) em terminal.conf sem executar codigo"
else
  fail "Falha grave na rejeicao de \$(...) em terminal.conf (exit=${RUN_EXIT}, pwned=$([[ -e "${PWN_MARKER}" ]] && echo yes || echo no))"
fi

# Chave duplicada em terminal.conf
DUP_CONF="${CASE_DIR}/dup.conf"
cat > "${DUP_CONF}" << 'EOF'
PROFILE=minimal
PROFILE=developer
EOF
assert_usage_failure "chave duplicada em terminal.conf" --config "${DUP_CONF}" --dry-run

# Chave desconhecida em terminal.conf
UNK_CONF="${CASE_DIR}/unk.conf"
cat > "${UNK_CONF}" << 'EOF'
PROFILE=minimal
SUDO_PASSWORD=123456
EOF
assert_usage_failure "chave desconhecida em terminal.conf" --config "${UNK_CONF}" --dry-run

# Byte NUL em terminal.conf
NUL_CONF="${CASE_DIR}/nul.conf"
printf 'PROFILE=minimal\0\n' > "${NUL_CONF}"
assert_usage_failure "byte NUL em terminal.conf" --config "${NUL_CONF}" --dry-run

# Conflito entre PROFILE em --config e --only na CLI
assert_usage_failure "PROFILE em --config combinado com --only na CLI" --config "${VALID_CONF}" --only superfile --dry-run

# Exemplo oficial examples/terminal.conf.example e aceito pelo parser
setup_isolated_env "example-conf"
run_installer "" --config "${REPO_ROOT}/examples/terminal.conf.example" --dry-run
if [[ "${RUN_EXIT}" -eq 0 ]] && grep -q "perfil 'developer'" "${OUT_STDOUT}"; then
  pass "examples/terminal.conf.example e valido e carrega sem erros em --dry-run"
else
  fail "examples/terminal.conf.example falhou no parser (exit=${RUN_EXIT})"
fi

# Requisito de jq informado claramente em operacao efetiva com --skip-system-packages quando jq esta ausente (Decisao P3)
setup_isolated_env "effective-requires-jq"
FAKE_OS_RELEASE="${CASE_DIR}/os-release-ubuntu"
cat > "${FAKE_OS_RELEASE}" << 'EOF'
ID=ubuntu
VERSION_ID="24.04"
PRETTY_NAME="Ubuntu 24.04.1 LTS"
EOF
NO_JQ_BIN2="${CASE_DIR}/no-jq-bin2"
mkdir -p "${NO_JQ_BIN2}"
for tool_cmd in bash id uname grep wc tr sort cat mkdir rm chmod readlink dirname pwd; do
  if command -v "${tool_cmd}" >/dev/null 2>&1; then
    ln -s "$(command -v "${tool_cmd}")" "${NO_JQ_BIN2}/${tool_cmd}"
  fi
done
TEST_OS_RELEASE_OVERRIDE="${FAKE_OS_RELEASE}"
run_installer "${NO_JQ_BIN2}" --profile minimal --non-interactive --skip-system-packages
unset TEST_OS_RELEASE_OVERRIDE
if [[ "${RUN_EXIT}" -eq 1 ]] && grep -q "O comando 'jq' e requisito base obrigatorio" "${OUT_STDERR}"; then
  pass "Operacao efetiva sem 'jq' e com --skip-system-packages informa requisito de 'jq' claramente (Decisao P3)"
else
  fail "Deveria informar requisito de 'jq' com codigo 1 (exit=${RUN_EXIT})" "$(cat "${OUT_STDERR}" 2>/dev/null)"
fi

printf '\n======================================================================\n'
printf 'Resumo: %d aprovados, %d falharam.\n' "${PASS_COUNT}" "${FAIL_COUNT}"
printf '======================================================================\n'

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi
exit 0
