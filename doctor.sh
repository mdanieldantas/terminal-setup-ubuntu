#!/usr/bin/env bash
# ==============================================================================
# doctor.sh — Diagnostico somente leitura do ambiente terminal-setup
# Plataforma alvo da v1: Ubuntu 24.04 LTS (amd64)
#
# Regras fundamentais (Secoes 7.3, 8 e 13 do guia):
#   - Estritamente somente leitura: NAO cria diretorios, NAO cria logs, NAO
#     modifica arquivos, NAO repara problemas, NAO usa sudo e NAO usa rede.
#   - Codigos de saida:
#       0 -> sem erros obrigatorios (e sem avisos se --strict estiver ativo)
#       1 -> requisito obrigatorio ou integridade falhou (ou aviso com --strict)
#       2 -> uso invalido de parametros
# ==============================================================================

if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  printf '[ERRO] Este script nao deve ser carregado com "source". Execute: bash ./doctor.sh [opcoes]\n' >&2
  # shellcheck disable=SC2317 # fallback caso return falhe fora de contexto source
  return 2 2>/dev/null || exit 2
fi

set -Eeuo pipefail

ts_resolve_repo_root() {
  local source_path="${BASH_SOURCE[0]}"
  local dir_path
  while [[ -L "${source_path}" ]]; do
    dir_path="$(cd -P "$(dirname "${source_path}")" >/dev/null 2>&1 && pwd)"
    source_path="$(readlink "${source_path}")"
    if [[ "${source_path}" != /* ]]; then
      source_path="${dir_path}/${source_path}"
    fi
  done
  cd -P "$(dirname "${source_path}")" >/dev/null 2>&1 && pwd
}

TS_REPO_ROOT="$(ts_resolve_repo_root)"
readonly TS_REPO_ROOT

# shellcheck source=lib/common.sh
source "${TS_REPO_ROOT}/lib/common.sh"
# shellcheck source=lib/platform.sh
source "${TS_REPO_ROOT}/lib/platform.sh"
# shellcheck source=lib/config-parser.sh
source "${TS_REPO_ROOT}/lib/config-parser.sh"
# shellcheck source=lib/arguments.sh
source "${TS_REPO_ROOT}/lib/arguments.sh"
# shellcheck source=lib/backups.sh
source "${TS_REPO_ROOT}/lib/backups.sh"
# shellcheck source=lib/manifest.sh
source "${TS_REPO_ROOT}/lib/manifest.sh"

DOCTOR_PROFILE="minimal"
DOCTOR_JSON="false"
DOCTOR_STRICT="false"

doctor_print_help() {
  cat <<'EOF'
Uso:
  bash ./doctor.sh [opcoes]

Descricao:
  Executa diagnostico somente leitura do ambiente terminal-setup.
  Nao cria logs, nao altera arquivos, nao usa sudo e nao faz chamadas de rede.

Opcoes:
  -h, --help                     Exibe esta ajuda sem realizar alteracoes.
  --profile <minimal|developer|server>
                                 Perfil de referencia para avaliar componentes
                                 obrigatorios e opcionais (padrao: minimal).
  --json                         Emite relatorio em JSON limpo (requer jq).
  --strict                       Trata avisos (warnings) como falha (codigo 1).

Codigos de saida:
  0  Nenhum erro obrigatorio encontrado.
  1  Requisito obrigatorio ausente, falha de sintaxe/integridade (ou aviso com --strict).
  2  Parametro invalido.
EOF
}

doctor_parse_args() {
  local arg opt_name opt_val
  while [[ $# -gt 0 ]]; do
    arg="$1"
    if [[ "${arg}" == --*=* ]]; then
      opt_name="${arg%%=*}"
      opt_val="${arg#*=}"
      if [[ -z "${opt_val}" ]]; then
        ts_die_usage "O parametro '${opt_name}' exige um valor nao vazio."
      fi
      case "${opt_name}" in
        --profile)
          DOCTOR_PROFILE="${opt_val}"
          ;;
        --help | --json | --strict)
          ts_die_usage "O parametro '${opt_name}' nao aceita valor ('${arg}')."
          ;;
        *)
          ts_die_usage "Parametro desconhecido em doctor.sh: '${opt_name}'."
          ;;
      esac
      shift
      continue
    fi

    case "${arg}" in
      -h | --help)
        doctor_print_help
        exit "${TS_EXIT_OK}"
        ;;
      --profile)
        if [[ $# -lt 2 ]] || [[ -z "${2:-}" ]]; then
          ts_die_usage "O parametro '--profile' exige um valor (minimal, developer ou server)."
        fi
        DOCTOR_PROFILE="$2"
        shift 2
        ;;
      --json)
        DOCTOR_JSON="true"
        shift
        ;;
      --strict)
        DOCTOR_STRICT="true"
        shift
        ;;
      -*)
        ts_die_usage "Parametro desconhecido em doctor.sh: '${arg}'."
        ;;
      *)
        ts_die_usage "Argumento posicional inesperado em doctor.sh: '${arg}'."
        ;;
    esac
  done

  ts_validate_enum "--profile" "${DOCTOR_PROFILE}" "${TS_VALID_PROFILES[@]}"
}

# Estruturas em memoria para os checks
declare -ga DOCTOR_CHECKS_CATEGORY=()
declare -ga DOCTOR_CHECKS_NAME=()
declare -ga DOCTOR_CHECKS_STATUS=()
declare -ga DOCTOR_CHECKS_DETAIL=()

DOCTOR_OK_COUNT=0
DOCTOR_WARN_COUNT=0
DOCTOR_ERR_COUNT=0

doctor_record_check() {
  local category="$1"
  local name="$2"
  local status="$3"
  local detail="$4"

  DOCTOR_CHECKS_CATEGORY+=("${category}")
  DOCTOR_CHECKS_NAME+=("${name}")
  DOCTOR_CHECKS_STATUS+=("${status}")
  DOCTOR_CHECKS_DETAIL+=("${detail}")

  case "${status}" in
    ok) DOCTOR_OK_COUNT=$((DOCTOR_OK_COUNT + 1)) ;;
    warn) DOCTOR_WARN_COUNT=$((DOCTOR_WARN_COUNT + 1)) ;;
    error) DOCTOR_ERR_COUNT=$((DOCTOR_ERR_COUNT + 1)) ;;
  esac
}

# Verifica disponibilidade e versao de um comando para um componente
doctor_check_component_tool() {
  local comp="$1"
  local requirement_level="$2" # required | optional
  local fail_status="error"
  if [[ "${requirement_level}" == "optional" ]]; then
    fail_status="warn"
  fi

  case "${comp}" in
    ca-certificates)
      if [[ -d /etc/ssl/certs ]] && [[ -n "$(ls -A /etc/ssl/certs 2>/dev/null || true)" ]]; then
        doctor_record_check "component" "ca-certificates" "ok" "Diretorio /etc/ssl/certs presente e populado"
      else
        doctor_record_check "component" "ca-certificates" "${fail_status}" "Certificados TLS ausentes em /etc/ssl/certs"
      fi
      ;;
    bat)
      if command -v bat >/dev/null 2>&1; then
        doctor_record_check "component" "bat" "ok" "Comando 'bat' disponivel em $(command -v bat)"
      elif [[ -x "${HOME}/.local/bin/bat" ]]; then
        doctor_record_check "component" "bat" "ok" "Link 'bat' disponivel em ${HOME}/.local/bin/bat (ativo no Zsh via .zshenv)"
      elif command -v batcat >/dev/null 2>&1; then
        doctor_record_check "component" "bat" "ok" "Comando Ubuntu 'batcat' disponivel em $(command -v batcat)"
      else
        doctor_record_check "component" "bat" "${fail_status}" "Nem 'bat' nem 'batcat' foram encontrados no PATH"
      fi
      ;;
    fd)
      if command -v fd >/dev/null 2>&1; then
        doctor_record_check "component" "fd" "ok" "Comando 'fd' disponivel em $(command -v fd)"
      elif [[ -x "${HOME}/.local/bin/fd" ]]; then
        doctor_record_check "component" "fd" "ok" "Link 'fd' disponivel em ${HOME}/.local/bin/fd (ativo no Zsh via .zshenv)"
      elif command -v fdfind >/dev/null 2>&1; then
        doctor_record_check "component" "fd" "ok" "Comando Ubuntu 'fdfind' disponivel em $(command -v fdfind)"
      else
        doctor_record_check "component" "fd" "${fail_status}" "Nem 'fd' nem 'fdfind' foram encontrados no PATH"
      fi
      ;;
    ripgrep)
      if command -v rg >/dev/null 2>&1; then
        doctor_record_check "component" "ripgrep" "ok" "Comando 'rg' disponivel em $(command -v rg)"
      else
        doctor_record_check "component" "ripgrep" "${fail_status}" "Comando 'rg' (ripgrep) ausente no PATH"
      fi
      ;;
    superfile)
      if command -v spf >/dev/null 2>&1; then
        doctor_record_check "component" "superfile" "ok" "Comando 'spf' disponivel em $(command -v spf)"
      elif [[ -x "${HOME}/.local/bin/spf" ]]; then
        doctor_record_check "component" "superfile" "ok" "Binario 'spf' instalado em ${HOME}/.local/bin/spf (ativo no Zsh via .zshenv)"
      else
        doctor_record_check "component" "superfile" "${fail_status}" "Comando 'spf' (Superfile) ausente no PATH"
      fi
      ;;
    zsh-autosuggestions | zsh-history-substring-search | zsh-syntax-highlighting | zsh-vi-mode)
      local plugin_dir="${TS_XDG_DATA_HOME}/${TS_PROJECT_NAME}/plugins/${comp}"
      if [[ -d "${plugin_dir}" ]]; then
        local commit_sha="desconhecido"
        if command -v git >/dev/null 2>&1 && [[ -d "${plugin_dir}/.git" ]]; then
          commit_sha="$(git -C "${plugin_dir}" rev-parse HEAD 2>/dev/null || printf 'desconhecido')"
        fi
        doctor_record_check "plugin" "${comp}" "ok" "Instalado em ${plugin_dir} (commit: ${commit_sha})"
      else
        doctor_record_check "plugin" "${comp}" "${fail_status}" "Plugin '${comp}' ausente em ${plugin_dir}"
      fi
      ;;
    *)
      if command -v "${comp}" >/dev/null 2>&1; then
        doctor_record_check "component" "${comp}" "ok" "Comando '${comp}' disponivel em $(command -v "${comp}")"
      elif [[ -x "${HOME}/.local/bin/${comp}" ]]; then
        doctor_record_check "component" "${comp}" "ok" "Binario '${comp}' instalado em ${HOME}/.local/bin/${comp} (ativo no Zsh via .zshenv)"
      else
        doctor_record_check "component" "${comp}" "${fail_status}" "Comando '${comp}' (${requirement_level}) ausente no PATH"
      fi
      ;;
  esac
}

main() {
  doctor_parse_args "$@"

  if [[ "${DOCTOR_JSON}" == "true" ]]; then
    ts_require_jq_for_json
  fi

  ts_detect_platform
  ts_init_state_paths

  # 1. Plataforma e usuario
  if [[ "${TS_IS_SUPPORTED_PLATFORM}" == "true" ]]; then
    doctor_record_check "platform" "os_arch" "ok" "${TS_PLATFORM_NOTE}"
  else
    doctor_record_check "platform" "os_arch" "warn" "${TS_PLATFORM_NOTE}"
  fi

  if [[ "${TS_EFFECTIVE_UID}" -eq 0 ]]; then
    doctor_record_check "platform" "user_privilege" "warn" "Executando diagnostico como root (UID 0); o ambiente alvo e de usuario comum"
  else
    doctor_record_check "platform" "user_privilege" "ok" "Usuario comum '${TS_EFFECTIVE_USER}' (UID ${TS_EFFECTIVE_UID})"
  fi

  # 2. PATH e ~/.local/bin
  case ":${PATH:-}:" in
    *":${HOME}/.local/bin:"*)
      doctor_record_check "environment" "path_local_bin" "ok" "${HOME}/.local/bin esta presente no PATH atual"
      ;;
    *)
      doctor_record_check "environment" "path_local_bin" "warn" "${HOME}/.local/bin nao esta no PATH do processo atual (sera adicionado pelo .zshenv no Zsh)"
      ;;
  esac

  # 3. Shell registrado vs variavel SHELL vs processo atual (Secao 13)
  local passwd_shell="desconhecido"
  if [[ -r /etc/passwd ]]; then
    passwd_shell="$(awk -F: -v u="${TS_EFFECTIVE_USER}" '$1 == u {print $7; exit}' /etc/passwd 2>/dev/null || true)"
    [[ -z "${passwd_shell}" ]] && passwd_shell="nao-encontrado-em-/etc/passwd"
  fi
  local env_shell="${SHELL:-nao-definido}"
  doctor_record_check "shell" "registered_and_env_shell" "ok" "Shell registrado em /etc/passwd: '${passwd_shell}'; variavel SHELL: '${env_shell}' (fatos separados do interpretador em execucao)"

  # 4. Carregar perfil selecionado e verificar componentes obrigatorios e opcionais
  ts_load_profile_file "${DOCTOR_PROFILE}" "${TS_REPO_ROOT}"
  local -a req_comps=()
  local -a opt_comps=()
  local parsed_csv comp
  parsed_csv="$(ts_split_csv_strict "${TS_PROFILE_VALUES[REQUIRED_COMPONENTS]}")"
  mapfile -t req_comps <<<"${parsed_csv}"
  if [[ -n "${TS_PROFILE_VALUES[OPTIONAL_COMPONENTS]:-}" ]]; then
    parsed_csv="$(ts_split_csv_strict "${TS_PROFILE_VALUES[OPTIONAL_COMPONENTS]}")"
    mapfile -t opt_comps <<<"${parsed_csv}"
  fi

  for comp in "${req_comps[@]}"; do
    doctor_check_component_tool "${comp}" "required"
  done
  for comp in "${opt_comps[@]}"; do
    doctor_check_component_tool "${comp}" "optional"
  done

  # 5. Verificar presenca e sintaxe individual de cada arquivo Zsh instalado
  local zdotdir_target="${HOME}"
  if [[ "${TS_ZDOTDIR_STATUS}" == "custom" ]] && [[ -n "${TS_ZDOTDIR_VALUE}" ]]; then
    zdotdir_target="${TS_ZDOTDIR_VALUE}"
  fi

  local -a expected_zsh_files=(
    "${zdotdir_target}/.zshenv"
    "${zdotdir_target}/.zshrc"
    "${TS_CONFIG_ROOT}/zsh/options.zsh"
    "${TS_CONFIG_ROOT}/zsh/aliases.zsh"
    "${TS_CONFIG_ROOT}/zsh/bindings.zsh"
    "${TS_CONFIG_ROOT}/zsh/containers.zsh"
    "${TS_CONFIG_ROOT}/zsh/database.zsh"
    "${TS_CONFIG_ROOT}/zsh/fzf.zsh"
    "${TS_CONFIG_ROOT}/zsh/git.zsh"
    "${TS_CONFIG_ROOT}/zsh/plugins.zsh"
    "${TS_CONFIG_ROOT}/zsh/prompt.zsh"
  )

  local has_zsh_bin="false"
  if command -v zsh >/dev/null 2>&1; then
    has_zsh_bin="true"
  fi

  local zf
  for zf in "${expected_zsh_files[@]}"; do
    if [[ ! -e "${zf}" ]] && [[ ! -L "${zf}" ]]; then
      doctor_record_check "config_zsh" "${zf}" "error" "Arquivo Zsh esperado nao encontrado: ${zf}"
    elif [[ ! -r "${zf}" ]]; then
      doctor_record_check "config_zsh" "${zf}" "error" "Arquivo Zsh sem permissao de leitura: ${zf}"
    elif [[ "${has_zsh_bin}" == "true" ]]; then
      if zsh -n "${zf}" >/dev/null 2>&1; then
        doctor_record_check "config_zsh" "${zf}" "ok" "Arquivo presente e aprovado em 'zsh -n' individual"
      else
        doctor_record_check "config_zsh" "${zf}" "error" "Falha de sintaxe em 'zsh -n' no arquivo: ${zf}"
      fi
    else
      doctor_record_check "config_zsh" "${zf}" "warn" "Arquivo presente, mas 'zsh' nao esta disponivel para validar 'zsh -n'"
    fi
  done

  # 6. Verificar configuracao do Starship e tmux conforme o perfil
  if ts_list_contains "starship" "${req_comps[@]}"; then
    if [[ -r "${TS_XDG_CONFIG_HOME}/starship.toml" ]]; then
      doctor_record_check "config_tool" "${TS_XDG_CONFIG_HOME}/starship.toml" "ok" "Configuracao do Starship presente"
    else
      doctor_record_check "config_tool" "${TS_XDG_CONFIG_HOME}/starship.toml" "error" "Configuracao do Starship ausente"
    fi
  fi

  if ts_list_contains "tmux" "${req_comps[@]}"; then
    if [[ -r "${TS_XDG_CONFIG_HOME}/tmux/tmux.conf" ]]; then
      doctor_record_check "config_tool" "${TS_XDG_CONFIG_HOME}/tmux/tmux.conf" "ok" "Configuracao do tmux presente"
    else
      doctor_record_check "config_tool" "${TS_XDG_CONFIG_HOME}/tmux/tmux.conf" "error" "Configuracao do tmux ausente"
    fi
  fi

  # 7. Verificar manifesto mais recente e integridade dos arquivos gerenciados (Secao 13)
  local latest_manifest=""
  if latest_manifest="$(ts_find_manifest_file "")"; then
    if [[ "${TS_HAS_JQ}" == "true" ]]; then
      if ts_validate_manifest_file "${latest_manifest}" 2>/dev/null; then
        doctor_record_check "manifest" "${latest_manifest}" "ok" "Manifesto mais recente valido"
        while ts_manifest_read_entry_nul; do
          [[ "${TS_ME_ACTION}" == "kept_existing" ]] && continue
          if [[ "${TS_ME_RESOURCE_TYPE}" == "file" ]]; then
            local cur_sha=""
            if cur_sha="$(ts_sha256_file "${TS_ME_PATH}" 2>/dev/null)"; then
              if [[ "${TS_ME_HAS_INST_SHA}" == "1" ]] && [[ "${cur_sha}" == "${TS_ME_INST_SHA}" ]]; then
                doctor_record_check "integrity" "${TS_ME_PATH}" "ok" "Integridade SHA-256 confirmada conforme o manifesto"
              else
                doctor_record_check "integrity" "${TS_ME_PATH}" "warn" "Arquivo foi modificado apos a instalacao (SHA-256 diverge do manifesto)"
              fi
            else
              doctor_record_check "integrity" "${TS_ME_PATH}" "error" "Arquivo registrado no manifesto esta ausente ou ilegivel"
            fi
          elif [[ "${TS_ME_RESOURCE_TYPE}" == "symlink" ]]; then
            if [[ -L "${TS_ME_PATH}" ]]; then
              local cur_link
              cur_link="$(readlink "${TS_ME_PATH}")"
              if [[ "${TS_ME_HAS_INST_LINK}" == "1" ]] && [[ "${cur_link}" == "${TS_ME_INST_LINK}" ]]; then
                doctor_record_check "integrity" "${TS_ME_PATH}" "ok" "Symlink gerenciado integro (-> ${cur_link})"
              else
                doctor_record_check "integrity" "${TS_ME_PATH}" "warn" "Symlink gerenciado aponta para '${cur_link}' (esperado '${TS_ME_INST_LINK}')"
              fi
            else
              doctor_record_check "integrity" "${TS_ME_PATH}" "error" "Symlink registrado no manifesto esta ausente"
            fi
          elif [[ "${TS_ME_RESOURCE_TYPE}" == "git_repo" ]]; then
            if [[ -d "${TS_ME_PATH}/.git" ]] && command -v git >/dev/null 2>&1; then
              local cur_commit
              cur_commit="$(git -C "${TS_ME_PATH}" rev-parse HEAD 2>/dev/null || printf '')"
              if [[ "${TS_ME_HAS_INST_SHA}" == "1" ]] && [[ "${cur_commit}" == "${TS_ME_INST_SHA}" ]]; then
                doctor_record_check "integrity" "${TS_ME_PATH}" "ok" "Plugin Git no commit esperado (${cur_commit})"
              else
                doctor_record_check "integrity" "${TS_ME_PATH}" "warn" "Plugin Git em commit diferente do manifesto (${cur_commit:-desconhecido})"
              fi
            else
              doctor_record_check "integrity" "${TS_ME_PATH}" "error" "Diretorio de plugin Git ausente: ${TS_ME_PATH}"
            fi
          fi
        done < <(ts_manifest_stream_entries_nul "${latest_manifest}" "false")
      else
        doctor_record_check "manifest" "${latest_manifest}" "error" "Manifesto mais recente falhou na validacao de schema ou seguranca"
      fi
    else
      doctor_record_check "manifest" "${latest_manifest}" "error" "Utilitario 'jq' ausente; impossivel validar integridade do manifesto JSON"
    fi
  else
    doctor_record_check "manifest" "latest" "warn" "Nenhum manifesto de instalacao encontrado em ${TS_MANIFESTS_DIR}"
  fi

  # Determinar codigo de saida final (Secao 13)
  local final_exit="${TS_EXIT_OK}"
  if [[ "${DOCTOR_ERR_COUNT}" -gt 0 ]]; then
    final_exit="${TS_EXIT_ERR}"
  elif [[ "${DOCTOR_STRICT}" == "true" ]] && [[ "${DOCTOR_WARN_COUNT}" -gt 0 ]]; then
    final_exit="${TS_EXIT_ERR}"
  fi

  # Emitir saida em JSON (via jq) ou texto humano em PT-BR
  if [[ "${DOCTOR_JSON}" == "true" ]]; then
    local checks_json="[]"
    local i=0
    local total="${#DOCTOR_CHECKS_NAME[@]}"
    local tmp_lines=""
    while [[ "${i}" -lt "${total}" ]]; do
      tmp_lines+=$(jq -nc \
        --arg category "${DOCTOR_CHECKS_CATEGORY[$i]}" \
        --arg name "${DOCTOR_CHECKS_NAME[$i]}" \
        --arg status "${DOCTOR_CHECKS_STATUS[$i]}" \
        --arg detail "${DOCTOR_CHECKS_DETAIL[$i]}" \
        '{category: $category, name: $name, status: $status, detail: $detail}')$'\n'
      i=$((i + 1))
    done
    if [[ -n "${tmp_lines}" ]]; then
      checks_json="$(printf '%s' "${tmp_lines}" | jq -s '.')"
    fi

    jq -n \
      --arg project "${TS_PROJECT_NAME}" \
      --arg version "${TS_PROJECT_VERSION}" \
      --arg profile "${DOCTOR_PROFILE}" \
      --argjson strict "${DOCTOR_STRICT}" \
      --arg os_id "${TS_OS_ID}" \
      --arg os_version "${TS_OS_VERSION_ID}" \
      --arg arch "${TS_NORM_ARCH}" \
      --arg user "${TS_EFFECTIVE_USER}" \
      --argjson uid "${TS_EFFECTIVE_UID}" \
      --arg home "${HOME}" \
      --arg zdotdir "${zdotdir_target}" \
      --arg passwd_shell "${passwd_shell}" \
      --arg env_shell "${env_shell}" \
      --argjson ok_count "${DOCTOR_OK_COUNT}" \
      --argjson warn_count "${DOCTOR_WARN_COUNT}" \
      --argjson error_count "${DOCTOR_ERR_COUNT}" \
      --argjson exit_code "${final_exit}" \
      --argjson checks "${checks_json}" \
      '{
        project: $project,
        version: $version,
        profile: $profile,
        strict: $strict,
        platform: {
          os_id: $os_id,
          os_version: $os_version,
          arch: $arch,
          user: $user,
          uid: $uid,
          home: $home,
          zdotdir: $zdotdir,
          passwd_shell: $passwd_shell,
          env_shell: $env_shell
        },
        summary: {
          ok: $ok_count,
          warnings: $warn_count,
          errors: $error_count,
          exit_code: $exit_code
        },
        checks: $checks
      }'
  else
    printf '%s======================================================================%s\n' "${TS_COLOR_BOLD}" "${TS_COLOR_RESET}"
    printf '%sDiagnostico somente leitura — %s (%s) — perfil: %s%s\n' \
      "${TS_COLOR_BOLD}" "${TS_PROJECT_NAME}" "${TS_PROJECT_VERSION}" "${DOCTOR_PROFILE}" "${TS_COLOR_RESET}"
    printf '%s======================================================================%s\n\n' "${TS_COLOR_BOLD}" "${TS_COLOR_RESET}"

    local idx=0
    local count="${#DOCTOR_CHECKS_NAME[@]}"
    while [[ "${idx}" -lt "${count}" ]]; do
      local st="${DOCTOR_CHECKS_STATUS[$idx]}"
      local cat_name="${DOCTOR_CHECKS_CATEGORY[$idx]}"
      local item_name="${DOCTOR_CHECKS_NAME[$idx]}"
      local det="${DOCTOR_CHECKS_DETAIL[$idx]}"
      case "${st}" in
        ok)
          printf '%s[OK]%s    (%s) %s — %s\n' "${TS_COLOR_OK}" "${TS_COLOR_RESET}" "${cat_name}" "${item_name}" "${det}"
          ;;
        warn)
          printf '%s[AVISO]%s (%s) %s — %s\n' "${TS_COLOR_WARN}" "${TS_COLOR_RESET}" "${cat_name}" "${item_name}" "${det}"
          ;;
        error)
          printf '%s[ERRO]%s  (%s) %s — %s\n' "${TS_COLOR_ERR}" "${TS_COLOR_RESET}" "${cat_name}" "${item_name}" "${det}"
          ;;
      esac
      idx=$((idx + 1))
    done

    printf '\nResumo: %d OK, %d aviso(s), %d erro(s) (modo strict: %s, codigo de saida: %d).\n' \
      "${DOCTOR_OK_COUNT}" "${DOCTOR_WARN_COUNT}" "${DOCTOR_ERR_COUNT}" "${DOCTOR_STRICT}" "${final_exit}"
  fi

  exit "${final_exit}"
}

main "$@"
