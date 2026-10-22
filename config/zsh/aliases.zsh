# ==============================================================================
# config/zsh/aliases.zsh — Atalhos conservadores (terminal-setup)
# Regra obrigatoria (Secao 2 do guia): NAO definir aliases sobre
# cat, ls, grep, find, rm, cd, vi, vim, top ou htop. Criar apenas atalhos
# opcionais separados (ll, la, lt, batp, fdf, fdd).
# ==============================================================================

# Atalhos opcionais para listagem: usam eza se disponivel, com fallback para ls
# O modo de icones respeita TS_ICONS_MODE (plain por padrao, nerd se configurado)
if (( $+commands[eza] )); then
  if [[ "${TS_ICONS_MODE:-plain}" == "nerd" ]]; then
    alias ll='eza -la --group-directories-first --git --icons=auto'
    alias la='eza -a --group-directories-first --icons=auto'
    alias lt='eza --tree --level=2 --group-directories-first --icons=auto'
  else
    alias ll='eza -la --group-directories-first --git --icons=never'
    alias la='eza -a --group-directories-first --icons=never'
    alias lt='eza --tree --level=2 --group-directories-first --icons=never'
  fi
else
  alias ll='ls -alF'
  alias la='ls -A'
fi

# Atalhos opcionais para bat/batcat (sem substituir 'cat')
if (( $+commands[bat] )); then
  alias batp='bat --paging=never --style=plain'
elif (( $+commands[batcat] )); then
  alias batp='batcat --paging=never --style=plain'
fi

# Atalhos opcionais para fd/fdfind (sem substituir 'find')
if (( $+commands[fd] )); then
  alias fdf='fd --type f'
  alias fdd='fd --type d'
elif (( $+commands[fdfind] )); then
  alias fdf='fdfind --type f'
  alias fdd='fdfind --type d'
fi

