#!/usr/bin/env bats
# ==============================================================================
# tests/bats/test_phase1_contract.bats — Adaptador Bats para a suite da Fase 1
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# ==============================================================================

@test "Fase 1: contrato de CLI, parser restrito, perfis, preflight e --dry-run" {
  run bash "${BATS_TEST_DIRNAME}/../unit/test_phase1_contract.sh"
  pass_cnt="$(printf '%s\n' "${output}" | grep -c '^[[:space:]]*\[PASS\]' || true)"
  fail_cnt="$(printf '%s\n' "${output}" | grep -c '^[[:space:]]*\[FAIL\]' || true)"
  printf '# Verificacoes internas executadas (Fase 1): %s PASS, %s FAIL\n' "${pass_cnt}" "${fail_cnt}" >&3
  [ "$status" -eq 0 ]
}
