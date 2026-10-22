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

# Trap que preserva o codigo de saida original em falhas inesperadas
ts_on_unexpected_error() {
  local exit_code=$?
  local line_no="${1:-desconhecida}"
  printf '[ERRO] Falha inesperada na linha %s (codigo de saida: %d).\n' "${line_no}" "${exit_code}" >&2
  exit "${exit_code}"
}
trap 'ts_on_unexpected_error ${LINENO}' ERR

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

  # Nota de estagio da Fase 1: as operacoes de escrita (backups, manifesto,
  # configuracao no HOME, APT e downloads) pertencem as Fases 2 e 3.
  ts_die "${TS_EXIT_NOT_IMPLEMENTED}" \
    "Estagio atual do projeto (Fase 1): validacao de contrato e planejamento concluidos, mas as rotinas de escrita e instalacao efetiva serao habilitadas nas Fases 2 e 3. Utilize --dry-run nesta etapa."
}

main "$@"

