#!/usr/bin/env bash
# ==============================================================================
# lib/common.sh — Constantes, formatacao, mensagens e utilitarios puros
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# Nota: Este modulo NAO cria diretorios, NAO grava logs e NAO executa rede/sudo.
# ==============================================================================

if [[ -n "${TS_COMMON_LOADED:-}" ]]; then
  return 0
fi
readonly TS_COMMON_LOADED=1

# Constantes e codigos de saida estaveis consumidos pelos modulos e scripts chamadores
# shellcheck disable=SC2034
readonly \
  TS_PROJECT_NAME="terminal-setup" \
  TS_PROJECT_VERSION="0.5.0-phase5" \
  TS_SUPPORTED_DISTRO_ID="ubuntu" \
  TS_SUPPORTED_DISTRO_VERSION="24.04" \
  TS_SUPPORTED_ARCH="amd64" \
  TS_EXIT_OK=0 \
  TS_EXIT_ERR=1 \
  TS_EXIT_USAGE=2 \
  TS_EXIT_PLATFORM=3 \
  TS_EXIT_PRIVILEGE=4 \
  TS_EXIT_NOT_IMPLEMENTED=5

# Verifica se um caminho de teste (ou seu diretorio pai existente) resolve
# efetivamente para dentro de /tmp sem atravessar symlinks que escapem de /tmp.
# Importante: Esta funcao NAO e mecanismo de isolamento nem barreira de seguranca;
# serve apenas para validar fixtures e mocks de teste em /tmp verificando o
# caminho efetivo (readlink -f) e a ausencia de symlinks, nao apenas o prefixo textual.
ts_is_effective_tmp_path() {
  local raw_path="${1:-}"
  if [[ -z "${raw_path}" ]] || [[ "${raw_path}" != /tmp/* ]] || [[ "${raw_path}" == *".."* ]]; then
    return 1
  fi
  if [[ "${raw_path}" == *$'\n'* ]] || [[ "${raw_path}" == *$'\r'* ]]; then
    return 1
  fi

  # Rejeitar se o proprio caminho (quando existente) for um symlink
  if [[ -L "${raw_path}" ]]; then
    return 1
  fi

  # Rejeitar se qualquer componente intermediario sob /tmp for um symlink
  local rel="${raw_path#/tmp/}"
  local cur="/tmp"
  local seg
  while [[ -n "${rel}" ]]; do
    if [[ "${rel}" == *"/"* ]]; then
      seg="${rel%%/*}"
      rel="${rel#*/}"
    else
      seg="${rel}"
      rel=""
    fi
    [[ -z "${seg}" ]] && continue
    cur="${cur}/${seg}"
    if [[ -L "${cur}" ]]; then
      return 1
    fi
  done

  # Resolver o caminho canonico do alvo existente (ou de seu diretorio pai) via readlink -f
  local check_target="${raw_path}"
  if [[ ! -e "${check_target}" ]]; then
    check_target="${raw_path%/*}"
  fi
  if [[ -e "${check_target}" ]]; then
    local resolved_tmp resolved_target
    resolved_tmp="$(readlink -f -- "/tmp" 2>/dev/null || printf '/tmp')"
    resolved_target="$(readlink -f -- "${check_target}" 2>/dev/null || true)"
    if [[ -z "${resolved_target}" ]] \
      || { [[ "${resolved_target}" != "${resolved_tmp}" ]] && [[ "${resolved_target}" != "${resolved_tmp}/"* ]]; }; then
      return 1
    fi
  fi

  return 0
}

# Limpa variaveis de hook de teste (TS_TEST_*) quando a execucao nao esta com
# TS_TEST_SANDBOX_MODE=1 sobre caminhos efetivos em /tmp.
# Nota de arquitetura: TS_TEST_SANDBOX_MODE e os hooks TS_TEST_* sao recursos
# auxiliares da suite de testes (simulacao de plataforma e injecao de mocks),
# NAO mecanismos de isolamento ou fronteira de seguranca. As verificacoes reais
# de seguranca residem nas checagens de UID do kernel (EUID), propriedade de
# arquivos (stat) e validacao canonica de destinos (ts_validate_managed_path).
ts_sanitize_test_hooks() {
  local allow_test_hooks="false"
  if [[ "${TS_TEST_SANDBOX_MODE:-0}" == "1" ]]; then
    local first_path_entry="${PATH%%:*}"
    if ts_is_effective_tmp_path "${HOME:-}"; then
      allow_test_hooks="true"
    elif ts_is_effective_tmp_path "${TS_TEST_OS_RELEASE_FILE:-}"; then
      allow_test_hooks="true"
    elif ts_is_effective_tmp_path "${first_path_entry}"; then
      allow_test_hooks="true"
    fi
  fi

  if [[ "${allow_test_hooks}" != "true" ]]; then
    unset TS_TEST_SANDBOX_MODE \
      TS_TEST_EUID \
      TS_TEST_ARCH \
      TS_TEST_OS_RELEASE_FILE \
      TS_TEST_TOOLS_LOCK_FILE \
      TS_TEST_PLUGINS_LOCK_FILE \
      TS_TEST_PLUGIN_REPO_BASE \
      TS_TEST_SKIP_EXTERNAL_DOWNLOADS || true
  fi
}

ts_sanitize_test_hooks

# Inicializacao de cores respeitando NO_COLOR (https://no-color.org/) e TTY
# shellcheck disable=SC2034 # TS_COLOR_BOLD e demais cores sao consumidas por lib/plan.sh, doctor.sh e uninstall-terminal.sh
ts_init_colors() {
  if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]] || [[ ! -t 1 ]]; then
    TS_COLOR_RESET=""
    TS_COLOR_BOLD=""
    TS_COLOR_INFO=""
    TS_COLOR_OK=""
    TS_COLOR_WARN=""
    TS_COLOR_ERR=""
  else
    TS_COLOR_RESET=$'\033[0m'
    TS_COLOR_BOLD=$'\033[1m'
    TS_COLOR_INFO=$'\033[34m'
    TS_COLOR_OK=$'\033[32m'
    TS_COLOR_WARN=$'\033[33m'
    TS_COLOR_ERR=$'\033[31m'
  fi
}

ts_init_colors

# Mensagens padronizadas em portugues (sem depender de cores ou emojis para sentido)
ts_info() {
  printf '%s[INFO]%s %s\n' "${TS_COLOR_INFO}" "${TS_COLOR_RESET}" "$*"
}

ts_ok() {
  printf '%s[OK]%s %s\n' "${TS_COLOR_OK}" "${TS_COLOR_RESET}" "$*"
}

ts_warn() {
  printf '%s[AVISO]%s %s\n' "${TS_COLOR_WARN}" "${TS_COLOR_RESET}" "$*" >&2
}

ts_error() {
  printf '%s[ERRO]%s %s\n' "${TS_COLOR_ERR}" "${TS_COLOR_RESET}" "$*" >&2
}

ts_die() {
  local exit_code="$1"
  shift
  ts_error "$*"
  exit "${exit_code}"
}

ts_die_usage() {
  ts_error "$*"
  printf 'Use "bash ./install-terminal.sh --help" para consultar os parametros validos.\n' >&2
  exit "${TS_EXIT_USAGE}"
}

# Remove espacos em branco (espaco e tab) apenas nas extremidades de uma string
ts_trim() {
  local val="$1"
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  printf '%s' "${val}"
}

# Verifica se um item existe em uma lista de argumentos
ts_list_contains() {
  local needle="$1"
  shift
  local item
  for item in "$@"; do
    if [[ "${item}" == "${needle}" ]]; then
      return 0
    fi
  done
  return 1
}

# Verifica se uma string contem caracteres de controle ASCII (0x00-0x1F ou 0x7F)
ts_has_control_chars() {
  local str="$1"
  local LC_ALL=C
  if [[ "${str}" =~ [[:cntrl:]] ]]; then
    return 0
  fi
  return 1
}

# Validacao conservadora de e-mail Git (evita espacos, quebras de linha, controle e formato obvio invalido)
ts_validate_email() {
  local email="$1"
  if [[ -z "${email}" ]]; then
    return 1
  fi
  if ts_has_control_chars "${email}"; then
    return 1
  fi
  if [[ "${email}" =~ [[:space:]] ]]; then
    return 1
  fi
  # Deve conter exatamente um '@', parte local nao vazia e dominio com pelo menos um ponto
  local local_part="${email%%@*}"
  local domain_part="${email#*@}"
  if [[ "${local_part}" == "${email}" ]] || [[ -z "${local_part}" ]] || [[ -z "${domain_part}" ]]; then
    return 1
  fi
  if [[ "${domain_part}" == *"@"* ]] || [[ "${domain_part}" != *"."* ]]; then
    return 1
  fi
  if [[ "${domain_part}" == .* ]] || [[ "${domain_part}" == *. ]]; then
    return 1
  fi
  return 0
}

# Validacao de nome Git (nao vazio, sem caracteres de controle/quebras de linha)
ts_validate_git_name() {
  local name="$1"
  if [[ -z "${name}" ]]; then
    return 1
  fi
  if ts_has_control_chars "${name}"; then
    return 1
  fi
  local trimmed
  trimmed="$(ts_trim "${name}")"
  if [[ -z "${trimmed}" ]]; then
    return 1
  fi
  return 0
}

# Validacao e divisao de lista separada por virgulas (rejeita string vazia ou itens vazios como "a,,b")
# Saida: imprime cada item validado em uma linha
ts_split_csv_strict() {
  local raw="$1"
  if [[ -z "${raw}" ]]; then
    return 1
  fi
  if [[ "${raw}" == *, ]] || [[ "${raw}" == ,* ]] || [[ "${raw}" == *",,"* ]]; then
    return 1
  fi

  local remaining="${raw}"
  local part
  while [[ -n "${remaining}" ]]; do
    if [[ "${remaining}" == *","* ]]; then
      part="${remaining%%,*}"
      remaining="${remaining#*,}"
    else
      part="${remaining}"
      remaining=""
    fi
    if [[ -z "${part}" ]] || [[ "${part}" =~ [[:space:]] ]] || ts_has_control_chars "${part}"; then
      return 1
    fi
    printf '%s\n' "${part}"
  done
  return 0
}
