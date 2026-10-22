#!/usr/bin/env bash
# ==============================================================================
# lib/plan.sh — Construcao e exibicao legivel do plano de execucao (sem escrita)
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# Nota: Este modulo NAO cria diretorios, NAO cria logs e NAO executa instalacoes.
# ==============================================================================

if [[ -n "${TS_PLAN_LOADED:-}" ]]; then
  return 0
fi
readonly TS_PLAN_LOADED=1

# Imprime o plano completo de execucao em portugues claro
ts_print_execution_plan() {
  local mode_label="interativo"
  if [[ "${TS_OPT_DRY_RUN}" == "true" ]]; then
    mode_label="dry-run (somente planejamento, sem escrita e sem rede)"
  elif [[ "${TS_OPT_NON_INTERACTIVE}" == "true" ]]; then
    mode_label="nao interativo (--non-interactive)"
  fi

  local selection_mode="perfil '${TS_OPT_PROFILE}'"
  if [[ "${TS_EXPLICIT_ONLY}" == "true" ]]; then
    selection_mode="selecao explicita (--only ${TS_OPT_ONLY_RAW})"
  fi

  local config_source="(nenhum; usando apenas defaults e CLI)"
  if [[ -n "${TS_OPT_CONFIG_FILE}" ]]; then
    config_source="${TS_OPT_CONFIG_FILE}"
  fi

  local zdotdir_target="${HOME}"
  if [[ "${TS_ZDOTDIR_STATUS}" == "custom" ]]; then
    zdotdir_target="${TS_ZDOTDIR_VALUE} (ZDOTDIR customizado detectado; sera preservado)"
  fi

  printf '%s======================================================================%s\n' "${TS_COLOR_BOLD}" "${TS_COLOR_RESET}"
  printf '%sPlano de execucao — %s (%s)%s\n' "${TS_COLOR_BOLD}" "${TS_PROJECT_NAME}" "${TS_PROJECT_VERSION}" "${TS_COLOR_RESET}"
  printf '%s======================================================================%s\n' "${TS_COLOR_BOLD}" "${TS_COLOR_RESET}"
  printf '\n'

  printf '%s1. Contexto e ambiente detectado (somente leitura):%s\n' "${TS_COLOR_BOLD}" "${TS_COLOR_RESET}"
  printf '   - Usuario efetivo      : %s (UID %s)\n' "${TS_EFFECTIVE_USER}" "${TS_EFFECTIVE_UID}"
  printf '   - Sistema detectado    : %s (%s %s, %s)\n' "${TS_OS_PRETTY_NAME}" "${TS_OS_ID}" "${TS_OS_VERSION_ID}" "${TS_NORM_ARCH}"
  printf '   - Status da plataforma : %s\n' "${TS_PLATFORM_NOTE}"
  printf '   - Ambiente WSL         : %s\n' "${TS_IS_WSL}"
  printf '   - Ambiente Container   : %s\n' "${TS_IS_CONTAINER}"
  printf '   - jq disponivel agora  : %s\n' "${TS_HAS_JQ}"
  printf '   - HOME alvo            : %s\n' "${HOME}"
  printf '   - Alvo Zsh (ZDOTDIR)   : %s\n' "${zdotdir_target}"
  printf '   - Config XDG prevista  : %s/%s\n' "${TS_XDG_CONFIG_HOME}" "${TS_PROJECT_NAME}"
  printf '   - Estado XDG previsto  : %s/%s (logs, backups, manifests)\n' "${TS_XDG_STATE_HOME}" "${TS_PROJECT_NAME}"
  printf '\n'

  printf '%s2. Modo e politicas efetivas:%s\n' "${TS_COLOR_BOLD}" "${TS_COLOR_RESET}"
  printf '   - Modo de execucao     : %s\n' "${mode_label}"
  printf '   - Base de selecao      : %s\n' "${selection_mode}"
  printf '   - Arquivo --config     : %s\n' "${config_source}"
  printf '   - Confirmacao (--yes)  : %s (nao aprova identidade Git, shell, vi-mode nem conflitos)\n' "${TS_OPT_YES}"
  printf '   - Pacotes de sistema   : %s\n' "$([[ "${TS_OPT_SKIP_SYSTEM_PACKAGES}" == "true" ]] && printf 'omitidos (--skip-system-packages)' || printf 'via helper administrativo (scripts/install-system-packages.sh)')"
  printf '   - Uso de Git           : %s\n' "$([[ "${TS_OPT_SKIP_GIT}" == "true" ]] && printf 'desativado (--skip-git)' || printf 'habilitado')"
  printf '   - Identidade Git       : %s\n' "${TS_OPT_GIT_IDENTITY}"
  printf '   - Defaults globais Git : %s\n' "${TS_OPT_GIT_DEFAULTS}"
  printf '   - Troca de shell       : %s\n' "${TS_OPT_CHANGE_SHELL}"
  printf '   - Modo de icones       : %s\n' "${TS_OPT_ICONS}"
  printf '   - Modo Vi (Zsh)        : %s\n' "${TS_OPT_VI_MODE}"
  printf '   - Politica de conflito : %s\n' "${TS_OPT_ON_CONFLICT}"
  printf '\n'

  printf '%s3. Componentes selecionados (%d):%s\n' "${TS_COLOR_BOLD}" "${#TS_SELECTED_COMPONENTS[@]}" "${TS_COLOR_RESET}"
  local comp
  for comp in "${TS_SELECTED_COMPONENTS[@]}"; do
    printf '   - %-30s -> comando/recurso: %s\n' "${comp}" "$(ts_component_command_name "${comp}")"
  done
  printf '\n'

  printf '%s4. Pacotes APT previstos (%d):%s\n' "${TS_COLOR_BOLD}" "${#TS_SELECTED_APT_PACKAGES[@]}" "${TS_COLOR_RESET}"
  if [[ "${TS_OPT_SKIP_SYSTEM_PACKAGES}" == "true" ]]; then
    printf '   - Nenhum pacote APT sera instalado (--skip-system-packages ativo).\n'
    printf '   - Pacotes que seriam exigidos no sistema: %s\n' "${TS_SELECTED_APT_PACKAGES[*]:-(nenhum)}"
  elif [[ "${#TS_SELECTED_APT_PACKAGES[@]}" -eq 0 ]]; then
    printf '   - Nenhum pacote APT selecionado.\n'
  else
    printf '   - %s\n' "${TS_SELECTED_APT_PACKAGES[*]}"
  fi
  printf '\n'

  printf '%s5. Ferramentas externas do usuario em ~/.local/bin (%d):%s\n' "${TS_COLOR_BOLD}" "${#TS_SELECTED_EXTERNAL_TOOLS[@]}" "${TS_COLOR_RESET}"
  if [[ "${#TS_SELECTED_EXTERNAL_TOOLS[@]}" -eq 0 ]]; then
    printf '   - Nenhuma ferramenta externa selecionada.\n'
  else
    local tool
    for tool in "${TS_SELECTED_EXTERNAL_TOOLS[@]}"; do
      printf '   - %s (artefato oficial versionado + SHA-256 em versions/tools.lock.json)\n' "${tool}"
    done
  fi
  printf '\n'

  printf '%s6. Plugins Zsh via Git com commit fixado (%d):%s\n' "${TS_COLOR_BOLD}" "${#TS_SELECTED_ZSH_PLUGINS[@]}" "${TS_COLOR_RESET}"
  if [[ "${#TS_SELECTED_ZSH_PLUGINS[@]}" -eq 0 ]]; then
    printf '   - Nenhum plugin Zsh selecionado.\n'
  else
    local plugin
    for plugin in "${TS_SELECTED_ZSH_PLUGINS[@]}"; do
      printf '   - %s (clone em %s/%s/plugins/%s, commit em versions/plugins.lock.json)\n' \
        "${plugin}" "${TS_XDG_DATA_HOME}" "${TS_PROJECT_NAME}" "${plugin}"
    done
  fi
  printf '\n'

  printf '%s7. Links de compatibilidade Ubuntu em ~/.local/bin (%d):%s\n' "${TS_COLOR_BOLD}" "${#TS_SELECTED_LOCAL_LINKS[@]}" "${TS_COLOR_RESET}"
  if [[ "${#TS_SELECTED_LOCAL_LINKS[@]}" -eq 0 ]]; then
    printf '   - Nenhum link adicional necessario.\n'
  else
    local link_desc
    for link_desc in "${TS_SELECTED_LOCAL_LINKS[@]}"; do
      printf '   - %s\n' "${link_desc}"
    done
  fi
  printf '\n'

  printf '%s8. Arquivos de configuracao e estado previstos no HOME:%s\n' "${TS_COLOR_BOLD}" "${TS_COLOR_RESET}"
  if ts_list_contains "zsh" "${TS_SELECTED_COMPONENTS[@]}"; then
    printf '   - %s/.zshenv (preservando existente conforme --on-conflict=%s)\n' "${zdotdir_target%% *}" "${TS_OPT_ON_CONFLICT}"
    printf '   - %s/.zshrc (preservando existente conforme --on-conflict=%s)\n' "${zdotdir_target%% *}" "${TS_OPT_ON_CONFLICT}"
    printf '   - %s/%s/zsh/*.zsh (modulos Zsh gerenciados pelo projeto)\n' "${TS_XDG_CONFIG_HOME}" "${TS_PROJECT_NAME}"
  fi
  if ts_list_contains "starship" "${TS_SELECTED_COMPONENTS[@]}"; then
    printf '   - %s/starship.toml (template: config/starship/%s.toml, conforme --on-conflict=%s)\n' \
      "${TS_XDG_CONFIG_HOME}" "${TS_OPT_ICONS}" "${TS_OPT_ON_CONFLICT}"
  fi
  if ts_list_contains "tmux" "${TS_SELECTED_COMPONENTS[@]}"; then
    printf '   - %s/tmux/tmux.conf (configuracao simples sem plugins/rede, conforme --on-conflict=%s)\n' \
      "${TS_XDG_CONFIG_HOME}" "${TS_OPT_ON_CONFLICT}"
  fi
  if ts_list_contains "superfile" "${TS_SELECTED_COMPONENTS[@]}"; then
    printf '   - Superfile (spf): nenhum config.toml ficticio sera gravado; usa defaults oficiais em %s/superfile/\n' \
      "${TS_XDG_CONFIG_HOME}"
  fi
  printf '   - Manifesto e backups (somente em execucao efetiva): %s/%s/{backups,manifests,logs}/\n' \
    "${TS_XDG_STATE_HOME}" "${TS_PROJECT_NAME}"

  if [[ "${#TS_PLAN_WARNINGS[@]}" -gt 0 ]]; then
    printf '\n%sAvisos do planejamento:%s\n' "${TS_COLOR_BOLD}" "${TS_COLOR_RESET}"
    local warn_msg
    for warn_msg in "${TS_PLAN_WARNINGS[@]}"; do
      ts_warn "${warn_msg}"
    done
  fi

  printf '\n'
  if [[ "${TS_OPT_DRY_RUN}" == "true" ]]; then
    ts_ok "Modo --dry-run concluido: nenhum arquivo, diretorio, log, backup ou chamada de rede/sudo foi executado."
  fi
}

