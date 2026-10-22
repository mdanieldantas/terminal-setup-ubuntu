#!/usr/bin/env bash
# ==============================================================================
# lib/tools.sh — Instalacao verificada de ferramentas externas (Starship/Superfile)
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# Segue estritamente a Secao 9 do guia de implementacao.
# ==============================================================================

if [[ -n "${TS_TOOLS_LOADED:-}" ]]; then
  return 0
fi
readonly TS_TOOLS_LOADED=1

# Valida a estrutura basica de versions/tools.lock.json via jq
ts_validate_tools_lock_file() {
  local lock_file="$1"
  ts_require_jq_for_json

  if [[ ! -f "${lock_file}" ]] || [[ ! -r "${lock_file}" ]]; then
    ts_die "${TS_EXIT_ERR}" "Arquivo de lock de ferramentas nao encontrado ou ilegivel: '${lock_file}'."
  fi

  if ! jq -e '
    type == "object" and
    .schema_version == 1 and
    (.tools | type == "object") and
    all(.tools[];
      (.version | type == "string" and length > 0 and . != "latest") and
      (.command | type == "string" and length > 0) and
      (.artifacts | type == "object")
    )
  ' "${lock_file}" >/dev/null 2>&1; then
    ts_die "${TS_EXIT_ERR}" "Arquivo '${lock_file}' possui JSON malformado, schema invalido ou versao 'latest' proibida."
  fi
}

# Garante ~/.local/bin na frente do PATH antes de verificar ferramentas recem-instaladas (Secao 9)
ts_ensure_local_bin_in_path() {
  mkdir -p "${HOME}/.local/bin"
  case ":${PATH:-}:" in
    *":${HOME}/.local/bin:"*) ;;
    *)
      export PATH="${HOME}/.local/bin${PATH:+:${PATH}}"
      ;;
  esac
}

# Instala uma ferramenta externa descrita em versions/tools.lock.json
ts_install_single_external_tool() {
  local repo_root="$1"
  local tool_name="$2"
  local lock_file="${repo_root}/versions/tools.lock.json"
  if [[ "${TS_TEST_SANDBOX_MODE:-0}" == "1" ]] \
    && ts_is_effective_tmp_path "${TS_TEST_TOOLS_LOCK_FILE:-}"; then
    lock_file="${TS_TEST_TOOLS_LOCK_FILE}"
  fi

  ts_validate_tools_lock_file "${lock_file}"

  if ! jq -e --arg t "${tool_name}" '.tools[$t] != null' "${lock_file}" >/dev/null 2>&1; then
    ts_die "${TS_EXIT_ERR}" "Ferramenta externa '${tool_name}' nao consta em '${lock_file}'."
  fi

  # Validar disponibilidade de artefato para a arquitetura atual (ex.: amd64)
  if ! jq -e --arg t "${tool_name}" --arg a "${TS_NORM_ARCH}" '.tools[$t].artifacts[$a] != null' "${lock_file}" >/dev/null 2>&1; then
    ts_die "${TS_EXIT_PLATFORM}" \
      "A ferramenta '${tool_name}' nao possui artefato verificado para a arquitetura '${TS_NORM_ARCH}' em '${lock_file}'."
  fi

  local version command_name url expected_sha filename binary_name archive_format
  version="$(jq -r --arg t "${tool_name}" '.tools[$t].version' "${lock_file}")"
  command_name="$(jq -r --arg t "${tool_name}" '.tools[$t].command' "${lock_file}")"
  url="$(jq -r --arg t "${tool_name}" --arg a "${TS_NORM_ARCH}" '.tools[$t].artifacts[$a].url' "${lock_file}")"
  expected_sha="$(jq -r --arg t "${tool_name}" --arg a "${TS_NORM_ARCH}" '.tools[$t].artifacts[$a].sha256' "${lock_file}")"
  filename="$(jq -r --arg t "${tool_name}" --arg a "${TS_NORM_ARCH}" '.tools[$t].artifacts[$a].filename' "${lock_file}")"
  binary_name="$(jq -r --arg t "${tool_name}" --arg a "${TS_NORM_ARCH}" '.tools[$t].artifacts[$a].binary_name' "${lock_file}")"
  archive_format="$(jq -r --arg t "${tool_name}" --arg a "${TS_NORM_ARCH}" '.tools[$t].artifacts[$a].archive_format' "${lock_file}")"

  if [[ "${archive_format}" != "tar.gz" ]]; then
    ts_die "${TS_EXIT_ERR}" "Formato de arquivo '${archive_format}' nao suportado para '${tool_name}'."
  fi

  ts_init_state_paths
  local tool_install_dir="${TS_DATA_ROOT}/tools/${tool_name}/${version}"
  local installed_bin_path="${tool_install_dir}/${binary_name}"
  local link_path="${HOME}/.local/bin/${command_name}"

  if ! ts_validate_managed_path "${installed_bin_path}" "false"; then
    ts_die "${TS_EXIT_ERR}" "Caminho de instalacao invalido para '${tool_name}': '${installed_bin_path}'."
  fi

  # Verificar idempotencia: se o binario desta versao ja esta instalado e funcional, nao baixar novamente
  if [[ -f "${installed_bin_path}" ]] && [[ ! -L "${installed_bin_path}" ]] && [[ -x "${installed_bin_path}" ]]; then
    local existing_bin_sha
    existing_bin_sha="$(ts_sha256_file "${installed_bin_path}")"
    ts_manifest_record_entry \
      "${installed_bin_path}" \
      "file" \
      "file" \
      "${existing_bin_sha}" \
      "" \
      "" \
      "${existing_bin_sha}" \
      "" \
      "unchanged" \
      "${version}"
    ts_install_managed_symlink_if_safe "${link_path}" "${installed_bin_path}"
    ts_ensure_local_bin_in_path
    ts_log_event "INFO" "Ferramenta externa ja instalada (idempotente): tool=${tool_name} version=${version}"
    return 0
  fi

  # Criar diretorio temporario exclusivo que e sempre limpo em sucesso ou falha (Secao 9)
  local tmp_work_dir=""
  tmp_work_dir="$(mktemp -d "${TMPDIR:-/tmp}/terminal-setup-dl-${tool_name}.XXXXXX")"

  local archive_tmp="${tmp_work_dir}/${filename}"
  local extract_dir="${tmp_work_dir}/extracted"
  mkdir -p "${extract_dir}"

  ts_info "Baixando ${tool_name} v${version} (${TS_NORM_ARCH}) de fonte oficial..."
  if ! ts_download_https_file "${url}" "${archive_tmp}"; then
    rm -rf -- "${tmp_work_dir}"
    ts_die "${TS_EXIT_ERR}" "Falha ao baixar o artefato oficial de '${tool_name}'."
  fi

  if ! ts_verify_downloaded_sha256 "${archive_tmp}" "${expected_sha}"; then
    rm -rf -- "${tmp_work_dir}"
    ts_die "${TS_EXIT_ERR}" "Checksum SHA-256 invalido para o artefato de '${tool_name}'. Instalacao abortada."
  fi

  if ! ts_validate_tar_gz_archive "${archive_tmp}"; then
    rm -rf -- "${tmp_work_dir}"
    ts_die "${TS_EXIT_ERR}" "Pacote tar.gz de '${tool_name}' reprovado na inspecao de seguranca."
  fi

  if ! tar -xzf "${archive_tmp}" -C "${extract_dir}" --no-same-owner --no-same-permissions; then
    rm -rf -- "${tmp_work_dir}"
    ts_die "${TS_EXIT_ERR}" "Falha ao extrair o pacote tar.gz de '${tool_name}'."
  fi

  # Localizar o binario extraido (na raiz ou ate 3 niveis dentro do tarball, ex.: dist/superfile-linux-.../spf)
  local extracted_bin=""
  extracted_bin="$(find "${extract_dir}" -maxdepth 3 -type f -name "${binary_name}" | head -n 1 || true)"
  if [[ -z "${extracted_bin}" ]] || [[ ! -f "${extracted_bin}" ]]; then
    rm -rf -- "${tmp_work_dir}"
    ts_die "${TS_EXIT_ERR}" "Binario '${binary_name}' nao encontrado dentro do arquivo extraido de '${tool_name}'."
  fi

  # Instalar no diretorio versionado do usuario e criar link controlado em ~/.local/bin
  mkdir -p "${tool_install_dir}"
  ts_atomic_write_from_file "${extracted_bin}" "${installed_bin_path}" "0755"
  rm -rf -- "${tmp_work_dir}"

  local final_bin_sha
  final_bin_sha="$(ts_sha256_file "${installed_bin_path}")"
  ts_manifest_record_entry \
    "${installed_bin_path}" \
    "file" \
    "absent" \
    "" \
    "" \
    "" \
    "${final_bin_sha}" \
    "" \
    "created" \
    "${version}"

  ts_install_managed_symlink_if_safe "${link_path}" "${installed_bin_path}"

  # Validar comando e versao apos instalar, garantindo ~/.local/bin no PATH (Secao 9)
  ts_ensure_local_bin_in_path
  if ! "${installed_bin_path}" --version >/dev/null 2>&1; then
    ts_die "${TS_EXIT_ERR}" "O binario instalado para '${tool_name}' ('${installed_bin_path}') falhou na verificacao '--version'."
  fi

  ts_ok "Ferramenta '${tool_name}' v${version} instalada e verificada (${command_name})."
  ts_log_event "INFO" "Ferramenta externa instalada: tool=${tool_name} version=${version} path=${installed_bin_path} sha256=${final_bin_sha}"
}

# Instala todas as ferramentas externas selecionadas na execucao atual
ts_install_selected_external_tools() {
  local repo_root="$1"
  if [[ "${#TS_SELECTED_EXTERNAL_TOOLS[@]}" -eq 0 ]]; then
    return 0
  fi

  local tool
  for tool in "${TS_SELECTED_EXTERNAL_TOOLS[@]}"; do
    ts_install_single_external_tool "${repo_root}" "${tool}"
  done
}
