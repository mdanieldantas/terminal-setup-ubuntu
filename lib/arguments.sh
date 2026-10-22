#!/usr/bin/env bash
# ==============================================================================
# lib/arguments.sh — Catalogo de componentes, parser de CLI e validacao de regras
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# Segue estritamente as Secoes 6 e 7 do guia de implementacao.
# ==============================================================================

if [[ -n "${TS_ARGUMENTS_LOADED:-}" ]]; then
  return 0
fi
readonly TS_ARGUMENTS_LOADED=1

# Perfis validos na v1
readonly -a TS_VALID_PROFILES=(
  "minimal"
  "developer"
  "server"
)

# Catalogo fechado de componentes conhecidos na v1 (ordem canonica de apresentacao/instalacao)
readonly -a TS_KNOWN_COMPONENTS=(
  "zsh"
  "git"
  "nano"
  "ca-certificates"
  "curl"
  "jq"
  "starship"
  "fzf"
  "ripgrep"
  "bat"
  "fd"
  "tmux"
  "zoxide"
  "eza"
  "superfile"
  "btop"
  "zsh-autosuggestions"
  "zsh-history-substring-search"
  "zsh-syntax-highlighting"
  "zsh-vi-mode"
)

# Componentes base obrigatorios em qualquer instalacao por perfil (exceto git quando --skip-git)
readonly -a TS_BASE_REQUIRED_COMPONENTS=(
  "zsh"
  "nano"
  "ca-certificates"
  "curl"
  "jq"
)

# Plugins que dependem obrigatoriamente de Git e Zsh
readonly -a TS_GIT_PLUGIN_COMPONENTS=(
  "zsh-autosuggestions"
  "zsh-history-substring-search"
  "zsh-syntax-highlighting"
  "zsh-vi-mode"
)

# Estado efetivo das opcoes apos aplicar precedencia (defaults < --config < CLI)
TS_ACTION="run"
TS_OPT_PROFILE="minimal"
TS_OPT_DRY_RUN="false"
TS_OPT_YES="false"
TS_OPT_NON_INTERACTIVE="false"
TS_OPT_CONFIG_FILE=""
TS_OPT_SKIP_SYSTEM_PACKAGES="false"
TS_OPT_SKIP_GIT="false"
TS_OPT_GIT_IDENTITY="ask"
TS_OPT_GIT_NAME=""
TS_OPT_GIT_EMAIL=""
TS_OPT_GIT_DEFAULTS="ask"
TS_OPT_CHANGE_SHELL="ask"
TS_OPT_ICONS="plain"
TS_OPT_VI_MODE="false"
TS_OPT_ON_CONFLICT="ask"
TS_OPT_INCLUDE_RAW=""
TS_OPT_EXCLUDE_RAW=""
TS_OPT_ONLY_RAW=""

# Rastreamento de origem explicita para detectar conflitos
TS_EXPLICIT_PROFILE="false"
TS_EXPLICIT_INCLUDE="false"
TS_EXPLICIT_EXCLUDE="false"
TS_EXPLICIT_ONLY="false"
TS_EXPLICIT_GIT_IDENTITY="false"
TS_EXPLICIT_GIT_NAME="false"
TS_EXPLICIT_GIT_EMAIL="false"
TS_EXPLICIT_GIT_DEFAULTS="false"
TS_EXPLICIT_CHANGE_SHELL="false"
TS_EXPLICIT_ON_CONFLICT="false"

# Listas resolvidas de componentes
declare -ga TS_SELECTED_COMPONENTS=()
declare -ga TS_SELECTED_APT_PACKAGES=()
declare -ga TS_SELECTED_EXTERNAL_TOOLS=()
declare -ga TS_SELECTED_ZSH_PLUGINS=()
declare -ga TS_SELECTED_LOCAL_LINKS=()
declare -ga TS_PLAN_WARNINGS=()

# Retorna o pacote APT correspondente a um componente (ou vazio se for externo/plugin)
ts_component_apt_package() {
  local comp="$1"
  case "${comp}" in
    zsh) printf 'zsh' ;;
    git) printf 'git' ;;
    nano) printf 'nano' ;;
    ca-certificates) printf 'ca-certificates' ;;
    curl) printf 'curl' ;;
    jq) printf 'jq' ;;
    fzf) printf 'fzf' ;;
    ripgrep) printf 'ripgrep' ;;
    bat) printf 'bat' ;;
    fd) printf 'fd-find' ;;
    tmux) printf 'tmux' ;;
    zoxide) printf 'zoxide' ;;
    eza) printf 'eza' ;;
    btop) printf 'btop' ;;
    *) printf '' ;;
  esac
}

# Retorna o comando final esperado no Ubuntu para um componente
ts_component_command_name() {
  local comp="$1"
  case "${comp}" in
    zsh) printf 'zsh' ;;
    git) printf 'git' ;;
    nano) printf 'nano' ;;
    ca-certificates) printf '(certificados TLS)' ;;
    curl) printf 'curl' ;;
    jq) printf 'jq' ;;
    starship) printf 'starship' ;;
    fzf) printf 'fzf' ;;
    ripgrep) printf 'rg' ;;
    bat) printf 'batcat (link opcional: bat)' ;;
    fd) printf 'fdfind (link opcional: fd)' ;;
    tmux) printf 'tmux' ;;
    zoxide) printf 'zoxide' ;;
    eza) printf 'eza' ;;
    superfile) printf 'spf' ;;
    btop) printf 'btop' ;;
    zsh-*) printf '(plugin Zsh)' ;;
    *) printf '%s' "${comp}" ;;
  esac
}

# Retorna as dependencias obrigatorias diretas de um componente
ts_component_dependencies() {
  local comp="$1"
  case "${comp}" in
    starship)
      printf 'ca-certificates\ncurl\njq\nzsh\n'
      ;;
    superfile)
      printf 'ca-certificates\ncurl\njq\n'
      ;;
    zoxide | fzf)
      printf 'zsh\n'
      ;;
    zsh-autosuggestions | zsh-history-substring-search | zsh-syntax-highlighting | zsh-vi-mode)
      printf 'zsh\ngit\njq\n'
      ;;
    *)
      return 0
      ;;
  esac
}

# Valida se todos os itens de uma lista pertencem ao catalogo conhecido
ts_validate_component_list() {
  local context_label="$1"
  shift
  local comp
  for comp in "$@"; do
    if ! ts_list_contains "${comp}" "${TS_KNOWN_COMPONENTS[@]}"; then
      ts_die_usage "${context_label}: componente desconhecido '${comp}'. Componentes validos: ${TS_KNOWN_COMPONENTS[*]}."
    fi
  done
}

# Valida valor de enum
ts_validate_enum() {
  local opt_name="$1"
  local value="$2"
  shift 2
  if ! ts_list_contains "${value}" "$@"; then
    ts_die_usage "Valor invalido para ${opt_name}: '${value}'. Valores permitidos: $*."
  fi
}

# Exibe texto de ajuda sem alterar o sistema
ts_print_help() {
  cat <<'EOF'
Uso:
  bash ./install-terminal.sh [opcoes]

Descricao:
  Instalador e configurador de ambiente de terminal para Ubuntu 24.04 LTS (amd64).
  Separa pacotes do sistema (APT via helper administrativo) da configuracao
  do usuario (Zsh, Starship, tmux, Superfile, plugins Zsh e Git no HOME).

Opcoes gerais:
  -h, --help                     Exibe esta ajuda sem realizar alteracoes.
  --version                      Exibe a versao do projeto sem realizar alteracoes.
  --profile <minimal|developer|server>
                                 Seleciona o perfil de ferramentas (padrao: minimal).
  --dry-run                      Apenas planeja e exibe as acoes previstas, sem escrita
                                 no disco, sem logs, sem backups, sem rede e sem sudo.
  --yes                          Aceita confirmacoes interativas de baixo risco com
                                 padrao positivo (nao altera identidade Git, shell
                                 padrao, vi-mode nem sobrescreve conflitos).
  --non-interactive              Proibe qualquer prompt interativo (read/chsh/sudo com
                                 senha). Converte politicas 'ask' padrao em 'skip',
                                 'keep' ou 'no'.
  --config <caminho>             Le preferencias de um arquivo explicito no formato
                                 restrito CHAVE=valor. Nenhum arquivo e lido
                                 implicitamente.

Opcoes de escopo e componentes:
  --skip-system-packages         Valida requisitos, mas nao executa APT nem sudo.
  --skip-git                     Nao instala, nao configura e nao usa Git (omite
                                 clonagem de plugins Zsh dependentes de Git).
  --include <comp1,comp2,...>    Acrescenta componentes conhecidos ao perfil.
  --exclude <comp1,comp2,...>    Exclui componentes opcionais ou nao obrigatorios.
  --only <comp1,comp2,...>       Substitui a selecao do perfil pelos componentes
                                 informados e resolve suas dependencias obrigatorias.
                                 Incompativel com --profile, --include e --exclude.

Opcoes de aparencia, editor de linha e conflitos:
  --icons <plain|nerd>           Modo visual do Starship e atalhos (padrao: plain).
  --vi-mode                      Habilita o plugin opcional zsh-vi-mode.
  --on-conflict <ask|keep|backup-replace>
                                 Politica para arquivos existentes no HOME (padrao: ask;
                                 em --non-interactive o padrao vira keep).

Opcoes de Git e shell de login:
  --git-identity <ask|skip|configure>
                                 Define se user.name e user.email globais do Git serao
                                 configurados (padrao: ask; em --non-interactive vira skip).
  --git-name "<nome>"            Nome para Git global (usado somente com
                                 --git-identity configure).
  --git-email <email>            E-mail para Git global (usado somente com
                                 --git-identity configure).
  --git-defaults <ask|keep|apply>
                                 Politica para defaults globais do Git como branch e
                                 editor (padrao: ask; em --non-interactive vira keep).
  --change-shell <ask|no|yes>    Politica para troca do shell de login via chsh
                                 (padrao: ask; proibido usar 'yes' com --non-interactive).

Exemplos:
  bash ./install-terminal.sh --profile developer --dry-run
  bash ./install-terminal.sh --profile server --include superfile --dry-run
  bash ./install-terminal.sh --only superfile --dry-run
EOF
}

# Exibe versao sem alterar o sistema
ts_print_version() {
  printf '%s %s\n' "${TS_PROJECT_NAME}" "${TS_PROJECT_VERSION}"
}

# Extrai o valor de uma flag que exige argumento
ts_require_arg_value() {
  local flag="$1"
  local argc="$2"
  local val="${3:-}"
  if [[ "${argc}" -lt 2 ]] || [[ -z "${val}" ]]; then
    ts_die_usage "O parametro '${flag}' exige um valor nao vazio."
  fi
}

# Faz o parsing completo da linha de comando, eventual --config e perfil selecionado
# shellcheck disable=SC2034 # TS_ACTION e TS_OPT_* sao variaveis globais consumidas por install-terminal.sh e lib/plan.sh
ts_parse_arguments() {
  local repo_root="$1"
  shift

  # Variaveis temporarias para capturar valores vindos exclusivamente da CLI
  local cli_help="false"
  local cli_version="false"
  local cli_profile=""
  local cli_dry_run="false"
  local cli_yes="false"
  local cli_non_interactive="false"
  local cli_config_file=""
  local cli_skip_system_packages="false"
  local cli_skip_git="false"
  local cli_git_identity=""
  local cli_git_name=""
  local cli_git_email=""
  local cli_git_defaults=""
  local cli_change_shell=""
  local cli_include=""
  local cli_exclude=""
  local cli_only=""
  local cli_icons=""
  local cli_on_conflict=""

  local cli_has_profile="false"
  local cli_has_include="false"
  local cli_has_exclude="false"
  local cli_has_only="false"
  local cli_has_git_identity="false"
  local cli_has_git_name="false"
  local cli_has_git_email="false"
  local cli_has_git_defaults="false"
  local cli_has_change_shell="false"
  local cli_has_icons="false"
  local cli_has_vi_mode="false"
  local cli_has_on_conflict="false"

  local arg opt_name opt_val
  while [[ $# -gt 0 ]]; do
    arg="$1"

    # Suporte a --opcao=valor para flags que aceitam valor
    if [[ "${arg}" == --*=* ]]; then
      opt_name="${arg%%=*}"
      opt_val="${arg#*=}"
      if [[ -z "${opt_val}" ]]; then
        ts_die_usage "O parametro '${opt_name}' exige um valor nao vazio."
      fi
      case "${opt_name}" in
        --profile)
          cli_profile="${opt_val}"
          cli_has_profile="true"
          ;;
        --config)
          cli_config_file="${opt_val}"
          ;;
        --git-identity)
          cli_git_identity="${opt_val}"
          cli_has_git_identity="true"
          ;;
        --git-name)
          cli_git_name="${opt_val}"
          cli_has_git_name="true"
          ;;
        --git-email)
          cli_git_email="${opt_val}"
          cli_has_git_email="true"
          ;;
        --git-defaults)
          cli_git_defaults="${opt_val}"
          cli_has_git_defaults="true"
          ;;
        --change-shell)
          cli_change_shell="${opt_val}"
          cli_has_change_shell="true"
          ;;
        --include)
          cli_include="${opt_val}"
          cli_has_include="true"
          ;;
        --exclude)
          cli_exclude="${opt_val}"
          cli_has_exclude="true"
          ;;
        --only)
          cli_only="${opt_val}"
          cli_has_only="true"
          ;;
        --icons)
          cli_icons="${opt_val}"
          cli_has_icons="true"
          ;;
        --on-conflict)
          cli_on_conflict="${opt_val}"
          cli_has_on_conflict="true"
          ;;
        --help | --version | --dry-run | --yes | --non-interactive | --skip-system-packages | --skip-git | --vi-mode)
          ts_die_usage "O parametro '${opt_name}' nao aceita valor ('${arg}')."
          ;;
        *)
          ts_die_usage "Parametro desconhecido: '${opt_name}'."
          ;;
      esac
      shift
      continue
    fi

    case "${arg}" in
      -h | --help)
        cli_help="true"
        shift
        ;;
      --version)
        cli_version="true"
        shift
        ;;
      --dry-run)
        cli_dry_run="true"
        shift
        ;;
      --yes)
        cli_yes="true"
        shift
        ;;
      --non-interactive)
        cli_non_interactive="true"
        shift
        ;;
      --skip-system-packages)
        cli_skip_system_packages="true"
        shift
        ;;
      --skip-git)
        cli_skip_git="true"
        shift
        ;;
      --vi-mode)
        cli_has_vi_mode="true"
        shift
        ;;
      --profile)
        ts_require_arg_value "--profile" "$#" "${2:-}"
        cli_profile="$2"
        cli_has_profile="true"
        shift 2
        ;;
      --config)
        ts_require_arg_value "--config" "$#" "${2:-}"
        cli_config_file="$2"
        shift 2
        ;;
      --git-identity)
        ts_require_arg_value "--git-identity" "$#" "${2:-}"
        cli_git_identity="$2"
        cli_has_git_identity="true"
        shift 2
        ;;
      --git-name)
        ts_require_arg_value "--git-name" "$#" "${2:-}"
        cli_git_name="$2"
        cli_has_git_name="true"
        shift 2
        ;;
      --git-email)
        ts_require_arg_value "--git-email" "$#" "${2:-}"
        cli_git_email="$2"
        cli_has_git_email="true"
        shift 2
        ;;
      --git-defaults)
        ts_require_arg_value "--git-defaults" "$#" "${2:-}"
        cli_git_defaults="$2"
        cli_has_git_defaults="true"
        shift 2
        ;;
      --change-shell)
        ts_require_arg_value "--change-shell" "$#" "${2:-}"
        cli_change_shell="$2"
        cli_has_change_shell="true"
        shift 2
        ;;
      --include)
        ts_require_arg_value "--include" "$#" "${2:-}"
        cli_include="$2"
        cli_has_include="true"
        shift 2
        ;;
      --exclude)
        ts_require_arg_value "--exclude" "$#" "${2:-}"
        cli_exclude="$2"
        cli_has_exclude="true"
        shift 2
        ;;
      --only)
        ts_require_arg_value "--only" "$#" "${2:-}"
        cli_only="$2"
        cli_has_only="true"
        shift 2
        ;;
      --icons)
        ts_require_arg_value "--icons" "$#" "${2:-}"
        cli_icons="$2"
        cli_has_icons="true"
        shift 2
        ;;
      --on-conflict)
        ts_require_arg_value "--on-conflict" "$#" "${2:-}"
        cli_on_conflict="$2"
        cli_has_on_conflict="true"
        shift 2
        ;;
      --)
        shift
        if [[ $# -gt 0 ]]; then
          ts_die_usage "Argumentos posicionais nao sao suportados: '$*'."
        fi
        ;;
      -*)
        ts_die_usage "Parametro desconhecido: '${arg}'."
        ;;
      *)
        ts_die_usage "Argumento posicional inesperado: '${arg}'."
        ;;
    esac
  done

  # Se --help ou --version foram solicitados (e todas as flags da linha eram sintaticamente validas),
  # definimos a acao imediata sem carregar arquivos nem validar estado externo.
  if [[ "${cli_help}" == "true" ]]; then
    TS_ACTION="help"
    return 0
  fi
  if [[ "${cli_version}" == "true" ]]; then
    TS_ACTION="version"
    return 0
  fi

  # 1. Inicializar com os defaults documentados (Secao 7.1)
  TS_ACTION="run"
  TS_OPT_PROFILE="minimal"
  TS_OPT_DRY_RUN="false"
  TS_OPT_YES="false"
  TS_OPT_NON_INTERACTIVE="false"
  TS_OPT_CONFIG_FILE=""
  TS_OPT_SKIP_SYSTEM_PACKAGES="false"
  TS_OPT_SKIP_GIT="false"
  TS_OPT_GIT_IDENTITY="ask"
  TS_OPT_GIT_NAME=""
  TS_OPT_GIT_EMAIL=""
  TS_OPT_GIT_DEFAULTS="ask"
  TS_OPT_CHANGE_SHELL="ask"
  TS_OPT_ICONS="plain"
  TS_OPT_VI_MODE="false"
  TS_OPT_ON_CONFLICT="ask"
  TS_OPT_INCLUDE_RAW=""
  TS_OPT_EXCLUDE_RAW=""
  TS_OPT_ONLY_RAW=""

  TS_EXPLICIT_PROFILE="false"
  TS_EXPLICIT_INCLUDE="false"
  TS_EXPLICIT_EXCLUDE="false"
  TS_EXPLICIT_ONLY="false"
  TS_EXPLICIT_GIT_IDENTITY="false"
  TS_EXPLICIT_GIT_NAME="false"
  TS_EXPLICIT_GIT_EMAIL="false"
  TS_EXPLICIT_GIT_DEFAULTS="false"
  TS_EXPLICIT_CHANGE_SHELL="false"
  TS_EXPLICIT_ON_CONFLICT="false"

  # 2. Se --config foi informado, carregar e sobrepor os defaults (Secao 7.2)
  if [[ -n "${cli_config_file}" ]]; then
    TS_OPT_CONFIG_FILE="${cli_config_file}"
    ts_load_user_config_file "${TS_OPT_CONFIG_FILE}"

    if [[ -n "${TS_CONFIG_VALUES[PROFILE]+x}" ]]; then
      TS_OPT_PROFILE="${TS_CONFIG_VALUES[PROFILE]}"
      TS_EXPLICIT_PROFILE="true"
    fi
    if [[ -n "${TS_CONFIG_VALUES[ICONS]+x}" ]]; then
      TS_OPT_ICONS="${TS_CONFIG_VALUES[ICONS]}"
    fi
    if [[ -n "${TS_CONFIG_VALUES[GIT_IDENTITY]+x}" ]]; then
      TS_OPT_GIT_IDENTITY="${TS_CONFIG_VALUES[GIT_IDENTITY]}"
      TS_EXPLICIT_GIT_IDENTITY="true"
    fi
    if [[ -n "${TS_CONFIG_VALUES[GIT_NAME]+x}" ]]; then
      TS_OPT_GIT_NAME="${TS_CONFIG_VALUES[GIT_NAME]}"
      TS_EXPLICIT_GIT_NAME="true"
    fi
    if [[ -n "${TS_CONFIG_VALUES[GIT_EMAIL]+x}" ]]; then
      TS_OPT_GIT_EMAIL="${TS_CONFIG_VALUES[GIT_EMAIL]}"
      TS_EXPLICIT_GIT_EMAIL="true"
    fi
    if [[ -n "${TS_CONFIG_VALUES[GIT_DEFAULTS]+x}" ]]; then
      TS_OPT_GIT_DEFAULTS="${TS_CONFIG_VALUES[GIT_DEFAULTS]}"
      TS_EXPLICIT_GIT_DEFAULTS="true"
    fi
    if [[ -n "${TS_CONFIG_VALUES[CHANGE_SHELL]+x}" ]]; then
      TS_OPT_CHANGE_SHELL="${TS_CONFIG_VALUES[CHANGE_SHELL]}"
      TS_EXPLICIT_CHANGE_SHELL="true"
    fi
    if [[ -n "${TS_CONFIG_VALUES[ON_CONFLICT]+x}" ]]; then
      TS_OPT_ON_CONFLICT="${TS_CONFIG_VALUES[ON_CONFLICT]}"
      TS_EXPLICIT_ON_CONFLICT="true"
    fi
    if [[ -n "${TS_CONFIG_VALUES[VI_MODE]+x}" ]]; then
      ts_validate_enum "VI_MODE (em ${TS_OPT_CONFIG_FILE})" "${TS_CONFIG_VALUES[VI_MODE]}" "true" "false"
      TS_OPT_VI_MODE="${TS_CONFIG_VALUES[VI_MODE]}"
    fi
    if [[ -n "${TS_CONFIG_VALUES[INCLUDE]+x}" ]]; then
      TS_OPT_INCLUDE_RAW="${TS_CONFIG_VALUES[INCLUDE]}"
      TS_EXPLICIT_INCLUDE="true"
    fi
    if [[ -n "${TS_CONFIG_VALUES[EXCLUDE]+x}" ]]; then
      TS_OPT_EXCLUDE_RAW="${TS_CONFIG_VALUES[EXCLUDE]}"
      TS_EXPLICIT_EXCLUDE="true"
    fi
  fi

  # 3. Aplicar opcoes de CLI (precedencia: defaults < --config < CLI)
  if [[ "${cli_has_profile}" == "true" ]]; then
    TS_OPT_PROFILE="${cli_profile}"
    TS_EXPLICIT_PROFILE="true"
  fi
  if [[ "${cli_dry_run}" == "true" ]]; then
    TS_OPT_DRY_RUN="true"
  fi
  if [[ "${cli_yes}" == "true" ]]; then
    TS_OPT_YES="true"
  fi
  if [[ "${cli_non_interactive}" == "true" ]]; then
    TS_OPT_NON_INTERACTIVE="true"
  fi
  if [[ "${cli_skip_system_packages}" == "true" ]]; then
    TS_OPT_SKIP_SYSTEM_PACKAGES="true"
  fi
  if [[ "${cli_skip_git}" == "true" ]]; then
    TS_OPT_SKIP_GIT="true"
  fi
  if [[ "${cli_has_git_identity}" == "true" ]]; then
    TS_OPT_GIT_IDENTITY="${cli_git_identity}"
    TS_EXPLICIT_GIT_IDENTITY="true"
  fi
  if [[ "${cli_has_git_name}" == "true" ]]; then
    TS_OPT_GIT_NAME="${cli_git_name}"
    TS_EXPLICIT_GIT_NAME="true"
  fi
  if [[ "${cli_has_git_email}" == "true" ]]; then
    TS_OPT_GIT_EMAIL="${cli_git_email}"
    TS_EXPLICIT_GIT_EMAIL="true"
  fi
  if [[ "${cli_has_git_defaults}" == "true" ]]; then
    TS_OPT_GIT_DEFAULTS="${cli_git_defaults}"
    TS_EXPLICIT_GIT_DEFAULTS="true"
  fi
  if [[ "${cli_has_change_shell}" == "true" ]]; then
    TS_OPT_CHANGE_SHELL="${cli_change_shell}"
    TS_EXPLICIT_CHANGE_SHELL="true"
  fi
  if [[ "${cli_has_include}" == "true" ]]; then
    TS_OPT_INCLUDE_RAW="${cli_include}"
    TS_EXPLICIT_INCLUDE="true"
  fi
  if [[ "${cli_has_exclude}" == "true" ]]; then
    TS_OPT_EXCLUDE_RAW="${cli_exclude}"
    TS_EXPLICIT_EXCLUDE="true"
  fi
  if [[ "${cli_has_only}" == "true" ]]; then
    TS_OPT_ONLY_RAW="${cli_only}"
    TS_EXPLICIT_ONLY="true"
  fi
  if [[ "${cli_has_icons}" == "true" ]]; then
    TS_OPT_ICONS="${cli_icons}"
  fi
  if [[ "${cli_has_vi_mode}" == "true" ]]; then
    TS_OPT_VI_MODE="true"
  fi
  if [[ "${cli_has_on_conflict}" == "true" ]]; then
    TS_OPT_ON_CONFLICT="${cli_on_conflict}"
    TS_EXPLICIT_ON_CONFLICT="true"
  fi

  # 4. Validar enums e combinacoes basicas antes de qualquer efeito colateral
  ts_validate_enum "--profile / PROFILE" "${TS_OPT_PROFILE}" "${TS_VALID_PROFILES[@]}"
  ts_validate_enum "--icons / ICONS" "${TS_OPT_ICONS}" "plain" "nerd"
  ts_validate_enum "--git-identity / GIT_IDENTITY" "${TS_OPT_GIT_IDENTITY}" "ask" "skip" "configure"
  ts_validate_enum "--git-defaults / GIT_DEFAULTS" "${TS_OPT_GIT_DEFAULTS}" "ask" "keep" "apply"
  ts_validate_enum "--change-shell / CHANGE_SHELL" "${TS_OPT_CHANGE_SHELL}" "ask" "no" "yes"
  ts_validate_enum "--on-conflict / ON_CONFLICT" "${TS_OPT_ON_CONFLICT}" "ask" "keep" "backup-replace"

  # Regra: --only e incompativel com perfil explicitamente informado e com include/exclude
  if [[ "${TS_EXPLICIT_ONLY}" == "true" ]]; then
    if [[ "${TS_EXPLICIT_PROFILE}" == "true" ]]; then
      ts_die_usage "--only e incompativel com --profile (ou PROFILE em --config)."
    fi
    if [[ "${TS_EXPLICIT_INCLUDE}" == "true" ]] || [[ "${TS_EXPLICIT_EXCLUDE}" == "true" ]]; then
      ts_die_usage "--only e incompativel com --include/--exclude (ou INCLUDE/EXCLUDE em --config)."
    fi
  fi

  # Regra: em --non-interactive, valores 'ask' herdados do padrao viram skip/keep/no/keep,
  # mas valores 'ask' explicitamente solicitados ou '--change-shell yes' sao erro.
  if [[ "${TS_OPT_NON_INTERACTIVE}" == "true" ]]; then
    if [[ "${TS_OPT_CHANGE_SHELL}" == "yes" ]]; then
      ts_die_usage "--non-interactive e incompativel com --change-shell yes (chsh exige interacao; em Docker defina o shell na criacao do usuario e no CMD)."
    fi
    if [[ "${TS_EXPLICIT_GIT_IDENTITY}" == "true" ]] && [[ "${TS_OPT_GIT_IDENTITY}" == "ask" ]]; then
      ts_die_usage "--non-interactive proibe '--git-identity ask' explicito. Use 'skip' ou 'configure'."
    fi
    if [[ "${TS_EXPLICIT_GIT_DEFAULTS}" == "true" ]] && [[ "${TS_OPT_GIT_DEFAULTS}" == "ask" ]]; then
      ts_die_usage "--non-interactive proibe '--git-defaults ask' explicito. Use 'keep' ou 'apply'."
    fi
    if [[ "${TS_EXPLICIT_CHANGE_SHELL}" == "true" ]] && [[ "${TS_OPT_CHANGE_SHELL}" == "ask" ]]; then
      ts_die_usage "--non-interactive proibe '--change-shell ask' explicito. Use 'no'."
    fi
    if [[ "${TS_EXPLICIT_ON_CONFLICT}" == "true" ]] && [[ "${TS_OPT_ON_CONFLICT}" == "ask" ]]; then
      ts_die_usage "--non-interactive proibe '--on-conflict ask' explicito. Use 'keep' ou 'backup-replace'."
    fi

    # Converter defaults 'ask' para equivalentes seguros nao interativos (Secao 7.1)
    if [[ "${TS_OPT_GIT_IDENTITY}" == "ask" ]]; then
      TS_OPT_GIT_IDENTITY="skip"
    fi
    if [[ "${TS_OPT_GIT_DEFAULTS}" == "ask" ]]; then
      TS_OPT_GIT_DEFAULTS="keep"
    fi
    if [[ "${TS_OPT_CHANGE_SHELL}" == "ask" ]]; then
      TS_OPT_CHANGE_SHELL="no"
    fi
    if [[ "${TS_OPT_ON_CONFLICT}" == "ask" ]]; then
      TS_OPT_ON_CONFLICT="keep"
    fi
  fi

  # Regra: --git-name e --git-email sao usados somente com --git-identity configure
  if [[ "${TS_OPT_GIT_IDENTITY}" != "configure" ]]; then
    if [[ "${TS_EXPLICIT_GIT_NAME}" == "true" ]] || [[ "${TS_EXPLICIT_GIT_EMAIL}" == "true" ]]; then
      ts_die_usage "--git-name e --git-email (ou GIT_NAME/GIT_EMAIL) so podem ser usados quando --git-identity for 'configure'."
    fi
  else
    # Quando --git-identity configure: validar se --git-name / --git-email foram passados
    if [[ -n "${TS_OPT_GIT_NAME}" ]] && ! ts_validate_git_name "${TS_OPT_GIT_NAME}"; then
      ts_die_usage "Valor invalido para --git-name / GIT_NAME."
    fi
    if [[ -n "${TS_OPT_GIT_EMAIL}" ]] && ! ts_validate_email "${TS_OPT_GIT_EMAIL}"; then
      ts_die_usage "Valor invalido para --git-email / GIT_EMAIL: '${TS_OPT_GIT_EMAIL}'."
    fi
    if [[ "${TS_OPT_NON_INTERACTIVE}" == "true" ]]; then
      if [[ -z "${TS_OPT_GIT_NAME}" ]] || [[ -z "${TS_OPT_GIT_EMAIL}" ]]; then
        ts_die_usage "--non-interactive com --git-identity configure exige --git-name e --git-email completos e validos."
      fi
    fi
  fi

  # Regra: --skip-git tem prioridade e conflita com configuracao explicita de Git
  if [[ "${TS_OPT_SKIP_GIT}" == "true" ]]; then
    if [[ "${TS_OPT_GIT_IDENTITY}" == "configure" ]]; then
      ts_die_usage "--skip-git e incompativel com --git-identity configure."
    fi
    if [[ "${TS_OPT_GIT_DEFAULTS}" == "apply" ]]; then
      ts_die_usage "--skip-git e incompativel com --git-defaults apply."
    fi
    TS_OPT_GIT_IDENTITY="skip"
    TS_OPT_GIT_DEFAULTS="keep"
  fi

  # 5. Resolver componentes selecionados, aplicando regras de include/exclude/only e dependencias
  ts_resolve_components "${repo_root}"
}

# Resolve a lista final de componentes, pacotes APT, binarios externos, plugins e links
ts_resolve_components() {
  local repo_root="$1"

  TS_SELECTED_COMPONENTS=()
  TS_SELECTED_APT_PACKAGES=()
  TS_SELECTED_EXTERNAL_TOOLS=()
  TS_SELECTED_ZSH_PLUGINS=()
  TS_SELECTED_LOCAL_LINKS=()
  TS_PLAN_WARNINGS=()

  local -a include_list=()
  local -a exclude_list=()
  local -a only_list=()
  local -a profile_required_list=()
  local -a profile_optional_list=()
  local parsed_csv item

  if [[ "${TS_EXPLICIT_INCLUDE}" == "true" ]]; then
    if ! parsed_csv="$(ts_split_csv_strict "${TS_OPT_INCLUDE_RAW}")"; then
      ts_die_usage "Lista invalida em --include / INCLUDE: '${TS_OPT_INCLUDE_RAW}'."
    fi
    mapfile -t include_list <<<"${parsed_csv}"
    ts_validate_component_list "--include / INCLUDE" "${include_list[@]}"
  fi

  if [[ "${TS_EXPLICIT_EXCLUDE}" == "true" ]]; then
    if ! parsed_csv="$(ts_split_csv_strict "${TS_OPT_EXCLUDE_RAW}")"; then
      ts_die_usage "Lista invalida em --exclude / EXCLUDE: '${TS_OPT_EXCLUDE_RAW}'."
    fi
    mapfile -t exclude_list <<<"${parsed_csv}"
    ts_validate_component_list "--exclude / EXCLUDE" "${exclude_list[@]}"
  fi

  if [[ "${TS_EXPLICIT_ONLY}" == "true" ]]; then
    if ! parsed_csv="$(ts_split_csv_strict "${TS_OPT_ONLY_RAW}")"; then
      ts_die_usage "Lista invalida em --only: '${TS_OPT_ONLY_RAW}'."
    fi
    mapfile -t only_list <<<"${parsed_csv}"
    ts_validate_component_list "--only" "${only_list[@]}"
  fi

  # Regra: incluir e excluir o mesmo componente e erro
  for item in "${include_list[@]}"; do
    if ts_list_contains "${item}" "${exclude_list[@]}"; then
      ts_die_usage "Conflito: o componente '${item}' foi simultaneamente incluido e excluido."
    fi
  done

  # Se --vi-mode foi ativado e zsh-vi-mode foi excluido, erro explicito
  if [[ "${TS_OPT_VI_MODE}" == "true" ]] && ts_list_contains "zsh-vi-mode" "${exclude_list[@]}"; then
    ts_die_usage "Conflito: --vi-mode (ou VI_MODE=true) nao pode ser usado quando 'zsh-vi-mode' esta em --exclude."
  fi

  local -A selected_map=()

  if [[ "${TS_EXPLICIT_ONLY}" == "true" ]]; then
    # Modo --only: parte exclusivamente dos itens solicitados (+ zsh-vi-mode se --vi-mode)
    for item in "${only_list[@]}"; do
      if [[ "${TS_OPT_SKIP_GIT}" == "true" ]]; then
        if [[ "${item}" == "git" ]] || ts_list_contains "${item}" "${TS_GIT_PLUGIN_COMPONENTS[@]}"; then
          ts_die_usage "Conflito: o componente '${item}' exigido em --only requer Git, mas --skip-git foi informado."
        fi
      fi
      selected_map["${item}"]=1
    done

    if [[ "${TS_OPT_VI_MODE}" == "true" ]]; then
      if [[ "${TS_OPT_SKIP_GIT}" == "true" ]]; then
        ts_die_usage "Conflito: --vi-mode requer Git para clonar o plugin 'zsh-vi-mode', mas --skip-git foi informado."
      fi
      selected_map["zsh-vi-mode"]=1
    fi

    # Resolver dependencias obrigatorias transitivas dos componentes solicitados em --only
    local changed="true"
    local dep
    while [[ "${changed}" == "true" ]]; do
      changed="false"
      for item in "${TS_KNOWN_COMPONENTS[@]}"; do
        if [[ -n "${selected_map[${item}]:-}" ]]; then
          while IFS= read -r dep; do
            [[ -z "${dep}" ]] && continue
            if [[ "${TS_OPT_SKIP_GIT}" == "true" ]] && [[ "${dep}" == "git" ]]; then
              ts_die_usage "O componente '${item}' selecionado em --only depende de 'git', mas --skip-git esta ativo."
            fi
            if [[ -z "${selected_map[${dep}]:-}" ]]; then
              selected_map["${dep}"]=1
              changed="true"
            fi
          done < <(ts_component_dependencies "${item}")
        fi
      done
    done
  else
    # Modo por perfil: carregar definicao de profiles/<perfil>.conf
    ts_load_profile_file "${TS_OPT_PROFILE}" "${repo_root}"

    if ! parsed_csv="$(ts_split_csv_strict "${TS_PROFILE_VALUES[REQUIRED_COMPONENTS]:-}")"; then
      ts_die "${TS_EXIT_ERR}" "Lista REQUIRED_COMPONENTS invalida no perfil '${TS_OPT_PROFILE}'."
    fi
    mapfile -t profile_required_list <<<"${parsed_csv}"
    ts_validate_component_list "Perfil ${TS_OPT_PROFILE} (REQUIRED_COMPONENTS)" "${profile_required_list[@]}"

    if [[ -n "${TS_PROFILE_VALUES[OPTIONAL_COMPONENTS]:-}" ]]; then
      if ! parsed_csv="$(ts_split_csv_strict "${TS_PROFILE_VALUES[OPTIONAL_COMPONENTS]}")"; then
        ts_die "${TS_EXIT_ERR}" "Lista OPTIONAL_COMPONENTS invalida no perfil '${TS_OPT_PROFILE}'."
      fi
      mapfile -t profile_optional_list <<<"${parsed_csv}"
      ts_validate_component_list "Perfil ${TS_OPT_PROFILE} (OPTIONAL_COMPONENTS)" "${profile_optional_list[@]}"
    fi

    # Validar --skip-git contra itens explicitamente exigidos em --include ou --vi-mode
    if [[ "${TS_OPT_SKIP_GIT}" == "true" ]]; then
      for item in "${include_list[@]}"; do
        if [[ "${item}" == "git" ]] || ts_list_contains "${item}" "${TS_GIT_PLUGIN_COMPONENTS[@]}"; then
          ts_die_usage "Conflito: o componente '${item}' foi exigido em --include, mas depende de Git e --skip-git esta ativo."
        fi
      done
      if [[ "${TS_OPT_VI_MODE}" == "true" ]]; then
        ts_die_usage "Conflito: --vi-mode requer Git para o plugin 'zsh-vi-mode', mas --skip-git esta ativo."
      fi
    fi

    # Validar se --exclude tenta remover componente base obrigatorio
    for item in "${exclude_list[@]}"; do
      if ts_list_contains "${item}" "${TS_BASE_REQUIRED_COMPONENTS[@]}"; then
        ts_die_usage "Nao e permitido excluir o componente base obrigatorio '${item}' via --exclude. Para selecionar apenas itens isolados, use --only."
      fi
      if [[ "${item}" == "git" ]] && [[ "${TS_OPT_SKIP_GIT}" != "true" ]]; then
        ts_die_usage "Para omitir 'git' e seus plugins dependentes, use a flag dedicada --skip-git em vez de '--exclude git'."
      fi
    done

    # Adicionar componentes do perfil (omitindo git e plugins dependentes se --skip-git)
    local -a omitted_by_skip_git=()
    for item in "${profile_required_list[@]}"; do
      if [[ "${TS_OPT_SKIP_GIT}" == "true" ]]; then
        if [[ "${item}" == "git" ]] || ts_list_contains "${item}" "${TS_GIT_PLUGIN_COMPONENTS[@]}"; then
          omitted_by_skip_git+=("${item}")
          continue
        fi
      fi
      selected_map["${item}"]=1
    done

    if [[ "${#omitted_by_skip_git[@]}" -gt 0 ]]; then
      TS_PLAN_WARNINGS+=("Devido a --skip-git, os seguintes componentes do perfil '${TS_OPT_PROFILE}' foram omitidos: ${omitted_by_skip_git[*]}.")
    fi

    # Aplicar --include
    for item in "${include_list[@]}"; do
      selected_map["${item}"]=1
    done

    # Aplicar --vi-mode
    if [[ "${TS_OPT_VI_MODE}" == "true" ]]; then
      selected_map["zsh-vi-mode"]=1
    fi

    # Aplicar --exclude
    for item in "${exclude_list[@]}"; do
      unset "selected_map[${item}]"
    done

    # Verificar se alguma dependencia obrigatoria de componente selecionado foi excluida
    local dep
    for item in "${TS_KNOWN_COMPONENTS[@]}"; do
      if [[ -n "${selected_map[${item}]:-}" ]]; then
        while IFS= read -r dep; do
          [[ -z "${dep}" ]] && continue
          if [[ -z "${selected_map[${dep}]:-}" ]]; then
            ts_die_usage "O componente '${item}' requer '${dep}', que foi excluido ou nao esta disponivel."
          fi
        done < <(ts_component_dependencies "${item}")
      fi
    done
  fi

  # Construir arrays finais na ordem canonica
  local apt_pkg
  for item in "${TS_KNOWN_COMPONENTS[@]}"; do
    if [[ -n "${selected_map[${item}]:-}" ]]; then
      TS_SELECTED_COMPONENTS+=("${item}")
      apt_pkg="$(ts_component_apt_package "${item}")"
      if [[ -n "${apt_pkg}" ]]; then
        TS_SELECTED_APT_PACKAGES+=("${apt_pkg}")
      fi
      case "${item}" in
        starship | superfile)
          TS_SELECTED_EXTERNAL_TOOLS+=("${item}")
          ;;
        zsh-autosuggestions | zsh-history-substring-search | zsh-syntax-highlighting | zsh-vi-mode)
          TS_SELECTED_ZSH_PLUGINS+=("${item}")
          ;;
      esac
      case "${item}" in
        bat)
          TS_SELECTED_LOCAL_LINKS+=("${HOME}/.local/bin/bat -> /usr/bin/batcat (se nao colidir)")
          ;;
        fd)
          TS_SELECTED_LOCAL_LINKS+=("${HOME}/.local/bin/fd -> /usr/bin/fdfind (se nao colidir)")
          ;;
      esac
    fi
  done
}
