#!/usr/bin/env bats
# ==============================================================================
# tests/bats/test_phase2_state_and_reversibility.bats — Adaptador Bats (Fase 2)
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# ==============================================================================

@test "Fase 2: estado XDG, backups, manifesto JSON, conflitos, doctor e restauracao" {
  run bash "${BATS_TEST_DIRNAME}/../unit/test_phase2_state_and_reversibility.sh"
  pass_cnt="$(printf '%s\n' "${output}" | grep -c '^[[:space:]]*\[PASS\]' || true)"
  fail_cnt="$(printf '%s\n' "${output}" | grep -c '^[[:space:]]*\[FAIL\]' || true)"
  printf '# Verificacoes internas executadas (Fase 2): %s PASS, %s FAIL\n' "${pass_cnt}" "${fail_cnt}" >&3
  [ "$status" -eq 0 ]
}
