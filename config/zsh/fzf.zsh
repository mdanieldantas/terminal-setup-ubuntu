# ==============================================================================
# config/zsh/fzf.zsh — Integracao do fzf com Zsh para Ubuntu 24.04 LTS
# Nota tecnica: O Ubuntu 24.04 LTS fornece fzf 0.44.1, que instala os scripts
# em /usr/share/doc/fzf/examples/ (a flag 'fzf --zsh' surgiu no fzf 0.48.0).
# Este modulo carrega os arquivos do pacote Ubuntu e usa 'fzf --zsh' apenas
# como fallback se os arquivos nao existirem e o binario suportar a flag.
# ==============================================================================

if (( $+commands[fzf] )); then
  export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:---height=40% --layout=reverse --border}"

  if [[ -r /usr/share/doc/fzf/examples/key-bindings.zsh ]]; then
    source /usr/share/doc/fzf/examples/key-bindings.zsh
  elif [[ -r /usr/share/fzf/key-bindings.zsh ]]; then
    source /usr/share/fzf/key-bindings.zsh
  elif fzf --zsh >/dev/null 2>&1; then
    eval "$(fzf --zsh)"
  fi

  if [[ -r /usr/share/doc/fzf/examples/completion.zsh ]]; then
    source /usr/share/doc/fzf/examples/completion.zsh
  elif [[ -r /usr/share/fzf/completion.zsh ]]; then
    source /usr/share/fzf/completion.zsh
  fi
fi

