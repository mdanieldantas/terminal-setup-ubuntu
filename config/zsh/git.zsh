# ==============================================================================
# config/zsh/git.zsh — Atalhos e funcoes auxiliares para Git (terminal-setup)
# ==============================================================================

if (( $+commands[git] )); then
  alias gst='git status -sb'
  alias glg='git log --oneline --graph --decorate -n 20'
  alias gdf='git diff'
  alias gds='git diff --staged'
  alias gbr='git branch -vv'

  # Cria e alterna para uma nova branch validando o nome
  gnew() {
    if [[ $# -ne 1 ]] || [[ -z "$1" ]]; then
      printf 'Uso: gnew <nome-da-nova-branch>\n' >&2
      return 2
    fi
    git switch -c "$1"
  }
fi

