# ==============================================================================
# config/zsh/bindings.zsh — Teclas de navegacao e edicao (terminal-setup)
# ==============================================================================

# Usar mapa de teclas emacs por padrao quando zsh-vi-mode nao estiver ativo
if [[ "${TS_VI_MODE_ENABLED:-false}" != "true" ]]; then
  bindkey -e
fi

zmodload zsh/terminfo 2>/dev/null || true

# Home / End / Delete / Ctrl+Setas
[[ -n "${terminfo[khome]:-}" ]] && bindkey "${terminfo[khome]}" beginning-of-line
[[ -n "${terminfo[kend]:-}" ]]  && bindkey "${terminfo[kend]}"  end-of-line
[[ -n "${terminfo[kdch1]:-}" ]] && bindkey "${terminfo[kdch1]}" delete-char
bindkey '^[[H'  beginning-of-line
bindkey '^[[F'  end-of-line
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word

# Se zsh-history-substring-search foi carregado, associar setas Cima/Baixo
if (( $+functions[history-substring-search-up] )); then
  [[ -n "${terminfo[kcuu1]:-}" ]] && bindkey "${terminfo[kcuu1]}" history-substring-search-up
  [[ -n "${terminfo[kcud1]:-}" ]] && bindkey "${terminfo[kcud1]}" history-substring-search-down
  bindkey '^[[A' history-substring-search-up
  bindkey '^[[B' history-substring-search-down
  bindkey -M emacs '^P' history-substring-search-up 2>/dev/null || true
  bindkey -M emacs '^N' history-substring-search-down 2>/dev/null || true
  bindkey -M vicmd 'k' history-substring-search-up 2>/dev/null || true
  bindkey -M vicmd 'j' history-substring-search-down 2>/dev/null || true
fi

