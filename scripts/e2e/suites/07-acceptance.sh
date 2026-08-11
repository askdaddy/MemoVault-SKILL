#!/usr/bin/env bash
# Sourced by run.sh. Memory Loop acceptance gaps (filters, daily, ledger, verify, metrics).

dom="e2e"
token="ACC_${E2E_STEM// /_}"

# --domain / --kind / --heat filters
e2e_mm new eng "Acc Eng Atom" --kind atom --body "filt $token" >/dev/null 2>&1 || true
e2e_mm new ops "Acc Ops Atom" --kind atom --body "filt $token" >/dev/null 2>&1 || true
e2e_mm new eng "Acc Eng Skill" --kind skill --body "filt $token" >/dev/null 2>&1 || true
e2e_mm promote "Acc Eng Skill" >/dev/null 2>&1 || true

sout_dom="$(e2e_mm search "filt $token" --domain eng 2>/dev/null || true)"
case "$sout_dom" in
  *"Acc Ops Atom"*) e2e_fail "search --domain eng excludes other domains ($E2E_PHASE)" "out=$sout_dom" ;;
  *"Acc Eng Atom"*|*"Acc Eng Skill"*) e2e_pass "search --domain eng ($E2E_PHASE)" ;;
  *) e2e_fail "search --domain eng ($E2E_PHASE)" "out=$sout_dom" ;;
esac

sout_kind="$(e2e_mm search "filt $token" --kind skill 2>/dev/null || true)"
case "$sout_kind" in
  *"Acc Eng Atom"*) e2e_fail "search --kind skill excludes atom ($E2E_PHASE)" "out=$sout_kind" ;;
  *"Acc Eng Skill"*) e2e_pass "search --kind skill ($E2E_PHASE)" ;;
  *) e2e_fail "search --kind skill ($E2E_PHASE)" "out=$sout_kind" ;;
esac

sout_heat="$(e2e_mm search "filt $token" --heat evergreen 2>/dev/null || true)"
case "$sout_heat" in
  *"Acc Eng Skill"*) e2e_pass "search --heat evergreen ($E2E_PHASE)" ;;
  *) e2e_fail "search --heat evergreen ($E2E_PHASE)" "out=$sout_heat" ;;
esac

# daily is outside search/recall root
e2e_mm daily:append "daily-only $token" >/dev/null 2>&1 || true
sout_daily="$(e2e_mm search "daily-only $token" 2>/dev/null || true)"
case "$sout_daily" in
  *daily/*|*"daily-only"*) e2e_fail "search excludes daily path ($E2E_PHASE)" "out=$sout_daily" ;;
  *) e2e_pass "search excludes daily path ($E2E_PHASE)" ;;
esac
rout_daily="$(e2e_mm recall "daily-only $token" --limit 5 2>/dev/null || true)"
case "$rout_daily" in
  *daily/*|*"daily-only"*) e2e_fail "recall excludes daily ($E2E_PHASE)" "out=$rout_daily" ;;
  *) e2e_pass "recall excludes daily ($E2E_PHASE)" ;;
esac

# distill scenario
raw_s="${E2E_STEM} AccRawSc"
sc_t="${E2E_STEM} AccScenario"
e2e_mm new inbox "$raw_s" --kind raw --body "scene $token" >/dev/null 2>&1 || true
d_sc="$(e2e_mm distill "$raw_s" "$dom" "$sc_t" --kind scenario 2>/dev/null || true)"
assert_contains "$d_sc" "AccScenario" "distill scenario path ($E2E_PHASE)"
sc_body="$(e2e_mm read "$sc_t" 2>/dev/null || true)"
assert_contains "$sc_body" "kind: scenario" "distill scenario kind ($E2E_PHASE)"

# health: domain_*, provenance_pct, legacy_daily_count, hints possible
hout="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hout" "domain_eng=" "health domain_eng ($E2E_PHASE)"
assert_contains "$hout" "provenance_pct=" "health provenance_pct ($E2E_PHASE)"
assert_contains "$hout" "legacy_daily_count=" "health legacy_daily_count ($E2E_PHASE)"
# after daily:append, legacy_daily should be >= 1
case "$hout" in
  *legacy_daily_count=0*) e2e_fail "legacy_daily_count > 0 after daily ($E2E_PHASE)" "out=$hout" ;;
  *legacy_daily_count=*) e2e_pass "legacy_daily_count nonzero ($E2E_PHASE)" ;;
  *) e2e_fail "legacy_daily_count present ($E2E_PHASE)" "out=$hout" ;;
esac

# cite_rate: recall with hits then cite -> cite_rate >= 0 and not -1
e2e_mm recall "filt $token" --limit 2 >/dev/null 2>&1 || true
e2e_mm cite "Acc Eng Skill" >/dev/null 2>&1 || true
hout2="$(e2e_mm health 2>/dev/null || true)"
case "$hout2" in
  *cite_rate=-1*) e2e_fail "cite_rate computed after recall+cite ($E2E_PHASE)" "out=$hout2" ;;
  *cite_rate=*) e2e_pass "cite_rate computed after recall+cite ($E2E_PHASE)" ;;
  *) e2e_fail "cite_rate present ($E2E_PHASE)" "out=$hout2" ;;
esac

# ledger unwritable: main command still succeeds
mkdir -p "$E2E_VAULT/.memovault"
chmod 555 "$E2E_VAULT/.memovault" 2>/dev/null || true
# On some systems chmod on dir may not block append by owner; also try locking ledger file
: > "$E2E_VAULT/.memovault/ledger.log" 2>/dev/null || true
chmod 444 "$E2E_VAULT/.memovault/ledger.log" 2>/dev/null || true
rc=0
e2e_mm new "$dom" "${E2E_STEM} AccStillWrites" --kind atom --body "ok $token" >/dev/null 2>&1 || rc=$?
chmod 755 "$E2E_VAULT/.memovault" 2>/dev/null || true
chmod 644 "$E2E_VAULT/.memovault/ledger.log" 2>/dev/null || true
if [ "$rc" -eq 0 ]; then
  e2e_pass "new succeeds when ledger not writable ($E2E_PHASE)"
else
  e2e_fail "new succeeds when ledger not writable ($E2E_PHASE)" "rc=$rc"
fi

# install --verify without templates dir
tmpv="$(mktemp -d)/novault"
mkdir -p "$tmpv/brain"
# Point verify at tmp vault by running install.sh in a subshell with env
# install.sh uses VAULT from AGENT_MEMO_VAULT / defaults — exercise helper path:
# Use install.sh --verify with AGENT_MEMO_VAULT=$tmpv and existing SOURCE
ver_out="$(
  AGENT_MEMO_VAULT="$tmpv" \
  "$E2E_REPO/install/install.sh" --verify --agent cursor 2>&1 || true
)"
case "$ver_out" in
  *"FAIL vault"*templates*) e2e_fail "verify does not require templates ($E2E_PHASE)" "out=$ver_out" ;;
  *"OK   vault"*|*"verify: OK"*|*"OK   vault"*) e2e_pass "verify without templates ($E2E_PHASE)" ;;
  *)
    # vault OK line is enough even if agent injection fails in sandbox
    case "$ver_out" in
      *"OK   vault"*) e2e_pass "verify without templates ($E2E_PHASE)" ;;
      *) e2e_fail "verify without templates ($E2E_PHASE)" "out=$ver_out" ;;
    esac
    ;;
esac
rm -rf "$(dirname "$tmpv")"
