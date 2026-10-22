#!/usr/bin/env bash
# ==============================================================================
# lib/user-config.sh — Instalacao idempotente de configuracoes no HOME do usuario
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# Segue estritamente as Secoes 8 e 10 do guia de implementacao.
# ==============================================================================

if [[ -n "${TS_USER_CONFIG_LOADED:-}" ]]; then
  return 0
fi
readonly TS_USER_CONFIG_LOADED=1

# Retorna o diretorio onde .zshenv e .zshrc devem ser gerenciados (respeita ZDOTDIR)
ts_effective_zdotdir() {
  if [[ "${TS_ZDOTDIR_STATUS}" == "custom" ]] && [[ -n "${TS_ZDOTDIR_VALUE}" ]]; then
    printf '%s' "${TS_ZDOTDIR_VALUE}"
  else
    printf '%s' "${HOME}"
  fi
}

# Gera arquivo temporario deterministico com as opcoes visuais selecionadas (icons / vi-mode)
ts_write_temp_zsh_options_file() {
  local dest_tmp="$1"
  cat > "${dest_tmp}" << EOF
# ==============================================================================
# options.zsh — Opcoes visuais geradas pelo terminal-setup (nao edite manualmente)
# ==============================================================================
export TS_ICONS_MODE="${TS_OPT_ICONS}"
export TS_VI_MODE_ENABLED="${TS_OPT_VI_MODE}"
EOF
}

# Aplica as configuracoes de Zsh, Starship, tmux e links ~/.local/bin no HOME do usuario
ts_apply_user_configurations() {
  local repo_root="$1"
  ts_init_state_paths

  # Garantir ~/.local/bin existente para ferramentas de usuario e links controlados
  mkdir -p "${HOME}/.local/bin"

  # 1. Configuracao do Zsh (quando zsh estiver entre os componentes selecionados)
  if ts_list_contains "zsh" "${TS_SELECTED_COMPONENTS[@]}"; then
    local zdotdir_target
    zdotdir_target="$(ts_effective_zdotdir)"
    local zsh_modules_dest="${TS_CONFIG_ROOT}/zsh"
    mkdir -p "${zsh_modules_dest}"

    # 1a. Gerar e instalar options.zsh de forma deterministica e idempotente
    local tmp_opts
    tmp_opts="$(mktemp "${TS_STATE_ROOT}/.opts-tmp.XXXXXX")"
    ts_write_temp_zsh_options_file "${tmp_opts}"
    ts_install_managed_file "${tmp_opts}" "${zsh_modules_dest}/options.zsh" "0644"
    rm -f -- "${tmp_opts}"

    # 1b. Instalar modulos Zsh gerenciados pelo projeto em ~/.config/terminal-setup/zsh/
    local -a zsh_mod_files=(
      "aliases.zsh"
      "bindings.zsh"
      "containers.zsh"
      "database.zsh"
      "fzf.zsh"
      "git.zsh"
      "plugins.zsh"
      "prompt.zsh"
    )
    local mod_name
    for mod_name in "${zsh_mod_files[@]}"; do
      ts_install_managed_file \
        "${repo_root}/config/zsh/${mod_name}" \
        "${zsh_modules_dest}/${mod_name}" \
        "0644"
    done

    # 1c. Instalar .zshenv e .zshrc respeitando ZDOTDIR e politica --on-conflict
    ts_install_managed_file \
      "${repo_root}/config/zsh/zshenv.template" \
      "${zdotdir_target}/.zshenv" \
      "0644"
    if [[ "${TS_LAST_FILE_ACTION}" == "kept_existing" ]]; then
      ts_warn "O arquivo '${zdotdir_target}/.zshenv' preexistente foi preservado (politica keep). Verifique se ~/.local/bin esta no seu PATH."
    fi

    ts_install_managed_file \
      "${repo_root}/config/zsh/zshrc" \
      "${zdotdir_target}/.zshrc" \
      "0644"
    if [[ "${TS_LAST_FILE_ACTION}" == "kept_existing" ]]; then
      ts_warn "O arquivo '${zdotdir_target}/.zshrc' preexistente foi preservado (politica keep). Isso impede a ativacao automatica do perfil Zsh do projeto; para substituir com backup, execute novamente com '--on-conflict backup-replace'."
    fi
  fi

  # 2. Configuracao do Starship (plain.toml por padrao, nerd.toml se --icons nerd)
  if ts_list_contains "starship" "${TS_SELECTED_COMPONENTS[@]}"; then
    local starship_template="${repo_root}/config/starship/${TS_OPT_ICONS}.toml"
    local starship_dest="${TS_XDG_CONFIG_HOME}/starship.toml"
    ts_install_managed_file "${starship_template}" "${starship_dest}" "0644"
    if [[ "${TS_LAST_FILE_ACTION}" == "kept_existing" ]]; then
      ts_warn "O arquivo '${starship_dest}' preexistente foi preservado (politica keep)."
    fi
  fi

  # 3. Configuracao do tmux
  if ts_list_contains "tmux" "${TS_SELECTED_COMPONENTS[@]}"; then
    local tmux_template="${repo_root}/config/tmux/tmux.conf"
    local tmux_dest="${TS_XDG_CONFIG_HOME}/tmux/tmux.conf"
    ts_install_managed_file "${tmux_template}" "${tmux_dest}" "0644"
    if [[ "${TS_LAST_FILE_ACTION}" == "kept_existing" ]]; then
      ts_warn "O arquivo '${tmux_dest}' preexistente foi preservado (politica keep)."
    fi
  fi

  # 4. Superfile (spf): conforme Secao 10, NAO instalar config.toml ficticio.
  if ts_list_contains "superfile" "${TS_SELECTED_COMPONENTS[@]}"; then
    ts_log_event "INFO" "Superfile selecionado: mantendo geracao padrao do upstream sem criar config.toml ficticio."
  fi

  # 5. Links controlados de compatibilidade Ubuntu em ~/.local/bin (bat -> batcat, fd -> fdfind)
  if ts_list_contains "bat" "${TS_SELECTED_COMPONENTS[@]}"; then
    local batcat_bin=""
    if batcat_bin="$(command -v batcat 2>/dev/null)"; then
      ts_install_managed_symlink_if_safe "${HOME}/.local/bin/bat" "${batcat_bin}"
    fi
  fi

  if ts_list_contains "fd" "${TS_SELECTED_COMPONENTS[@]}"; then
    local fdfind_bin=""
    if fdfind_bin="$(command -v fdfind 2>/dev/null)"; then
      ts_install_managed_symlink_if_safe "${HOME}/.local/bin/fd" "${fdfind_bin}"
    fi
  fi
}

