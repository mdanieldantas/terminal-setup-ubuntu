#!/usr/bin/env bash
# ==============================================================================
# lib/packages.sh — Coordenacao entre instalador de usuario e helper APT root
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# Segue estritamente as Secoes 4 e 7.1 do guia de implementacao.
# ==============================================================================

if [[ -n "${TS_PACKAGES_LOADED:-}" ]]; then
  return 0
fi
readonly TS_PACKAGES_LOADED=1

# Verifica se um pacote APT ja consta como instalado via dpkg-query (somente leitura)
ts_is_apt_package_installed() {
  local pkg="$1"
  if ! command -v dpkg-query >/dev/null 2>&1; then
    return 1
  fi
  local status_out=""
  status_out="$(dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null || true)"
  [[ "${status_out}" == "install ok installed" ]]
}

# Converte array de pacotes em string CSV
ts_join_by_comma() {
  local IFS=","
  printf '%s' "$*"
}

# Verifica ou instala os pacotes APT selecionados delegando ao helper administrativo
ts_handle_system_packages() {
  local repo_root="$1"
  local helper_script="${repo_root}/scripts/install-system-packages.sh"

  if [[ "${#TS_SELECTED_APT_PACKAGES[@]}" -eq 0 ]]; then
    ts_log_event "INFO" "Nenhum pacote APT selecionado para esta execucao."
    return 0
  fi

  if [[ "${TS_OPT_SKIP_SYSTEM_PACKAGES}" == "true" ]]; then
    ts_info "Pulando instalacao de pacotes APT do sistema (--skip-system-packages ativo)."
    ts_log_event "INFO" "Pacotes APT omitidos por --skip-system-packages: ${TS_SELECTED_APT_PACKAGES[*]}"
    return 0
  fi

  # Verificar quais pacotes da lista ainda nao estao instalados
  local -a missing_pkgs=()
  local pkg
  for pkg in "${TS_SELECTED_APT_PACKAGES[@]}"; do
    if ! ts_is_apt_package_installed "${pkg}"; then
      missing_pkgs+=("${pkg}")
    fi
  done

  if [[ "${#missing_pkgs[@]}" -eq 0 ]]; then
    ts_ok "Todos os pacotes APT requeridos ja estao instalados no sistema."
    ts_log_event "INFO" "Pacotes APT ja instalados (sudo nao necessario): ${TS_SELECTED_APT_PACKAGES[*]}"
    return 0
  fi

  local csv_packages
  csv_packages="$(ts_join_by_comma "${TS_SELECTED_APT_PACKAGES[@]}")"

  if [[ ! -r "${helper_script}" ]]; then
    ts_die "${TS_EXIT_ERR}" "Helper administrativo nao encontrado em '${helper_script}'."
  fi

  # Se sudo nao estiver disponivel, explicar a alternativa de duas etapas (Secao 4)
  if ! command -v sudo >/dev/null 2>&1; then
    ts_error "Pacotes APT pendentes (${missing_pkgs[*]}), mas o comando 'sudo' nao esta disponivel."
    printf 'Alternativa em duas etapas (Secao 4 do guia):\n' >&2
    printf '  1. O administrador (root) executa:\n' >&2
    printf '       bash ./scripts/install-system-packages.sh --packages %s\n' "${csv_packages}" >&2
    printf '  2. Em seguida, seu usuario comum executa:\n' >&2
    printf '       bash ./install-terminal.sh --skip-system-packages [demais opcoes]\n' >&2
    exit "${TS_EXIT_PRIVILEGE}"
  fi

  # Regra obrigatoria (Secao 7.1): --non-interactive NAO pode travar esperando senha de sudo!
  if [[ "${TS_OPT_NON_INTERACTIVE}" == "true" ]]; then
    if ! sudo -n true 2>/dev/null; then
      ts_error "Modo --non-interactive ativo e ha pacotes APT ausentes (${missing_pkgs[*]}), mas 'sudo -n' exige senha."
      printf 'Para execucao nao interativa:\n' >&2
      printf '  1. Execute previamente como root: bash ./scripts/install-system-packages.sh --packages %s\n' "${csv_packages}" >&2
      printf '  2. Execute este instalador com --skip-system-packages.\n' >&2
      exit "${TS_EXIT_PRIVILEGE}"
    fi
    ts_info "Delegando instalacao de pacotes APT ao helper administrativo via 'sudo -n'..."
    ts_log_event "INFO" "Chamando helper administrativo via sudo -n: packages=${csv_packages}"
    sudo -n bash "${helper_script}" --packages "${csv_packages}"
  else
    ts_info "Delegando instalacao de pacotes APT ao helper administrativo via 'sudo'..."
    ts_log_event "INFO" "Chamando helper administrativo via sudo: packages=${csv_packages}"
    sudo bash "${helper_script}" --packages "${csv_packages}"
  fi
}
