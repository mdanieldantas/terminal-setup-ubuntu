#!/usr/bin/env bash
# ==============================================================================
# uninstall-terminal.sh — Desinstalacao e restauracao segura baseada em manifesto
# Plataforma alvo da v1: Ubuntu 24.04 LTS (amd64)
#
# Regras fundamentais (Secoes 7.3, 8 e 13 do guia):
#   - Opera exclusivamente sobre recursos registrados no manifesto validado e
#     dentro dos diretorios permitidos do usuario.
#   - NAO remove pacotes APT na v1.
#   - Preserva qualquer arquivo modificado pelo usuario apos a instalacao
#     (--on-modified keep), informando o conflito.
#   - Preserva os arquivos de backup por padrao e permite executar a restauracao
#     duas vezes seguidas sem danos (idempotencia de restauracao).
#   - Nao apaga diretorios se houver qualquer arquivo desconhecido ou preservado.
# ==============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  printf '[ERRO] Este script nao deve ser carregado com "source". Execute: bash ./uninstall-terminal.sh [opcoes]\n' >&2
  # shellcheck disable=SC2317 # fallback caso return falhe fora de contexto source
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
  cd -P "$(dirname "${source_path}")" >/dev/null 2>&1 && pwd
}

TS_REPO_ROOT="$(ts_resolve_repo_root)"
readonly TS_REPO_ROOT

# shellcheck source=lib/common.sh
source "${TS_REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/platform.sh
source "${TS_REPO_ROOT}/lib/platform.sh"
# shellcheck source=lib/backups.sh
source "${TS_REPO_ROOT}/lib/backups.sh"
# shellcheck source=lib/manifest.sh
source "${TS_REPO_ROOT}/lib/manifest.sh"

UNINSTALL_DRY_RUN="false"
UNINSTALL_NON_INTERACTIVE="false"
UNINSTALL_RESTORE_ID=""
UNINSTALL_ON_MODIFIED="keep"

uninstall_print_help() {
  cat <<'EOF'
Uso:
  bash ./uninstall-terminal.sh [opcoes]

Descricao:
  Remove configuracoes gerenciadas pelo terminal-setup ou restaura backups
  registrados em um manifesto de instalacao especifico.
  Nao remove pacotes APT e nao remove arquivos desconhecidos ou editados
  pelo usuario apos a instalacao.

Opcoes:
  -h, --help                     Exibe esta ajuda sem realizar alteracoes.
  --dry-run                      Apenas exibe as acoes de restauracao/remocao
                                 previstas, sem alterar arquivos e sem criar logs.
  --non-interactive              Nao solicita confirmacao interativa antes de
                                 aplicar a restauracao/remocao.
  --restore <INSTALL_ID>         Utiliza o manifesto especifico <INSTALL_ID>
                                 (padrao: manifesto mais recente).
  --on-modified <keep>           Politica para arquivos modificados apos a
                                 instalacao (na v1 suporta apenas 'keep').
EOF
}

uninstall_parse_args() {
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
        --restore)
          UNINSTALL_RESTORE_ID="${opt_val}"
          ;;
        --on-modified)
          UNINSTALL_ON_MODIFIED="${opt_val}"
          ;;
        --help | --dry-run | --non-interactive)
          ts_die_usage "O parametro '${opt_name}' nao aceita valor ('${arg}')."
          ;;
        *)
          ts_die_usage "Parametro desconhecido em uninstall-terminal.sh: '${opt_name}'."
          ;;
      esac
      shift
      continue
    fi

    case "${arg}" in
      -h | --help)
        uninstall_print_help
        exit "${TS_EXIT_OK}"
        ;;
      --dry-run)
        UNINSTALL_DRY_RUN="true"
        shift
        ;;
      --non-interactive)
        UNINSTALL_NON_INTERACTIVE="true"
        shift
        ;;
      --restore)
        if [[ $# -lt 2 ]] || [[ -z "${2:-}" ]]; then
          ts_die_usage "O parametro '--restore' exige um INSTALL_ID nao vazio."
        fi
        UNINSTALL_RESTORE_ID="$2"
        shift 2
        ;;
      --on-modified)
        if [[ $# -lt 2 ]] || [[ -z "${2:-}" ]]; then
          ts_die_usage "O parametro '--on-modified' exige o valor 'keep'."
        fi
        UNINSTALL_ON_MODIFIED="$2"
        shift 2
        ;;
      -*)
        ts_die_usage "Parametro desconhecido em uninstall-terminal.sh: '${arg}'."
        ;;
      *)
        ts_die_usage "Argumento posicional inesperado em uninstall-terminal.sh: '${arg}'."
        ;;
    esac
  done

  if [[ "${UNINSTALL_ON_MODIFIED}" != "keep" ]]; then
    ts_die_usage "Valor invalido para --on-modified: '${UNINSTALL_ON_MODIFIED}'. Na v1 apenas 'keep' e permitido."
  fi
}

# shellcheck disable=SC2317 # funcao invocada indiretamente via trap EXIT
cleanup_uninstall_lock() {
  local exit_code=$?
  ts_release_execution_lock
  exit "${exit_code}"
}
trap 'cleanup_uninstall_lock' EXIT

# Verifica se uma entrada ja se encontra no seu estado anterior esperado (idempotencia)
ts_entry_is_already_restored() {
  local path="$1"
  local prev_state="$2"
  local has_prev_sha="$3"
  local prev_sha="$4"
  local has_prev_link="$5"
  local prev_link="$6"

  local cur_state
  cur_state="$(ts_path_state "${path}")"
  if [[ "${prev_state}" == "git_repo" ]]; then
    if [[ ! -L "${path}" ]] && [[ -d "${path}/.git" ]] && command -v git >/dev/null 2>&1; then
      local cur_head
      cur_head="$(git -C "${path}" rev-parse HEAD 2>/dev/null || true)"
      [[ "${has_prev_sha}" == "1" ]] && [[ "${cur_head}" == "${prev_sha}" ]]
      return $?
    fi
    return 1
  fi

  if [[ "${cur_state}" != "${prev_state}" ]]; then
    return 1
  fi

  case "${prev_state}" in
    absent)
      return 0
      ;;
    file)
      local cur_sha
      cur_sha="$(ts_sha256_file "${path}" 2>/dev/null || true)"
      [[ "${has_prev_sha}" == "1" ]] && [[ -n "${cur_sha}" ]] && [[ "${cur_sha}" == "${prev_sha}" ]]
      return $?
      ;;
    symlink)
      local cur_link
      cur_link="$(readlink "${path}" 2>/dev/null || true)"
      [[ "${has_prev_link}" == "1" ]] && [[ "${cur_link}" == "${prev_link}" ]]
      return $?
      ;;
    *)
      return 1
      ;;
  esac
}

# Verifica se o recurso atual permanece identico ao que foi instalado pelo manifesto
ts_entry_matches_installed_state() {
  local path="$1"
  local res_type="$2"
  local has_inst_sha="$3"
  local inst_sha="$4"
  local has_inst_link="$5"
  local inst_link="$6"

  local cur_state
  cur_state="$(ts_path_state "${path}")"
  if [[ "${res_type}" == "file" ]]; then
    if [[ "${cur_state}" != "file" ]]; then
      return 1
    fi
    local cur_sha
    cur_sha="$(ts_sha256_file "${path}" 2>/dev/null || true)"
    [[ "${has_inst_sha}" == "1" ]] && [[ -n "${cur_sha}" ]] && [[ "${cur_sha}" == "${inst_sha}" ]]
    return $?
  elif [[ "${res_type}" == "symlink" ]]; then
    if [[ "${cur_state}" != "symlink" ]]; then
      return 1
    fi
    local cur_link
    cur_link="$(readlink "${path}" 2>/dev/null || true)"
    [[ "${has_inst_link}" == "1" ]] && [[ "${cur_link}" == "${inst_link}" ]]
    return $?
  elif [[ "${res_type}" == "git_repo" ]]; then
    if [[ -L "${path}" ]] || [[ ! -d "${path}/.git" ]] || ! command -v git >/dev/null 2>&1; then
      return 1
    fi
    local cur_head dirty_status
    cur_head="$(git -C "${path}" rev-parse HEAD 2>/dev/null || true)"
    dirty_status="$(git -C "${path}" status --porcelain 2>/dev/null || printf 'dirty')"
    [[ "${has_inst_sha}" == "1" ]] && [[ "${cur_head}" == "${inst_sha}" ]] && [[ -z "${dirty_status}" ]]
    return $?
  fi
  return 1
}

# Restaura um arquivo ou symlink a partir do backup validado sem seguir symlinks no destino
ts_restore_from_backup() {
  local has_backup="$1"
  local backup_path="$2"
  local dest_path="$3"
  local prev_state="$4"
  local has_prev_sha="$5"
  local prev_sha="$6"
  local has_prev_link="$7"
  local prev_link="$8"

  if [[ "${has_backup}" != "1" ]] || [[ -z "${backup_path}" ]]; then
    ts_error "Caminho de backup ausente no manifesto para restaurar '${dest_path}'."
    return 1
  fi

  local bkp_state
  bkp_state="$(ts_path_state "${backup_path}")"
  if [[ "${bkp_state}" != "${prev_state}" ]]; then
    ts_error "O backup '${backup_path}' tem tipo '${bkp_state}', mas o manifesto esperava '${prev_state}'."
    return 1
  fi

  if [[ "${prev_state}" == "file" ]]; then
    local bkp_sha
    bkp_sha="$(ts_sha256_file "${backup_path}" 2>/dev/null || true)"
    if [[ "${has_prev_sha}" != "1" ]] || [[ -z "${bkp_sha}" ]] || [[ "${bkp_sha}" != "${prev_sha}" ]]; then
      ts_error "Integridade do backup '${backup_path}' falhou (SHA-256 diferente do registrado no manifesto)."
      return 1
    fi
    ts_atomic_write_from_file "${backup_path}" "${dest_path}" "0600"
  elif [[ "${prev_state}" == "symlink" ]]; then
    local bkp_link
    bkp_link="$(readlink "${backup_path}" 2>/dev/null || true)"
    if [[ "${has_prev_link}" != "1" ]] || [[ "${bkp_link}" != "${prev_link}" ]]; then
      ts_error "Alvo do symlink de backup '${backup_path}' ('${bkp_link}') difere do manifesto ('${prev_link}')."
      return 1
    fi
    mkdir -p "${dest_path%/*}"
    rm -f -- "${dest_path}"
    ln -s "${bkp_link}" "${dest_path}"
  fi
  return 0
}

main() {
  uninstall_parse_args "$@"

  ts_require_non_root
  ts_detect_platform
  ts_init_state_paths
  ts_require_jq_for_json

  local manifest_file=""
  if ! manifest_file="$(ts_find_manifest_file "${UNINSTALL_RESTORE_ID}")"; then
    if [[ -n "${UNINSTALL_RESTORE_ID}" ]]; then
      ts_die "${TS_EXIT_ERR}" "Manifesto para INSTALL_ID '${UNINSTALL_RESTORE_ID}' nao encontrado em '${TS_MANIFESTS_DIR}'."
    else
      ts_die "${TS_EXIT_ERR}" "Nenhum manifesto de instalacao encontrado em '${TS_MANIFESTS_DIR}'."
    fi
  fi

  # Validar estrutura, propriedade e ausencia de path traversal no manifesto antes de confiar nele
  if ! ts_validate_manifest_file "${manifest_file}"; then
    ts_die "${TS_EXIT_ERR}" "Recusando prosseguir: o manifesto '${manifest_file}' e invalido ou inseguro."
  fi

  local manifest_id
  manifest_id="$(jq -r '.install_id' "${manifest_file}")"

  printf '%s======================================================================%s\n' "${TS_COLOR_BOLD}" "${TS_COLOR_RESET}"
  printf '%sDesinstalacao / Restauracao — %s (manifesto: %s)%s\n' \
    "${TS_COLOR_BOLD}" "${TS_PROJECT_NAME}" "${manifest_id}" "${TS_COLOR_RESET}"
  printf '%s======================================================================%s\n' "${TS_COLOR_BOLD}" "${TS_COLOR_RESET}"

  # Orientar caso o shell padrao do usuario seja Zsh (Secao 13: nao remove Zsh nem altera shell)
  if [[ -r /etc/passwd ]]; then
    local current_login_shell
    current_login_shell="$(awk -F: -v u="${TS_EFFECTIVE_USER}" '$1 == u {print $7; exit}' /etc/passwd 2>/dev/null || true)"
    if [[ "${current_login_shell}" == *"zsh"* ]]; then
      ts_info "Nota: seu shell de login registrado e '${current_login_shell}'. Este script NAO remove o pacote Zsh nem altera seu shell de login."
    fi
  fi

  if [[ "${UNINSTALL_DRY_RUN}" != "true" ]]; then
    if [[ "${UNINSTALL_NON_INTERACTIVE}" != "true" ]]; then
      if [[ ! -t 0 ]]; then
        ts_die_usage "Stdin nao interativo detectado sem --non-interactive. Informe --non-interactive para confirmar a restauracao."
      fi
      local ans=""
      printf 'Deseja restaurar/remover os recursos gerenciados pelo manifesto "%s"? [y/N]: ' "${manifest_id}" >&2
      IFS= read -r ans || ans="n"
      case "${ans}" in
        y | Y | yes | YES | s | S | sim | SIM) ;;
        *)
          ts_info "Operacao cancelada pelo usuario."
          exit "${TS_EXIT_OK}"
          ;;
      esac
    fi
    ts_acquire_execution_lock
  fi

  local restored_count=0
  local removed_count=0
  local already_count=0
  local preserved_count=0
  local skipped_count=0
  local error_count=0

  # Processar entradas do manifesto em ordem reversa via stream NUL-delimited (sem sentinelas magicas)
  while ts_manifest_read_entry_nul; do
    if [[ "${TS_ME_ACTION}" == "kept_existing" ]]; then
      skipped_count=$((skipped_count + 1))
      printf '  [IGNORADO]   %s (foi mantido sem alteracao na instalacao)\n' "${TS_ME_PATH}"
      continue
    fi

    # 1. Verificar se ja esta no estado anterior (permite rodar duas vezes sem danos)
    if ts_entry_is_already_restored \
      "${TS_ME_PATH}" \
      "${TS_ME_PREV_STATE}" \
      "${TS_ME_HAS_PREV_SHA}" \
      "${TS_ME_PREV_SHA}" \
      "${TS_ME_HAS_PREV_LINK}" \
      "${TS_ME_PREV_LINK}"; then
      already_count=$((already_count + 1))
      printf '  [JA RESTAURADO] %s (estado atual ja corresponde ao estado pre-instalacao: %s)\n' "${TS_ME_PATH}" "${TS_ME_PREV_STATE}"
      continue
    fi

    # 2. Verificar se o recurso foi modificado pelo usuario apos a instalacao
    if ! ts_entry_matches_installed_state \
      "${TS_ME_PATH}" \
      "${TS_ME_RESOURCE_TYPE}" \
      "${TS_ME_HAS_INST_SHA}" \
      "${TS_ME_INST_SHA}" \
      "${TS_ME_HAS_INST_LINK}" \
      "${TS_ME_INST_LINK}"; then
      preserved_count=$((preserved_count + 1))
      ts_warn "Conflito de modificacao pos-instalacao em '${TS_ME_PATH}': o recurso atual difere do instalado pelo projeto e foi PRESERVADO (--on-modified=${UNINSTALL_ON_MODIFIED})."
      continue
    fi

    # 3. O recurso corresponde exatamente ao instalado: remover (se prev_state=absent) ou restaurar backup
    if [[ "${TS_ME_PREV_STATE}" == "absent" ]]; then
      if [[ "${UNINSTALL_DRY_RUN}" == "true" ]]; then
        printf '  [DRY-RUN REMOVER] %s (nao existia antes da instalacao)\n' "${TS_ME_PATH}"
      else
        if [[ "${TS_ME_RESOURCE_TYPE}" == "git_repo" ]]; then
          rm -rf -- "${TS_ME_PATH}"
        else
          rm -f -- "${TS_ME_PATH}"
        fi
        printf '  [REMOVIDO]   %s\n' "${TS_ME_PATH}"
      fi
      removed_count=$((removed_count + 1))
    else
      if [[ "${UNINSTALL_DRY_RUN}" == "true" ]]; then
        printf '  [DRY-RUN RESTAURAR] %s <- %s (%s)\n' "${TS_ME_PATH}" "${TS_ME_BACKUP_PATH}" "${TS_ME_PREV_STATE}"
        restored_count=$((restored_count + 1))
      else
        if ts_restore_from_backup \
          "${TS_ME_HAS_BACKUP_PATH}" \
          "${TS_ME_BACKUP_PATH}" \
          "${TS_ME_PATH}" \
          "${TS_ME_PREV_STATE}" \
          "${TS_ME_HAS_PREV_SHA}" \
          "${TS_ME_PREV_SHA}" \
          "${TS_ME_HAS_PREV_LINK}" \
          "${TS_ME_PREV_LINK}"; then
          printf '  [RESTAURADO] %s <- %s (%s)\n' "${TS_ME_PATH}" "${TS_ME_BACKUP_PATH}" "${TS_ME_PREV_STATE}"
          restored_count=$((restored_count + 1))
        else
          error_count=$((error_count + 1))
        fi
      fi
    fi
  done < <(ts_manifest_stream_entries_nul "${manifest_file}" "true")

  # Remover diretorios vazios do projeto sem apagar diretorios com arquivos desconhecidos
  if [[ "${UNINSTALL_DRY_RUN}" != "true" ]]; then
    rmdir "${TS_DATA_ROOT}/plugins" 2>/dev/null || true
    rmdir "${TS_DATA_ROOT}/tools" 2>/dev/null || true
    rmdir "${TS_DATA_ROOT}" 2>/dev/null || true
    rmdir "${TS_CONFIG_ROOT}/zsh" 2>/dev/null || true
    rmdir "${TS_CONFIG_ROOT}" 2>/dev/null || true
  fi

  printf '\nResumo: %d removido(s), %d restaurado(s) de backup, %d ja restaurado(s), %d preservado(s) por edicao posterior, %d ignorado(s), %d erro(s).\n' \
    "${removed_count}" "${restored_count}" "${already_count}" "${preserved_count}" "${skipped_count}" "${error_count}"

  if [[ "${UNINSTALL_DRY_RUN}" == "true" ]]; then
    ts_ok "Modo --dry-run concluido: nenhum arquivo foi removido ou modificado."
  fi

  if [[ "${error_count}" -gt 0 ]]; then
    exit "${TS_EXIT_ERR}"
  fi
  exit "${TS_EXIT_OK}"
}

main "$@"
