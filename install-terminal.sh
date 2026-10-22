#!/usr/bin/env bash
# ==============================================================================
# install-terminal.sh — Instalador principal do projeto terminal-setup
# Plataforma alvo da v1: Ubuntu 24.04 LTS (amd64)
#
# Regras fundamentais:
#   - Deve ser executado como arquivo (bash ./install-terminal.sh), nunca via source.
#   - Recusa execucao como root (UID 0) sem modificar arquivos.
#   - Em --help, --version e --dry-run, nao cria diretorios, logs, backups,
#     chamadas de rede ou comandos sudo.
# ==============================================================================

# Impedir execucao via "source"
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  printf '[ERRO] Este script nao deve ser carregado com "source". Execute: bash ./install-terminal.sh [opcoes]\n' >&2
  return 2 2>/dev/null || exit 2
fi

set -Eeuo pipefail

# Resolver diretorio real do script sem depender do diretorio atual de trabalho
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
  cd -P "$(dirname "${source_path}")" >/dev/null 2>&1 && pwd
}

readonly TS_REPO_ROOT="$(ts_resolve_repo_root)"

# Carregar bibliotecas confiaveis do proprio repositorio
# shellcheck source=lib/common.sh
source "${TS_REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/platform.sh
source "${TS_REPO_ROOT}/lib/platform.sh"
# shellcheck source=lib/config-parser.sh
source "${TS_REPO_ROOT}/lib/config-parser.sh"
# shellcheck source=lib/arguments.sh
source "${TS_REPO_ROOT}/lib/arguments.sh"
# shellcheck source=lib/plan.sh
source "${TS_REPO_ROOT}/lib/plan.sh"
# shellcheck source=lib/backups.sh
source "${TS_REPO_ROOT}/lib/backups.sh"
# shellcheck source=lib/manifest.sh
source "${TS_REPO_ROOT}/lib/manifest.sh"
# shellcheck source=lib/packages.sh
source "${TS_REPO_ROOT}/lib/packages.sh"
# shellcheck source=lib/downloads.sh
source "${TS_REPO_ROOT}/lib/downloads.sh"
# shellcheck source=lib/tools.sh
source "${TS_REPO_ROOT}/lib/tools.sh"
# shellcheck source=lib/plugins.sh
source "${TS_REPO_ROOT}/lib/plugins.sh"
# shellcheck source=lib/user-config.sh
source "${TS_REPO_ROOT}/lib/user-config.sh"
# shellcheck source=lib/git-config.sh
source "${TS_REPO_ROOT}/lib/git-config.sh"

TS_INSTALL_COMPLETED="false"

# Trap que preserva o codigo de saida original, marca falha parcial no manifesto
# (se uma sessao efetiva ja tiver sido iniciada) e libera o lock de concorrencia.
ts_on_exit() {
  local exit_code=$?
  if [[ "${TS_LOCK_ACQUIRED:-false}" == "true" ]]; then
    if [[ "${TS_INSTALL_COMPLETED}" != "true" ]] && [[ -n "${TS_CURRENT_MANIFEST_FILE:-}" ]] && [[ -f "${TS_CURRENT_MANIFEST_FILE}" ]]; then
      ts_manifest_finalize "failed" || true
    fi
    ts_release_execution_lock
  fi
  exit "${exit_code}"
}

ts_on_unexpected_error() {
  local exit_code=$?
  local line_no="${1:-desconhecida}"
  printf '[ERRO] Falha inesperada na linha %s (codigo de saida: %d).\n' "${line_no}" "${exit_code}" >&2
  exit "${exit_code}"
}

trap 'ts_on_unexpected_error ${LINENO}' ERR
trap 'ts_on_exit' EXIT

main() {
  # 1. Validar argumentos e carregar perfil/config antes de qualquer efeito colateral
  ts_parse_arguments "${TS_REPO_ROOT}" "$@"

  # 2. Atender --help e --version imediatamente sem tocar no sistema de arquivos
  if [[ "${TS_ACTION}" == "help" ]]; then
    ts_print_help
    exit "${TS_EXIT_OK}"
  fi
  if [[ "${TS_ACTION}" == "version" ]]; then
    ts_print_version
    exit "${TS_EXIT_OK}"
  fi

  # 3. Recusar execucao como root (UID 0) sem modificar arquivos
  ts_require_non_root

  # 4. Preflight somente leitura de plataforma e caminhos do usuario
  ts_detect_platform
  ts_validate_user_paths

  # 5. Se --dry-run estiver ativo, exibir o plano e encerrar com sucesso sem escrita/rede/sudo
  if [[ "${TS_OPT_DRY_RUN}" == "true" ]]; then
    ts_print_execution_plan
    exit "${TS_EXIT_OK}"
  fi

  # 6. Verificacoes adicionais para execucao efetiva (fora de --dry-run)
  if [[ "${TS_OPT_NON_INTERACTIVE}" != "true" ]] && [[ ! -t 0 ]]; then
    ts_die_usage "Entrada padrao (stdin) fechada ou nao interativa detectada sem a flag --non-interactive. Informe --non-interactive para execucao automatizada."
  fi

  ts_require_supported_execution_environment "${TS_OPT_SKIP_SYSTEM_PACKAGES}"

  # Exibir o plano antes de iniciar alteracoes
  ts_print_execution_plan

  # Confirmacao interativa para iniciar se nao estiver em --non-interactive nem --yes
  if [[ "${TS_OPT_NON_INTERACTIVE}" != "true" ]] && [[ "${TS_OPT_YES}" != "true" ]]; then
    local confirm_start=""
    printf 'Deseja aplicar o plano de instalacao e configuracao acima? [Y/n]: ' >&2
    IFS= read -r confirm_start || confirm_start="n"
    case "${confirm_start}" in
      "" | y | Y | yes | YES | s | S | sim | SIM) ;;
      *)
        ts_info "Operacao cancelada pelo usuario antes de qualquer escrita."
        exit "${TS_EXIT_OK}"
        ;;
    esac
  fi

  # 7. Instalar pacotes APT do sistema via helper administrativo (quando nao omitido)
  ts_handle_system_packages "${TS_REPO_ROOT}"

  # Revalidar disponibilidade de jq apos etapa de pacotes do sistema (Decisao P3)
  if ! command -v jq >/dev/null 2>&1; then
    ts_die "${TS_EXIT_ERR}" "O comando 'jq' e obrigatorio para prosseguir com locks e manifesto JSON, mas nao foi encontrado no PATH."
  fi

  # 8. Inicializar estado XDG efetivo (umask 077, lock e manifesto JSON via jq)
  ts_prepare_effective_state
  ts_manifest_init

  # 9. Instalar ferramentas externas do usuario (Starship / Superfile) em ~/.local/bin
  # (Apenas se selecionadas; quando --skip-system-packages e usado apenas para dotfiles
  # ou quando TS_SKIP_EXTERNAL_DOWNLOADS=true em testes de config pura, respeita a selecao)
  if [[ "${TS_SKIP_EXTERNAL_DOWNLOADS:-false}" != "true" ]]; then
    ts_install_selected_external_tools "${TS_REPO_ROOT}"
    ts_install_selected_zsh_plugins "${TS_REPO_ROOT}"
  fi

  # 10. Aplicar configuracoes de usuario (Zsh, Starship, tmux e links controlados)
  ts_apply_user_configurations "${TS_REPO_ROOT}"

  # 11. Aplicar configuracao opcional de Git (respeitando --git-identity, --git-defaults e --skip-git)
  ts_apply_git_configuration

  # 12. Troca opcional do shell de login (somente interativo e com consentimento especifico)
  if [[ "${TS_OPT_CHANGE_SHELL}" == "yes" ]]; then
    if [[ "${TS_OPT_NON_INTERACTIVE}" == "true" ]] || [[ ! -t 0 ]]; then
      ts_die_usage "--change-shell yes exige ambiente interativo."
    fi
    local zsh_bin=""
    zsh_bin="$(command -v zsh 2>/dev/null || printf '/usr/bin/zsh')"
    local confirm_chsh=""
    printf '\n[SHELL] Confirma a alteracao do seu shell de login padrao para "%s" via chsh? [y/N]: ' "${zsh_bin}" >&2
    IFS= read -r confirm_chsh || confirm_chsh="n"
    case "${confirm_chsh}" in
      y | Y | yes | YES | s | S | sim | SIM)
        if command -v chsh >/dev/null 2>&1; then
          chsh -s "${zsh_bin}"
          ts_log_event "INFO" "Shell de login alterado via chsh para ${zsh_bin}"
        else
          ts_warn "Comando 'chsh' nao disponivel no sistema; altere o shell manualmente."
        fi
        ;;
      *)
        ts_info "Troca de shell de login cancelada pelo usuario."
        ;;
    esac
  fi

  # 13. Finalizar manifesto como completed
  ts_manifest_finalize "completed"
  TS_INSTALL_COMPLETED="true"

  ts_ok "Instalacao e configuracao do usuario concluidas (install_id: ${TS_INSTALL_ID})."
  ts_info "Manifesto registrado em: ${TS_CURRENT_MANIFEST_FILE}"
}

main "$@"
