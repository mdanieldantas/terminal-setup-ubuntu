#!/usr/bin/env bash
# ==============================================================================
# lib/git-config.sh — Configuracao conservadora e isolada de identidade e defaults Git
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# Segue estritamente a Secao 11 do guia de implementacao:
#   - Instalar Git nao altera a identidade global sem consentimento especifico.
#   - Preservar identidade e defaults atuais ate consentimento especifico.
#   - Respeitar GIT_CONFIG_GLOBAL quando definido (e ~/.gitconfig por padrao).
#   - NUNCA registrar nome ou e-mail Git em logs, manifestos ou exemplos.
# ==============================================================================

if [[ -n "${TS_GIT_CONFIG_LOADED:-}" ]]; then
  return 0
fi
readonly TS_GIT_CONFIG_LOADED=1

# Retorna o caminho do arquivo de configuracao global do Git a ser gerenciado
ts_target_gitconfig_file() {
  if [[ -n "${GIT_CONFIG_GLOBAL:-}" ]]; then
    printf '%s' "${GIT_CONFIG_GLOBAL}"
  elif [[ -f "${TS_XDG_CONFIG_HOME}/git/config" ]] && [[ ! -f "${HOME}/.gitconfig" ]]; then
    printf '%s/git/config' "${TS_XDG_CONFIG_HOME}"
  else
    printf '%s/.gitconfig' "${HOME}"
  fi
}

# Le uma chave do arquivo de configuracao global do Git sem depender de configs do sistema
ts_git_get_global_value() {
  local gitconfig_file="$1"
  local key="$2"
  if [[ ! -f "${gitconfig_file}" ]]; then
    return 1
  fi
  git config --file "${gitconfig_file}" --get "${key}" 2>/dev/null
}

# Executa a configuracao opcional do Git com backup e registro no manifesto
ts_apply_git_configuration() {
  if [[ "${TS_OPT_SKIP_GIT}" == "true" ]]; then
    ts_log_event "INFO" "Configuracao Git ignorada (--skip-git ativo)."
    return 0
  fi

  if ! ts_list_contains "git" "${TS_SELECTED_COMPONENTS[@]}"; then
    return 0
  fi

  local gitconfig_file
  gitconfig_file="$(ts_target_gitconfig_file)"
  if ! ts_validate_managed_path "${gitconfig_file}" "false"; then
    ts_die "${TS_EXIT_ERR}" "Caminho de configuracao global do Git fora dos diretorios permitidos: '${gitconfig_file}'."
  fi

  local want_identity="false"
  local target_name="${TS_OPT_GIT_NAME:-}"
  local target_email="${TS_OPT_GIT_EMAIL:-}"
  local want_defaults="false"

  # 1. Resolver politica de identidade Git (ask | skip | configure)
  if [[ "${TS_OPT_GIT_IDENTITY}" == "configure" ]]; then
    if [[ -z "${target_name}" ]] || [[ -z "${target_email}" ]]; then
      if [[ "${TS_OPT_NON_INTERACTIVE}" == "true" ]] || [[ ! -t 0 ]]; then
        ts_die_usage "Modo nao interativo com --git-identity configure exige --git-name e --git-email."
      fi
      printf '\n[GIT] Configuracao de identidade global do Git solicitada:\n' >&2
      while [[ -z "${target_name}" ]] || ! ts_validate_git_name "${target_name}"; do
        printf '  Informe seu nome para commits Git (user.name): ' >&2
        IFS= read -r target_name || ts_die "${TS_EXIT_ERR}" "Leitura cancelada."
        target_name="$(ts_trim "${target_name}")"
      done
      while [[ -z "${target_email}" ]] || ! ts_validate_email "${target_email}"; do
        printf '  Informe seu e-mail para commits Git (user.email): ' >&2
        IFS= read -r target_email || ts_die "${TS_EXIT_ERR}" "Leitura cancelada."
        target_email="$(ts_trim "${target_email}")"
      done
    fi
    want_identity="true"
  elif [[ "${TS_OPT_GIT_IDENTITY}" == "ask" ]]; then
    # Nota (Secao 7.1): --yes NAO autoriza alterar identidade pessoal do Git!
    if [[ "${TS_OPT_NON_INTERACTIVE}" != "true" ]] && [[ -t 0 ]]; then
      local current_name current_email ans=""
      current_name="$(ts_git_get_global_value "${gitconfig_file}" "user.name" || true)"
      current_email="$(ts_git_get_global_value "${gitconfig_file}" "user.email" || true)"
      if [[ -n "${current_name}" ]] && [[ -n "${current_email}" ]]; then
        printf '\n[GIT] Uma identidade Git global ja esta configurada em "%s".\n' "${gitconfig_file}" >&2
        printf 'Deseja substitui-la por novos dados? [y/N]: ' >&2
      else
        printf '\n[GIT] Deseja configurar nome e e-mail globais do Git agora? [y/N]: ' >&2
      fi
      IFS= read -r ans || ans="n"
      case "${ans}" in
        y | Y | yes | YES | s | S | sim | SIM)
          while [[ -z "${target_name}" ]] || ! ts_validate_git_name "${target_name}"; do
            printf '  Informe seu nome para commits Git (user.name): ' >&2
            IFS= read -r target_name || ts_die "${TS_EXIT_ERR}" "Leitura cancelada."
            target_name="$(ts_trim "${target_name}")"
          done
          while [[ -z "${target_email}" ]] || ! ts_validate_email "${target_email}"; do
            printf '  Informe seu e-mail para commits Git (user.email): ' >&2
            IFS= read -r target_email || ts_die "${TS_EXIT_ERR}" "Leitura cancelada."
            target_email="$(ts_trim "${target_email}")"
          done
          want_identity="true"
          ;;
        *)
          want_identity="false"
          ;;
      esac
    fi
  fi

  # 2. Resolver politica de defaults globais do Git (ask | keep | apply)
  if [[ "${TS_OPT_GIT_DEFAULTS}" == "apply" ]]; then
    want_defaults="true"
  elif [[ "${TS_OPT_GIT_DEFAULTS}" == "ask" ]]; then
    if [[ "${TS_OPT_NON_INTERACTIVE}" != "true" ]] && [[ -t 0 ]]; then
      local ans_def=""
      printf '\n[GIT] Deseja aplicar defaults globais conservadores do Git (init.defaultBranch=main, core.editor=nano, pull.ff=only)? [y/N]: ' >&2
      IFS= read -r ans_def || ans_def="n"
      case "${ans_def}" in
        y | Y | yes | YES | s | S | sim | SIM)
          want_defaults="true"
          ;;
        *)
          want_defaults="false"
          ;;
      esac
    fi
  fi

  # Se nenhuma alteracao Git foi solicitada, preservar estado atual sem tocar no arquivo
  if [[ "${want_identity}" != "true" ]] && [[ "${want_defaults}" != "true" ]]; then
    ts_log_event "INFO" "Configuracao Git global mantida sem alteracoes (identity=${TS_OPT_GIT_IDENTITY}, defaults=${TS_OPT_GIT_DEFAULTS})."
    return 0
  fi

  if ! command -v git >/dev/null 2>&1; then
    ts_die "${TS_EXIT_ERR}" "O comando 'git' e necessario para aplicar configuracoes Git, mas nao foi encontrado no PATH."
  fi

  local prev_state prev_sha="" prev_link="" backup_path="" final_sha="" action=""
  prev_state="$(ts_path_state "${gitconfig_file}")"
  if [[ "${prev_state}" == "other" ]]; then
    ts_die "${TS_EXIT_ERR}" "O caminho '${gitconfig_file}' existe mas nao e arquivo regular nem symlink."
  fi

  mkdir -p "${gitconfig_file%/*}"
  local tmp_git
  tmp_git="$(mktemp "${gitconfig_file%/*}/.gitconfig-tmp.XXXXXX")"

  if [[ "${prev_state}" == "file" ]]; then
    prev_sha="$(ts_sha256_file "${gitconfig_file}")"
    cp -p -- "${gitconfig_file}" "${tmp_git}"
  elif [[ "${prev_state}" == "symlink" ]]; then
    prev_link="$(readlink "${gitconfig_file}")"
    if [[ -f "${gitconfig_file}" ]]; then
      cp -- "${gitconfig_file}" "${tmp_git}"
    fi
  fi

  # Aplicar alteracoes no arquivo temporario via git config --file
  if [[ "${want_identity}" == "true" ]]; then
    git config --file "${tmp_git}" user.name "${target_name}"
    git config --file "${tmp_git}" user.email "${target_email}"
  fi

  if [[ "${want_defaults}" == "true" ]]; then
    git config --file "${tmp_git}" init.defaultBranch "main"
    git config --file "${tmp_git}" core.editor "nano"
    git config --file "${tmp_git}" pull.ff "only"
  fi

  local new_sha
  new_sha="$(ts_sha256_file "${tmp_git}")"

  if [[ "${prev_state}" == "absent" ]]; then
    chmod 0600 "${tmp_git}" 2>/dev/null || true
    mv -Tf -- "${tmp_git}" "${gitconfig_file}"
    final_sha="${new_sha}"
    action="created"
    ts_log_event "INFO" "Arquivo Git global criado (valores de identidade omitidos por privacidade): path=${gitconfig_file}"
  elif [[ "${prev_state}" == "file" ]] && [[ "${prev_sha}" == "${new_sha}" ]]; then
    rm -f -- "${tmp_git}"
    final_sha="${prev_sha}"
    action="unchanged"
    ts_log_event "INFO" "Arquivo Git global ja possuia as configuracoes solicitadas (idempotente): path=${gitconfig_file}"
  else
    backup_path="$(ts_create_backup_item "${gitconfig_file}")"
    chmod 0600 "${tmp_git}" 2>/dev/null || true
    if [[ -L "${gitconfig_file}" ]]; then
      rm -f -- "${gitconfig_file}"
    fi
    mv -Tf -- "${tmp_git}" "${gitconfig_file}"
    final_sha="${new_sha}"
    action="replaced"
    ts_log_event "INFO" "Arquivo Git global atualizado com backup (valores de identidade omitidos por privacidade): path=${gitconfig_file} backup=${backup_path}"
  fi

  ts_manifest_record_entry \
    "${gitconfig_file}" \
    "file" \
    "${prev_state}" \
    "${prev_sha}" \
    "${prev_link}" \
    "${backup_path}" \
    "${final_sha}" \
    "" \
    "${action}"
}
