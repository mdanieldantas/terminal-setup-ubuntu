#!/usr/bin/env bats
# ==============================================================================
# tests/bats/test_phase3_packages_tools_plugins.bats — Adaptador Bats (Fase 3)
# Projeto: terminal-setup (Ubuntu 24.04 LTS amd64)
# ==============================================================================

@test "Fase 3: helper APT, locks JSON, Starship, Superfile (spf) e plugins Zsh" {
  run bash "${BATS_TEST_DIRNAME}/../unit/test_phase3_packages_tools_plugins.sh"
  pass_cnt="$(printf '%s\n' "${output}" | grep -c '^[[:space:]]*\[PASS\]' || true)"
  fail_cnt="$(printf '%s\n' "${output}" | grep -c '^[[:space:]]*\[FAIL\]' || true)"
  printf '# Verificacoes internas executadas (Fase 3): %s PASS, %s FAIL\n' "${pass_cnt}" "${fail_cnt}" >&3
  [ "$status" -eq 0 ]
}
