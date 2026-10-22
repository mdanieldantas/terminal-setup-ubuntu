#!/usr/bin/env bash
# ==============================================================================
# lib/config-parser.sh — Parser restrito de pares CHAVE=valor (sem source/eval)
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# Segue estritamente as Secoes 2 e 7.2 do guia de implementacao.
# ==============================================================================

if [[ -n "${TS_CONFIG_PARSER_LOADED:-}" ]]; then
  return 0
fi
readonly TS_CONFIG_PARSER_LOADED=1

# Chaves permitidas em terminal.conf (Secao 7.2)
readonly -a TS_ALLOWED_USER_CONFIG_KEYS=(
  "PROFILE"
  "ICONS"
  "GIT_IDENTITY"
  "GIT_NAME"
  "GIT_EMAIL"
  "GIT_DEFAULTS"
  "CHANGE_SHELL"
  "ON_CONFLICT"
  "VI_MODE"
  "INCLUDE"
  "EXCLUDE"
)

# Chaves permitidas nos arquivos internos profiles/*.conf
readonly -a TS_ALLOWED_PROFILE_KEYS=(
  "PROFILE_NAME"
  "PROFILE_DESCRIPTION"
  "REQUIRED_COMPONENTS"
  "OPTIONAL_COMPONENTS"
  "DEFAULT_ICONS"
  "DEFAULT_VI_MODE"
)

# Associative arrays preenchidos pelos parsers
declare -gA TS_CONFIG_VALUES=()
declare -gA TS_PROFILE_VALUES=()

# Verifica se um arquivo contem byte NUL (0x00) sem executar codigo externo perigoso
ts_file_has_nul_byte() {
  local filepath="$1"
  local file_size char_count
  file_size="$(wc -c < "${filepath}" 2>/dev/null | tr -d '[:space:]')"
  char_count="$(LC_ALL=C tr -d '\000' < "${filepath}" 2>/dev/null | wc -c | tr -d '[:space:]')"
  if [[ "${file_size}" != "${char_count}" ]]; then
    return 0
  fi
  return 1
}

# Rejeita caracteres ou construcoes de expansao de shell onde nao sao permitidos
ts_reject_shell_expansion_syntax() {
  local value="$1"
  local context_label="$2"
  if [[ "${value}" == *'$('* ]] || [[ "${value}" == *'`'* ]] || [[ "${value}" == *'${'* ]]; then
    ts_die_usage "${context_label}: sintaxe de expansao ou substituicao de shell nao e permitida ('${value}')."
  fi
}

# Parser generico seguro para arquivos CHAVE=valor
# Uso: ts_parse_kv_file <caminho> <modo: user|profile>
ts_parse_kv_file() {
  local filepath="$1"
  local mode="$2"

  if [[ -z "${filepath}" ]]; then
    ts_die_usage "Caminho de arquivo de configuracao vazio."
  fi
  if [[ ! -e "${filepath}" ]]; then
    ts_die_usage "Arquivo de configuracao nao encontrado: '${filepath}'."
  fi
  if [[ -d "${filepath}" ]]; then
    ts_die_usage "O caminho informado para configuracao e um diretorio, nao um arquivo: '${filepath}'."
  fi
  if [[ ! -r "${filepath}" ]]; then
    ts_die_usage "Arquivo de configuracao sem permissao de leitura: '${filepath}'."
  fi
  if ts_file_has_nul_byte "${filepath}"; then
    ts_die_usage "Arquivo '${filepath}' contem byte NUL invalido e foi rejeitado."
  fi

  local -A seen_keys=()
  local line_num=0
  local raw_line line key value trimmed_check

  while IFS= read -r raw_line || [[ -n "${raw_line}" ]]; do
    line_num=$((line_num + 1))
    # Remove CR final caso o arquivo tenha sido editado no Windows
    line="${raw_line%$'\r'}"

    # Linhas vazias ou apenas espacos
    trimmed_check="$(ts_trim "${line}")"
    if [[ -z "${trimmed_check}" ]]; then
      continue
    fi

    # Comentarios em linha propria iniciados por '#'
    if [[ "${trimmed_check}" == \#* ]]; then
      continue
    fi

    # Rejeitar caracteres de controle na linha
    if ts_has_control_chars "${line}"; then
      ts_die_usage "Arquivo '${filepath}' (linha ${line_num}): contem caracteres de controle invalidos."
    fi

    # Deve conter '='
    if [[ "${line}" != *"="* ]]; then
      ts_die_usage "Arquivo '${filepath}' (linha ${line_num}): formato invalido (esperado CHAVE=valor)."
    fi

    # Separar no primeiro '='
    key="${line%%=*}"
    value="${line#*=}"

    # Chave nao pode ter espacos nas pontas nem caracteres fora de [A-Z0-9_]
    if [[ -z "${key}" ]] || [[ ! "${key}" =~ ^[A-Z][A-Z0-9_]*$ ]]; then
      ts_die_usage "Arquivo '${filepath}' (linha ${line_num}): nome de chave invalido '${key}'."
    fi

    # Validar lista de chaves permitidas conforme o modo
    if [[ "${mode}" == "user" ]]; then
      if ! ts_list_contains "${key}" "${TS_ALLOWED_USER_CONFIG_KEYS[@]}"; then
        ts_die_usage "Arquivo '${filepath}' (linha ${line_num}): chave desconhecida ou nao permitida '${key}'."
      fi
    elif [[ "${mode}" == "profile" ]]; then
      if ! ts_list_contains "${key}" "${TS_ALLOWED_PROFILE_KEYS[@]}"; then
        ts_die "${TS_EXIT_ERR}" "Arquivo de perfil '${filepath}' (linha ${line_num}): chave desconhecida '${key}'."
      fi
    else
      ts_die "${TS_EXIT_ERR}" "Modo interno invalido em ts_parse_kv_file: '${mode}'."
    fi

    # Rejeitar chaves duplicadas (Secao 7.2)
    if [[ -n "${seen_keys[${key}]:-}" ]]; then
      ts_die_usage "Arquivo '${filepath}' (linha ${line_num}): chave duplicada '${key}' (ja definida na linha ${seen_keys[${key}]})."
    fi
    seen_keys["${key}"]="${line_num}"

    # Regra documentada de preservacao de espacos e proibicao de aspas/expansao:
    # - Para GIT_NAME e PROFILE_DESCRIPTION: removemos espacos apenas nas extremidades e preservamos espacos internos;
    #   rejeitamos substituicao de comando, crases, ponto-e-virgula ou pipe.
    # - Para as demais chaves: nao podem conter espacos nem metacaracteres de shell.
    if [[ "${mode}" == "user" ]]; then
      ts_reject_shell_expansion_syntax "${value}" "Arquivo '${filepath}' (linha ${line_num}, chave ${key})"
      if [[ "${value}" == \"*\" ]] || [[ "${value}" == \'*\' ]]; then
        ts_die_usage "Arquivo '${filepath}' (linha ${line_num}, chave ${key}): nao use aspas de shell ao redor do valor; informe o texto literal."
      fi
      if [[ "${key}" == "GIT_NAME" ]]; then
        value="$(ts_trim "${value}")"
        if [[ "${value}" == *";"* ]] || [[ "${value}" == *"|"* ]] || [[ "${value}" == *"&"* ]]; then
          ts_die_usage "Arquivo '${filepath}' (linha ${line_num}, chave GIT_NAME): caracteres de encadeamento de shell nao permitidos."
        fi
      else
        if [[ "${value}" =~ [[:space:]] ]]; then
          ts_die_usage "Arquivo '${filepath}' (linha ${line_num}, chave ${key}): espacos em branco ou comentarios na mesma linha nao sao permitidos no valor '${value}'."
        fi
      fi
      TS_CONFIG_VALUES["${key}"]="${value}"
    else
      TS_PROFILE_VALUES["${key}"]="${value}"
    fi
  done < "${filepath}"
}

# Carrega e valida um arquivo terminal.conf explicitamente indicado via --config
ts_load_user_config_file() {
  local filepath="$1"
  TS_CONFIG_VALUES=()
  ts_parse_kv_file "${filepath}" "user"
}

# Carrega um arquivo de perfil interno (profiles/<nome>.conf)
ts_load_profile_file() {
  local profile_name="$1"
  local repo_root="$2"
  local profile_path="${repo_root}/profiles/${profile_name}.conf"

  if [[ ! -r "${profile_path}" ]]; then
    ts_die_usage "Arquivo de perfil nao encontrado para '${profile_name}': '${profile_path}'."
  fi

  TS_PROFILE_VALUES=()
  ts_parse_kv_file "${profile_path}" "profile"

  if [[ "${TS_PROFILE_VALUES[PROFILE_NAME]:-}" != "${profile_name}" ]]; then
    ts_die "${TS_EXIT_ERR}" "Inconsistencia no perfil '${profile_path}': PROFILE_NAME='${TS_PROFILE_VALUES[PROFILE_NAME]:-}'."
  fi
}

