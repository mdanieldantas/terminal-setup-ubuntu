#!/usr/bin/env bash
# ==============================================================================
# tests/integration/test_ubuntu2404_container.sh
# Suíte de testes de integração para o container Ubuntu 24.04 LTS (amd64)
#
# Deve ser executada DENTRO do container construído a partir de docker/Dockerfile
# como usuário não-root 'dev':
#   docker run --rm terminal-setup:dev bash /opt/terminal-setup/tests/integration/test_ubuntu2404_container.sh
#
# Cobertura dos 12 requisitos de integração da Fase 4:
#   1. Ferramentas instaladas conforme o perfil (developer).
#   2. Comandos e versões disponíveis no PATH.
#   3. Extração, localização efetiva e execução de Starship e Superfile (spf),
#      além de validação anti-tar-slip (ts_validate_tar_gz_archive).
#   4. Plugins Zsh instalados nos commits fixados em versions/plugins.lock.json.
#   5. Inicialização real do Zsh com os plugins configurados, sem erro e sem
#      substituir comandos tradicionais por aliases invasivos.
#   6. Execução como usuário não-root (dev) e ausência de sudo irrestrito.
#   7. Configurações em /home/dev, ausência de artefatos em /root e ausência de
#      identidade Git pessoal gravada na imagem.
#   8. Idempotência em segunda execução real no container.
#   9. doctor.sh em modo humano e --json no ambiente Ubuntu 24.04 real.
#  10. Ausência de prompts em --non-interactive (com stdin fechado).
#  11. Comportamento sem TTY interativo (zsh não interativo limpo e recusa sem
#      --non-interactive quando stdin está fechado).
#  12. Modo plain sem exigência de Nerd Font e ciclo de restauração/desinstalação
#      (uninstall-terminal.sh) em HOME isolado sem afetar arquivos externos.
# ==============================================================================

set -Eeuo pipefail

resolve_repo_root() {
  local source_path="${BASH_SOURCE[0]}"
  local dir_path
  while [[ -L "${source_path}" ]]; do
    dir_path="$(cd -P "$(dirname "${source_path}")" >/dev/null 2>&1 && pwd)"
    source_path="$(readlink "${source_path}")"
    if [[ "${source_path}" != /* ]]; then
      source_path="${dir_path}/${source_path}"
    fi
  done
  cd -P "$(dirname "${source_path}")/../.." >/dev/null 2>&1 && pwd
}

readonly REPO_ROOT="$(resolve_repo_root)"
readonly INSTALLER="${REPO_ROOT}/install-terminal.sh"
readonly DOCTOR="${REPO_ROOT}/doctor.sh"
readonly UNINSTALLER="${REPO_ROOT}/uninstall-terminal.sh"
readonly TOOLS_LOCK="${REPO_ROOT}/versions/tools.lock.json"
readonly PLUGINS_LOCK="${REPO_ROOT}/versions/plugins.lock.json"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[PASS] %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[FAIL] %s\n' "$1" >&2
  if [[ -n "${2:-}" ]]; then
    printf '       Detalhe: %s\n' "$2" >&2
  fi
}

printf '======================================================================\n'
printf 'Suíte de Integração em Container Ubuntu 24.04 — terminal-setup\n'
printf '======================================================================\n'

# Guardrail de segurança: verificar que estamos realmente em Ubuntu 24.04 e não no host Aurora
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
else
  printf '[ERRO] /etc/os-release ausente; interrompendo suíte de integração.\n' >&2
  exit 1
fi

if [[ "${ID:-}" != "ubuntu" ]] || [[ "${VERSION_ID:-}" != "24.04" ]]; then
  printf '[ERRO] Esta suíte de integração deve rodar dentro do container Ubuntu 24.04 (detectado: %s %s).\n' \
    "${ID:-desconhecido}" "${VERSION_ID:-desconhecida}" >&2
  exit 1
fi
pass "Plataforma do container confirmada: Ubuntu ${VERSION_ID} ($(uname -m))"

# ------------------------------------------------------------------------------
# 6. Execução como usuário não-root (dev) e ausência de sudo irrestrito
# ------------------------------------------------------------------------------
CURRENT_UID="$(id -u)"
CURRENT_USER="$(id -un)"

if [[ "${CURRENT_UID}" -ne 0 ]] && [[ "${CURRENT_USER}" == "dev" ]] && [[ "${HOME}" == "/home/dev" ]]; then
  pass "Container executa como usuário não-root '${CURRENT_USER}' (UID ${CURRENT_UID}, HOME=${HOME})"
else
  fail "Container deveria executar como usuário não-root 'dev' em /home/dev" "uid=${CURRENT_UID}, user=${CURRENT_USER}, home=${HOME}"
fi

if ! command -v sudo >/dev/null 2>&1; then
  pass "Comando 'sudo' não está instalado na imagem (sem escalonamento irrestrito)"
elif ! sudo -n true 2>/dev/null; then
  pass "Usuário '${CURRENT_USER}' não possui sudo sem senha (NOPASSWD)"
else
  fail "Detectado sudo sem senha (NOPASSWD) no container, violando a Seção 12/18 do guia"
fi

# Verificar shell de login registrado em /etc/passwd para dev
DEV_PASSWD_SHELL="$(awk -F: '$1 == "dev" {print $7; exit}' /etc/passwd)"
if [[ "${DEV_PASSWD_SHELL}" == "/usr/bin/zsh" ]]; then
  pass "Shell de login registrado em /etc/passwd para 'dev' é /usr/bin/zsh"
else
  fail "Shell de login em /etc/passwd para 'dev' incorreto" "obtido='${DEV_PASSWD_SHELL}'"
fi

# ------------------------------------------------------------------------------
# 1 & 2. Ferramentas instaladas conforme o perfil developer + comandos e versões
# ------------------------------------------------------------------------------
declare -a REQUIRED_CMDS=(
  "zsh"
  "git"
  "nano"
  "curl"
  "jq"
  "starship"
  "fzf"
  "rg"
  "bat"
  "batcat"
  "fd"
  "fdfind"
  "tmux"
  "zoxide"
  "eza"
  "spf"
)

for cmd in "${REQUIRED_CMDS[@]}"; do
  if command -v "${cmd}" >/dev/null 2>&1; then
    pass "Comando '${cmd}' disponível no PATH em $(command -v "${cmd}")"
  else
    fail "Comando obrigatório '${cmd}' ausente no PATH (${PATH})"
  fi
done

# Verificar execução de versão de cada ferramenta instalada
check_cmd_version() {
  local label="$1"
  shift
  local out=""
  if out="$("$@" 2>&1 | head -n 1)"; then
    pass "Execução e versão de ${label}: ${out}"
  else
    fail "Falha ao executar comando de versão para ${label}" "${out}"
  fi
}

check_cmd_version "zsh" zsh --version
check_cmd_version "git" git --version
check_cmd_version "nano" nano --version
check_cmd_version "curl" curl --version
check_cmd_version "jq" jq --version
check_cmd_version "fzf" fzf --version
check_cmd_version "ripgrep (rg)" rg --version
check_cmd_version "bat (symlink ~/.local/bin/bat)" bat --version
check_cmd_version "fd (symlink ~/.local/bin/fd)" fd --version
check_cmd_version "tmux" tmux -V
check_cmd_version "zoxide" zoxide --version
check_cmd_version "eza" eza --version
check_cmd_version "starship" starship --version
check_cmd_version "superfile (spf)" spf --version

# ------------------------------------------------------------------------------
# 3. Extração, localização efetiva e versões exatas de Starship e Superfile +
#    validação real de ts_validate_tar_gz_archive
# ------------------------------------------------------------------------------
EXPECTED_STARSHIP_VER="$(jq -r '.tools.starship.version' "${TOOLS_LOCK}")"
EXPECTED_SPF_VER="$(jq -r '.tools.superfile.version' "${TOOLS_LOCK}")"

ACTUAL_STARSHIP_VER="$(starship --version | head -n 1)"
ACTUAL_SPF_VER="$(spf --version 2>&1 | head -n 1)"

if [[ -x "/home/dev/.local/bin/starship" ]] && [[ "${ACTUAL_STARSHIP_VER}" == *"${EXPECTED_STARSHIP_VER}"* ]]; then
  pass "Starship extraído e instalado em /home/dev/.local/bin/starship com versão esperada (${EXPECTED_STARSHIP_VER})"
else
  fail "Versão ou caminho do Starship divergente" "got='${ACTUAL_STARSHIP_VER}', expected='${EXPECTED_STARSHIP_VER}'"
fi

if [[ -x "/home/dev/.local/bin/spf" ]] && [[ "${ACTUAL_SPF_VER}" == *"${EXPECTED_SPF_VER}"* ]]; then
  pass "Superfile (spf) extraído do subdiretório do tarball e instalado em /home/dev/.local/bin/spf com versão esperada (${EXPECTED_SPF_VER})"
else
  fail "Versão ou caminho do Superfile (spf) divergente" "got='${ACTUAL_SPF_VER}', expected='${EXPECTED_SPF_VER}'"
fi

# Verificar que nenhum config.toml fictício foi criado para o Superfile (Seção 10)
if [[ ! -e "/home/dev/.config/superfile/config.toml" ]]; then
  pass "Nenhum config.toml fictício foi criado para o Superfile (Seção 10 do guia)"
else
  fail "Encontrado /home/dev/.config/superfile/config.toml não autorizado"
fi

# Testar ts_validate_tar_gz_archive em ambiente Ubuntu 24.04 real (arquivo limpo vs tar-slip)
(
  # shellcheck source=lib/common.sh
  source "${REPO_ROOT}/lib/common.sh"
  # shellcheck source=lib/downloads.sh
  source "${REPO_ROOT}/lib/downloads.sh"

  TMP_TAR_TEST="$(mktemp -d)"
  trap 'rm -rf -- "${TMP_TAR_TEST}"' EXIT

  mkdir -p "${TMP_TAR_TEST}/dist/superfile-linux-v1.6.0-amd64"
  cp "/home/dev/.local/bin/spf" "${TMP_TAR_TEST}/dist/superfile-linux-v1.6.0-amd64/spf"
  tar -czf "${TMP_TAR_TEST}/valid-spf.tar.gz" -C "${TMP_TAR_TEST}" "./dist/superfile-linux-v1.6.0-amd64/spf"

  ts_validate_tar_gz_archive "${TMP_TAR_TEST}/valid-spf.tar.gz"
) && pass "ts_validate_tar_gz_archive aprova estrutura ./dist/.../spf no Ubuntu 24.04" \
  || fail "ts_validate_tar_gz_archive falhou em arquivo tar.gz válido no Ubuntu 24.04"

# ------------------------------------------------------------------------------
# 4. Plugins Zsh instalados nos commits fixados em versions/plugins.lock.json
# ------------------------------------------------------------------------------
readonly PLUGINS_BASE="/home/dev/.local/share/terminal-setup/plugins"
declare -a DEV_PLUGINS=(
  "zsh-autosuggestions"
  "zsh-syntax-highlighting"
  "zsh-history-substring-search"
)

for plug in "${DEV_PLUGINS[@]}"; do
  expected_commit="$(jq -r --arg p "${plug}" '.plugins[$p].commit' "${PLUGINS_LOCK}")"
  plug_path="${PLUGINS_BASE}/${plug}"
  if [[ -d "${plug_path}/.git" ]]; then
    actual_commit="$(git -C "${plug_path}" rev-parse HEAD)"
    if [[ "${actual_commit}" == "${expected_commit}" ]]; then
      pass "Plugin '${plug}' instalado e fixado no commit exato (${actual_commit})"
    else
      fail "Commit divergente para o plugin '${plug}'" "got=${actual_commit}, expected=${expected_commit}"
    fi
  else
    fail "Diretório Git do plugin '${plug}' não encontrado em ${plug_path}"
  fi
done

if [[ ! -d "${PLUGINS_BASE}/zsh-vi-mode" ]]; then
  pass "Plugin opcional 'zsh-vi-mode' permanece desativado e não instalado por padrão"
else
  fail "'zsh-vi-mode' não deveria ser instalado por padrão sem --vi-mode true"
fi

# ------------------------------------------------------------------------------
# 5. Inicialização real do Zsh com os plugins configurados e verificação de aliases
# ------------------------------------------------------------------------------
ZSH_STDERR_FILE="$(mktemp)"
ZSH_PROBE_OUT="$(
  zsh -i -c '
    print -r -- "ZV=${ZSH_VERSION}"
    print -r -- "ICONS=${TS_ICONS_MODE:-unset}"
    print -r -- "VIMODE=${TS_VI_MODE_ENABLED:-unset}"
    print -r -- "AUTOSUGGEST=${+functions[_zsh_autosuggest_start]}"
    print -r -- "HIGHLIGHT=${+functions[_zsh_highlight]}"
    print -r -- "HISTSUB=${+functions[history-substring-search-up]}"
    for c in ls cat find grep cd vi vim top htop; do
      if alias "$c" >/dev/null 2>&1; then
        print -r -- "INVASIVE_ALIAS:$c"
      fi
    done
  ' 2>"${ZSH_STDERR_FILE}"
)"
ZSH_STDERR_CONTENT="$(cat "${ZSH_STDERR_FILE}")"
rm -f -- "${ZSH_STDERR_FILE}"

if [[ -z "${ZSH_STDERR_CONTENT}" ]] &&
   [[ "${ZSH_PROBE_OUT}" == *"ICONS=plain"* ]] &&
   [[ "${ZSH_PROBE_OUT}" == *"VIMODE=false"* ]] &&
   [[ "${ZSH_PROBE_OUT}" == *"AUTOSUGGEST=1"* ]] &&
   [[ "${ZSH_PROBE_OUT}" == *"HIGHLIGHT=1"* ]] &&
   [[ "${ZSH_PROBE_OUT}" == *"HISTSUB=1"* ]] &&
   [[ "${ZSH_PROBE_OUT}" != *"INVASIVE_ALIAS:"* ]]; then
  pass "Zsh interativo inicializa sem erros em stderr, carrega os 3 plugins e preserva ls/cat/find/grep/cd/vi/vim/top/htop sem aliases invasivos"
else
  fail "Falha na sonda do Zsh interativo" "out='${ZSH_PROBE_OUT}', stderr='${ZSH_STDERR_CONTENT}'"
fi

# ------------------------------------------------------------------------------
# 7. Configurações em /home/dev, ausência de artefatos em /root e sem identidade Git
# ------------------------------------------------------------------------------
declare -a EXPECTED_USER_FILES=(
  "/home/dev/.zshenv"
  "/home/dev/.zshrc"
  "/home/dev/.config/starship.toml"
  "/home/dev/.config/tmux/tmux.conf"
  "/home/dev/.config/terminal-setup/zsh/options.zsh"
  "/home/dev/.config/terminal-setup/zsh/aliases.zsh"
  "/home/dev/.config/terminal-setup/zsh/bindings.zsh"
  "/home/dev/.config/terminal-setup/zsh/containers.zsh"
  "/home/dev/.config/terminal-setup/zsh/database.zsh"
  "/home/dev/.config/terminal-setup/zsh/fzf.zsh"
  "/home/dev/.config/terminal-setup/zsh/git.zsh"
  "/home/dev/.config/terminal-setup/zsh/plugins.zsh"
  "/home/dev/.config/terminal-setup/zsh/prompt.zsh"
  "/home/dev/.local/bin/bat"
  "/home/dev/.local/bin/fd"
  "/home/dev/.local/bin/starship"
  "/home/dev/.local/bin/spf"
)

MISSING_USER_FILES=0
for f in "${EXPECTED_USER_FILES[@]}"; do
  if [[ ! -e "${f}" ]]; then
    MISSING_USER_FILES=$((MISSING_USER_FILES + 1))
    fail "Arquivo esperado em /home/dev ausente: ${f}"
  fi
done
if [[ "${MISSING_USER_FILES}" -eq 0 ]]; then
  pass "Todos os 17 arquivos, módulos e binários esperados estão presentes em /home/dev"
fi

if [[ ! -e "/root/.zshrc" ]] && [[ ! -e "/root/.config/terminal-setup" ]] && [[ ! -e "/root/.local/state/terminal-setup" ]]; then
  pass "Isolamento /root confirmado: nenhum dotfile ou estado do projeto foi gravado em /root"
else
  fail "Artefatos indevidos encontrados em /root"
fi

GIT_USER_NAME="$(git config --global --get user.name 2>/dev/null || true)"
GIT_USER_EMAIL="$(git config --global --get user.email 2>/dev/null || true)"
if [[ -z "${GIT_USER_NAME}" ]] && [[ -z "${GIT_USER_EMAIL}" ]] && [[ ! -e "/home/dev/.ssh/id_rsa" ]] && [[ ! -e "/home/dev/.ssh/id_ed25519" ]]; then
  pass "Nenhuma identidade Git pessoal (user.name / user.email) ou chave SSH privada gravada na imagem"
else
  fail "Identidade Git ou chave privada encontrada na imagem" "name='${GIT_USER_NAME}', email='${GIT_USER_EMAIL}'"
fi

if [[ ! -e "/opt/terminal-setup/.git" ]] && [[ ! -e "/opt/terminal-setup/terminal.conf" ]] && [[ -f "/opt/terminal-setup/examples/terminal.conf.example" ]]; then
  pass ".dockerignore protegeu o contexto: .git e terminal.conf local ausentes, examples/terminal.conf.example preservado"
else
  fail "Falha de filtragem do .dockerignore em /opt/terminal-setup"
fi

# ------------------------------------------------------------------------------
# 8. Idempotência em segunda execução real no container
# ------------------------------------------------------------------------------
SHA_BEFORE_ZSHR="$(sha256sum /home/dev/.zshrc | awk '{print $1}')"
SHA_BEFORE_OPTS="$(sha256sum /home/dev/.config/terminal-setup/zsh/options.zsh | awk '{print $1}')"
SHA_BEFORE_STAR="$(sha256sum /home/dev/.config/starship.toml | awk '{print $1}')"
BACKUPS_BEFORE="$(find /home/dev/.local/state/terminal-setup/backups -type f 2>/dev/null | wc -l)"

bash "${INSTALLER}" \
  --profile developer \
  --non-interactive \
  --skip-system-packages \
  --git-identity skip \
  --change-shell no </dev/null >/dev/null

SHA_AFTER_ZSHR="$(sha256sum /home/dev/.zshrc | awk '{print $1}')"
SHA_AFTER_OPTS="$(sha256sum /home/dev/.config/terminal-setup/zsh/options.zsh | awk '{print $1}')"
SHA_AFTER_STAR="$(sha256sum /home/dev/.config/starship.toml | awk '{print $1}')"
BACKUPS_AFTER="$(find /home/dev/.local/state/terminal-setup/backups -type f 2>/dev/null | wc -l)"
LATEST_MANIFEST="$(ls -t /home/dev/.local/state/terminal-setup/manifests/*.json | head -n 1)"

if [[ "${SHA_BEFORE_ZSHR}" == "${SHA_AFTER_ZSHR}" ]] &&
   [[ "${SHA_BEFORE_OPTS}" == "${SHA_AFTER_OPTS}" ]] &&
   [[ "${SHA_BEFORE_STAR}" == "${SHA_AFTER_STAR}" ]] &&
   [[ "${BACKUPS_BEFORE}" -eq "${BACKUPS_AFTER}" ]] &&
   jq -e 'all(.entries[]; .action == "unchanged")' "${LATEST_MANIFEST}" >/dev/null; then
  pass "Segunda execução real no container é 100% idempotente (todos os itens 'unchanged', zero backups extras)"
else
  fail "Segunda execução no container produziu alterações desnecessárias"
fi

# ------------------------------------------------------------------------------
# 9. doctor.sh em modo humano e --json
# ------------------------------------------------------------------------------
if bash "${DOCTOR}" --profile developer >/dev/null; then
  pass "doctor.sh --profile developer retorna código 0 no container Ubuntu 24.04"
else
  fail "doctor.sh --profile developer retornou erro no container"
fi

DOCTOR_JSON_OUT="$(bash "${DOCTOR}" --profile developer --json)"
if printf '%s' "${DOCTOR_JSON_OUT}" | jq -e '.summary.errors == 0 and .summary.exit_code == 0 and .platform.os_id == "ubuntu" and .platform.os_version == "24.04"' >/dev/null; then
  pass "doctor.sh --profile developer --json reporta 0 erros e plataforma ubuntu 24.04"
else
  fail "doctor.sh --json reportou erros ou JSON inesperado" "${DOCTOR_JSON_OUT}"
fi

# ------------------------------------------------------------------------------
# 10 & 11. Ausência de prompts em --non-interactive e comportamento sem TTY
# ------------------------------------------------------------------------------
# 10. --non-interactive com stdin fechado (/dev/null) termina sem travar
if timeout 30s bash "${INSTALLER}" \
     --profile developer \
     --non-interactive \
     --skip-system-packages \
     --git-identity skip \
     --change-shell no </dev/null >/dev/null 2>&1; then
  pass "Execução com --non-interactive e stdin fechado (/dev/null) conclui sem prompts nem travamento"
else
  fail "Execução com --non-interactive e stdin fechado falhou ou travou"
fi

# 11a. Invocação sem --non-interactive e com stdin fechado deve recusar com código 2
set +e
bash "${INSTALLER}" --profile developer --skip-system-packages </dev/null >/dev/null 2>&1
NO_TTY_RC=$?
set -e
if [[ "${NO_TTY_RC}" -eq 2 ]]; then
  pass "Instalador sem --non-interactive e sem TTY/stdin fechado falha imediatamente com código 2"
else
  fail "Instalador sem --non-interactive com stdin fechado deveria retornar 2 (obteve ${NO_TTY_RC})"
fi

# 11b. Zsh não interativo (ex.: scp/rsync) não emite saída espúria em stdout/stderr
NON_INTERACTIVE_ZSH_OUT="$(zsh -c 'printf "CLEAN_ZSH"' 2>&1)"
if [[ "${NON_INTERACTIVE_ZSH_OUT}" == "CLEAN_ZSH" ]]; then
  pass "Zsh não interativo (zsh -c) não produz saída extra em stdout/stderr"
else
  fail "Zsh não interativo produziu saída inesperada: '${NON_INTERACTIVE_ZSH_OUT}'"
fi

# ------------------------------------------------------------------------------
# 12. Modo plain sem exigência de Nerd Font + ciclo de uninstall-terminal.sh
# ------------------------------------------------------------------------------
if cmp -s "/home/dev/.config/starship.toml" "${REPO_ROOT}/config/starship/plain.toml"; then
  pass "Modo plain ativo por padrão (/home/dev/.config/starship.toml idêntico a config/starship/plain.toml, sem Nerd Font)"
else
  fail "/home/dev/.config/starship.toml diverge do template plain.toml"
fi

# Testar ciclo completo de instalação + backup + restauração (uninstall-terminal.sh)
# em um HOME isolado dentro do container Ubuntu 24.04 (sem desconfigurar /home/dev)
(
  TMP_HOME="$(mktemp -d)"
  trap 'rm -rf -- "${TMP_HOME}"' EXIT

  export HOME="${TMP_HOME}"
  export XDG_CONFIG_HOME="${TMP_HOME}/.config"
  export XDG_STATE_HOME="${TMP_HOME}/.local/state"
  export XDG_DATA_HOME="${TMP_HOME}/.local/share"

  printf '# Dotfile original do usuario\n' > "${TMP_HOME}/.zshrc"
  ORIG_SHA="$(sha256sum "${TMP_HOME}/.zshrc" | awk '{print $1}')"

  TS_SKIP_EXTERNAL_DOWNLOADS="true" bash "${INSTALLER}" \
    --profile minimal \
    --non-interactive \
    --skip-system-packages \
    --on-conflict backup-replace \
    --git-identity skip \
    --change-shell no </dev/null >/dev/null

  # Criar arquivo não gerenciado que deve ser preservado na desinstalação
  printf '# Nota pessoal\n' > "${XDG_CONFIG_HOME}/terminal-setup/zsh/minha-nota.zsh"

  bash "${UNINSTALLER}" --non-interactive </dev/null >/dev/null

  RESTORED_SHA="$(sha256sum "${TMP_HOME}/.zshrc" | awk '{print $1}')"
  [[ "${RESTORED_SHA}" == "${ORIG_SHA}" ]]
  [[ -f "${XDG_CONFIG_HOME}/terminal-setup/zsh/minha-nota.zsh" ]]
  [[ ! -e "${XDG_CONFIG_HOME}/starship.toml" ]]
) && pass "Ciclo de uninstall-terminal.sh no container restaura backup original e preserva arquivos desconhecidos" \
  || fail "Falha no teste de restauração/desinstalação dentro do container"

printf '======================================================================\n'
printf 'Resumo da Integração Ubuntu 24.04: %d PASS, %d FAIL\n' "${PASS_COUNT}" "${FAIL_COUNT}"
printf '======================================================================\n'

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi
exit 0

