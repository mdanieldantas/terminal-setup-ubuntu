#!/usr/bin/env bash
# ==============================================================================
# lib/manifest.sh — Criacao, atualizacao e validacao de manifestos JSON via jq
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# Regra (Decisao P3 e Secao 8):
#   - Usar exclusivamente 'jq' para leitura e geracao de JSON.
#   - Extracao de campos usa delimitador NUL (\u0000) com flags explicitas de
#     presenca ("1" vs "0"), preservando sem ambiguidade a distincao entre
#     campo ausente (null), string vazia ("") e qualquer valor literal
#     (inclusive "__NULL__").
#   - Nunca armazenar nome Git, e-mail Git, senhas ou tokens no manifesto.
#   - Validar propriedade, schema e ausencia de traversal antes de restaurar.
# ==============================================================================

if [[ -n "${TS_MANIFEST_LOADED:-}" ]]; then
  return 0
fi
readonly TS_MANIFEST_LOADED=1

readonly TS_MANIFEST_SCHEMA_VERSION=1
TS_PRIOR_MANIFEST_FILE=""

# Verifica se jq esta disponivel antes de operacoes de manifesto
ts_require_jq_for_json() {
  if ! command -v jq >/dev/null 2>&1; then
    ts_die "${TS_EXIT_ERR}" \
      "O utilitario 'jq' e obrigatorio para manipular manifestos, locks e saidas JSON, mas nao esta instalado no PATH."
  fi
}

# Inicializa um novo arquivo de manifesto JSON com umask 077
ts_manifest_init() {
  ts_require_jq_for_json

  if [[ -z "${TS_CURRENT_MANIFEST_FILE:-}" ]]; then
    ts_die "${TS_EXIT_ERR}" "ts_manifest_init chamado antes de ts_prepare_effective_state."
  fi

  TS_PRIOR_MANIFEST_FILE=""
  local prior_candidate=""
  if prior_candidate="$(ts_find_manifest_file "" 2>/dev/null)" && [[ "${prior_candidate}" != "${TS_CURRENT_MANIFEST_FILE}" ]]; then
    TS_PRIOR_MANIFEST_FILE="${prior_candidate}"
  fi

  local ts_utc zdotdir_effective
  ts_utc="$(date -u '+%Y-%m-%dT%H%M%SZ')"
  zdotdir_effective="${HOME}"
  if [[ "${TS_ZDOTDIR_STATUS}" == "custom" ]] && [[ -n "${TS_ZDOTDIR_VALUE}" ]]; then
    zdotdir_effective="${TS_ZDOTDIR_VALUE}"
  fi

  local old_umask
  old_umask="$(umask)"
  umask 077

  local tmp_manifest
  tmp_manifest="$(mktemp "${TS_MANIFESTS_DIR}/.manifest-tmp.XXXXXX")"

  jq -n \
    --argjson schema_version "${TS_MANIFEST_SCHEMA_VERSION}" \
    --arg project "${TS_PROJECT_NAME}" \
    --arg project_version "${TS_PROJECT_VERSION}" \
    --arg install_id "${TS_INSTALL_ID}" \
    --arg timestamp_utc "${ts_utc}" \
    --arg status "in_progress" \
    --arg profile "${TS_OPT_PROFILE}" \
    --arg icons "${TS_OPT_ICONS}" \
    --argjson vi_mode "${TS_OPT_VI_MODE}" \
    --arg on_conflict "${TS_OPT_ON_CONFLICT}" \
    --arg git_identity_policy "${TS_OPT_GIT_IDENTITY}" \
    --arg git_defaults_policy "${TS_OPT_GIT_DEFAULTS}" \
    --arg user "${TS_EFFECTIVE_USER}" \
    --argjson uid "${TS_EFFECTIVE_UID}" \
    --arg home "${HOME}" \
    --arg xdg_config_home "${TS_XDG_CONFIG_HOME}" \
    --arg xdg_state_home "${TS_XDG_STATE_HOME}" \
    --arg xdg_data_home "${TS_XDG_DATA_HOME}" \
    --arg zdotdir "${zdotdir_effective}" \
    '{
      schema_version: $schema_version,
      project: $project,
      project_version: $project_version,
      install_id: $install_id,
      timestamp_utc: $timestamp_utc,
      completed_at_utc: null,
      status: $status,
      profile: $profile,
      icons: $icons,
      vi_mode: $vi_mode,
      on_conflict: $on_conflict,
      git_identity_policy: $git_identity_policy,
      git_defaults_policy: $git_defaults_policy,
      user: $user,
      uid: $uid,
      home: $home,
      xdg_config_home: $xdg_config_home,
      xdg_state_home: $xdg_state_home,
      xdg_data_home: $xdg_data_home,
      zdotdir: $zdotdir,
      entries: []
    }' > "${tmp_manifest}"

  chmod 600 "${tmp_manifest}" 2>/dev/null || true
  mv -Tf -- "${tmp_manifest}" "${TS_CURRENT_MANIFEST_FILE}"
  umask "${old_umask}"
}

# Registra uma operacao de arquivo, symlink ou repositorio de plugin no manifesto atual via jq
ts_manifest_record_entry() {
  local path="$1"
  local resource_type="$2"
  local previous_state="$3"
  local previous_checksum="$4"
  local previous_symlink_target="$5"
  local backup_path="$6"
  local installed_checksum="$7"
  local installed_symlink_target="$8"
  local action="$9"
  local installed_version="${10:-}"

  ts_require_jq_for_json

  local old_umask
  old_umask="$(umask)"
  umask 077

  local tmp_manifest
  tmp_manifest="$(mktemp "${TS_MANIFESTS_DIR}/.manifest-tmp.XXXXXX")"

  local -a prior_arg=()
  if [[ "${action}" == "unchanged" ]] && [[ -n "${TS_PRIOR_MANIFEST_FILE:-}" ]] && [[ -f "${TS_PRIOR_MANIFEST_FILE}" ]]; then
    prior_arg=(--slurpfile prior "${TS_PRIOR_MANIFEST_FILE}")
  else
    prior_arg=(--argjson prior '[]')
  fi

  jq \
    "${prior_arg[@]}" \
    --arg path "${path}" \
    --arg resource_type "${resource_type}" \
    --arg previous_state "${previous_state}" \
    --arg previous_checksum "${previous_checksum}" \
    --arg previous_symlink_target "${previous_symlink_target}" \
    --arg backup_path "${backup_path}" \
    --arg installed_checksum "${installed_checksum}" \
    --arg installed_symlink_target "${installed_symlink_target}" \
    --arg action "${action}" \
    --arg installed_version "${installed_version}" \
    '(if $action == "unchanged" and ($prior | length > 0) then
        (($prior[0].entries // []) | map(select(.path == $path and (.action == "created" or .action == "replaced" or .action == "unchanged"))) | last)
      else
        null
      end) as $inherited |
    .entries += [{
      path: $path,
      resource_type: $resource_type,
      previous_state: (if $inherited != null then $inherited.previous_state else $previous_state end),
      previous_checksum: (if $inherited != null then $inherited.previous_checksum elif $previous_checksum == "" then null else $previous_checksum end),
      previous_symlink_target: (if $inherited != null then $inherited.previous_symlink_target elif $previous_symlink_target == "" then null else $previous_symlink_target end),
      backup_path: (if $inherited != null then $inherited.backup_path elif $backup_path == "" then null else $backup_path end),
      installed_checksum: (if $installed_checksum == "" then null else $installed_checksum end),
      installed_symlink_target: (if $installed_symlink_target == "" then null else $installed_symlink_target end),
      installed_version: (if $installed_version == "" then null else $installed_version end),
      action: $action
    }]' "${TS_CURRENT_MANIFEST_FILE}" > "${tmp_manifest}"

  chmod 600 "${tmp_manifest}" 2>/dev/null || true
  mv -Tf -- "${tmp_manifest}" "${TS_CURRENT_MANIFEST_FILE}"
  umask "${old_umask}"
}

# Finaliza o status do manifesto ("completed" ou "failed")
ts_manifest_finalize() {
  local final_status="$1"
  if [[ -z "${TS_CURRENT_MANIFEST_FILE:-}" ]] || [[ ! -f "${TS_CURRENT_MANIFEST_FILE}" ]]; then
    return 0
  fi
  ts_require_jq_for_json

  local ts_utc old_umask tmp_manifest
  ts_utc="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  old_umask="$(umask)"
  umask 077

  tmp_manifest="$(mktemp "${TS_MANIFESTS_DIR}/.manifest-tmp.XXXXXX")"
  jq \
    --arg status "${final_status}" \
    --arg completed_at "${ts_utc}" \
    '.status = $status | .completed_at_utc = $completed_at' \
    "${TS_CURRENT_MANIFEST_FILE}" > "${tmp_manifest}"

  chmod 600 "${tmp_manifest}" 2>/dev/null || true
  mv -Tf -- "${tmp_manifest}" "${TS_CURRENT_MANIFEST_FILE}"
  umask "${old_umask}"
  ts_log_event "INFO" "Manifesto finalizado: status=${final_status} manifest=${TS_CURRENT_MANIFEST_FILE}"
}

# Localiza o manifesto mais recente (ou um install_id especifico) sem modificar nada
ts_find_manifest_file() {
  local requested_id="${1:-}"
  ts_init_state_paths

  if [[ -n "${requested_id}" ]]; then
    if [[ ! "${requested_id}" =~ ^[A-Za-z0-9._-]+$ ]] || [[ "${requested_id}" == *".."* ]]; then
      return 1
    fi
    local candidate="${TS_MANIFESTS_DIR}/${requested_id}.json"
    if [[ -f "${candidate}" ]] && [[ ! -L "${candidate}" ]]; then
      printf '%s' "${candidate}"
      return 0
    fi
    return 1
  fi

  if [[ ! -d "${TS_MANIFESTS_DIR}" ]]; then
    return 1
  fi

  local latest=""
  local f
  for f in "${TS_MANIFESTS_DIR}"/*.json; do
    [[ -e "${f}" ]] || continue
    [[ -L "${f}" ]] && continue
    [[ -f "${f}" ]] || continue
    latest="${f}"
  done

  if [[ -z "${latest}" ]]; then
    return 1
  fi
  printf '%s' "${latest}"
  return 0
}

# Emite as entradas de um manifesto como stream delimitado por NUL (\0), sem
# usar sentinelas magicas como "__NULL__". Cada entrada produz 14 tokens NUL-terminated:
#   1. path
#   2. resource_type
#   3. previous_state
#   4. has_previous_checksum ("1" ou "0")
#   5. previous_checksum
#   6. has_previous_symlink_target ("1" ou "0")
#   7. previous_symlink_target
#   8. has_backup_path ("1" ou "0")
#   9. backup_path
#  10. has_installed_checksum ("1" ou "0")
#  11. installed_checksum
#  12. has_installed_symlink_target ("1" ou "0")
#  13. installed_symlink_target
#  14. action
ts_manifest_stream_entries_nul() {
  local manifest_file="$1"
  local reverse_order="${2:-false}"

  local iter_expr=".entries[]"
  if [[ "${reverse_order}" == "true" ]]; then
    iter_expr=".entries | reverse[]"
  fi

  jq -j "${iter_expr} | [
    .path,
    .resource_type,
    .previous_state,
    (if .previous_checksum == null then \"0\" else \"1\" end),
    (.previous_checksum // \"\"),
    (if .previous_symlink_target == null then \"0\" else \"1\" end),
    (.previous_symlink_target // \"\"),
    (if .backup_path == null then \"0\" else \"1\" end),
    (.backup_path // \"\"),
    (if .installed_checksum == null then \"0\" else \"1\" end),
    (.installed_checksum // \"\"),
    (if .installed_symlink_target == null then \"0\" else \"1\" end),
    (.installed_symlink_target // \"\"),
    .action
  ][] | ., \"\u0000\"" "${manifest_file}"
}

# Le uma entrada completa (14 campos NUL-terminated) produzida por ts_manifest_stream_entries_nul
# Define variaveis globais TS_ME_* para o chamador
ts_manifest_read_entry_nul() {
  IFS= read -r -d '' TS_ME_PATH || return 1
  IFS= read -r -d '' TS_ME_RESOURCE_TYPE || return 1
  IFS= read -r -d '' TS_ME_PREV_STATE || return 1
  IFS= read -r -d '' TS_ME_HAS_PREV_SHA || return 1
  IFS= read -r -d '' TS_ME_PREV_SHA || return 1
  IFS= read -r -d '' TS_ME_HAS_PREV_LINK || return 1
  IFS= read -r -d '' TS_ME_PREV_LINK || return 1
  IFS= read -r -d '' TS_ME_HAS_BACKUP_PATH || return 1
  IFS= read -r -d '' TS_ME_BACKUP_PATH || return 1
  IFS= read -r -d '' TS_ME_HAS_INST_SHA || return 1
  IFS= read -r -d '' TS_ME_INST_SHA || return 1
  IFS= read -r -d '' TS_ME_HAS_INST_LINK || return 1
  IFS= read -r -d '' TS_ME_INST_LINK || return 1
  IFS= read -r -d '' TS_ME_ACTION || return 1
  return 0
}

# Valida estrutura, schema, propriedade e caminhos de um manifesto antes de confiar nele
ts_validate_manifest_file() {
  local manifest_file="$1"
  ts_require_jq_for_json

  if [[ -z "${manifest_file}" ]] || [[ -L "${manifest_file}" ]] || [[ ! -f "${manifest_file}" ]] || [[ ! -r "${manifest_file}" ]]; then
    ts_error "Arquivo de manifesto ausente, ilegivel ou e um symlink: '${manifest_file}'."
    return 1
  fi

  local file_uid
  file_uid="$(stat -c '%u' "${manifest_file}" 2>/dev/null || printf '')"
  if [[ -n "${file_uid}" ]] && [[ "${file_uid}" != "${TS_EFFECTIVE_UID}" ]]; then
    ts_error "O manifesto '${manifest_file}' pertence ao UID ${file_uid}, diferente do usuario atual (${TS_EFFECTIVE_UID})."
    return 1
  fi

  if ! jq -e '
    type == "object" and
    .schema_version == 1 and
    .project == "terminal-setup" and
    (.install_id | type == "string" and length > 0) and
    (.uid | type == "number") and
    (.home | type == "string" and startswith("/")) and
    (.entries | type == "array") and
    all(.entries[];
      type == "object" and
      (.path | type == "string" and length > 0) and
      (.resource_type == "file" or .resource_type == "symlink" or .resource_type == "git_repo") and
      (.previous_state == "absent" or .previous_state == "file" or .previous_state == "symlink" or .previous_state == "git_repo") and
      (.previous_checksum == null or (.previous_checksum | type == "string")) and
      (.previous_symlink_target == null or (.previous_symlink_target | type == "string")) and
      (.backup_path == null or (.backup_path | type == "string")) and
      (.installed_checksum == null or (.installed_checksum | type == "string")) and
      (.installed_symlink_target == null or (.installed_symlink_target | type == "string")) and
      (.action == "created" or .action == "replaced" or .action == "unchanged" or .action == "kept_existing")
    )
  ' "${manifest_file}" >/dev/null 2>&1; then
    ts_error "Manifesto '${manifest_file}' possui JSON malformado ou schema invalido."
    return 1
  fi

  while ts_manifest_read_entry_nul; do
    if ! ts_validate_managed_path "${TS_ME_PATH}" "false"; then
      ts_error "Manifesto '${manifest_file}' contem caminho nao permitido ou com tentativa de path traversal: '${TS_ME_PATH}'."
      return 1
    fi
    if [[ "${TS_ME_HAS_BACKUP_PATH}" == "1" ]]; then
      if [[ -z "${TS_ME_BACKUP_PATH}" ]] || ! ts_validate_managed_path "${TS_ME_BACKUP_PATH}" "true"; then
        ts_error "Manifesto '${manifest_file}' contem caminho de backup fora da arvore de estado permitida: '${TS_ME_BACKUP_PATH}'."
        return 1
      fi
    fi
  done < <(ts_manifest_stream_entries_nul "${manifest_file}" "false")

  return 0
}
