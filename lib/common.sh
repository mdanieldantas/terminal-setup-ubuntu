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

readonly TS_PROJECT_NAME="terminal-setup"
readonly TS_PROJECT_VERSION="0.1.0-phase1"
readonly TS_SUPPORTED_DISTRO_ID="ubuntu"
readonly TS_SUPPORTED_DISTRO_VERSION="24.04"
readonly TS_SUPPORTED_ARCH="amd64"

# Codigos de saida estaveis
readonly TS_EXIT_OK=0
readonly TS_EXIT_ERR=1
readonly TS_EXIT_USAGE=2
readonly TS_EXIT_PLATFORM=3
readonly TS_EXIT_PRIVILEGE=4
readonly TS_EXIT_NOT_IMPLEMENTED=5

# Inicializacao de cores respeitando NO_COLOR (https://no-color.org/) e TTY
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

