#!/usr/bin/env bash
# ==============================================================================
# lib/plugins.sh — Gerenciamento de plugins Zsh via Git com commits fixados
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# Segue estritamente as Secoes 7.1 e 9 do guia e a Decisao P2.
# ==============================================================================

if [[ -n "${TS_PLUGINS_LOADED:-}" ]]; then
  return 0
fi
readonly TS_PLUGINS_LOADED=1

# Valida o arquivo versions/plugins.lock.json via jq
ts_validate_plugins_lock_file() {
  local lock_file="$1"
  ts_require_jq_for_json

  if [[ ! -f "${lock_file}" ]] || [[ ! -r "${lock_file}" ]]; then
    ts_die "${TS_EXIT_ERR}" "Arquivo de lock de plugins nao encontrado ou ilegivel: '${lock_file}'."
  fi

  if ! jq -e '
    type == "object" and
    .schema_version == 1 and
    (.plugins | type == "object") and
    all(.plugins[];
      (.repository | type == "string" and startswith("https://")) and
      (.commit | type == "string" and test("^[0-9a-fA-F]{40}$")) and
      (.entry_file | type == "string" and length > 0)
    )
  ' "${lock_file}" >/dev/null 2>&1; then
    ts_die "${TS_EXIT_ERR}" "Arquivo '${lock_file}' possui JSON malformado ou commit fora do padrao SHA-1 de 40 caracteres."
  fi
}

# Instala ou valida um plugin Zsh em commit fixado no diretorio do usuario
ts_install_single_zsh_plugin() {
  local repo_root="$1"
  local plugin_name="$2"
  local lock_file="${TS_PLUGINS_LOCK_FILE:-${repo_root}/versions/plugins.lock.json}"

  ts_validate_plugins_lock_file "${lock_file}"

  if ! jq -e --arg p "${plugin_name}" '.plugins[$p] != null' "${lock_file}" >/dev/null 2>&1; then
    ts_die "${TS_EXIT_ERR}" "Plugin Zsh '${plugin_name}' nao consta em '${lock_file}'."
  fi

  local repo_url expected_commit entry_file tag_name
  repo_url="$(jq -r --arg p "${plugin_name}" '.plugins[$p].repository' "${lock_file}")"
  expected_commit="$(jq -r --arg p "${plugin_name}" '.plugins[$p].commit' "${lock_file}")"
  entry_file="$(jq -r --arg p "${plugin_name}" '.plugins[$p].entry_file' "${lock_file}")"
  tag_name="$(jq -r --arg p "${plugin_name}" '.plugins[$p].tag' "${lock_file}")"

  # Permitir override de repositorio base apenas para testes locais isolados sem rede
  if [[ -n "${TS_TEST_PLUGIN_REPO_BASE:-}" ]]; then
    repo_url="${TS_TEST_PLUGIN_REPO_BASE}/${plugin_name}.git"
  elif ! ts_validate_https_url "${repo_url}"; then
    ts_die "${TS_EXIT_ERR}" "URL de repositorio invalida para o plugin '${plugin_name}': '${repo_url}'."
  fi

  ts_init_state_paths
  local plugins_base_dir="${TS_DATA_ROOT}/plugins"
  local plugin_dir="${plugins_base_dir}/${plugin_name}"

  if ! ts_validate_managed_path "${plugin_dir}" "false"; then
    ts_die "${TS_EXIT_ERR}" "Caminho de plugin fora do escopo permitido: '${plugin_dir}'."
  fi

  if ! command -v git >/dev/null 2>&1; then
    ts_die "${TS_EXIT_ERR}" "O comando 'git' e obrigatorio para instalar o plugin '${plugin_name}', mas nao esta disponivel."
  fi

  # Verificar se o diretorio do plugin ja existe
  if [[ -L "${plugin_dir}" ]]; then
    ts_die "${TS_EXIT_ERR}" "O caminho do plugin '${plugin_dir}' e um symlink inesperado. Recusando sobrescrever."
  fi

  if [[ -d "${plugin_dir}" ]]; then
    if [[ ! -d "${plugin_dir}/.git" ]]; then
      ts_warn "O diretorio '${plugin_dir}' ja existe mas nao e um repositorio Git; preservando sem alteracao."
      ts_manifest_record_entry \
        "${plugin_dir}" \
        "git_repo" \
        "git_repo" \
        "" \
        "" \
        "" \
        "" \
        "" \
        "kept_existing" \
        "${tag_name}"
      return 0
    fi

    local current_head=""
    current_head="$(git -C "${plugin_dir}" rev-parse HEAD 2>/dev/null || true)"
    if [[ "${current_head,,}" == "${expected_commit,,}" ]]; then
      ts_manifest_record_entry \
        "${plugin_dir}" \
        "git_repo" \
        "git_repo" \
        "${current_head}" \
        "" \
        "" \
        "${current_head}" \
        "" \
        "unchanged" \
        "${tag_name}"
      ts_log_event "INFO" "Plugin Zsh inalterado (idempotente): plugin=${plugin_name} commit=${current_head}"
      return 0
    fi

    # Se o diretorio existe em outro commit, respeitar --on-conflict
    if [[ "${TS_OPT_ON_CONFLICT}" == "keep" ]]; then
      ts_warn "Plugin '${plugin_name}' existente esta no commit '${current_head}' (esperado '${expected_commit}') e foi preservado (politica keep)."
      ts_manifest_record_entry \
        "${plugin_dir}" \
        "git_repo" \
        "git_repo" \
        "${current_head}" \
        "" \
        "" \
        "${current_head}" \
        "" \
        "kept_existing" \
        "${tag_name}"
      return 0
    fi
  fi

  mkdir -p "${plugins_base_dir}"
  local tmp_clone_dir
  tmp_clone_dir="$(mktemp -d "${plugins_base_dir}/.tmp-${plugin_name}.XXXXXX")"

  ts_info "Obtendo plugin Zsh '${plugin_name}' (${tag_name}, commit ${expected_commit:0:12})..."
  if ! (
    cd "${tmp_clone_dir}" &&
    GIT_TERMINAL_PROMPT=0 git init -q &&
    GIT_TERMINAL_PROMPT=0 git remote add origin "${repo_url}" &&
    GIT_TERMINAL_PROMPT=0 git fetch --quiet --depth 1 origin "${expected_commit}" &&
    GIT_TERMINAL_PROMPT=0 git checkout --quiet --detach FETCH_HEAD
  ); then
    rm -rf -- "${tmp_clone_dir}"
    ts_die "${TS_EXIT_ERR}" "Falha ao obter o commit fixado '${expected_commit}' do plugin '${plugin_name}'."
  fi

  local fetched_head=""
  fetched_head="$(git -C "${tmp_clone_dir}" rev-parse HEAD 2>/dev/null || true)"
  if [[ "${fetched_head,,}" != "${expected_commit,,}" ]]; then
    rm -rf -- "${tmp_clone_dir}"
    ts_die "${TS_EXIT_ERR}" \
      "Verificacao de commit falhou para '${plugin_name}': esperado '${expected_commit}', obtido '${fetched_head}'."
  fi

  if [[ ! -f "${tmp_clone_dir}/${entry_file}" ]]; then
    rm -rf -- "${tmp_clone_dir}"
    ts_die "${TS_EXIT_ERR}" \
      "Arquivo de entrada '${entry_file}' nao encontrado no plugin '${plugin_name}' (commit ${expected_commit})."
  fi

  if command -v zsh >/dev/null 2>&1; then
    if ! zsh -n "${tmp_clone_dir}/${entry_file}" >/dev/null 2>&1; then
      rm -rf -- "${tmp_clone_dir}"
      ts_die "${TS_EXIT_ERR}" \
        "Arquivo de entrada '${entry_file}' do plugin '${plugin_name}' falhou na validacao 'zsh -n'."
    fi
  fi

  if [[ -d "${plugin_dir}" ]]; then
    rm -rf -- "${plugin_dir}"
  fi
  mv -Tf -- "${tmp_clone_dir}" "${plugin_dir}"

  ts_manifest_record_entry \
    "${plugin_dir}" \
    "git_repo" \
    "absent" \
    "" \
    "" \
    "" \
    "${fetched_head}" \
    "" \
    "created" \
    "${tag_name}"

  ts_ok "Plugin Zsh '${plugin_name}' instalado no commit fixado ${fetched_head:0:12}."
  ts_log_event "INFO" "Plugin Zsh instalado: plugin=${plugin_name} commit=${fetched_head} path=${plugin_dir}"
}

# Instala todos os plugins Zsh selecionados (respeitando --skip-git)
ts_install_selected_zsh_plugins() {
  local repo_root="$1"
  if [[ "${TS_OPT_SKIP_GIT}" == "true" ]]; then
    ts_log_event "INFO" "Clonagem de plugins Zsh ignorada (--skip-git ativo)."
    return 0
  fi

  if [[ "${#TS_SELECTED_ZSH_PLUGINS[@]}" -eq 0 ]]; then
    return 0
  fi

  local plugin
  for plugin in "${TS_SELECTED_ZSH_PLUGINS[@]}"; do
    ts_install_single_zsh_plugin "${repo_root}" "${plugin}"
  done
}
