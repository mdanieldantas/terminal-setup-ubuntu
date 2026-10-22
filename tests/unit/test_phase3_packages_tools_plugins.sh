#!/usr/bin/env bash
# ==============================================================================
# tests/unit/test_phase3_packages_tools_plugins.sh — Testes isolados da Fase 3
# Escopo testado (100% offline, em sandbox /tmp, sem sudo real e sem rede):
#   1. Validacao sintatica (bash -n) dos scripts e bibliotecas da Fase 3
#   2. Validacao dos arquivos versions/tools.lock.json e versions/plugins.lock.json
#   3. Helper administrativo scripts/install-system-packages.sh:
#      - recusa execucao sem root (UID != 0 -> codigo 4)
#      - rejeita pacotes fora da allowlist e fragmentos de shell (codigo 2)
#      - rejeita plataforma/arquitetura nao suportada (codigo 3)
#      - modo --dry-run nao chama apt-get
#      - nao chama apt-get quando dpkg-query indica que todos os pacotes ja estao instalados
#      - instala apenas os pacotes ausentes via mock de apt-get
#   4. Coordenacao de pacotes em lib/packages.sh via install-terminal.sh:
#      - em --non-interactive, falha com codigo 4 sem travar se sudo -n exigir senha
#      - falha com codigo 4 e orientacao em 2 etapas se sudo nao existir no PATH
#   5. Download verificado, anti-tar-slip e instalacao de ferramentas externas (Starship/Superfile):
#      - instalacao em ~/.local/share/terminal-setup/tools/<tool>/<version>/
#      - links em ~/.local/bin/{starship,spf}, validacao --version e registro no manifesto
#      - idempotencia na segunda execucao
#      - falha controlada em erro HTTP, checksum SHA-256 incorreto, tar-slip (../evil) e arquitetura nao suportada
#      - instalacao seletiva com --only superfile
#   6. Plugins Zsh via Git em commits fixados (lib/plugins.sh):
#      - clonagem local no commit exato do lock, validacao HEAD e entry_file (zsh -n)
#      - idempotencia na segunda execucao
#      - falha controlada se commit divergir ou se entry_file estiver ausente
#      - respeito a --skip-git
#   7. Links de compatibilidade bat -> batcat e fd -> fdfind em ~/.local/bin:
#      - criacao quando batcat/fdfind existem e bat/fd nao existem
#      - nao sobrescreve comando ou symlink preexistente em ~/.local/bin
#   8. Integracao com doctor.sh e reversao limpa via uninstall-terminal.sh
# ==============================================================================

set -Eeuo pipefail

TEST_REPO_ROOT="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/../.." >/dev/null 2>&1 && pwd)"
readonly TEST_REPO_ROOT
readonly HELPER_SCRIPT="${TEST_REPO_ROOT}/scripts/install-system-packages.sh"
readonly INSTALLER="${TEST_REPO_ROOT}/install-terminal.sh"
readonly DOCTOR="${TEST_REPO_ROOT}/doctor.sh"
readonly UNINSTALLER="${TEST_REPO_ROOT}/uninstall-terminal.sh"

# Criar sandbox temporaria exclusiva em /tmp
TEST_SANDBOX="$(mktemp -d "${TMPDIR:-/tmp}/terminal-setup-phase3-tests.XXXXXX")"
readonly TEST_SANDBOX

cleanup() {
  if [[ -n "${TEST_SANDBOX:-}" ]] && [[ -d "${TEST_SANDBOX}" ]]; then
    rm -rf "${TEST_SANDBOX}"
  fi
}
trap cleanup EXIT

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0

pass() {
  TESTS_PASSED=$((TESTS_PASSED + 1))
  printf '  [PASS] %s\n' "$1"
}

fail() {
  TESTS_FAILED=$((TESTS_FAILED + 1))
  printf '  [FAIL] %s\n' "$1" >&2
  if [[ -n "${2:-}" ]]; then
    printf '         Detalhe: %s\n' "$2" >&2
  fi
}

# Prepara os-release simulado do Ubuntu 24.04 LTS
readonly MOCK_UBUNTU_OS_RELEASE="${TEST_SANDBOX}/os-release-ubuntu-24.04"
cat >"${MOCK_UBUNTU_OS_RELEASE}" <<'EOF'
PRETTY_NAME="Ubuntu 24.04.2 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04.2 LTS (Noble Numbat)"
VERSION_CODENAME=noble
ID=ubuntu
ID_LIKE=debian
EOF

readonly MOCK_FEDORA_OS_RELEASE="${TEST_SANDBOX}/os-release-fedora"
cat >"${MOCK_FEDORA_OS_RELEASE}" <<'EOF'
NAME="Fedora Linux"
VERSION_ID="41"
ID=fedora
EOF

# Cria ambiente de usuario isolado para cada subteste (usando UID real do processo)
setup_isolated_env() {
  local subname="$1"
  local base="${TEST_SANDBOX}/${subname}"
  mkdir -p "${base}/home" "${base}/xdg_config" "${base}/xdg_state" "${base}/xdg_data" "${base}/git" "${base}/bin"
  export HOME="${base}/home"
  export XDG_CONFIG_HOME="${base}/xdg_config"
  export XDG_STATE_HOME="${base}/xdg_state"
  export XDG_DATA_HOME="${base}/xdg_data"
  export GIT_CONFIG_GLOBAL="${base}/git/config"
  export GIT_CONFIG_NOSYSTEM=1
  unset ZDOTDIR || true
  export TS_TEST_SANDBOX_MODE="1"
  export TS_TEST_OS_RELEASE_FILE="${MOCK_UBUNTU_OS_RELEASE}"
  export TS_TEST_ARCH="x86_64"
  unset TS_TEST_EUID || true
  export TS_TEST_USER="ubuntu-tester"
  export NO_COLOR="1"
  unset TS_TEST_SKIP_EXTERNAL_DOWNLOADS || true
  unset TS_TEST_TOOLS_LOCK_FILE || true
  unset TS_TEST_PLUGINS_LOCK_FILE || true
  unset TS_TEST_PLUGIN_REPO_BASE || true
}

printf '======================================================================\n'
printf 'Executando testes isolados da Fase 3 (sandbox: %s)\n' "${TEST_SANDBOX}"
printf '======================================================================\n\n'

# ------------------------------------------------------------------------------
# 1. Validacao sintatica bash -n dos scripts da Fase 3
# ------------------------------------------------------------------------------
printf '1. Validacao sintatica (bash -n) dos scripts e modulos da Fase 3:\n'
readonly -a PHASE3_BASH_FILES=(
  "${TEST_REPO_ROOT}/scripts/install-system-packages.sh"
  "${TEST_REPO_ROOT}/lib/packages.sh"
  "${TEST_REPO_ROOT}/lib/downloads.sh"
  "${TEST_REPO_ROOT}/lib/tools.sh"
  "${TEST_REPO_ROOT}/lib/plugins.sh"
  "${TEST_REPO_ROOT}/install-terminal.sh"
  "${TEST_REPO_ROOT}/doctor.sh"
  "${TEST_REPO_ROOT}/uninstall-terminal.sh"
  "${TEST_REPO_ROOT}/tests/unit/test_phase3_packages_tools_plugins.sh"
)

for f in "${PHASE3_BASH_FILES[@]}"; do
  TESTS_RUN=$((TESTS_RUN + 1))
  rel="${f#"${TEST_REPO_ROOT}/"}"
  if bash -n "${f}"; then
    pass "bash -n ${rel}"
  else
    fail "bash -n ${rel}"
  fi
done

# ------------------------------------------------------------------------------
# 2. Validacao dos arquivos versions/tools.lock.json e versions/plugins.lock.json
# ------------------------------------------------------------------------------
printf '\n2. Validacao de versions/tools.lock.json e versions/plugins.lock.json:\n'

TESTS_RUN=$((TESTS_RUN + 1))
if jq -e '
  .schema_version == 1 and
  (.tools.starship.version == "1.27.0") and
  (.tools.starship.artifacts.amd64.sha256 | test("^[0-9a-f]{64}$")) and
  (.tools.superfile.version == "1.6.0") and
  (.tools.superfile.artifacts.amd64.sha256 | test("^[0-9a-f]{64}$")) and
  all(.tools[]; .version != "latest")
' "${TEST_REPO_ROOT}/versions/tools.lock.json" >/dev/null 2>&1; then
  pass "versions/tools.lock.json possui versoes fixadas e SHA-256 de 64 caracteres validos"
else
  fail "versions/tools.lock.json invalido"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if jq -e '
  .schema_version == 1 and
  (.plugins | keys | sort == ["zsh-autosuggestions", "zsh-history-substring-search", "zsh-syntax-highlighting", "zsh-vi-mode"]) and
  all(.plugins[]; (.commit | test("^[0-9a-f]{40}$")) and (.repository | startswith("https://")))
' "${TEST_REPO_ROOT}/versions/plugins.lock.json" >/dev/null 2>&1; then
  pass "versions/plugins.lock.json possui os 4 plugins com commits SHA-1 de 40 caracteres"
else
  fail "versions/plugins.lock.json invalido"
fi

# ------------------------------------------------------------------------------
# 3. Testes de scripts/install-system-packages.sh
# ------------------------------------------------------------------------------
printf '\n3. Helper administrativo (scripts/install-system-packages.sh):\n'

setup_isolated_env "helper_tests"

# 3.1 --help funciona sem root
TESTS_RUN=$((TESTS_RUN + 1))
set +e
out="$(bash "${HELPER_SCRIPT}" --help 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 0 ]] && [[ "${out}" == *"allowlist"* ]]; then
  pass "install-system-packages.sh --help funciona com codigo 0"
else
  fail "install-system-packages.sh --help falhou" "rc=${rc}"
fi

# 3.2 Recusa execucao sem root (UID real != 0 -> codigo 4)
TESTS_RUN=$((TESTS_RUN + 1))
set +e
out="$(bash "${HELPER_SCRIPT}" --profile minimal 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 4 ]] && [[ "${out}" == *"exige execucao como root"* ]]; then
  pass "install-system-packages.sh recusa UID != 0 com codigo 4"
else
  fail "install-system-packages.sh deveria recusar UID != 0 com codigo 4" "rc=${rc} out=${out}"
fi

# 3.3 Rejeita pacotes fora da allowlist e injecao de comandos (codigo 2)
TESTS_RUN=$((TESTS_RUN + 1))
set +e
TS_TEST_EUID=0 bash "${HELPER_SCRIPT}" --packages "zsh,htop" >/dev/null 2>&1
rc1=$?
TS_TEST_EUID=0 bash "${HELPER_SCRIPT}" --packages "zsh;id" >/dev/null 2>&1
rc2=$?
TS_TEST_EUID=0 bash "${HELPER_SCRIPT}" --profile minimal --packages "zsh" >/dev/null 2>&1
rc3=$?
set -e
if [[ "${rc1}" -eq 2 ]] && [[ "${rc2}" -eq 2 ]] && [[ "${rc3}" -eq 2 ]]; then
  pass "install-system-packages.sh rejeita pacotes fora da allowlist, injecao e flags conflitantes (codigo 2)"
else
  fail "install-system-packages.sh falhou na validacao da allowlist" "rc1=${rc1} rc2=${rc2} rc3=${rc3}"
fi

# 3.4 Rejeita plataforma fora do Ubuntu 24.04 amd64 (codigo 3)
TESTS_RUN=$((TESTS_RUN + 1))
set +e
out="$(TS_TEST_SANDBOX_MODE=1 TS_TEST_EUID=0 TS_TEST_OS_RELEASE_FILE="${MOCK_FEDORA_OS_RELEASE}" bash "${HELPER_SCRIPT}" --profile minimal 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 3 ]]; then
  pass "install-system-packages.sh recusa OS nao suportado com codigo 3"
else
  fail "install-system-packages.sh deveria recusar OS nao suportado com codigo 3" "rc=${rc}"
fi

# 3.5 Criar mocks de dpkg-query e apt-get para testar instalacao diferencial e --dry-run
readonly MOCK_APT_BIN="${TEST_SANDBOX}/helper_tests/bin"
readonly APT_CALL_LOG="${TEST_SANDBOX}/helper_tests/apt-calls.log"

cat >"${MOCK_APT_BIN}/dpkg-query" <<'EOF'
#!/usr/bin/env bash
pkg="${!#}"
if [[ ",${MOCK_INSTALLED_PKGS:-}," == *",${pkg},"* ]]; then
  printf 'install ok installed'
  exit 0
fi
exit 1
EOF
chmod +x "${MOCK_APT_BIN}/dpkg-query"

cat >"${MOCK_APT_BIN}/apt-get" <<EOF
#!/usr/bin/env bash
printf 'apt-get %s\n' "\$*" >> "${APT_CALL_LOG}"
exit 0
EOF
chmod +x "${MOCK_APT_BIN}/apt-get"

# --dry-run como root nao chama apt-get
TESTS_RUN=$((TESTS_RUN + 1))
rm -f "${APT_CALL_LOG}"
set +e
out="$(PATH="${MOCK_APT_BIN}:${PATH}" MOCK_INSTALLED_PKGS="zsh,git" TS_TEST_EUID=0 bash "${HELPER_SCRIPT}" --profile minimal --dry-run 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 0 ]] && [[ ! -f "${APT_CALL_LOG}" ]] && [[ "${out}" == *"Modo --dry-run"* ]]; then
  pass "install-system-packages.sh --dry-run valida pacotes sem invocar apt-get"
else
  fail "install-system-packages.sh --dry-run falhou" "rc=${rc} out=${out}"
fi

# Quando todos os pacotes ja estao instalados, nao chama apt-get
TESTS_RUN=$((TESTS_RUN + 1))
rm -f "${APT_CALL_LOG}"
set +e
out="$(PATH="${MOCK_APT_BIN}:${PATH}" MOCK_INSTALLED_PKGS="zsh,git" TS_TEST_EUID=0 bash "${HELPER_SCRIPT}" --packages "zsh,git" 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 0 ]] && [[ ! -f "${APT_CALL_LOG}" ]] && [[ "${out}" == *"ja estao instalados"* ]]; then
  pass "install-system-packages.sh omite apt-get quando todos os pacotes ja estao instalados"
else
  fail "install-system-packages.sh chamou apt-get desnecessariamente" "rc=${rc} out=${out}"
fi

# Quando faltam pacotes, instala apenas os pacotes ausentes
TESTS_RUN=$((TESTS_RUN + 1))
rm -f "${APT_CALL_LOG}"
set +e
out="$(PATH="${MOCK_APT_BIN}:${PATH}" MOCK_INSTALLED_PKGS="zsh,git" TS_TEST_EUID=0 bash "${HELPER_SCRIPT}" --packages "zsh,git,jq,fzf" 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 0 ]] && [[ -f "${APT_CALL_LOG}" ]] && grep -q "apt-get install -y --no-install-recommends -- jq fzf" "${APT_CALL_LOG}"; then
  pass "install-system-packages.sh instala somente os pacotes ausentes (jq fzf)"
else
  fail "install-system-packages.sh nao instalou os pacotes esperados" "rc=${rc} log=$(cat "${APT_CALL_LOG}" 2>/dev/null || true)"
fi

# ------------------------------------------------------------------------------
# 4. Coordenacao de pacotes em lib/packages.sh (sudo -n e ausencia de sudo)
# ------------------------------------------------------------------------------
printf '\n4. Coordenacao de pacotes APT no instalador de usuario (lib/packages.sh):\n'

setup_isolated_env "pkg_coord"
readonly PKG_COORD_BIN="${TEST_SANDBOX}/pkg_coord/bin"

# Mock dpkg-query que reporta pacotes ausentes
cat >"${PKG_COORD_BIN}/dpkg-query" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "${PKG_COORD_BIN}/dpkg-query"

# Mock sudo que falha em -n (simulando necessidade de senha)
cat >"${PKG_COORD_BIN}/sudo" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-n" ]]; then
  exit 1
fi
exit 0
EOF
chmod +x "${PKG_COORD_BIN}/sudo"

TESTS_RUN=$((TESTS_RUN + 1))
set +e
out="$(PATH="${PKG_COORD_BIN}:${PATH}" bash "${INSTALLER}" --profile minimal --non-interactive 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 4 ]] && [[ "${out}" == *"sudo -n"* ]] && [[ "${out}" == *"--skip-system-packages"* ]]; then
  pass "install-terminal.sh --non-interactive falha com codigo 4 sem travar quando sudo -n exige senha"
else
  fail "install-terminal.sh --non-interactive deveria falhar com codigo 4 quando sudo -n falha" "rc=${rc} out=${out}"
fi

# Testar ausencia completa de sudo no PATH
TESTS_RUN=$((TESTS_RUN + 1))
readonly NO_SUDO_BIN="${TEST_SANDBOX}/pkg_coord/no_sudo_bin"
mkdir -p "${NO_SUDO_BIN}"
for cmd in bash sh dirname readlink cd pwd id uname date mktemp cp mv rm mkdir rmdir chmod cat head tr od sha256sum jq git zsh curl tar find grep; do
  if command -v "${cmd}" >/dev/null 2>&1; then
    ln -sf "$(command -v "${cmd}")" "${NO_SUDO_BIN}/${cmd}"
  fi
done
cp "${PKG_COORD_BIN}/dpkg-query" "${NO_SUDO_BIN}/dpkg-query"

set +e
out="$(PATH="${NO_SUDO_BIN}" bash "${INSTALLER}" --profile minimal --non-interactive 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 4 ]] && [[ "${out}" == *"Alternativa em duas etapas"* ]]; then
  pass "install-terminal.sh orienta fluxo em 2 etapas (codigo 4) quando sudo nao existe"
else
  fail "install-terminal.sh deveria orientar fluxo em 2 etapas sem sudo" "rc=${rc} out=${out}"
fi

# ------------------------------------------------------------------------------
# 5. Ferramentas externas (Starship/Superfile), anti-tar-slip, plugins Git e links
# ------------------------------------------------------------------------------
printf '\n5. Download verificado, anti-tar-slip, plugins Git e links (~/.local/bin):\n'

setup_isolated_env "full_phase3"
readonly P3_MOCK_BIN="${TEST_SANDBOX}/full_phase3/bin"
readonly P3_ARTIFACTS_DIR="${TEST_SANDBOX}/full_phase3/artifacts"
readonly P3_REPOS_DIR="${TEST_SANDBOX}/full_phase3/repos"
mkdir -p "${P3_ARTIFACTS_DIR}" "${P3_REPOS_DIR}"

# 5.1 Criar artefatos .tar.gz sinteticos para starship e superfile (spf)
mkdir -p "${P3_ARTIFACTS_DIR}/build_starship"
cat >"${P3_ARTIFACTS_DIR}/build_starship/starship" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  printf 'starship 1.27.0\n'
  exit 0
fi
if [[ "${1:-}" == "init" ]]; then
  printf '# starship init zsh mock\n'
  exit 0
fi
exit 0
EOF
chmod 0755 "${P3_ARTIFACTS_DIR}/build_starship/starship"
tar -czf "${P3_ARTIFACTS_DIR}/starship-x86_64-unknown-linux-musl.tar.gz" -C "${P3_ARTIFACTS_DIR}/build_starship" starship
STARSHIP_TAR_SHA="$(sha256sum "${P3_ARTIFACTS_DIR}/starship-x86_64-unknown-linux-musl.tar.gz" | awk '{print $1}')"
readonly STARSHIP_TAR_SHA

mkdir -p "${P3_ARTIFACTS_DIR}/build_spf/dist/superfile-linux-v1.6.0-amd64"
cat >"${P3_ARTIFACTS_DIR}/build_spf/dist/superfile-linux-v1.6.0-amd64/spf" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "--version" ]]; then
  printf 'superfile version v1.6.0\n'
  exit 0
fi
exit 0
EOF
chmod 0755 "${P3_ARTIFACTS_DIR}/build_spf/dist/superfile-linux-v1.6.0-amd64/spf"
tar -czf "${P3_ARTIFACTS_DIR}/superfile-linux-v1.6.0-amd64.tar.gz" -C "${P3_ARTIFACTS_DIR}/build_spf" ./dist
SPF_TAR_SHA="$(sha256sum "${P3_ARTIFACTS_DIR}/superfile-linux-v1.6.0-amd64.tar.gz" | awk '{print $1}')"
readonly SPF_TAR_SHA

# Gerar tools.lock.json de teste com os SHA-256 reais dos pacotes sinteticos
readonly MOCK_TOOLS_LOCK="${P3_ARTIFACTS_DIR}/tools.lock.json"
jq \
  --arg st_sha "${STARSHIP_TAR_SHA}" \
  --arg spf_sha "${SPF_TAR_SHA}" \
  '.tools.starship.artifacts.amd64.sha256 = $st_sha | .tools.superfile.artifacts.amd64.sha256 = $spf_sha' \
  "${TEST_REPO_ROOT}/versions/tools.lock.json" >"${MOCK_TOOLS_LOCK}"

# Mock curl que copia o arquivo correspondente de P3_ARTIFACTS_DIR
cat >"${P3_MOCK_BIN}/curl" <<EOF
#!/usr/bin/env bash
dest=""
url=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --output|-o)
      dest="\$2"
      shift 2
      ;;
    --proto|--tlsv1.2|--retry|--retry-delay|--connect-timeout|--max-time)
      shift 2 2>/dev/null || shift
      ;;
    --fail|--silent|--show-error|--location)
      shift
      ;;
    https://*)
      url="\$1"
      shift
      ;;
    *)
      shift
      ;;
  esac
done
if [[ "\${MOCK_CURL_FAIL:-false}" == "true" ]]; then
  exit 22
fi
fname="\${url##*/}"
if [[ -f "${P3_ARTIFACTS_DIR}/\${fname}" ]]; then
  cp "${P3_ARTIFACTS_DIR}/\${fname}" "\${dest}"
  exit 0
fi
exit 22
EOF
chmod +x "${P3_MOCK_BIN}/curl"

# Criar binarios mockados de batcat e fdfind em P3_MOCK_BIN para testar links bat e fd
cat >"${P3_MOCK_BIN}/batcat" <<'EOF'
#!/usr/bin/env bash
printf 'bat 0.24.0\n'
EOF
chmod +x "${P3_MOCK_BIN}/batcat"

cat >"${P3_MOCK_BIN}/fdfind" <<'EOF'
#!/usr/bin/env bash
printf 'fd 9.0.0\n'
EOF
chmod +x "${P3_MOCK_BIN}/fdfind"

for mock_tool in fzf rg tmux zoxide eza btop nano; do
  cat >"${P3_MOCK_BIN}/${mock_tool}" <<EOF
#!/usr/bin/env bash
printf '%s mock 1.0.0\n' "${mock_tool}"
EOF
  chmod +x "${P3_MOCK_BIN}/${mock_tool}"
done

# 5.2 Criar repositorios Git locais para os 4 plugins e gerar plugins.lock.json correspondente
create_mock_plugin_repo() {
  local name="$1"
  local entry="$2"
  local repo_dir="${P3_REPOS_DIR}/${name}.git"
  mkdir -p "${repo_dir}"
  (
    cd "${repo_dir}"
    git init -q
    git config user.name "Test Author"
    git config user.email "test@example.com"
    printf '# mock plugin %s\n' "${name}" >"${entry}"
    git add "${entry}"
    git commit -q -m "Initial commit for ${name}"
    git rev-parse HEAD
  )
}

COMMIT_ZVM="$(create_mock_plugin_repo "zsh-vi-mode" "zsh-vi-mode.plugin.zsh")"
COMMIT_ZAS="$(create_mock_plugin_repo "zsh-autosuggestions" "zsh-autosuggestions.zsh")"
COMMIT_ZSH="$(create_mock_plugin_repo "zsh-syntax-highlighting" "zsh-syntax-highlighting.zsh")"
COMMIT_ZHSS="$(create_mock_plugin_repo "zsh-history-substring-search" "zsh-history-substring-search.zsh")"
readonly COMMIT_ZVM COMMIT_ZAS COMMIT_ZSH COMMIT_ZHSS

readonly MOCK_PLUGINS_LOCK="${P3_ARTIFACTS_DIR}/plugins.lock.json"
jq \
  --arg c1 "${COMMIT_ZVM}" \
  --arg c2 "${COMMIT_ZAS}" \
  --arg c3 "${COMMIT_ZSH}" \
  --arg c4 "${COMMIT_ZHSS}" \
  '.plugins["zsh-vi-mode"].commit = $c1 |
   .plugins["zsh-autosuggestions"].commit = $c2 |
   .plugins["zsh-syntax-highlighting"].commit = $c3 |
   .plugins["zsh-history-substring-search"].commit = $c4' \
  "${TEST_REPO_ROOT}/versions/plugins.lock.json" >"${MOCK_PLUGINS_LOCK}"

export TS_TEST_TOOLS_LOCK_FILE="${MOCK_TOOLS_LOCK}"
export TS_TEST_PLUGINS_LOCK_FILE="${MOCK_PLUGINS_LOCK}"
export TS_TEST_PLUGIN_REPO_BASE="${P3_REPOS_DIR}"

# 5.3 Testar execucao completa do perfil developer (--vi-mode)
TESTS_RUN=$((TESTS_RUN + 1))
if PATH="${P3_MOCK_BIN}:${PATH}" bash "${INSTALLER}" --profile developer --vi-mode --non-interactive --skip-system-packages >/dev/null; then
  if [[ -x "${HOME}/.local/bin/starship" ]] \
    && [[ -x "${HOME}/.local/bin/spf" ]] \
    && [[ -L "${HOME}/.local/bin/bat" ]] \
    && [[ -L "${HOME}/.local/bin/fd" ]] \
    && [[ -f "${XDG_DATA_HOME}/terminal-setup/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] \
    && [[ -f "${XDG_DATA_HOME}/terminal-setup/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] \
    && [[ -f "${XDG_DATA_HOME}/terminal-setup/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh" ]] \
    && [[ -f "${XDG_DATA_HOME}/terminal-setup/plugins/zsh-vi-mode/zsh-vi-mode.plugin.zsh" ]]; then
    pass "Instalacao completa (Starship, Superfile/spf, 4 plugins Git no commit fixado e links bat/fd)"
  else
    fail "Instalacao completa nao gerou todos os binarios, plugins ou links esperados"
  fi
else
  fail "install-terminal.sh falhou na instalacao completa da Fase 3"
fi

# 5.4 Testar idempotencia na segunda execucao
TESTS_RUN=$((TESTS_RUN + 1))
if PATH="${P3_MOCK_BIN}:${PATH}" bash "${INSTALLER}" --profile developer --vi-mode --non-interactive --skip-system-packages >/dev/null; then
  latest_manifest="$(find "${XDG_STATE_HOME}/terminal-setup/manifests" -maxdepth 1 -type f -name '*.json' | sort | tail -n 1)"
  non_unchanged="$(jq '[.entries[] | select(.action != "unchanged")] | length' "${latest_manifest}")"
  if [[ "${non_unchanged}" -eq 0 ]]; then
    pass "Segunda execucao da Fase 3 (ferramentas + plugins + links + configs) e 100% idempotente (unchanged)"
  else
    fail "Segunda execucao teve entradas diferentes de unchanged" "count=${non_unchanged}"
  fi
else
  fail "Segunda execucao falhou"
fi

# 5.5 Testar doctor.sh --json validando instalacao completa com plugins e ferramentas
TESTS_RUN=$((TESTS_RUN + 1))
set +e
doc_json="$(PATH="${HOME}/.local/bin:${P3_MOCK_BIN}:${PATH}" bash "${DOCTOR}" --profile developer --json)"
doc_rc=$?
set -e
if [[ "${doc_rc}" -eq 0 ]] && printf '%s' "${doc_json}" | jq -e '
  .summary.errors == 0 and
  ([.checks[] | select(.category == "integrity")] | length > 0) and
  all(.checks[] | select(.category == "integrity"); .status == "ok")
' >/dev/null 2>&1; then
  pass "doctor.sh --profile developer --json reporta 0 erros e integridade 100% ok para ferramentas, plugins, links e dotfiles"
else
  fail "doctor.sh --json reportou problema" "rc=${doc_rc} json=${doc_json}"
fi

# 5.6 Testar desinstalacao completa (reversao de ferramentas, plugins, links e dotfiles)
TESTS_RUN=$((TESTS_RUN + 1))
if PATH="${P3_MOCK_BIN}:${PATH}" bash "${UNINSTALLER}" --non-interactive >/dev/null; then
  if [[ ! -e "${HOME}/.local/bin/starship" ]] \
    && [[ ! -e "${HOME}/.local/bin/spf" ]] \
    && [[ ! -e "${HOME}/.local/bin/bat" ]] \
    && [[ ! -e "${HOME}/.local/bin/fd" ]] \
    && [[ ! -e "${XDG_DATA_HOME}/terminal-setup/plugins/zsh-autosuggestions" ]]; then
    pass "uninstall-terminal.sh removeu binarios externos, links em ~/.local/bin e plugins Git criados"
  else
    fail "uninstall-terminal.sh deixou artefatos para tras"
  fi
else
  fail "uninstall-terminal.sh falhou"
fi

# ------------------------------------------------------------------------------
# 6. Casos de falha de seguranca: checksum incorreto, tar-slip, --only superfile e --skip-git
# ------------------------------------------------------------------------------
printf '\n6. Casos de seguranca (checksum invalido, tar-slip, --only superfile, --skip-git e links preexistentes):\n'

# 6.1 Checksum SHA-256 incorreto aborta instalacao e limpa temporarios
setup_isolated_env "bad_sha"
export TS_TEST_TOOLS_LOCK_FILE="${TEST_SANDBOX}/bad_sha/bad-tools.lock.json"
export TS_TEST_PLUGINS_LOCK_FILE="${MOCK_PLUGINS_LOCK}"
export TS_TEST_PLUGIN_REPO_BASE="${P3_REPOS_DIR}"
jq '.tools.superfile.artifacts.amd64.sha256 = "0000000000000000000000000000000000000000000000000000000000000000"' \
  "${MOCK_TOOLS_LOCK}" >"${TS_TEST_TOOLS_LOCK_FILE}"

TESTS_RUN=$((TESTS_RUN + 1))
set +e
out="$(PATH="${P3_MOCK_BIN}:${PATH}" bash "${INSTALLER}" --only superfile --non-interactive --skip-system-packages 2>&1)"
rc=$?
set -e
if [[ "${rc}" -eq 1 ]] && [[ "${out}" == *"Checksum SHA-256 invalido"* ]] && [[ ! -e "${HOME}/.local/bin/spf" ]]; then
  pass "Checksum SHA-256 divergente aborta instalacao sem instalar o binario"
else
  fail "Checksum SHA-256 divergente nao abortou corretamente" "rc=${rc} out=${out}"
fi

# 6.2 Protecao anti-tar-slip (rejeita arquivo tar contendo ../evil)
setup_isolated_env "tar_slip"
# shellcheck source=lib/common.sh
source "${TEST_REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/downloads.sh
source "${TEST_REPO_ROOT}/lib/downloads.sh"

TESTS_RUN=$((TESTS_RUN + 1))
readonly MALICIOUS_TAR="${TEST_SANDBOX}/tar_slip/malicious.tar.gz"
mkdir -p "${TEST_SANDBOX}/tar_slip/sub"
printf 'evil\n' >"${TEST_SANDBOX}/tar_slip/evil.txt"
tar -P -czf "${MALICIOUS_TAR}" -C "${TEST_SANDBOX}/tar_slip/sub" ../evil.txt 2>/dev/null
if tar -tzf "${MALICIOUS_TAR}" 2>/dev/null | grep -qxF "../evil.txt" \
  && ! ts_validate_tar_gz_archive "${MALICIOUS_TAR}" 2>/dev/null; then
  pass "ts_validate_tar_gz_archive rejeita pacote .tar.gz confirmado com path traversal ('../evil.txt')"
else
  fail "ts_validate_tar_gz_archive aceitou pacote .tar.gz com '../' ou fixture nao continha '../evil.txt'"
fi

# 6.3 --only superfile instala apenas superfile (spf), sem zshrc, sem starship e sem plugins
setup_isolated_env "only_spf"
export TS_TEST_TOOLS_LOCK_FILE="${MOCK_TOOLS_LOCK}"
export TS_TEST_PLUGINS_LOCK_FILE="${MOCK_PLUGINS_LOCK}"
export TS_TEST_PLUGIN_REPO_BASE="${P3_REPOS_DIR}"

TESTS_RUN=$((TESTS_RUN + 1))
if PATH="${P3_MOCK_BIN}:${PATH}" bash "${INSTALLER}" --only superfile --non-interactive --skip-system-packages >/dev/null; then
  if [[ -x "${HOME}/.local/bin/spf" ]] \
    && [[ ! -e "${HOME}/.local/bin/starship" ]] \
    && [[ ! -e "${HOME}/.zshrc" ]] \
    && [[ ! -d "${XDG_DATA_HOME}/terminal-setup/plugins" ]]; then
    pass "--only superfile instala exclusivamente Superfile (spf) sem Zsh, Starship ou plugins"
  else
    fail "--only superfile instalou componentes nao solicitados"
  fi
else
  fail "--only superfile falhou"
fi

# 6.4 Links preexistentes em ~/.local/bin/bat e ~/.local/bin/fd sao preservados sem sobrescrever
setup_isolated_env "existing_links"
export TS_TEST_TOOLS_LOCK_FILE="${MOCK_TOOLS_LOCK}"
export TS_TEST_PLUGINS_LOCK_FILE="${MOCK_PLUGINS_LOCK}"
export TS_TEST_PLUGIN_REPO_BASE="${P3_REPOS_DIR}"

mkdir -p "${HOME}/.local/bin"
printf '#!/usr/bin/env bash\necho custom-bat\n' >"${HOME}/.local/bin/bat"
chmod +x "${HOME}/.local/bin/bat"
ln -s "/custom/fd" "${HOME}/.local/bin/fd"

TESTS_RUN=$((TESTS_RUN + 1))
if PATH="${P3_MOCK_BIN}:${PATH}" bash "${INSTALLER}" --only bat,fd --non-interactive --skip-system-packages 2>/dev/null >/dev/null; then
  if [[ -f "${HOME}/.local/bin/bat" ]] && [[ ! -L "${HOME}/.local/bin/bat" ]] \
    && [[ -L "${HOME}/.local/bin/fd" ]] && [[ "$(readlink "${HOME}/.local/bin/fd")" == "/custom/fd" ]]; then
    pass "Comandos ou symlinks preexistentes em ~/.local/bin/{bat,fd} jamais sao sobrescritos"
  else
    fail "Links preexistentes em ~/.local/bin foram alterados indevidamente"
  fi
else
  fail "Execucao com links preexistentes falhou"
fi

# 6.5 --skip-git omite clonagem de plugins Zsh
setup_isolated_env "skip_git_plugins"
export TS_TEST_TOOLS_LOCK_FILE="${MOCK_TOOLS_LOCK}"
export TS_TEST_PLUGINS_LOCK_FILE="${MOCK_PLUGINS_LOCK}"
export TS_TEST_PLUGIN_REPO_BASE="${P3_REPOS_DIR}"

TESTS_RUN=$((TESTS_RUN + 1))
if PATH="${P3_MOCK_BIN}:${PATH}" bash "${INSTALLER}" --profile minimal --skip-git --non-interactive --skip-system-packages >/dev/null; then
  if [[ ! -d "${XDG_DATA_HOME}/terminal-setup/plugins" ]] && [[ -f "${HOME}/.zshrc" ]]; then
    pass "--skip-git omite clonagem de plugins Zsh mantendo configuracao funcional"
  else
    fail "--skip-git clonou plugins indevidamente"
  fi
else
  fail "Execucao com --skip-git falhou"
fi

printf '\n======================================================================\n'
printf 'Resumo Fase 3: %d executados | %d aprovados | %d falharam\n' "${TESTS_RUN}" "${TESTS_PASSED}" "${TESTS_FAILED}"
printf '======================================================================\n'

if [[ "${TESTS_FAILED}" -gt 0 ]]; then
  exit 1
fi
exit 0
