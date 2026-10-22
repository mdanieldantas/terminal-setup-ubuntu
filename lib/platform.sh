#!/usr/bin/env bash
# ==============================================================================
# lib/platform.sh — Deteccao somente leitura de plataforma, privilegios e XDG
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# Nota: Este modulo NAO cria diretorios, NAO executa sudo e NAO altera arquivos.
# ==============================================================================

if [[ -n "${TS_PLATFORM_LOADED:-}" ]]; then
  return 0
fi
readonly TS_PLATFORM_LOADED=1

# Variaveis globais preenchidas por ts_detect_platform
TS_EFFECTIVE_UID=""
TS_EFFECTIVE_USER=""
TS_OS_ID="unknown"
TS_OS_VERSION_ID="unknown"
TS_OS_PRETTY_NAME="unknown"
TS_RAW_ARCH="unknown"
TS_NORM_ARCH="unknown"
TS_IS_WSL="false"
TS_IS_CONTAINER="false"
TS_IS_SUPPORTED_PLATFORM="false"
TS_PLATFORM_NOTE=""
TS_HAS_JQ="false"
TS_HAS_SUDO="false"
TS_HAS_GIT="false"
TS_HAS_CURL="false"
TS_XDG_CONFIG_HOME=""
TS_XDG_STATE_HOME=""
TS_XDG_DATA_HOME=""
TS_ZDOTDIR_STATUS="default"
TS_ZDOTDIR_VALUE=""

# Recusa execucao como root no instalador de usuario (Secao 4 e Secao 18 do guia)
ts_require_non_root() {
  local euid="${TS_TEST_EUID:-${EUID:-$(id -u)}}"
  TS_EFFECTIVE_UID="${euid}"
  if [[ "${euid}" -eq 0 ]]; then
    ts_die "${TS_EXIT_PRIVILEGE}" \
      "O instalador principal nao deve ser executado como root (UID 0). Execute como usuario comum; para pacotes do sistema, use o helper administrativo ou permita sudo quando solicitado."
  fi
}

# Detecta sistema operacional, arquitetura, WSL, container e caminhos XDG (somente leitura)
ts_detect_platform() {
  TS_EFFECTIVE_UID="${TS_TEST_EUID:-${EUID:-$(id -u)}}"
  TS_EFFECTIVE_USER="${USER:-$(id -un 2>/dev/null || printf 'uid-%s' "${TS_EFFECTIVE_UID}")}"

  local os_release_file="${TS_OS_RELEASE_FILE:-/etc/os-release}"
  TS_OS_ID="unknown"
  TS_OS_VERSION_ID="unknown"
  TS_OS_PRETTY_NAME="unknown"

  if [[ -r "${os_release_file}" ]]; then
    local line key val
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="${line%$'\r'}"
      if [[ -z "${line}" ]] || [[ "${line}" == \#* ]] || [[ "${line}" != *"="* ]]; then
        continue
      fi
      key="${line%%=*}"
      val="${line#*=}"
      # Remover aspas simples ou duplas externas sem usar eval/source
      if [[ "${val}" == \"*\" ]] && [[ "${#val}" -ge 2 ]]; then
        val="${val:1:${#val}-2}"
      elif [[ "${val}" == \'*\' ]] && [[ "${#val}" -ge 2 ]]; then
        val="${val:1:${#val}-2}"
      fi
      case "${key}" in
        ID) TS_OS_ID="${val}" ;;
        VERSION_ID) TS_OS_VERSION_ID="${val}" ;;
        PRETTY_NAME) TS_OS_PRETTY_NAME="${val}" ;;
      esac
    done < "${os_release_file}"
  fi

  TS_RAW_ARCH="${TS_TEST_ARCH:-$(uname -m 2>/dev/null || printf 'unknown')}"
  case "${TS_RAW_ARCH}" in
    x86_64 | amd64)
      TS_NORM_ARCH="amd64"
      ;;
    aarch64 | arm64)
      TS_NORM_ARCH="arm64"
      ;;
    *)
      TS_NORM_ARCH="${TS_RAW_ARCH}"
      ;;
  esac

  # Deteccao somente leitura de WSL
  TS_IS_WSL="false"
  if [[ -n "${WSL_DISTRO_NAME:-}" ]] || [[ -e /proc/sys/fs/binfmt_misc/WSLInterop ]]; then
    TS_IS_WSL="true"
  elif [[ -r /proc/version ]] && grep -qiE 'microsoft|wsl' /proc/version 2>/dev/null; then
    TS_IS_WSL="true"
  fi

  # Deteccao somente leitura de container
  TS_IS_CONTAINER="false"
  if [[ -e /.dockerenv ]] || [[ -e /run/.containerenv ]] || [[ -n "${container:-}" ]]; then
    TS_IS_CONTAINER="true"
  fi

  # Verificacao da matriz de suporte da v1: Ubuntu 24.04 LTS amd64
  TS_IS_SUPPORTED_PLATFORM="false"
  TS_PLATFORM_NOTE=""
  if [[ "${TS_OS_ID}" == "${TS_SUPPORTED_DISTRO_ID}" ]] &&
     [[ "${TS_OS_VERSION_ID}" == "${TS_SUPPORTED_DISTRO_VERSION}" ]] &&
     [[ "${TS_NORM_ARCH}" == "${TS_SUPPORTED_ARCH}" ]]; then
    TS_IS_SUPPORTED_PLATFORM="true"
    TS_PLATFORM_NOTE="Plataforma suportada na v1 (Ubuntu 24.04 LTS amd64)."
  elif [[ "${TS_OS_ID}" == "${TS_SUPPORTED_DISTRO_ID}" ]] &&
       [[ "${TS_OS_VERSION_ID}" == "${TS_SUPPORTED_DISTRO_VERSION}" ]] &&
       [[ "${TS_NORM_ARCH}" == "arm64" ]]; then
    TS_PLATFORM_NOTE="Ubuntu 24.04 arm64 detectado: fora do suporte garantido da v1 ate verificacao completa de artefatos e testes."
  else
    TS_PLATFORM_NOTE="Ambiente atual (${TS_OS_ID} ${TS_OS_VERSION_ID}, ${TS_NORM_ARCH}) fora do alvo de instalacao da v1 (Ubuntu 24.04 LTS amd64)."
  fi

  # Verificacao somente leitura de comandos no PATH atual
  if command -v jq >/dev/null 2>&1; then
    TS_HAS_JQ="true"
  else
    TS_HAS_JQ="false"
  fi

  if command -v sudo >/dev/null 2>&1; then
    TS_HAS_SUDO="true"
  else
    TS_HAS_SUDO="false"
  fi

  if command -v git >/dev/null 2>&1; then
    TS_HAS_GIT="true"
  else
    TS_HAS_GIT="false"
  fi

  if command -v curl >/dev/null 2>&1; then
    TS_HAS_CURL="true"
  else
    TS_HAS_CURL="false"
  fi
}

# Valida HOME, caminhos XDG e ZDOTDIR sem escrever no disco
ts_validate_user_paths() {
  if [[ -z "${HOME:-}" ]]; then
    ts_die "${TS_EXIT_ERR}" "A variavel de ambiente HOME nao esta definida."
  fi
  if [[ "${HOME}" != /* ]] || ts_has_control_chars "${HOME}"; then
    ts_die "${TS_EXIT_ERR}" "A variavel HOME deve ser um caminho absoluto valido: '${HOME}'."
  fi

  TS_XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-${HOME}/.config}"
  TS_XDG_STATE_HOME="${XDG_STATE_HOME:-${HOME}/.local/state}"
  TS_XDG_DATA_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}"

  local xdg_var
  for xdg_var in "${TS_XDG_CONFIG_HOME}" "${TS_XDG_STATE_HOME}" "${TS_XDG_DATA_HOME}"; do
    if [[ "${xdg_var}" != /* ]] || ts_has_control_chars "${xdg_var}"; then
      ts_die "${TS_EXIT_ERR}" "Caminho XDG invalido (deve ser absoluto e sem caracteres de controle): '${xdg_var}'."
    fi
  done

  TS_ZDOTDIR_STATUS="default"
  TS_ZDOTDIR_VALUE="${ZDOTDIR:-}"
  if [[ -n "${TS_ZDOTDIR_VALUE}" ]] && [[ "${TS_ZDOTDIR_VALUE}" != "${HOME}" ]]; then
    if [[ "${TS_ZDOTDIR_VALUE}" != /* ]] || ts_has_control_chars "${TS_ZDOTDIR_VALUE}"; then
      ts_die "${TS_EXIT_ERR}" "ZDOTDIR customizado invalido (deve ser caminho absoluto): '${TS_ZDOTDIR_VALUE}'."
    fi
    TS_ZDOTDIR_STATUS="custom"
  fi
}

# Valida requisitos obrigatorios para execucao efetiva (nao chamado em --help, --version ou --dry-run)
ts_require_supported_execution_environment() {
  local skip_system_packages="$1"
  if [[ "${TS_IS_SUPPORTED_PLATFORM}" != "true" ]]; then
    ts_die "${TS_EXIT_PLATFORM}" \
      "Execucao efetiva bloqueada: ${TS_PLATFORM_NOTE} Use --dry-run apenas para inspecionar o plano sem alterar o sistema."
  fi

  # Conforme decisao P3: operacoes efetivas que manipulam locks/manifestos JSON exigem jq
  # (quando --skip-system-packages estiver ativo e jq nao for instalado via APT previamente).
  if [[ "${skip_system_packages}" == "true" ]] && [[ "${TS_HAS_JQ}" != "true" ]]; then
    ts_die "${TS_EXIT_ERR}" \
      "O comando 'jq' e requisito base obrigatorio para leitura de locks e geracao de manifesto JSON, mas nao foi encontrado no PATH com --skip-system-packages. Instale o pacote 'jq' via APT antes de prosseguir."
  fi
}

