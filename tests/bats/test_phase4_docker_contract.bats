#!/usr/bin/env bats
# ==============================================================================
# tests/bats/test_phase4_docker_contract.bats — Adaptador Bats (Fase 4)
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# ==============================================================================

@test "Fase 4: contrato estatico de Dockerfile, compose.yaml, .dockerignore e suite de container" {
  run bash "${BATS_TEST_DIRNAME}/../unit/test_phase4_docker_contract.sh"
  pass_cnt="$(printf '%s\n' "${output}" | grep -c '^[[:space:]]*\[PASS\]' || true)"
  fail_cnt="$(printf '%s\n' "${output}" | grep -c '^[[:space:]]*\[FAIL\]' || true)"
  printf '# Verificacoes internas executadas (Fase 4): %s PASS, %s FAIL\n' "${pass_cnt}" "${fail_cnt}" >&3
  [ "$status" -eq 0 ]
}
