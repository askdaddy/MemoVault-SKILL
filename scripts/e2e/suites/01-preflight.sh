#!/usr/bin/env bash
# Sourced by run.sh. Uses E2E_PHASE=shell.
# Top-level asserts; must not call exit (run.sh sources this file).
# Preflight contract (spec §4.3): runtime=shell mode=fs vault=... search=rg|grep forced=0

out="$(e2e_mm preflight 2>/dev/null || true)"
assert_contains "$out" "runtime=shell" "preflight runtime ($E2E_PHASE)"
assert_contains "$out" "vault=$E2E_VAULT" "preflight vault ($E2E_PHASE)"
# Transitional fields kept for one minor version; assert they still print.
assert_contains "$out" "mode=fs" "preflight mode=fs transitional ($E2E_PHASE)"
assert_contains "$out" "forced=0" "preflight forced=0 ($E2E_PHASE)"
