#!/usr/bin/env bash
# ==============================================================================
# lib/backups.sh — Diretorios XDG de estado, lock, checksums, backups e escrita
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# Segue estritamente as Secoes 8, 10 e 13 do guia de implementacao.
# ==============================================================================

if [[ -n "${TS_BACKUPS_LOADED:-}" ]]; then
  return 0
fi
readonly TS_BACKUPS_LOADED=1

# Estado da sessao efetiva (preenchido somente quando NAO estiver em dry-run)
TS_INSTALL_ID=""
TS_STATE_ROOT=""
TS_CONFIG_ROOT=""
TS_DATA_ROOT=""
TS_LOGS_DIR=""
TS_BACKUPS_ROOT=""
TS_CURRENT_BACKUP_DIR=""
TS_MANIFESTS_DIR=""
TS_CURRENT_LOG_FILE=""
TS_CURRENT_MANIFEST_FILE=""
TS_LOCK_DIR=""
TS_LOCK_ACQUIRED="false"

# Gera identificador de instalacao resistente a colisao: YYYYMMDDTHHMMSSZ-PID-RAND
ts_generate_install_id() {
  local ts_utc rand_hex
  ts_utc="$(date -u '+%Y%m%dT%H%M%SZ')"
  if [[ -r /dev/urandom ]]; then
    rand_hex="$(od -An -N4 -tx1 /dev/urandom 2>/dev/null | tr -d '[:space:]')"
  fi
  if [[ -z "${rand_hex:-}" ]]; then
    rand_hex="$(printf '%04x%04x' "${RANDOM:-0}" "$$")"
  fi
  printf '%s-%s-%s' "${ts_utc}" "$$" "${rand_hex}"
}

# Inicializa os caminhos XDG em variaveis sem criar diretorios no disco
# shellcheck disable=SC2034 # TS_DATA_ROOT e demais caminhos globais sao lidos por lib/tools.sh, lib/plugins.sh e doctor.sh
ts_init_state_paths() {
  ts_validate_user_paths
  TS_CONFIG_ROOT="${TS_XDG_CONFIG_HOME}/${TS_PROJECT_NAME}"
  TS_STATE_ROOT="${TS_XDG_STATE_HOME}/${TS_PROJECT_NAME}"
  TS_DATA_ROOT="${TS_XDG_DATA_HOME}/${TS_PROJECT_NAME}"
  TS_LOGS_DIR="${TS_STATE_ROOT}/logs"
  TS_BACKUPS_ROOT="${TS_STATE_ROOT}/backups"
  TS_MANIFESTS_DIR="${TS_STATE_ROOT}/manifests"
  TS_LOCK_DIR="${TS_STATE_ROOT}/lock"
}

# Registra mensagem no arquivo de log privado da execucao efetiva
# Regra (Secao 8 e 11): NUNCA registrar e-mail Git, nome Git pessoal, senhas ou tokens.
ts_log_event() {
  local level="$1"
  shift
  if [[ -z "${TS_CURRENT_LOG_FILE:-}" ]] || [[ ! -f "${TS_CURRENT_LOG_FILE}" ]]; then
    return 0
  fi
  local ts_now
  ts_now="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  printf '%s [%s] %s\n' "${ts_now}" "${level}" "$*" >>"${TS_CURRENT_LOG_FILE}"
}

# Adquire lock de execucao concorrente (somente em execucao efetiva)
ts_acquire_execution_lock() {
  ts_init_state_paths
  local old_umask
  old_umask="$(umask)"
  umask 077
  mkdir -p "${TS_STATE_ROOT}"
  if ! mkdir "${TS_LOCK_DIR}" 2>/dev/null; then
    local lock_owner=""
    if [[ -r "${TS_LOCK_DIR}/pid" ]]; then
      lock_owner="$(cat "${TS_LOCK_DIR}/pid" 2>/dev/null || true)"
    fi
    umask "${old_umask}"
    ts_die "${TS_EXIT_ERR}" \
      "Outra execucao do ${TS_PROJECT_NAME} parece estar ativa (lock em '${TS_LOCK_DIR}', PID '${lock_owner:-desconhecido}'). Se não houver processo ativo, remova '${TS_LOCK_DIR}' manualmente."
  fi
  printf '%s\n' "$$" >"${TS_LOCK_DIR}/pid"
  TS_LOCK_ACQUIRED="true"
  umask "${old_umask}"
}

# Libera lock de execucao concorrente
ts_release_execution_lock() {
  if [[ "${TS_LOCK_ACQUIRED:-false}" == "true" ]] && [[ -n "${TS_LOCK_DIR:-}" ]] && [[ -d "${TS_LOCK_DIR}" ]]; then
    rm -f "${TS_LOCK_DIR}/pid" 2>/dev/null || true
    rmdir "${TS_LOCK_DIR}" 2>/dev/null || true
    TS_LOCK_ACQUIRED="false"
  fi
}

# Cria estrutura de estado XDG para uma execucao efetiva com umask 077
# shellcheck disable=SC2034 # TS_CURRENT_MANIFEST_FILE e consumido por lib/manifest.sh e install-terminal.sh
ts_prepare_effective_state() {
  ts_init_state_paths
  ts_acquire_execution_lock

  if [[ -z "${TS_INSTALL_ID}" ]]; then
    TS_INSTALL_ID="$(ts_generate_install_id)"
  fi

  local old_umask
  old_umask="$(umask)"
  umask 077

  mkdir -p "${TS_CONFIG_ROOT}" "${TS_LOGS_DIR}" "${TS_BACKUPS_ROOT}" "${TS_MANIFESTS_DIR}"
  TS_CURRENT_BACKUP_DIR="${TS_BACKUPS_ROOT}/${TS_INSTALL_ID}"
  TS_CURRENT_LOG_FILE="${TS_LOGS_DIR}/${TS_INSTALL_ID}.log"
  TS_CURRENT_MANIFEST_FILE="${TS_MANIFESTS_DIR}/${TS_INSTALL_ID}.json"

  : >"${TS_CURRENT_LOG_FILE}"
  chmod 600 "${TS_CURRENT_LOG_FILE}" 2>/dev/null || true

  umask "${old_umask}"
  ts_log_event "INFO" "Sessao iniciada: install_id=${TS_INSTALL_ID} profile=${TS_OPT_PROFILE} user=${TS_EFFECTIVE_USER} uid=${TS_EFFECTIVE_UID}"
}

# Verifica se um caminho e estritamente seguro, sem path traversal e dentro das raizes do usuario
# Uso: ts_validate_managed_path <caminho> [allow_state: true|false]
ts_validate_managed_path() {
  local target_path="$1"
  local allow_state="${2:-false}"

  if [[ -z "${target_path}" ]] || [[ "${target_path}" != /* ]]; then
    return 1
  fi
  if ts_has_control_chars "${target_path}"; then
    return 1
  fi
  # Rejeitar segmentos '.', '..' ou barras duplas
  case "${target_path}/" in
    *"/../"* | *"/./"* | *"//"*)
      return 1
      ;;
  esac
  if [[ "${target_path}" == "/" ]]; then
    return 1
  fi

  ts_init_state_paths

  # Verificar se o caminho pertence a uma das arvores permitidas do usuario
  local -a allowed_roots=(
    "${HOME}"
    "${TS_XDG_CONFIG_HOME}"
    "${TS_XDG_DATA_HOME}"
  )
  if [[ "${TS_ZDOTDIR_STATUS}" == "custom" ]] && [[ -n "${TS_ZDOTDIR_VALUE}" ]]; then
    allowed_roots+=("${TS_ZDOTDIR_VALUE}")
  fi
  if [[ "${allow_state}" == "true" ]]; then
    allowed_roots+=("${TS_XDG_STATE_HOME}")
  fi
  if [[ -n "${GIT_CONFIG_GLOBAL:-}" ]] && [[ "${GIT_CONFIG_GLOBAL}" == /* ]]; then
    allowed_roots+=("$(dirname "${GIT_CONFIG_GLOBAL}")")
  fi

  local matched_root=""
  local root_candidate
  for root_candidate in "${allowed_roots[@]}"; do
    root_candidate="${root_candidate%/}"
    if [[ -z "${root_candidate}" ]]; then
      continue
    fi
    if [[ "${target_path}" == "${root_candidate}/"* ]]; then
      matched_root="${root_candidate}"
      break
    fi
  done

  if [[ -z "${matched_root}" ]]; then
    return 1
  fi

  # Rejeitar se a propria raiz selecionada (ex.: HOME, ZDOTDIR, XDG_CONFIG_HOME) for um symlink
  if [[ -L "${matched_root}" ]]; then
    return 1
  fi

  # Determinar ancestral base de verificacao de symlinks:
  # - Se matched_root estiver sob HOME, verificar cada segmento a partir de HOME.
  # - Se matched_root estiver sob /tmp, verificar cada segmento a partir de /tmp.
  # - Caso contrario, verificar a partir de matched_root.
  local walk_base="${matched_root}"
  if [[ "${matched_root}" == "${HOME}/"* ]] && [[ ! -L "${HOME}" ]]; then
    walk_base="${HOME%/}"
  elif [[ "${matched_root}" == /tmp/* ]] && [[ ! -L "/tmp" ]]; then
    walk_base="/tmp"
  fi

  # Impedir que qualquer diretorio intermediario entre walk_base e dirname(target_path)
  # seja um symlink que escape para fora da arvore permitida do usuario
  local parent_dir="${target_path%/*}"
  local rel_sub="${parent_dir#"${walk_base}"}"
  rel_sub="${rel_sub#/}"
  local cur_check="${walk_base}"
  local seg
  if [[ -n "${rel_sub}" ]]; then
    local remaining="${rel_sub}"
    while [[ -n "${remaining}" ]]; do
      if [[ "${remaining}" == *"/"* ]]; then
        seg="${remaining%%/*}"
        remaining="${remaining#*/}"
      else
        seg="${remaining}"
        remaining=""
      fi
      cur_check="${cur_check}/${seg}"
      if [[ -L "${cur_check}" ]]; then
        return 1
      fi
    done
  fi

  # Quando matched_root e parent_dir ja existirem no disco, confirmar via readlink -f
  # que o caminho canonico do diretorio pai permanece dentro do caminho canonico da raiz
  if [[ -e "${matched_root}" ]] && [[ -e "${parent_dir}" ]]; then
    local canon_root canon_parent
    canon_root="$(readlink -f -- "${matched_root}" 2>/dev/null || true)"
    canon_parent="$(readlink -f -- "${parent_dir}" 2>/dev/null || true)"
    if [[ -z "${canon_root}" ]] || [[ -z "${canon_parent}" ]]; then
      return 1
    fi
    if [[ "${canon_parent}" != "${canon_root}" ]] && [[ "${canon_parent}" != "${canon_root}/"* ]]; then
      return 1
    fi
  fi

  return 0
}

# Calcula SHA-256 de um arquivo regular (nao segue symlinks por seguranca)
ts_sha256_file() {
  local filepath="$1"
  if [[ -L "${filepath}" ]] || [[ ! -f "${filepath}" ]] || [[ ! -r "${filepath}" ]]; then
    return 1
  fi
  local out
  out="$(sha256sum -- "${filepath}" 2>/dev/null)" || return 1
  printf '%s' "${out%% *}"
}

# Detecta o estado atual de um caminho sem seguir symlinks
# Saida: "absent" | "symlink" | "file" | "other"
ts_path_state() {
  local filepath="$1"
  if [[ -L "${filepath}" ]]; then
    printf 'symlink'
  elif [[ ! -e "${filepath}" ]]; then
    printf 'absent'
  elif [[ -f "${filepath}" ]]; then
    printf 'file'
  else
    printf 'other'
  fi
}

# Cria backup de um arquivo regular ou symlink dentro de TS_CURRENT_BACKUP_DIR
# Preserva symlinks como links textuais (sem seguir o alvo).
# Imprime o caminho absoluto do backup criado.
ts_create_backup_item() {
  local target_path="$1"
  if ! ts_validate_managed_path "${target_path}" "false"; then
    ts_die "${TS_EXIT_ERR}" "Tentativa de backup fora dos diretorios permitidos: '${target_path}'."
  fi

  local state
  state="$(ts_path_state "${target_path}")"
  if [[ "${state}" != "file" ]] && [[ "${state}" != "symlink" ]]; then
    ts_die "${TS_EXIT_ERR}" "Nao e possivel fazer backup de '${target_path}' (estado: ${state})."
  fi

  local rel_path="${target_path#/}"
  local backup_dest="${TS_CURRENT_BACKUP_DIR}/files/${rel_path}"
  local backup_parent="${backup_dest%/*}"

  local old_umask
  old_umask="$(umask)"
  umask 077
  mkdir -p "${backup_parent}"

  if [[ "${state}" == "symlink" ]]; then
    local link_target
    link_target="$(readlink "${target_path}")"
    rm -f "${backup_dest}"
    ln -s "${link_target}" "${backup_dest}"
  else
    cp -p -- "${target_path}" "${backup_dest}"
    chmod 600 "${backup_dest}" 2>/dev/null || true
  fi

  umask "${old_umask}"
  ts_log_event "INFO" "Backup criado: origem=${target_path} tipo=${state} destino=${backup_dest}"
  printf '%s' "${backup_dest}"
}

# Escreve um arquivo de forma atomica (temporario no mesmo diretorio + mv -Tf)
# Se o destino era um symlink, substitui o proprio symlink sem tocar no alvo do link!
ts_atomic_write_from_file() {
  local src_file="$1"
  local dest_file="$2"
  local file_mode="${3:-0644}"

  if ! ts_validate_managed_path "${dest_file}" "false"; then
    ts_die "${TS_EXIT_ERR}" "Recusando escrita fora dos diretorios permitidos do usuario: '${dest_file}'."
  fi
  if [[ ! -f "${src_file}" ]] || [[ ! -r "${src_file}" ]]; then
    ts_die "${TS_EXIT_ERR}" "Arquivo fonte de configuracao ausente ou ilegivel: '${src_file}'."
  fi

  local dest_parent="${dest_file%/*}"
  mkdir -p "${dest_parent}"

  local tmp_dest
  tmp_dest="$(mktemp "${dest_parent}/.ts-tmp.XXXXXX")"
  cp -- "${src_file}" "${tmp_dest}"
  chmod "${file_mode}" "${tmp_dest}" 2>/dev/null || true

  # Se dest_file for symlink, removemos a entrada do symlink antes do mv para garantir
  # em qualquer implementacao que o alvo do symlink jamais seja alterado.
  if [[ -L "${dest_file}" ]]; then
    rm -f -- "${dest_file}"
  fi
  mv -Tf -- "${tmp_dest}" "${dest_file}"
}

# Pergunta interativamente sobre conflito quando --on-conflict=ask
# Retorna "keep" ou "backup-replace"
ts_resolve_conflict_policy_for_path() {
  local target_path="$1"
  if [[ "${TS_OPT_ON_CONFLICT}" == "keep" ]] || [[ "${TS_OPT_ON_CONFLICT}" == "backup-replace" ]]; then
    printf '%s' "${TS_OPT_ON_CONFLICT}"
    return 0
  fi

  # Modo nao interativo nunca chega aqui com 'ask', mas protegemos por defesa em profundidade
  if [[ "${TS_OPT_NON_INTERACTIVE}" == "true" ]] || [[ ! -t 0 ]]; then
    printf 'keep'
    return 0
  fi

  # Importante (Secao 7.1): --yes NAO autoriza substituir arquivos em conflito!
  local answer=""
  printf '\n[CONFLITO] O arquivo "%s" ja existe e difere da configuracao do projeto.\n' "${target_path}" >&2
  printf 'Escolha a acao: [k] preservar atual (padrao seguro) | [b] fazer backup e substituir: ' >&2
  IFS= read -r answer || answer="k"
  case "${answer}" in
    b | B | backup | replace | backup-replace)
      printf 'backup-replace'
      ;;
    *)
      printf 'keep'
      ;;
  esac
}

# Instala/atualiza um arquivo gerenciado com idempotencia, backup e registro no manifesto
# Uso: ts_install_managed_file <src_file> <dest_file> [file_mode]
# Define TS_LAST_FILE_ACTION="created|replaced|unchanged|kept_existing"
TS_LAST_FILE_ACTION=""
ts_install_managed_file() {
  local src_file="$1"
  local dest_file="$2"
  local file_mode="${3:-0644}"

  if ! ts_validate_managed_path "${dest_file}" "false"; then
    ts_die "${TS_EXIT_ERR}" "Caminho gerenciado invalido ou fora do escopo do usuario: '${dest_file}'."
  fi

  local src_sha
  src_sha="$(ts_sha256_file "${src_file}")" || ts_die "${TS_EXIT_ERR}" "Falha ao calcular SHA-256 de '${src_file}'."

  local prev_state prev_sha="" prev_link="" backup_path="" final_sha="" action=""
  prev_state="$(ts_path_state "${dest_file}")"

  if [[ "${prev_state}" == "other" ]]; then
    ts_die "${TS_EXIT_ERR}" "O destino '${dest_file}' existe mas nao e arquivo regular nem symlink."
  fi

  if [[ "${prev_state}" == "absent" ]]; then
    ts_atomic_write_from_file "${src_file}" "${dest_file}" "${file_mode}"
    final_sha="$(ts_sha256_file "${dest_file}")"
    action="created"
    ts_log_event "INFO" "Arquivo criado: path=${dest_file} sha256=${final_sha}"
  elif [[ "${prev_state}" == "file" ]]; then
    prev_sha="$(ts_sha256_file "${dest_file}")"
    if [[ "${prev_sha}" == "${src_sha}" ]]; then
      # Idempotencia (Secao 8): segunda execucao com conteudo identico nao reescreve nem faz backup
      final_sha="${prev_sha}"
      action="unchanged"
      ts_log_event "INFO" "Arquivo inalterado (idempotente): path=${dest_file} sha256=${final_sha}"
    else
      local decision
      decision="$(ts_resolve_conflict_policy_for_path "${dest_file}")"
      if [[ "${decision}" == "backup-replace" ]]; then
        backup_path="$(ts_create_backup_item "${dest_file}")"
        ts_atomic_write_from_file "${src_file}" "${dest_file}" "${file_mode}"
        final_sha="$(ts_sha256_file "${dest_file}")"
        action="replaced"
        ts_log_event "INFO" "Arquivo substituido com backup: path=${dest_file} backup=${backup_path} sha256=${final_sha}"
      else
        final_sha="${prev_sha}"
        action="kept_existing"
        ts_log_event "INFO" "Arquivo existente preservado (keep): path=${dest_file}"
      fi
    fi
  elif [[ "${prev_state}" == "symlink" ]]; then
    prev_link="$(readlink "${dest_file}")"
    local decision
    decision="$(ts_resolve_conflict_policy_for_path "${dest_file}")"
    if [[ "${decision}" == "backup-replace" ]]; then
      backup_path="$(ts_create_backup_item "${dest_file}")"
      ts_atomic_write_from_file "${src_file}" "${dest_file}" "${file_mode}"
      final_sha="$(ts_sha256_file "${dest_file}")"
      action="replaced"
      ts_log_event "INFO" "Symlink substituido por arquivo com backup do link: path=${dest_file} target_anterior=${prev_link} backup=${backup_path}"
    else
      action="kept_existing"
      ts_log_event "INFO" "Symlink existente preservado (keep): path=${dest_file} target=${prev_link}"
    fi
  fi

  TS_LAST_FILE_ACTION="${action}"

  ts_manifest_record_entry \
    "${dest_file}" \
    "file" \
    "${prev_state}" \
    "${prev_sha}" \
    "${prev_link}" \
    "${backup_path}" \
    "${final_sha}" \
    "" \
    "${action}"
}

# Instala/atualiza um symlink gerenciado em ~/.local/bin (ex.: bat -> /usr/bin/batcat)
# Regra (Secao 6): links em ~/.local/bin so podem ser criados quando nao sobrescrevem
# arquivos ou links preexistentes de outra origem; registrar propriedade no manifesto.
ts_install_managed_symlink_if_safe() {
  local link_path="$1"
  local target_bin="$2"

  if ! ts_validate_managed_path "${link_path}" "false"; then
    ts_die "${TS_EXIT_ERR}" "Caminho de link gerenciado fora do escopo do usuario: '${link_path}'."
  fi

  local prev_state prev_sha="" prev_link="" action="" installed_link=""
  prev_state="$(ts_path_state "${link_path}")"

  if [[ "${prev_state}" == "absent" ]]; then
    mkdir -p "${link_path%/*}"
    ln -s "${target_bin}" "${link_path}"
    installed_link="${target_bin}"
    action="created"
    ts_log_event "INFO" "Symlink gerenciado criado: link=${link_path} -> ${target_bin}"
  elif [[ "${prev_state}" == "symlink" ]]; then
    prev_link="$(readlink "${link_path}")"
    if [[ "${prev_link}" == "${target_bin}" ]]; then
      installed_link="${target_bin}"
      action="unchanged"
      ts_log_event "INFO" "Symlink gerenciado inalterado (idempotente): link=${link_path} -> ${target_bin}"
    else
      action="kept_existing"
      ts_warn "Link preexistente '${link_path}' aponta para '${prev_link}' e foi preservado sem alteracao."
      ts_log_event "WARN" "Link preexistente preservado: link=${link_path} target=${prev_link}"
    fi
  else
    if [[ "${prev_state}" == "file" ]]; then
      prev_sha="$(ts_sha256_file "${link_path}" || true)"
    fi
    action="kept_existing"
    ts_warn "Caminho '${link_path}' ja existe (${prev_state}) e nao foi sobrescrito pelo link para '${target_bin}'."
    ts_log_event "WARN" "Arquivo preexistente em ~/.local/bin preservado: path=${link_path}"
  fi

  # shellcheck disable=SC2034 # TS_LAST_FILE_ACTION faz parte do contrato publico das funcoes ts_install_managed_*
  TS_LAST_FILE_ACTION="${action}"

  ts_manifest_record_entry \
    "${link_path}" \
    "symlink" \
    "${prev_state}" \
    "${prev_sha}" \
    "${prev_link}" \
    "" \
    "" \
    "${installed_link}" \
    "${action}"
}
