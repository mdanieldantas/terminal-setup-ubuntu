# ==============================================================================
# config/zsh/containers.zsh — Funcoes auxiliares para Docker/Podman
# Regra (Secao 10 do guia): NAO executar chamadas custosas ao daemon Docker ou
# Podman no startup do shell; definir funcoes apenas se o comando existir.
# ==============================================================================

if (( $+commands[docker] )); then
  alias dps='docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}"'
  alias dpa='docker ps -a --format "table {{.Names}}\t{{.Image}}\t{{.Status}}"'

  # Abre shell interativo em um container em execucao validando o argumento
  dsh() {
    if [[ $# -lt 1 ]] || [[ -z "$1" ]]; then
      printf 'Uso: dsh <nome-ou-id-do-container> [shell]\n' >&2
      return 2
    fi
    local container_target="$1"
    local target_shell="${2:-/bin/sh}"
    docker exec -it "${container_target}" "${target_shell}"
  }

  # Exibe logs de um container validando o argumento
  dlogs() {
    if [[ $# -lt 1 ]] || [[ -z "$1" ]]; then
      printf 'Uso: dlogs <nome-ou-id-do-container> [opcoes]\n' >&2
      return 2
    fi
    local container_target="$1"
    shift
    docker logs --tail 100 -f "$@" "${container_target}"
  }
fi

