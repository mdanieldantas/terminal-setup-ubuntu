#!/usr/bin/env bash
# ==============================================================================
# scripts/install-system-packages.sh — Helper administrativo de pacotes APT
# Plataforma alvo da v1: Ubuntu 24.04 LTS (amd64)
#
# Regras fundamentais (Secoes 4, 7.3 e 14 do guia):
#   - Recusa execucao sem UID 0 (root).
#   - Opera SOMENTE sobre a lista fechada (allowlist) de pacotes APT do projeto.
#   - Nunca aceita fragmentos de shell, URLs ou pacotes arbitrarios.
#   - Nao escreve no HOME do usuario, nao configura Git e nao executa
#     instaladores remotos.
#   - Nao executa apt-get upgrade, dist-upgrade nem reboot.
# ==============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  printf '[ERRO] Este script nao deve ser carregado com "source". Execute como root: bash ./scripts/install-system-packages.sh [opcoes]\n' >&2
  return 2 2>/dev/null || exit 2
fi

set -Eeuo pipefail

ts_resolve_repo_root() {
  local source_path="${BASH_SOURCE[0]}"
  local dir_path
  while [[ -L "${source_path}" ]]; do
    dir_path="$(cd -P "$(dirname "${source_path}")" >/dev/null 2>&1 && pwd)"
    source_path="$(readlink "${source_path}")"
    if [[ "${source_path}" != /* ]]; then
      source_path="${dir_path}/${source_path}"
    fi
  done
  cd -P "$(dirname "${source_path}")/.." >/dev/null 2>&1 && pwd
}

readonly TS_REPO_ROOT="$(ts_resolve_repo_root)"

# shellcheck source=lib/common.sh
source "${TS_REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/platform.sh
source "${TS_REPO_ROOT}/lib/platform.sh"
# shellcheck source=lib/config-parser.sh
source "${TS_REPO_ROOT}/lib/config-parser.sh"
# shellcheck source=lib/arguments.sh
source "${TS_REPO_ROOT}/lib/arguments.sh"

# Lista fechada (allowlist) de pacotes APT permitidos no Ubuntu 24.04 LTS
readonly -a TS_ALLOWED_APT_PACKAGES=(
  "zsh"
  "git"
  "nano"
  "ca-certificates"
  "curl"
  "jq"
  "fzf"
  "ripgrep"
  "bat"
  "fd-find"
  "tmux"
  "zoxide"
  "eza"
  "btop"
)

HELPER_PROFILE=""
HELPER_PACKAGES_RAW=""
HELPER_DRY_RUN="false"

helper_print_help() {
  cat << 'EOF'
Uso:
  sudo bash ./scripts/install-system-packages.sh [opcoes]

Descricao:
  Helper administrativo do terminal-setup para instalar exclusivamente os
  pacotes APT oficiais requeridos pelo perfil ou pela selecao validada.
  Exige UID 0 (root). Nao altera arquivos no HOME do usuario.

Opcoes:
  -h, --help                     Exibe esta ajuda sem realizar alteracoes.
  --profile <minimal|developer|server>
                                 Seleciona os pacotes APT correspondentes ao perfil.
  --packages <pkg1,pkg2,...>     Lista explicita de pacotes APT (validada contra
                                 a allowlist fechada do projeto).
  --dry-run                      Apenas valida e exibe os pacotes que seriam
                                 instalados, sem executar apt-get.

Pacotes APT permitidos na allowlist da v1:
  zsh, git, nano, ca-certificates, curl, jq, fzf, ripgrep, bat, fd-find,
  tmux, zoxide, eza, btop
EOF
}

helper_parse_args() {
  local arg opt_name opt_val
  while [[ $# -gt 0 ]]; do
    arg="$1"
    if [[ "${arg}" == --*=* ]]; then
      opt_name="${arg%%=*}"
      opt_val="${arg#*=}"
      if [[ -z "${opt_val}" ]]; then
        ts_die_usage "O parametro '${opt_name}' exige um valor nao vazio."
      fi
      case "${opt_name}" in
        --profile) HELPER_PROFILE="${opt_val}" ;;
        --packages) HELPER_PACKAGES_RAW="${opt_val}" ;;
        --help | --dry-run)
          ts_die_usage "O parametro '${opt_name}' nao aceita valor ('${arg}')."
          ;;
        *)
          ts_die_usage "Parametro desconhecido no helper de pacotes: '${opt_name}'."
          ;;
      esac
      shift
      continue
    fi

    case "${arg}" in
      -h | --help)
        helper_print_help
        exit "${TS_EXIT_OK}"
        ;;
      --profile)
        if [[ $# -lt 2 ]] || [[ -z "${2:-}" ]]; then
          ts_die_usage "O parametro '--profile' exige um valor (minimal, developer ou server)."
        fi
        HELPER_PROFILE="$2"
        shift 2
        ;;
      --packages)
        if [[ $# -lt 2 ]] || [[ -z "${2:-}" ]]; then
          ts_die_usage "O parametro '--packages' exige uma lista CSV de pacotes permitidos."
        fi
        HELPER_PACKAGES_RAW="$2"
        shift 2
        ;;
      --dry-run)
        HELPER_DRY_RUN="true"
        shift
        ;;
      -*)
        ts_die_usage "Parametro desconhecido no helper de pacotes: '${arg}'."
        ;;
      *)
        ts_die_usage "Argumento posicional inesperado no helper de pacotes: '${arg}'."
        ;;
    esac
  done

  if [[ -n "${HELPER_PROFILE}" ]] && [[ -n "${HELPER_PACKAGES_RAW}" ]]; then
    ts_die_usage "Informe apenas --profile OU --packages no helper administrativo, nao ambos."
  fi
  if [[ -z "${HELPER_PROFILE}" ]] && [[ -z "${HELPER_PACKAGES_RAW}" ]]; then
    HELPER_PROFILE="minimal"
  fi
}

# Verifica se um pacote APT ja esta instalado segundo dpkg-query
helper_is_pkg_installed() {
  local pkg="$1"
  if ! command -v dpkg-query >/dev/null 2>&1; then
    return 1
  fi
  local status_out=""
  status_out="$(dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null || true)"
  [[ "${status_out}" == "install ok installed" ]]
}

main() {
  helper_parse_args "$@"

  local -a target_packages=()
  local parsed_csv pkg comp apt_pkg

  if [[ -n "${HELPER_PROFILE}" ]]; then
    ts_validate_enum "--profile" "${HELPER_PROFILE}" "${TS_VALID_PROFILES[@]}"
    ts_load_profile_file "${HELPER_PROFILE}" "${TS_REPO_ROOT}"
    parsed_csv="$(ts_split_csv_strict "${TS_PROFILE_VALUES[REQUIRED_COMPONENTS]}")"
    local -a prof_comps=()
    mapfile -t prof_comps <<< "${parsed_csv}"
    for comp in "${prof_comps[@]}"; do
      apt_pkg="$(ts_component_apt_package "${comp}")"
      if [[ -n "${apt_pkg}" ]]; then
        target_packages+=("${apt_pkg}")
      fi
    done
  else
    if ! parsed_csv="$(ts_split_csv_strict "${HELPER_PACKAGES_RAW}")"; then
      ts_die_usage "Lista de pacotes malformada em --packages: '${HELPER_PACKAGES_RAW}'."
    fi
    mapfile -t target_packages <<< "${parsed_csv}"
  fi

  # Validar cada pacote estritamente contra a allowlist fechada
  for pkg in "${target_packages[@]}"; do
    if ! ts_list_contains "${pkg}" "${TS_ALLOWED_APT_PACKAGES[@]}"; then
      ts_die_usage "Pacote nao permitido ou desconhecido na allowlist do helper: '${pkg}'."
    fi
  done

  # Exigir UID 0 (root) para qualquer operacao (Secao 4 e Secao 18 do guia)
  local euid="${TS_TEST_EUID:-${EUID:-$(id -u)}}"
  if [[ "${euid}" -ne 0 ]]; then
    ts_die "${TS_EXIT_PRIVILEGE}" \
      "O helper administrativo 'scripts/install-system-packages.sh' exige execucao como root (UID 0). UID atual: ${euid}."
  fi

  ts_detect_platform
  if [[ "${TS_IS_SUPPORTED_PLATFORM}" != "true" ]]; then
    ts_die "${TS_EXIT_PLATFORM}" \
      "Recusando executar APT fora da plataforma suportada (Ubuntu 24.04 LTS amd64). Detectado: ${TS_OS_ID} ${TS_OS_VERSION_ID} (${TS_NORM_ARCH})."
  fi

  # Identificar quais pacotes ainda nao estao instalados
  local -a missing_packages=()
  for pkg in "${target_packages[@]}"; do
    if ! helper_is_pkg_installed "${pkg}"; then
      missing_packages+=("${pkg}")
    fi
  done

  if [[ "${HELPER_DRY_RUN}" == "true" ]]; then
    ts_info "Modo --dry-run (helper administrativo): pacotes validados: ${target_packages[*]}"
    ts_info "Pacotes pendentes de instalacao: ${missing_packages[*]:-(nenhum; todos ja instalados)}"
    exit "${TS_EXIT_OK}"
  fi

  if [[ "${#missing_packages[@]}" -eq 0 ]]; then
    ts_ok "Todos os pacotes APT solicitados ja estao instalados: ${target_packages[*]}"
    exit "${TS_EXIT_OK}"
  fi

  if ! command -v apt-get >/dev/null 2>&1; then
    ts_die "${TS_EXIT_ERR}" "Comando 'apt-get' nao encontrado no sistema."
  fi

  ts_info "Atualizando indices APT e instalando pacotes ausentes (${#missing_packages[@]}): ${missing_packages[*]}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  apt-get install -y --no-install-recommends -- "${missing_packages[@]}"
  ts_ok "Pacotes APT instalados com sucesso: ${missing_packages[*]}"
}

main "$@"
