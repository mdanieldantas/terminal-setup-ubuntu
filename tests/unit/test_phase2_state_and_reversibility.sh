#!/usr/bin/env bash
# ==============================================================================
# tests/unit/test_phase2_state_and_reversibility.sh — Suite de testes da Fase 2
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
#
# NOTA SOBRE O EXECUTOR E ISOLAMENTO:
#   Executor em Bash puro (provisorio enquanto 'bats' nao esta instalado no host).
#   Cria um diretorio temporario exclusivo em /tmp, definindo HOME, XDG_* e
#   GIT_CONFIG_GLOBAL dentro dele. Nenhum arquivo do usuario real e lido ou
#   modificado. Nao utiliza sudo, APT, chsh, Docker, Podman ou rede.
# ==============================================================================

set -Eeuo pipefail

TEST_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
REPO_ROOT="$(cd -P "${TEST_DIR}/../.." >/dev/null 2>&1 && pwd)"
INSTALLER="${REPO_ROOT}/install-terminal.sh"
DOCTOR="${REPO_ROOT}/doctor.sh"
UNINSTALLER="${REPO_ROOT}/uninstall-terminal.sh"

# Criar sandbox temporario exclusivo em /tmp com validacao rigorosa antes de limpar
SANDBOX_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/terminal-setup-phase2-tests.XXXXXX")"
# shellcheck disable=SC2317 # funcao invocada indiretamente via trap EXIT
cleanup() {
  if [[ -n "${SANDBOX_ROOT:-}" ]] \
    && [[ "${SANDBOX_ROOT}" == */terminal-setup-phase2-tests.* ]] \
    && [[ -d "${SANDBOX_ROOT}" ]]; then
    chmod -R u+w "${SANDBOX_ROOT}" 2>/dev/null || true
    rm -rf -- "${SANDBOX_ROOT}"
  fi
}
trap cleanup EXIT

latest_file_in_dir() {
  local dir="$1"
  local pattern="$2"
  find "${dir}" -maxdepth 1 -type f -name "${pattern}" | sort | tail -n 1
}

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

# Prepara um ambiente HOME/XDG/GIT totalmente isolado dentro de SANDBOX_ROOT
setup_case_sandbox() {
  local case_id="$1"
  CASE_DIR="${SANDBOX_ROOT}/${case_id}"
  FAKE_HOME="${CASE_DIR}/home"
  FAKE_XDG_CONFIG="${FAKE_HOME}/.config"
  FAKE_XDG_STATE="${FAKE_HOME}/.local/state"
  FAKE_XDG_DATA="${FAKE_HOME}/.local/share"
  FAKE_GITCONFIG="${FAKE_HOME}/.gitconfig"
  MOCK_BIN="${CASE_DIR}/mock-bin"
  SIDE_EFFECT_LOG="${CASE_DIR}/side-effects.log"
  FAKE_OS_RELEASE="${CASE_DIR}/os-release-ubuntu"

  mkdir -p "${FAKE_HOME}" "${MOCK_BIN}"

  cat >"${FAKE_OS_RELEASE}" <<'EOF'
ID=ubuntu
VERSION_ID="24.04"
PRETTY_NAME="Ubuntu 24.04.1 LTS"
EOF

  # Mocks para comandos administrativos ou de rede proibidos nesta fase
  local cmd
  for cmd in sudo apt-get apt curl wget chsh; do
    cat >"${MOCK_BIN}/${cmd}" <<EOF
#!/usr/bin/env bash
printf 'FORBIDDEN_CALL:%s %s\n' "${cmd}" "\$*" >> "${SIDE_EFFECT_LOG}"
exit 99
EOF
    chmod +x "${MOCK_BIN}/${cmd}"
  done
}

# Executa qualquer script (install-terminal.sh, doctor.sh, uninstall-terminal.sh) na sandbox
# Usa o UID real do processo no kernel (sem assumir 1000 e sem herdar override externo).
run_in_sandbox() {
  local script_path="$1"
  shift
  OUT_STDOUT="${CASE_DIR}/stdout.txt"
  OUT_STDERR="${CASE_DIR}/stderr.txt"
  local zdot_env=()
  if [[ -n "${CUSTOM_ZDOTDIR_VALUE:-}" ]]; then
    zdot_env=(ZDOTDIR="${CUSTOM_ZDOTDIR_VALUE}")
  fi

  set +e
  env -i \
    HOME="${FAKE_HOME}" \
    USER="sandboxuser" \
    PATH="${MOCK_BIN}:/usr/bin:/bin" \
    TERM="dumb" \
    NO_COLOR="1" \
    XDG_CONFIG_HOME="${FAKE_XDG_CONFIG}" \
    XDG_STATE_HOME="${FAKE_XDG_STATE}" \
    XDG_DATA_HOME="${FAKE_XDG_DATA}" \
    GIT_CONFIG_GLOBAL="${FAKE_GITCONFIG}" \
    GIT_CONFIG_NOSYSTEM="1" \
    TS_TEST_SANDBOX_MODE="1" \
    TS_TEST_OS_RELEASE_FILE="${FAKE_OS_RELEASE}" \
    TS_TEST_ARCH="x86_64" \
    TS_TEST_SKIP_EXTERNAL_DOWNLOADS="true" \
    "${zdot_env[@]}" \
    bash "${script_path}" "$@" </dev/null >"${OUT_STDOUT}" 2>"${OUT_STDERR}"
  RUN_EXIT=$?
  set -e
}

printf '======================================================================\n'
printf 'Suite de testes da Fase 2 — Estado, Backups, Doctor e Restauracao\n'
printf 'Sandbox temporario: %s\n' "${SANDBOX_ROOT}"
printf '======================================================================\n\n'

# ------------------------------------------------------------------------------
# 1. Validacao individual de sintaxe Bash (bash -n) em todos os scripts
# ------------------------------------------------------------------------------
readonly -a PHASE2_BASH_SCRIPTS=(
  "${REPO_ROOT}/install-terminal.sh"
  "${REPO_ROOT}/doctor.sh"
  "${REPO_ROOT}/uninstall-terminal.sh"
  "${REPO_ROOT}/lib/common.sh"
  "${REPO_ROOT}/lib/platform.sh"
  "${REPO_ROOT}/lib/config-parser.sh"
  "${REPO_ROOT}/lib/arguments.sh"
  "${REPO_ROOT}/lib/plan.sh"
  "${REPO_ROOT}/lib/backups.sh"
  "${REPO_ROOT}/lib/manifest.sh"
  "${REPO_ROOT}/lib/user-config.sh"
  "${REPO_ROOT}/lib/git-config.sh"
  "${REPO_ROOT}/tests/unit/test_phase2_state_and_reversibility.sh"
)

for bfile in "${PHASE2_BASH_SCRIPTS[@]}"; do
  rel="${bfile#"${REPO_ROOT}/"}"
  if bash -n "${bfile}"; then
    pass "bash -n individual aprovado: ${rel}"
  else
    fail "bash -n falhou em: ${rel}"
  fi
done

# ------------------------------------------------------------------------------
# 2. Validacao individual de sintaxe Zsh (zsh -n) em cada arquivo de config/zsh/
# ------------------------------------------------------------------------------
readonly -a PHASE2_ZSH_FILES=(
  "${REPO_ROOT}/config/zsh/zshenv.template"
  "${REPO_ROOT}/config/zsh/zshrc"
  "${REPO_ROOT}/config/zsh/aliases.zsh"
  "${REPO_ROOT}/config/zsh/bindings.zsh"
  "${REPO_ROOT}/config/zsh/containers.zsh"
  "${REPO_ROOT}/config/zsh/database.zsh"
  "${REPO_ROOT}/config/zsh/fzf.zsh"
  "${REPO_ROOT}/config/zsh/git.zsh"
  "${REPO_ROOT}/config/zsh/plugins.zsh"
  "${REPO_ROOT}/config/zsh/prompt.zsh"
)

if command -v zsh >/dev/null 2>&1; then
  for zfile in "${PHASE2_ZSH_FILES[@]}"; do
    rel="${zfile#"${REPO_ROOT}/"}"
    if zsh -n "${zfile}"; then
      pass "zsh -n individual aprovado: ${rel}"
    else
      fail "zsh -n falhou em: ${rel}"
    fi
  done
else
  fail "Binario 'zsh' nao encontrado para validar 'zsh -n'"
fi

# ------------------------------------------------------------------------------
# 3. Instalacao limpa em HOME temporario + Manifesto JSON + permissoes privadas
# ------------------------------------------------------------------------------
setup_case_sandbox "clean-install"
run_in_sandbox "${INSTALLER}" --profile developer --skip-system-packages --non-interactive

if [[ "${RUN_EXIT}" -eq 0 ]] && [[ ! -e "${SIDE_EFFECT_LOG}" ]]; then
  pass "Instalacao limpa (--profile developer --skip-system-packages --non-interactive) concluiu com codigo 0"
else
  fail "Instalacao limpa falhou (exit=${RUN_EXIT})" "$(cat "${OUT_STDERR}" 2>/dev/null)"
fi

if [[ -f "${FAKE_HOME}/.zshenv" ]] \
  && [[ -f "${FAKE_HOME}/.zshrc" ]] \
  && [[ -f "${FAKE_XDG_CONFIG}/terminal-setup/zsh/options.zsh" ]] \
  && [[ -f "${FAKE_XDG_CONFIG}/terminal-setup/zsh/aliases.zsh" ]] \
  && [[ -f "${FAKE_XDG_CONFIG}/starship.toml" ]] \
  && [[ -f "${FAKE_XDG_CONFIG}/tmux/tmux.conf" ]] \
  && [[ ! -e "${FAKE_XDG_CONFIG}/superfile/config.toml" ]]; then
  pass "Arquivos Zsh, Starship e tmux criados no HOME temporario; nenhum config.toml ficticio criado para Superfile"
else
  fail "Conjunto de arquivos criados no HOME temporario nao corresponde ao esperado"
fi

MANIFEST_1="$(latest_file_in_dir "${FAKE_XDG_STATE}/terminal-setup/manifests" '*.json')"
LOG_1="$(latest_file_in_dir "${FAKE_XDG_STATE}/terminal-setup/logs" '*.log')"

if [[ -f "${MANIFEST_1}" ]] && jq -e '.status == "completed" and (.entries | length > 0)' "${MANIFEST_1}" >/dev/null; then
  pass "Manifesto JSON valido gerado via jq com status 'completed'"
else
  fail "Manifesto JSON ausente ou invalido"
fi

MANIFEST_PERM="$(stat -c '%a' "${MANIFEST_1}")"
LOG_PERM="$(stat -c '%a' "${LOG_1}")"
if [[ "${MANIFEST_PERM}" == "600" ]] && [[ "${LOG_PERM}" == "600" ]]; then
  pass "Arquivos de estado (manifesto e log) possuem permissao privada 0600 (umask 077)"
else
  fail "Permissoes de manifesto/log incorretas: manifest=${MANIFEST_PERM}, log=${LOG_PERM}"
fi

# ------------------------------------------------------------------------------
# 4. Segunda execucao identica (Idempotencia: sem reescrita e sem backups)
# ------------------------------------------------------------------------------
sleep 1
run_in_sandbox "${INSTALLER}" --profile developer --skip-system-packages --non-interactive
MANIFEST_2="$(latest_file_in_dir "${FAKE_XDG_STATE}/terminal-setup/manifests" '*.json')"
SECOND_ID="$(jq -r '.install_id' "${MANIFEST_2}")"

if [[ "${RUN_EXIT}" -eq 0 ]] \
  && [[ "${MANIFEST_2}" != "${MANIFEST_1}" ]] \
  && jq -e 'all(.entries[]; .action == "unchanged")' "${MANIFEST_2}" >/dev/null \
  && [[ ! -d "${FAKE_XDG_STATE}/terminal-setup/backups/${SECOND_ID}" ]]; then
  pass "Segunda execucao identica marca todos os recursos como 'unchanged' e nao cria backups redundantes"
else
  fail "Falha de idempotencia na segunda execucao (exit=${RUN_EXIT})"
fi

# ------------------------------------------------------------------------------
# 5. Smoke test de Zsh interativo isolado na sandbox (sem carregar HOME real)
# ------------------------------------------------------------------------------
if command -v zsh >/dev/null 2>&1; then
  set +e
  # shellcheck disable=SC2016 # expansao intencional pelo zsh filho, nao pelo bash pai
  SMOKE_OUT="$(env -i \
    HOME="${FAKE_HOME}" \
    USER="sandboxuser" \
    PATH="${MOCK_BIN}:/usr/bin:/bin" \
    TERM="xterm-256color" \
    XDG_CONFIG_HOME="${FAKE_XDG_CONFIG}" \
    XDG_STATE_HOME="${FAKE_XDG_STATE}" \
    XDG_DATA_HOME="${FAKE_XDG_DATA}" \
    zsh -i -c 'printf "SMOKE_OK:%s" "${TS_ICONS_MODE:-unset}"' </dev/null 2>&1)"
  SMOKE_RC=$?
  set -e
  if [[ "${SMOKE_RC}" -eq 0 ]] && [[ "${SMOKE_OUT}" == *"SMOKE_OK:plain"* ]] && [[ ! -e "${SIDE_EFFECT_LOG}" ]]; then
    pass "Smoke test do Zsh interativo em HOME temporario iniciou sem erros e sem chamadas de rede"
  else
    fail "Smoke test do Zsh interativo falhou (rc=${SMOKE_RC}, out=${SMOKE_OUT})"
  fi
fi

# ------------------------------------------------------------------------------
# 6. Politica de conflitos (--on-conflict keep vs backup-replace)
# ------------------------------------------------------------------------------
setup_case_sandbox "conflict-policy"
printf '# MEU ZSHRC PERSONALIZADO ORIGINAL\n' >"${FAKE_HOME}/.zshrc"
ORIG_ZSHRC_SHA="$(sha256sum "${FAKE_HOME}/.zshrc" | awk '{print $1}')"

# 6a. Com --on-conflict keep (padrao em --non-interactive)
run_in_sandbox "${INSTALLER}" --profile minimal --skip-system-packages --non-interactive --on-conflict keep
CUR_ZSHRC_SHA="$(sha256sum "${FAKE_HOME}/.zshrc" | awk '{print $1}')"
M_KEEP="$(latest_file_in_dir "${FAKE_XDG_STATE}/terminal-setup/manifests" '*.json')"

if [[ "${RUN_EXIT}" -eq 0 ]] \
  && [[ "${CUR_ZSHRC_SHA}" == "${ORIG_ZSHRC_SHA}" ]] \
  && grep -q "impede a ativacao automatica" "${OUT_STDERR}" \
  && jq -e '.entries[] | select(.path | endswith("/.zshrc")) | .action == "kept_existing"' "${M_KEEP}" >/dev/null; then
  pass "--on-conflict keep preserva ~/.zshrc preexistente e avisa sobre ativacao automatica"
else
  fail "Falha no teste --on-conflict keep (exit=${RUN_EXIT})"
fi

# 6b. Com --on-conflict backup-replace
sleep 1
run_in_sandbox "${INSTALLER}" --profile minimal --skip-system-packages --non-interactive --on-conflict backup-replace
NEW_ZSHRC_SHA="$(sha256sum "${FAKE_HOME}/.zshrc" | awk '{print $1}')"
M_REPLACE="$(latest_file_in_dir "${FAKE_XDG_STATE}/terminal-setup/manifests" '*.json')"
BKP_FILE="$(jq -r '.entries[] | select(.path | endswith("/.zshrc")) | .backup_path' "${M_REPLACE}")"
BKP_SHA="$(sha256sum "${BKP_FILE}" | awk '{print $1}')"

if [[ "${RUN_EXIT}" -eq 0 ]] \
  && [[ "${NEW_ZSHRC_SHA}" != "${ORIG_ZSHRC_SHA}" ]] \
  && [[ -f "${BKP_FILE}" ]] \
  && [[ "${BKP_SHA}" == "${ORIG_ZSHRC_SHA}" ]]; then
  pass "--on-conflict backup-replace cria backup integro antes de substituir ~/.zshrc"
else
  fail "Falha no teste --on-conflict backup-replace (exit=${RUN_EXIT})"
fi

# ------------------------------------------------------------------------------
# 7. Protecao de symlinks: nao seguir link para sobrescrever o alvo
# ------------------------------------------------------------------------------
setup_case_sandbox "symlink-safety"
EXTERNAL_TARGET="${CASE_DIR}/external-dotfile-target"
printf 'CONTEUDO_INTOCAVEL_DO_ALVO_DO_SYMLINK\n' >"${EXTERNAL_TARGET}"
ORIG_TARGET_SHA="$(sha256sum "${EXTERNAL_TARGET}" | awk '{print $1}')"
ln -s "${EXTERNAL_TARGET}" "${FAKE_HOME}/.zshrc"

# 7a. Com backup-replace sobre um symlink: deve fazer backup do link, transformar
# ~/.zshrc em arquivo regular e JAMAIS alterar EXTERNAL_TARGET
run_in_sandbox "${INSTALLER}" --profile minimal --skip-system-packages --non-interactive --on-conflict backup-replace
AFTER_TARGET_SHA="$(sha256sum "${EXTERNAL_TARGET}" | awk '{print $1}')"
M_SYM="$(latest_file_in_dir "${FAKE_XDG_STATE}/terminal-setup/manifests" '*.json')"
SYM_BKP="$(jq -r '.entries[] | select(.path | endswith("/.zshrc")) | .backup_path' "${M_SYM}")"

if [[ "${RUN_EXIT}" -eq 0 ]] \
  && [[ ! -L "${FAKE_HOME}/.zshrc" ]] \
  && [[ -f "${FAKE_HOME}/.zshrc" ]] \
  && [[ -L "${SYM_BKP}" ]] \
  && [[ "$(readlink "${SYM_BKP}")" == "${EXTERNAL_TARGET}" ]] \
  && [[ "${AFTER_TARGET_SHA}" == "${ORIG_TARGET_SHA}" ]]; then
  pass "Substituicao de symlink faz backup do proprio link e NAO altera o arquivo-alvo apontado"
else
  fail "Falha de seguranca com symlink durante instalacao"
fi

# 7b. Restaurar com uninstall-terminal.sh deve recriar o symlink original
run_in_sandbox "${UNINSTALLER}" --non-interactive
if [[ "${RUN_EXIT}" -eq 0 ]] \
  && [[ -L "${FAKE_HOME}/.zshrc" ]] \
  && [[ "$(readlink "${FAKE_HOME}/.zshrc")" == "${EXTERNAL_TARGET}" ]] \
  && [[ "$(sha256sum "${EXTERNAL_TARGET}" | awk '{print $1}')" == "${ORIG_TARGET_SHA}" ]]; then
  pass "Restauracao recria o symlink original sem tocar no arquivo-alvo"
else
  fail "Falha ao restaurar symlink original na desinstalacao"
fi

# ------------------------------------------------------------------------------
# 8. ZDOTDIR customizado e caminho com espacos
# ------------------------------------------------------------------------------
setup_case_sandbox "custom-zdotdir"
CUSTOM_ZDOTDIR_VALUE="${FAKE_HOME}/meu zdotdir custom"
mkdir -p "${CUSTOM_ZDOTDIR_VALUE}"
run_in_sandbox "${INSTALLER}" --profile minimal --skip-system-packages --non-interactive
unset CUSTOM_ZDOTDIR_VALUE

if [[ "${RUN_EXIT}" -eq 0 ]] \
  && [[ -f "${FAKE_HOME}/meu zdotdir custom/.zshenv" ]] \
  && [[ -f "${FAKE_HOME}/meu zdotdir custom/.zshrc" ]] \
  && [[ ! -e "${FAKE_HOME}/.zshrc" ]]; then
  pass "Respeita ZDOTDIR customizado (inclusive com espacos no caminho) sem criar ~/.zshrc na raiz"
else
  fail "Falha no suporte a ZDOTDIR customizado com espacos (exit=${RUN_EXIT})"
fi

# ------------------------------------------------------------------------------
# 9. Configuracao Git isolada e privacidade em logs/manifestos
# ------------------------------------------------------------------------------
setup_case_sandbox "git-privacy"
SECRET_NAME="Pessoa Teste Privacidade"
SECRET_EMAIL="privacidade.unica@example.invalid"

run_in_sandbox "${INSTALLER}" \
  --profile minimal \
  --skip-system-packages \
  --non-interactive \
  --git-identity configure \
  --git-name "${SECRET_NAME}" \
  --git-email "${SECRET_EMAIL}" \
  --git-defaults apply

M_GIT="$(latest_file_in_dir "${FAKE_XDG_STATE}/terminal-setup/manifests" '*.json')"
L_GIT="$(latest_file_in_dir "${FAKE_XDG_STATE}/terminal-setup/logs" '*.log')"

if [[ "${RUN_EXIT}" -eq 0 ]] \
  && [[ -f "${FAKE_GITCONFIG}" ]] \
  && [[ "$(git config --file "${FAKE_GITCONFIG}" --get user.name)" == "${SECRET_NAME}" ]] \
  && [[ "$(git config --file "${FAKE_GITCONFIG}" --get user.email)" == "${SECRET_EMAIL}" ]] \
  && [[ "$(git config --file "${FAKE_GITCONFIG}" --get init.defaultBranch)" == "main" ]]; then
  pass "Configuracao Git aplica user.name, user.email e defaults no GIT_CONFIG_GLOBAL temporario"
else
  fail "Falha ao aplicar configuracao Git isolada (exit=${RUN_EXIT})"
fi

if ! grep -Fq "${SECRET_NAME}" "${M_GIT}" \
  && ! grep -Fq "${SECRET_EMAIL}" "${M_GIT}" \
  && ! grep -Fq "${SECRET_NAME}" "${L_GIT}" \
  && ! grep -Fq "${SECRET_EMAIL}" "${L_GIT}"; then
  pass "Privacidade garantida: nem o manifesto JSON nem o log contem nome ou e-mail Git"
else
  fail "Vazamento de nome ou e-mail Git detectado no manifesto ou no log!"
fi

# ------------------------------------------------------------------------------
# 10. doctor.sh: somente leitura, --json valido e --strict
# ------------------------------------------------------------------------------
setup_case_sandbox "doctor-ro"
chmod 500 "${FAKE_HOME}"
before_doc="$(find "${FAKE_HOME}" -maxdepth 3 | sort)"
run_in_sandbox "${DOCTOR}" --profile minimal
after_doc="$(find "${FAKE_HOME}" -maxdepth 3 | sort)"
chmod 700 "${FAKE_HOME}"

if [[ "${before_doc}" == "${after_doc}" ]] && [[ ! -e "${SIDE_EFFECT_LOG}" ]]; then
  pass "doctor.sh executa em HOME somente leitura sem criar diretorios/logs e sem chamar sudo/rede"
else
  fail "doctor.sh modificou arquivos ou chamou comandos proibidos"
fi

# Executar doctor --json na sandbox onde instalamos o perfil minimal
run_in_sandbox "${INSTALLER}" --profile minimal --skip-system-packages --non-interactive
run_in_sandbox "${DOCTOR}" --profile minimal --json
if jq -e '.project == "terminal-setup" and (.summary.ok > 0) and (.checks | type == "array")' "${OUT_STDOUT}" >/dev/null; then
  pass "doctor.sh --json produz JSON limpo e estruturado via jq"
else
  fail "doctor.sh --json nao produziu JSON valido" "$(cat "${OUT_STDOUT}" 2>/dev/null)"
fi

# Argumento invalido em doctor.sh deve retornar codigo 2
run_in_sandbox "${DOCTOR}" --flag-inexistente
if [[ "${RUN_EXIT}" -eq 2 ]]; then
  pass "doctor.sh rejeita flag invalida com codigo 2"
else
  fail "doctor.sh deveria retornar codigo 2 para flag invalida (obteve ${RUN_EXIT})"
fi

# ------------------------------------------------------------------------------
# 11. Desinstalacao/restauracao: --dry-run, edicao posterior, arquivo desconhecido e 2x restore
# ------------------------------------------------------------------------------
setup_case_sandbox "uninstall-flow"
printf '# ZSHRC PRE-EXISTENTE DO USUARIO\n' >"${FAKE_HOME}/.zshrc"
PRE_SHA="$(sha256sum "${FAKE_HOME}/.zshrc" | awk '{print $1}')"

run_in_sandbox "${INSTALLER}" --profile minimal --skip-system-packages --non-interactive --on-conflict backup-replace

# Simular que o usuario editou starship.toml DEPOIS da instalacao e adicionou um arquivo desconhecido
printf '\n# Edicao manual do usuario apos instalacao\n' >>"${FAKE_XDG_CONFIG}/starship.toml"
EDITED_STARSHIP_SHA="$(sha256sum "${FAKE_XDG_CONFIG}/starship.toml" | awk '{print $1}')"
UNKNOWN_FILE="${FAKE_XDG_CONFIG}/terminal-setup/zsh/meu-custom-desconhecido.zsh"
printf '# Arquivo pessoal fora do manifesto\n' >"${UNKNOWN_FILE}"

# 11a. --dry-run do uninstall-terminal.sh nao deve alterar nada
before_uninst="$(find "${FAKE_HOME}" -type f -exec sha256sum {} + | sort)"
run_in_sandbox "${UNINSTALLER}" --dry-run
after_uninst="$(find "${FAKE_HOME}" -type f -exec sha256sum {} + | sort)"
if [[ "${RUN_EXIT}" -eq 0 ]] && [[ "${before_uninst}" == "${after_uninst}" ]]; then
  pass "uninstall-terminal.sh --dry-run simula restauracao sem alterar nenhum arquivo"
else
  fail "uninstall-terminal.sh --dry-run modificou arquivos (exit=${RUN_EXIT})"
fi

# 11b. Execucao real de uninstall-terminal.sh
run_in_sandbox "${UNINSTALLER}" --non-interactive
if [[ "${RUN_EXIT}" -eq 0 ]] \
  && [[ ! -e "${FAKE_HOME}/.zshenv" ]] \
  && [[ -f "${FAKE_HOME}/.zshrc" ]] \
  && [[ "$(sha256sum "${FAKE_HOME}/.zshrc" | awk '{print $1}')" == "${PRE_SHA}" ]] \
  && [[ -f "${FAKE_XDG_CONFIG}/starship.toml" ]] \
  && [[ "$(sha256sum "${FAKE_XDG_CONFIG}/starship.toml" | awk '{print $1}')" == "${EDITED_STARSHIP_SHA}" ]] \
  && [[ -f "${UNKNOWN_FILE}" ]] \
  && grep -q "Conflito de modificacao pos-instalacao" "${OUT_STDERR}"; then
  pass "uninstall-terminal.sh restaura ~/.zshrc do backup, remove ~/.zshenv criado e preserva starship.toml editado e arquivo desconhecido"
else
  fail "uninstall-terminal.sh falhou nos criterios de restauracao/preservacao (exit=${RUN_EXIT})" "$(cat "${OUT_STDERR}" 2>/dev/null)"
fi

# 11c. Executar uninstall-terminal.sh uma segunda vez seguida (idempotencia de restauracao)
run_in_sandbox "${UNINSTALLER}" --non-interactive
if [[ "${RUN_EXIT}" -eq 0 ]] \
  && [[ "$(sha256sum "${FAKE_HOME}/.zshrc" | awk '{print $1}')" == "${PRE_SHA}" ]] \
  && grep -q "\[JA RESTAURADO\]" "${OUT_STDOUT}"; then
  pass "Segunda execucao de uninstall-terminal.sh e idempotente e preserva o estado restaurado"
else
  fail "Segunda execucao de uninstall-terminal.sh falhou (exit=${RUN_EXIT})"
fi

# ------------------------------------------------------------------------------
# 12. Seguranca do manifesto: JSON malformado e tentativa de path traversal
# ------------------------------------------------------------------------------
setup_case_sandbox "manifest-security"
mkdir -p "${FAKE_XDG_STATE}/terminal-setup/manifests"
OUTSIDE_VICTIM="${CASE_DIR}/victim-outside-home.txt"
printf 'NAO_APAGAR\n' >"${OUTSIDE_VICTIM}"

# 12a. Manifesto com tentativa de path traversal (../)
TRAVERSAL_MANIFEST="${FAKE_XDG_STATE}/terminal-setup/manifests/20261022T000001Z-1-traversal.json"
cat >"${TRAVERSAL_MANIFEST}" <<EOF
{
  "schema_version": 1,
  "project": "terminal-setup",
  "project_version": "0.2.0-phase2",
  "install_id": "20261022T000001Z-1-traversal",
  "timestamp_utc": "2026-10-22T00:00:01Z",
  "completed_at_utc": "2026-10-22T00:00:02Z",
  "status": "completed",
  "profile": "minimal",
  "icons": "plain",
  "vi_mode": false,
  "on_conflict": "keep",
  "git_identity_policy": "skip",
  "git_defaults_policy": "keep",
  "user": "sandboxuser",
  "uid": ${EUID:-$(/usr/bin/id -u)},
  "home": "${FAKE_HOME}",
  "xdg_config_home": "${FAKE_XDG_CONFIG}",
  "xdg_state_home": "${FAKE_XDG_STATE}",
  "xdg_data_home": "${FAKE_XDG_DATA}",
  "zdotdir": "${FAKE_HOME}",
  "entries": [
    {
      "path": "${FAKE_HOME}/../victim-outside-home.txt",
      "resource_type": "file",
      "previous_state": "absent",
      "previous_checksum": null,
      "previous_symlink_target": null,
      "backup_path": null,
      "installed_checksum": "$(sha256sum "${OUTSIDE_VICTIM}" | awk '{print $1}')",
      "installed_symlink_target": null,
      "action": "created"
    }
  ]
}
EOF

run_in_sandbox "${UNINSTALLER}" --restore "20261022T000001Z-1-traversal" --non-interactive
if [[ "${RUN_EXIT}" -eq 1 ]] && [[ -f "${OUTSIDE_VICTIM}" ]]; then
  pass "Rejeita manifesto com path traversal (../) sem remover arquivo fora do HOME"
else
  fail "Falha na rejeicao de path traversal no manifesto (exit=${RUN_EXIT})"
fi

# 12b. Manifesto apontando para caminho absoluto externo (/etc/passwd)
EXTERNAL_MANIFEST="${FAKE_XDG_STATE}/terminal-setup/manifests/20261022T000002Z-1-external.json"
jq '.install_id = "20261022T000002Z-1-external" | .entries[0].path = "/etc/passwd"' "${TRAVERSAL_MANIFEST}" >"${EXTERNAL_MANIFEST}"
run_in_sandbox "${UNINSTALLER}" --restore "20261022T000002Z-1-external" --non-interactive
if [[ "${RUN_EXIT}" -eq 1 ]]; then
  pass "Rejeita manifesto apontando para caminho fora das arvores do usuario (/etc/passwd)"
else
  fail "Falha na rejeicao de caminho externo no manifesto (exit=${RUN_EXIT})"
fi

# 12c. Manifesto com JSON malformado
BROKEN_MANIFEST="${FAKE_XDG_STATE}/terminal-setup/manifests/20261022T000003Z-1-broken.json"
printf '{ "schema_version": 1, "entries": [ INVALID_JSON ' >"${BROKEN_MANIFEST}"
run_in_sandbox "${UNINSTALLER}" --restore "20261022T000003Z-1-broken" --non-interactive
if [[ "${RUN_EXIT}" -eq 1 ]] && grep -q "JSON malformado ou schema invalido" "${OUT_STDERR}"; then
  pass "Rejeita manifesto com JSON malformado com codigo 1"
else
  fail "Deveria rejeitar manifesto malformado com codigo 1 (obteve ${RUN_EXIT})" "$(cat "${OUT_STDERR}" 2>/dev/null)"
fi

# 12d. Manifesto com diretorio pai intermediario sendo symlink para fora do HOME
ln -s "${CASE_DIR}" "${FAKE_HOME}/escape-dir"
SYMPARENT_MANIFEST="${FAKE_XDG_STATE}/terminal-setup/manifests/20261022T000004Z-1-symparent.json"
jq --arg p "${FAKE_HOME}/escape-dir/victim-outside-home.txt" \
  '.install_id = "20261022T000004Z-1-symparent" | .entries[0].path = $p' \
  "${TRAVERSAL_MANIFEST}" >"${SYMPARENT_MANIFEST}"
run_in_sandbox "${UNINSTALLER}" --restore "20261022T000004Z-1-symparent" --non-interactive
if [[ "${RUN_EXIT}" -eq 1 ]] && [[ -f "${OUTSIDE_VICTIM}" ]]; then
  pass "Rejeita manifesto quando diretorio pai intermediario e um symlink escapando do HOME"
else
  fail "Falha na rejeicao de symlink intermediario no manifesto (exit=${RUN_EXIT})"
fi

# 12e. Teste negativo de proprietario divergente do manifesto (UID 99999 != UID real)
FOREIGN_UID_MANIFEST="${FAKE_XDG_STATE}/terminal-setup/manifests/20261022T000005Z-1-foreignuid.json"
jq --arg p "${FAKE_HOME}/.zshrc" \
  '.install_id = "20261022T000005Z-1-foreignuid" | .entries[0].path = $p' \
  "${TRAVERSAL_MANIFEST}" >"${FOREIGN_UID_MANIFEST}"
cat >"${MOCK_BIN}/stat" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-c" ]] && [[ "${2:-}" == "%u" ]]; then
  printf '99999\n'
  exit 0
fi
exec /usr/bin/stat "$@"
EOF
chmod +x "${MOCK_BIN}/stat"
run_in_sandbox "${UNINSTALLER}" --restore "20261022T000005Z-1-foreignuid" --non-interactive
rm -f -- "${MOCK_BIN}/stat"
if [[ "${RUN_EXIT}" -eq 1 ]] && grep -q "pertence ao UID 99999, diferente do usuario atual" "${OUT_STDERR}"; then
  pass "Rejeita manifesto com proprietario divergente (UID 99999 != UID real) sem enfraquecer lib/manifest.sh"
else
  fail "Deveria rejeitar manifesto com proprietario divergente (exit=${RUN_EXIT})" "$(cat "${OUT_STDERR}" 2>/dev/null)"
fi

# 12f. Rejeita raiz gerenciada (ZDOTDIR) que seja ela propria um symlink para fora do HOME
mkdir -p "${CASE_DIR}/outside-zdot-target"
ln -s "${CASE_DIR}/outside-zdot-target" "${CASE_DIR}/zdot-root-symlink"
CUSTOM_ZDOTDIR_VALUE="${CASE_DIR}/zdot-root-symlink" run_in_sandbox "${INSTALLER}" --profile minimal --skip-system-packages --non-interactive
if [[ "${RUN_EXIT}" -ne 0 ]] && [[ ! -e "${CASE_DIR}/outside-zdot-target/.zshrc" ]]; then
  pass "Rejeita raiz gerenciada (ZDOTDIR) quando o proprio diretorio raiz e um symlink"
else
  fail "Deveria rejeitar ZDOTDIR que e symlink na raiz (exit=${RUN_EXIT})"
fi

# 12g. ts_is_effective_tmp_path rejeita symlink em /tmp apontando para fora de /tmp
ln -s "/etc/os-release" "${CASE_DIR}/sym-outside-tmp"
if (
  # shellcheck source=lib/common.sh
  source "${REPO_ROOT}/lib/common.sh"
  ! ts_is_effective_tmp_path "${CASE_DIR}/sym-outside-tmp"
); then
  pass "ts_is_effective_tmp_path rejeita symlink em /tmp apontando para fora de /tmp"
else
  fail "ts_is_effective_tmp_path deveria rejeitar symlink apontando para fora de /tmp"
fi

# ------------------------------------------------------------------------------
# 13. Revisao Item 1: Literal "__NULL__" vs null ausente vs string vazia
# ------------------------------------------------------------------------------
setup_case_sandbox "literal-null-token"
# Criar um symlink preexistente cujo alvo literal e exatamente "__NULL__"
ln -s "__NULL__" "${FAKE_HOME}/.zshrc"
run_in_sandbox "${INSTALLER}" --profile minimal --skip-system-packages --non-interactive --on-conflict backup-replace
M_LIT="$(latest_file_in_dir "${FAKE_XDG_STATE}/terminal-setup/manifests" '*.json')"

if [[ "${RUN_EXIT}" -eq 0 ]] \
  && jq -e '.entries[] | select(.path | endswith("/.zshrc")) | (.previous_symlink_target == "__NULL__" and .previous_checksum == null)' "${M_LIT}" >/dev/null; then
  pass "Manifesto registra alvo literal '__NULL__' sem confundi-lo com null ausente"
else
  fail "Falha ao registrar literal '__NULL__' no manifesto"
fi

# Restaurar via uninstall-terminal.sh: deve recriar o symlink apontando literalmente para "__NULL__"
run_in_sandbox "${UNINSTALLER}" --non-interactive
if [[ "${RUN_EXIT}" -eq 0 ]] \
  && [[ -L "${FAKE_HOME}/.zshrc" ]] \
  && [[ "$(readlink "${FAKE_HOME}/.zshrc")" == "__NULL__" ]]; then
  pass "uninstall-terminal.sh restaura symlink com alvo literal '__NULL__' sem confundi-lo com campo ausente"
else
  fail "uninstall-terminal.sh confundiu literal '__NULL__' com campo ausente na restauracao (exit=${RUN_EXIT})" "$(cat "${OUT_STDERR}" 2>/dev/null)"
fi

# Executar segunda vez: deve reconhecer que o symlink com alvo "__NULL__" ja esta restaurado
run_in_sandbox "${UNINSTALLER}" --non-interactive
if [[ "${RUN_EXIT}" -eq 0 ]] && grep -q "\[JA RESTAURADO\].*/\.zshrc" "${OUT_STDOUT}"; then
  pass "Segunda execucao de uninstall-terminal.sh reconhece estado restaurado com literal '__NULL__'"
else
  fail "Falha na idempotencia de restauracao com literal '__NULL__'"
fi

# ------------------------------------------------------------------------------
# 14. Revisao Item 2: Ciclo completo de options.zsh (manifesto, conflito, backup, doctor zsh -n e restore)
# ------------------------------------------------------------------------------
setup_case_sandbox "options-zsh-lifecycle"
OPTS_PATH="${FAKE_XDG_CONFIG}/terminal-setup/zsh/options.zsh"
mkdir -p "${OPTS_PATH%/*}"
printf '# OPTIONS_ZSH_CUSTOMIZADO_PRE_EXISTENTE\nexport TS_ICONS_MODE="plain"\n' >"${OPTS_PATH}"
ORIG_OPTS_SHA="$(sha256sum "${OPTS_PATH}" | awk '{print $1}')"

# 14a. Com --on-conflict keep: options.zsh preexistente deve ser preservado e constar no manifesto
run_in_sandbox "${INSTALLER}" --profile minimal --skip-system-packages --non-interactive --on-conflict keep
M_OPTS_KEEP="$(latest_file_in_dir "${FAKE_XDG_STATE}/terminal-setup/manifests" '*.json')"
if [[ "${RUN_EXIT}" -eq 0 ]] \
  && [[ "$(sha256sum "${OPTS_PATH}" | awk '{print $1}')" == "${ORIG_OPTS_SHA}" ]] \
  && jq -e --arg p "${OPTS_PATH}" '.entries[] | select(.path == $p) | .action == "kept_existing"' "${M_OPTS_KEEP}" >/dev/null; then
  pass "options.zsh participa da politica --on-conflict keep e e registrado no manifesto"
else
  fail "options.zsh falhou no teste --on-conflict keep"
fi

# 14b. Com --on-conflict backup-replace: options.zsh faz backup e substitui
sleep 1
run_in_sandbox "${INSTALLER}" --profile minimal --skip-system-packages --non-interactive --on-conflict backup-replace --icons nerd --vi-mode
M_OPTS_REP="$(latest_file_in_dir "${FAKE_XDG_STATE}/terminal-setup/manifests" '*.json')"
if [[ "${RUN_EXIT}" -eq 0 ]] \
  && grep -q 'TS_ICONS_MODE="nerd"' "${OPTS_PATH}" \
  && grep -q 'TS_VI_MODE_ENABLED="true"' "${OPTS_PATH}" \
  && jq -e --arg p "${OPTS_PATH}" '.entries[] | select(.path == $p) | (.action == "replaced" and .backup_path != null)' "${M_OPTS_REP}" >/dev/null; then
  pass "options.zsh participa de --on-conflict backup-replace com backup registrado no manifesto"
else
  fail "options.zsh falhou no teste --on-conflict backup-replace"
fi

# 14c. Validacao individual de sintaxe de options.zsh pelo doctor.sh
run_in_sandbox "${DOCTOR}" --profile minimal --json
if jq -e --arg p "${OPTS_PATH}" '.checks[] | select(.category == "config_zsh" and .name == $p) | .status == "ok"' "${OUT_STDOUT}" >/dev/null; then
  pass "doctor.sh valida individualmente a sintaxe 'zsh -n' de options.zsh"
else
  fail "doctor.sh nao validou individualmente options.zsh"
fi

# 14d. Restauracao de options.zsh para o backup original via uninstall-terminal.sh
run_in_sandbox "${UNINSTALLER}" --non-interactive
if [[ "${RUN_EXIT}" -eq 0 ]] \
  && [[ -f "${OPTS_PATH}" ]] \
  && [[ "$(sha256sum "${OPTS_PATH}" | awk '{print $1}')" == "${ORIG_OPTS_SHA}" ]]; then
  pass "uninstall-terminal.sh restaura o backup anterior de options.zsh corretamente"
else
  fail "uninstall-terminal.sh falhou ao restaurar backup de options.zsh"
fi

printf '\n======================================================================\n'
printf 'Resumo da Fase 2: %d aprovados, %d falharam.\n' "${PASS_COUNT}" "${FAIL_COUNT}"
printf '======================================================================\n'

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi
exit 0
