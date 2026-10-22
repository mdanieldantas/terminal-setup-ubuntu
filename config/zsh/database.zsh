# ==============================================================================
# config/zsh/database.zsh — Funcoes auxiliares para clientes de banco de dados
# Regra (Secao 10 do guia): definir apenas quando o cliente existir no PATH e
# validar argumentos. Nunca armazenar senhas ou credenciais em variaveis.
# ==============================================================================

if (( $+commands[psql] )); then
  pgconnect() {
    if [[ $# -lt 1 ]] || [[ -z "$1" ]]; then
      printf 'Uso: pgconnect < nome-do-banco-ou-uri > [argumentos-extras-do-psql]\n' >&2
      return 2
    fi
    psql "$@"
  }
fi

if (( $+commands[sqlite3] )); then
  sqliteread() {
    if [[ $# -ne 1 ]] || [[ -z "$1" ]]; then
      printf 'Uso: sqliteread <caminho-do-arquivo.sqlite>\n' >&2
      return 2
    fi
    if [[ ! -f "$1" ]]; then
      printf '[ERRO] Arquivo SQLite nao encontrado: %s\n' "$1" >&2
      return 1
    fi
    sqlite3 -header -column "$1"
  }
fi

