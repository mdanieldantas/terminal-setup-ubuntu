# ==============================================================================
# config/zsh/plugins.zsh — Carregamento ordenado de plugins Zsh
# Regra (Secao 9 do guia):
#   - Sem git pull ou chamadas de rede ao abrir o terminal.
#   - Ordem de carga verificada na documentacao upstream:
#       1. zsh-vi-mode (opcional, apenas quando TS_VI_MODE_ENABLED=true, com
#          ZVM_INIT_MODE=sourcing definido ANTES do source)
#       2. zsh-autosuggestions
#       3. zsh-syntax-highlighting
#       4. zsh-history-substring-search (deve vir apos zsh-syntax-highlighting)
# ==============================================================================

typeset -g TS_ZSH_PLUGINS_DIR="${XDG_DATA_HOME:-${HOME}/.local/share}/terminal-setup/plugins"

# 1. zsh-vi-mode (somente quando explicitamente habilitado pelo usuario)
if [[ "${TS_VI_MODE_ENABLED:-false}" == "true" ]]; then
  if [[ -r "${TS_ZSH_PLUGINS_DIR}/zsh-vi-mode/zsh-vi-mode.plugin.zsh" ]]; then
    ZVM_INIT_MODE=sourcing
    source "${TS_ZSH_PLUGINS_DIR}/zsh-vi-mode/zsh-vi-mode.plugin.zsh"
  fi
fi

# 2. zsh-autosuggestions
if [[ -r "${TS_ZSH_PLUGINS_DIR}/zsh-autosuggestions/zsh-autosuggestions.zsh" ]]; then
  source "${TS_ZSH_PLUGINS_DIR}/zsh-autosuggestions/zsh-autosuggestions.zsh"
fi

# 3. zsh-syntax-highlighting (carregado apos widgets e antes do history-substring-search)
if [[ -r "${TS_ZSH_PLUGINS_DIR}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]]; then
  source "${TS_ZSH_PLUGINS_DIR}/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
fi

# 4. zsh-history-substring-search (carregado por ultimo; teclas associadas em bindings.zsh)
if [[ -r "${TS_ZSH_PLUGINS_DIR}/zsh-history-substring-search/zsh-history-substring-search.zsh" ]]; then
  source "${TS_ZSH_PLUGINS_DIR}/zsh-history-substring-search/zsh-history-substring-search.zsh"
fi

