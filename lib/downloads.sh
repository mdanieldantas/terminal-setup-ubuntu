#!/usr/bin/env bash
# ==============================================================================
# lib/downloads.sh — Download HTTPS seguro, verificacao SHA-256 e anti-tar-slip
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# Segue estritamente a Secao 9 do guia de implementacao.
# ==============================================================================

if [[ -n "${TS_DOWNLOADS_LOADED:-}" ]]; then
  return 0
fi
readonly TS_DOWNLOADS_LOADED=1

# Valida que uma URL e estritamente HTTPS e sem caracteres de controle/espacos
ts_validate_https_url() {
  local url="$1"
  if [[ -z "${url}" ]] || [[ "${url}" != https://* ]]; then
    return 1
  fi
  if [[ "${url}" =~ [[:space:]] ]] || ts_has_control_chars "${url}"; then
    return 1
  fi
  return 0
}

# Valida formato de hash SHA-256 (64 caracteres hexadecimais minusculos/maiusculos)
ts_validate_sha256_format() {
  local hash="$1"
  [[ "${hash}" =~ ^[0-9a-fA-F]{64}$ ]]
}

# Baixa um arquivo via HTTPS com timeouts, tentativas limitadas e falha em erro HTTP
# Uso: ts_download_https_file <url> <dest_file>
ts_download_https_file() {
  local url="$1"
  local dest_file="$2"

  if ! ts_validate_https_url "${url}"; then
    ts_error "URL de download invalida ou nao utiliza HTTPS: '${url}'."
    return 1
  fi

  if ! command -v curl >/dev/null 2>&1; then
    ts_error "O utilitario 'curl' e obrigatorio para baixar artefatos externos, mas nao esta instalado."
    return 1
  fi

  if ! curl \
    --proto '=https' \
    --tlsv1.2 \
    --fail \
    --silent \
    --show-error \
    --location \
    --retry 2 \
    --retry-delay 1 \
    --connect-timeout 15 \
    --max-time 120 \
    --output "${dest_file}" \
    "${url}"; then
    ts_error "Falha no download HTTPS de '${url}'."
    rm -f -- "${dest_file}" 2>/dev/null || true
    return 1
  fi

  if [[ ! -f "${dest_file}" ]] || [[ ! -s "${dest_file}" ]]; then
    ts_error "Arquivo baixado de '${url}' esta vazio ou ausente."
    rm -f -- "${dest_file}" 2>/dev/null || true
    return 1
  fi

  return 0
}

# Verifica o SHA-256 de um arquivo baixado contra o valor esperado no lock
# Uso: ts_verify_downloaded_sha256 <filepath> <expected_sha256>
ts_verify_downloaded_sha256() {
  local filepath="$1"
  local expected_sha="$2"

  if ! ts_validate_sha256_format "${expected_sha}"; then
    ts_error "Checksum esperado no lock possui formato SHA-256 invalido: '${expected_sha}'."
    return 1
  fi

  local actual_sha=""
  if ! actual_sha="$(ts_sha256_file "${filepath}")"; then
    ts_error "Nao foi possivel calcular o SHA-256 do arquivo '${filepath}'."
    return 1
  fi

  local expected_lower="${expected_sha,,}"
  local actual_lower="${actual_sha,,}"
  if [[ "${actual_lower}" != "${expected_lower}" ]]; then
    ts_error "Falha de verificacao de checksum SHA-256 para '${filepath}': esperado '${expected_lower}', calculado '${actual_lower}'."
    return 1
  fi

  return 0
}

# Inspeciona um arquivo .tar.gz antes de extrair para prevenir tar-slip (caminhos absolutos, '..', links maliciosos)
ts_validate_tar_gz_archive() {
  local archive_file="$1"
  if ! command -v tar >/dev/null 2>&1; then
    ts_error "O utilitario 'tar' e necessario para inspecionar e extrair '${archive_file}'."
    return 1
  fi

  local listing=""
  if ! listing="$(tar -tzf "${archive_file}" 2>/dev/null)"; then
    ts_error "O arquivo '${archive_file}' nao e um pacote .tar.gz valido ou esta corrompido."
    return 1
  fi

  if [[ -z "${listing}" ]]; then
    ts_error "O arquivo .tar.gz '${archive_file}' esta vazio."
    return 1
  fi

  local entry
  while IFS= read -r entry; do
    [[ -z "${entry}" ]] && continue
    if [[ "${entry}" == /* ]] \
      || [[ "${entry}" == ".." ]] \
      || [[ "${entry}" == "../"* ]] \
      || [[ "${entry}" == *"/../"* ]] \
      || [[ "${entry}" == *"/.." ]] \
      || ts_has_control_chars "${entry}"; then
      ts_error "Entrada insegura detectada dentro do arquivo tar '${archive_file}': '${entry}'."
      return 1
    fi
  done <<<"${listing}"

  return 0
}
