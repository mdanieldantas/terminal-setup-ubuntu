# ==============================================================================
# config/zsh/prompt.zsh — Inicializacao do Starship com fallback seguro
# Excecao delimitada para uso de eval: documentacao oficial do Starship
# ("eval \"$(starship init zsh)\"").
# ==============================================================================

if (( $+commands[starship] )); then
  export STARSHIP_CONFIG="${STARSHIP_CONFIG:-${XDG_CONFIG_HOME:-${HOME}/.config}/starship.toml}"
  eval "$(starship init zsh)"
else
  # Fallback limpo em texto puro caso o binario starship nao esteja instalado
  autoload -Uz vcs_info
  precmd() { vcs_info 2>/dev/null || true }
  zstyle ':vcs_info:git:*' formats ' (%b)'
  setopt PROMPT_SUBST
  PROMPT='%n@%m:%~${vcs_info_msg_0_}%# '
fi

