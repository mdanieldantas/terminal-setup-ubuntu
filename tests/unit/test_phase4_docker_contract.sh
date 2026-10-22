#!/usr/bin/env bash
# ==============================================================================
# tests/unit/test_phase4_docker_contract.sh
# Testes locais (offline e sem executar Docker/Podman) para validar a estrutura,
# segurança e contratos estáticos dos arquivos da Fase 4:
#   - .dockerignore
#   - docker/Dockerfile
#   - docker/compose.yaml
#   - docs/docker.md
#   - tests/integration/test_ubuntu2404_container.sh
# ==============================================================================

set -Eeuo pipefail

resolve_repo_root() {
  local source_path="${BASH_SOURCE[0]}"
  local dir_path
  while [[ -L "${source_path}" ]]; do
    dir_path="$(cd -P "$(dirname "${source_path}")" >/dev/null 2>&1 && pwd)"
    source_path="$(readlink "${source_path}")"
    if [[ "${source_path}" != /* ]]; then
      source_path="${dir_path}/${source_path}"
    fi
  done
  cd -P "$(dirname "${source_path}")/../.." >/dev/null 2>&1 && pwd
}

readonly REPO_ROOT="$(resolve_repo_root)"
readonly DOCKERIGNORE="${REPO_ROOT}/.dockerignore"
readonly DOCKERFILE="${REPO_ROOT}/docker/Dockerfile"
readonly COMPOSE_FILE="${REPO_ROOT}/docker/compose.yaml"
readonly DOCKER_DOC="${REPO_ROOT}/docs/docker.md"
readonly INTEGRATION_SCRIPT="${REPO_ROOT}/tests/integration/test_ubuntu2404_container.sh"

PASS_COUNT=0
FAIL_COUNT=0

pass() {
  PASS_COUNT=$((PASS_COUNT + 1))
  printf '[PASS] %s\n' "$1"
}

fail() {
  FAIL_COUNT=$((FAIL_COUNT + 1))
  printf '[FAIL] %s\n' "$1" >&2
}

printf '======================================================================\n'
printf 'Suíte de Testes Offline da Fase 4 — Contrato Docker e Integração\n'
printf '======================================================================\n'

# 1. Presença dos arquivos obrigatórios da Fase 4
for f in "${DOCKERIGNORE}" "${DOCKERFILE}" "${COMPOSE_FILE}" "${DOCKER_DOC}" "${INTEGRATION_SCRIPT}"; do
  if [[ -f "${f}" ]]; then
    pass "Arquivo presente: ${f#"${REPO_ROOT}/"}"
  else
    fail "Arquivo ausente: ${f}"
  fi
done

# 2. Validação de sintaxe Bash do script de integração e deste teste
if bash -n "${INTEGRATION_SCRIPT}" && bash -n "${BASH_SOURCE[0]}"; then
  pass "Scripts Bash da Fase 4 aprovados em 'bash -n'"
else
  fail "Erro de sintaxe em script Bash da Fase 4"
fi

# 3. Verificações do .dockerignore (Seções 12 e 15)
if grep -qxF ".git" "${DOCKERIGNORE}" &&
   grep -qxF "terminal.conf" "${DOCKERIGNORE}" &&
   grep -qxF "!examples/terminal.conf.example" "${DOCKERIGNORE}" &&
   grep -qxF "!profiles/*.conf" "${DOCKERIGNORE}" &&
   grep -qxF "*.log" "${DOCKERIGNORE}" &&
   grep -qxF "*.bak" "${DOCKERIGNORE}" &&
   grep -qxF "backups/" "${DOCKERIGNORE}" &&
   grep -qxF ".env" "${DOCKERIGNORE}" &&
   grep -qxF "*.key" "${DOCKERIGNORE}"; then
  pass ".dockerignore exclui .git, terminal.conf, logs, backups e segredos preservando examples/terminal.conf.example e profiles/*.conf"
else
  fail ".dockerignore não contém todas as regras obrigatórias das Seções 12 e 15"
fi

# 4. Verificações do docker/Dockerfile (Seção 12)
if grep -qE '^FROM ubuntu:24\.04' "${DOCKERFILE}"; then
  pass "Dockerfile usa base oficial ubuntu:24.04"
else
  fail "Dockerfile não usa base ubuntu:24.04"
fi

if grep -q 'scripts/install-system-packages.sh --profile' "${DOCKERFILE}" &&
   grep -q 'rm -rf /var/lib/apt/lists/\*' "${DOCKERFILE}"; then
  pass "Dockerfile instala pacotes APT via helper oficial e limpa /var/lib/apt/lists/* na mesma camada"
else
  fail "Dockerfile não executa o helper APT ou não limpa /var/lib/apt/lists/*"
fi

if ! grep -vE '^[[:space:]]*#' "${DOCKERFILE}" | grep -qiE 'sudo|NOPASSWD'; then
  pass "Dockerfile não instala sudo nem configura NOPASSWD:ALL"
else
  fail "Dockerfile menciona sudo ou NOPASSWD nas instruções de build"
fi

if grep -q 'getent group' "${DOCKERFILE}" && grep -q 'getent passwd' "${DOCKERFILE}"; then
  pass "Dockerfile trata colisão de UID/GID na criação do usuário dev (não assume UID 1000 livre)"
else
  fail "Dockerfile não valida colisão de UID/GID na criação do usuário"
fi

# Verificar que USER vem antes da chamada a install-terminal.sh
USER_LINE="$(grep -nE '^USER ' "${DOCKERFILE}" | head -n 1 | cut -d: -f1)"
INSTALL_LINE="$(grep -n 'install-terminal.sh' "${DOCKERFILE}" | tail -n 1 | cut -d: -f1)"
if [[ -n "${USER_LINE}" ]] && [[ -n "${INSTALL_LINE}" ]] && [[ "${USER_LINE}" -lt "${INSTALL_LINE}" ]]; then
  pass "Dockerfile alterna para USER não-root (linha ${USER_LINE}) antes de executar install-terminal.sh (linha ${INSTALL_LINE})"
else
  fail "Dockerfile não alterna para USER não-root antes de install-terminal.sh"
fi

if grep -q -- '--non-interactive' "${DOCKERFILE}" &&
   grep -q -- '--skip-system-packages' "${DOCKERFILE}" &&
   grep -q -- '--git-identity skip' "${DOCKERFILE}" &&
   grep -q -- '--change-shell no' "${DOCKERFILE}"; then
  pass "Dockerfile invoca install-terminal.sh com --non-interactive --skip-system-packages --git-identity skip --change-shell no"
else
  fail "Dockerfile não passa todas as flags obrigatórias ao install-terminal.sh"
fi

if grep -qF 'CMD ["/usr/bin/zsh", "-l"]' "${DOCKERFILE}"; then
  pass "Dockerfile define CMD [\"/usr/bin/zsh\", \"-l\"]"
else
  fail "Dockerfile não define CMD para iniciar Zsh como shell de login"
fi

# 5. Verificações do docker/compose.yaml (Seções 12 e 17)
if ! grep -qE '^version:' "${COMPOSE_FILE}"; then
  pass "docker/compose.yaml usa especificação moderna sem campo top-level 'version' legado"
else
  fail "docker/compose.yaml contém campo legado 'version'"
fi

if grep -qE '^  terminal:$' "${COMPOSE_FILE}" &&
   grep -qE 'context: \.\.' "${COMPOSE_FILE}" &&
   grep -qE 'dockerfile: docker/Dockerfile' "${COMPOSE_FILE}" &&
   grep -qE 'stdin_open: true' "${COMPOSE_FILE}" &&
   grep -qE 'tty: true' "${COMPOSE_FILE}" &&
   grep -qE 'user: dev' "${COMPOSE_FILE}"; then
  pass "docker/compose.yaml define serviço 'terminal', context '..', dockerfile 'docker/Dockerfile', user 'dev', stdin_open e tty"
else
  fail "docker/compose.yaml não cumpre todos os requisitos de estrutura da Seção 12/17"
fi

if ! grep -vE '^[[:space:]]*#' "${COMPOSE_FILE}" | grep -qE 'privileged:|network_mode:[[:space:]]*host|docker\.sock|^    volumes:'; then
  pass "docker/compose.yaml não habilita privileged, host network, docker.sock nem volumes automáticos do host"
else
  fail "docker/compose.yaml contém configuração insegura (privileged, host network, docker.sock ou volume ativo por padrão)"
fi

printf '======================================================================\n'
printf 'Resumo da Fase 4 (Contrato Offline): %d PASS, %d FAIL\n' "${PASS_COUNT}" "${FAIL_COUNT}"
printf '======================================================================\n'

if [[ "${FAIL_COUNT}" -gt 0 ]]; then
  exit 1
fi
exit 0
