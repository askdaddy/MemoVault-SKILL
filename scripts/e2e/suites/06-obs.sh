#!/usr/bin/env bash
# Sourced by run.sh. Observability + distill suite.

dom="e2e"
token="OBS_${E2E_STEM// /_}"
raw_t="${E2E_STEM} ObsRaw"
atom_t="${E2E_STEM} ObsAtom"

e2e_mm new inbox "$raw_t" --kind raw --body "obs-raw $token" >/dev/null 2>&1 || true
dout="$(e2e_mm distill "$raw_t" "$dom" "$atom_t" --kind atom 2>/dev/null || true)"
assert_contains "$dout" "ObsAtom" "distill creates atom path ($E2E_PHASE)"

body="$(e2e_mm read "$atom_t" 2>/dev/null || true)"
assert_contains "$body" "[[$raw_t]]" "distill body links raw ($E2E_PHASE)"
assert_contains "$body" "sources:" "distill has sources frontmatter ($E2E_PHASE)"
assert_contains "$body" "$raw_t" "distill sources mention raw ($E2E_PHASE)"

raw_body="$(e2e_mm read "$raw_t" 2>/dev/null || true)"
assert_contains "$raw_body" "Distilled to [[$atom_t]]" "distill pointer on raw ($E2E_PHASE)"

# recall + cite + health
e2e_mm append "$atom_t" "findable $token" >/dev/null 2>&1 || true
rout="$(e2e_mm recall "$token" --limit 3 2>/dev/null || true)"
assert_contains "$rout" "title=$atom_t" "recall finds distilled atom ($E2E_PHASE)"

cout="$(e2e_mm cite "$atom_t" 2>/dev/null || true)"
assert_contains "$cout" "cited=$atom_t" "cite records title ($E2E_PHASE)"

hout="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hout" "notes_total=" "health prints notes_total ($E2E_PHASE)"
assert_contains "$hout" "cite_rate=" "health prints cite_rate ($E2E_PHASE)"
assert_contains "$hout" "kind_raw=" "health prints kind_raw ($E2E_PHASE)"

# stats alias
sout="$(e2e_mm stats 2>/dev/null || true)"
assert_contains "$sout" "notes_total=" "stats aliases health ($E2E_PHASE)"

# ledger exists after ops
assert_file "$E2E_VAULT/.memovault/ledger.log" "ledger.log created ($E2E_PHASE)"

rot="$(e2e_mm ledger:rotate --keep 5000 2>/dev/null || true)"
assert_contains "$rot" "keep=5000" "ledger:rotate runs ($E2E_PHASE)"

# --- 0.7.2 search ledger ---
ledger="$E2E_VAULT/.memovault/ledger.log"
tok_s="SRCH_${E2E_STEM// /_}"
note_two="${E2E_STEM} TwoLine"
e2e_mm new e2e "$note_two" --kind atom --body "$tok_s line-a
$tok_s line-b" >/dev/null 2>&1 || true

before_s="$(grep -c 'event=search' "$ledger" 2>/dev/null || true)"
[ -n "$before_s" ] || before_s=0
e2e_mm search "$tok_s" >/dev/null 2>&1 || true
after_s="$(grep -c 'event=search' "$ledger" 2>/dev/null || true)"
[ -n "$after_s" ] || after_s=0
assert_eq "$((before_s + 1))" "$after_s" "public search logs one event=search ($E2E_PHASE)"

last_s="$(grep 'event=search' "$ledger" | tail -1)"
assert_contains "$last_s" "hits=1" "search hits= unique notes not rg lines ($E2E_PHASE)"
assert_contains "$last_s" "q=" "search ledger has q= ($E2E_PHASE)"
case "$last_s" in
  *top=*) e2e_fail "search ledger has no top= ($E2E_PHASE)" "line=$last_s" ;;
  *) e2e_pass "search ledger has no top= ($E2E_PHASE)" ;;
esac

tok_miss="SRCHMISS_${E2E_STEM// /_}"
before_m="$(grep -c 'event=search' "$ledger" 2>/dev/null || true)"
[ -n "$before_m" ] || before_m=0
e2e_mm search "$tok_miss" >/dev/null 2>&1 || true
after_m="$(grep -c 'event=search' "$ledger" 2>/dev/null || true)"
[ -n "$after_m" ] || after_m=0
assert_eq "$((before_m + 1))" "$after_m" "zero-hit search still logs event=search ($E2E_PHASE)"
last_m="$(grep 'event=search' "$ledger" | tail -1)"
assert_contains "$last_m" "hits=0" "zero-hit search logs hits=0 ($E2E_PHASE)"

before_d="$(grep -c 'event=search' "$ledger" 2>/dev/null || true)"
[ -n "$before_d" ] || before_d=0
e2e_mm dedupe "$note_two" --limit 5 >/dev/null 2>&1 || true
after_d="$(grep -c 'event=search' "$ledger" 2>/dev/null || true)"
[ -n "$after_d" ] || after_d=0
assert_eq "$before_d" "$after_d" "dedupe does not log event=search ($E2E_PHASE)"

# --- 0.7.2 health fields ---
hout="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hout" "kind_other_pct=" "health prints kind_other_pct ($E2E_PHASE)"
assert_contains "$hout" "search_7d=" "health prints search_7d ($E2E_PHASE)"
assert_contains "$hout" "recall_hits_7d=" "health prints recall_hits_7d ($E2E_PHASE)"
assert_contains "$hout" "recall_hit_rate=" "health prints recall_hit_rate ($E2E_PHASE)"
assert_contains "$hout" "capture_after_miss_7d=" "health prints capture_after_miss_7d ($E2E_PHASE)"
assert_contains "$hout" "cite_7d=" "health prints cite_7d ($E2E_PHASE)"
assert_contains "$hout" "recapture_new_dup=" "health prints recapture_new_dup ($E2E_PHASE)"
assert_contains "$hout" "wide_query_7d=" "health prints wide_query_7d ($E2E_PHASE)"
assert_contains "$hout" "cite_rate=" "health still prints cite_rate ($E2E_PHASE)"
assert_contains "$hout" "recapture_dup=" "health still prints recapture_dup ($E2E_PHASE)"

# old keys keep relative order; new L1 block comes after recapture_dup
line_of() { printf '%s\n' "$hout" | grep -n "^${1}=" | head -1 | cut -d: -f1; }
ko="$(line_of kind_other)"
kop="$(line_of kind_other_pct)"
cr="$(line_of cite_rate)"
rd="$(line_of recapture_dup)"
s7="$(line_of search_7d)"
if [ -n "$ko" ] && [ -n "$kop" ] && [ "$ko" -lt "$kop" ]; then
  e2e_pass "kind_other_pct follows kind_other ($E2E_PHASE)"
else
  e2e_fail "kind_other_pct follows kind_other ($E2E_PHASE)" "kind_other=$ko kind_other_pct=$kop"
fi
if [ -n "$cr" ] && [ -n "$rd" ] && [ -n "$s7" ] && [ "$cr" -lt "$rd" ] && [ "$rd" -lt "$s7" ]; then
  e2e_pass "cite_rate then recapture_dup then search_7d ($E2E_PHASE)"
else
  e2e_fail "cite_rate then recapture_dup then search_7d ($E2E_PHASE)" "cite_rate=$cr recapture_dup=$rd search_7d=$s7"
fi

tok_miss_r="RECMISS_${E2E_STEM// /_}"
e2e_mm recall "$tok_miss_r" --limit 3 >/dev/null 2>&1 || true
e2e_mm new e2e "${E2E_STEM} AfterMiss" --kind atom --body "after miss" >/dev/null 2>&1 || true
hout2="$(e2e_mm health 2>/dev/null || true)"
case "$hout2" in
  *capture_after_miss_7d=0*|*capture_after_miss_7d=-*) e2e_fail "capture_after_miss_7d >= 1 after miss+capture ($E2E_PHASE)" "out=$hout2" ;;
  *capture_after_miss_7d=*) e2e_pass "capture_after_miss_7d >= 1 after miss+capture ($E2E_PHASE)" ;;
  *) e2e_fail "capture_after_miss_7d present ($E2E_PHASE)" "out=$hout2" ;;
esac

dup_t="${E2E_STEM} DupNew"
e2e_mm new e2e-a "$dup_t" --kind atom --body "dup-a" >/dev/null 2>&1 || true
e2e_mm new e2e-b "$dup_t" --kind atom --body "dup-b" >/dev/null 2>&1 || true
hout3="$(e2e_mm health 2>/dev/null || true)"
case "$hout3" in
  *recapture_new_dup=0*) e2e_fail "recapture_new_dup >= 1 after two-domain new ($E2E_PHASE)" "out=$hout3" ;;
  *recapture_new_dup=*) e2e_pass "recapture_new_dup >= 1 after two-domain new ($E2E_PHASE)" ;;
  *) e2e_fail "recapture_new_dup present ($E2E_PHASE)" "out=$hout3" ;;
esac

snap_new="$(printf '%s\n' "$hout3" | awk -F= '/^recapture_new_dup=/{print $2; exit}')"
app_t="${E2E_STEM} AppendOnly"
e2e_mm new e2e "$app_t" --kind atom --body "once" >/dev/null 2>&1 || true
e2e_mm append "$app_t" "twice" >/dev/null 2>&1 || true
e2e_mm append "$app_t" "thrice" >/dev/null 2>&1 || true
hout4="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hout4" "recapture_dup=" "recapture_dup still present after appends ($E2E_PHASE)"
snap_new2="$(printf '%s\n' "$hout4" | awk -F= '/^recapture_new_dup=/{print $2; exit}')"
# two-domain new already counted; append-only title must not bump recapture_new_dup
assert_eq "$snap_new" "$snap_new2" "append-only repeats do not bump recapture_new_dup ($E2E_PHASE)"
case "$hout4" in
  *recapture_dup=0*) e2e_fail "recapture_dup >= 1 after append repeats ($E2E_PHASE)" "out=$hout4" ;;
  *recapture_dup=*) e2e_pass "recapture_dup >= 1 after append repeats ($E2E_PHASE)" ;;
  *) e2e_fail "recapture_dup present ($E2E_PHASE)" "out=$hout4" ;;
esac

# isolated vault: recall_hit_rate=-1 and new hints (do not reset E2E_VAULT)
iso="$E2E_ROOT/iso-obs"
mkdir -p "$iso"
old_vault="$E2E_VAULT"
E2E_VAULT="$iso"

e2e_mm new iso "Only Note" --kind atom --body "solo" >/dev/null 2>&1 || true
hiso0="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hiso0" "recall_hit_rate=-1" "recall_hit_rate=-1 when no recall ($E2E_PHASE)"

i=1
while [ "$i" -le 5 ]; do
  e2e_mm recall "ISOMISS${i}_${E2E_STEM}" --limit 3 >/dev/null 2>&1 || true
  i=$((i + 1))
done
hiso1="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hiso1" "hint=low_recall_hit_rate" "hint low_recall_hit_rate after 5 misses ($E2E_PHASE)"

e2e_mm new iso "MissCap A" --kind atom --body "a" >/dev/null 2>&1 || true
e2e_mm new iso "MissCap B" --kind atom --body "b" >/dev/null 2>&1 || true
e2e_mm new iso "MissCap C" --kind atom --body "c" >/dev/null 2>&1 || true
hiso2="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hiso2" "hint=capture_after_miss" "hint capture_after_miss after miss day + 3 captures ($E2E_PHASE)"

j=1
while [ "$j" -le 10 ]; do
  e2e_mm new iso "NoKind $j" --body "nk" >/dev/null 2>&1 || true
  j=$((j + 1))
done
hiso3="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hiso3" "hint=high_kind_other" "hint high_kind_other with 10+ unkinded notes ($E2E_PHASE)"

# --- 0.8.0: 7d window, token_n, capture_after_miss causality ---
iso2="$E2E_ROOT/iso-obs-window"
mkdir -p "$iso2/.memovault" "$iso2/brain/iso"
E2E_VAULT="$iso2"
printf '%s\n' "ts=2000-01-01T00:00:00Z event=recall q=ancient hits=1 top=Old" > "$iso2/.memovault/ledger.log"
e2e_mm recall "NOWMISS_${E2E_STEM}" --limit 3 >/dev/null 2>&1 || true
hw="$(e2e_mm health 2>/dev/null || true)"
r7="$(printf '%s\n' "$hw" | awk -F= '/^recall_7d=/{print $2; exit}')"
assert_eq "1" "$r7" "recall_7d ignores 2000-01-01 ledger row ($E2E_PHASE)"
rh="$(printf '%s\n' "$hw" | awk -F= '/^recall_hits_7d=/{print $2; exit}')"
assert_eq "0" "$rh" "ancient hits=1 does not count in 7d ($E2E_PHASE)"

last_r="$(grep 'event=recall' "$iso2/.memovault/ledger.log" | tail -1)"
assert_contains "$last_r" "token_n=" "recall ledger has token_n= ($E2E_PHASE)"

today="$(date -u +%Y-%m-%d)"
printf '%s\n' "ts=${today}T00:00:00Z event=recall q=unrelated_query hits=0 top= token_n=2" > "$iso2/.memovault/ledger.log"
printf '%s\n' "ts=${today}T04:00:00Z event=capture title=Completely Different Title kind=atom domain=iso op=new" >> "$iso2/.memovault/ledger.log"
hw2="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hw2" "capture_after_miss_7d=0" "no overlap + 4h gap is not capture_after_miss ($E2E_PHASE)"

printf '%s\n' "ts=${today}T00:00:00Z event=recall q=PERC_copyback hits=0 top= token_n=2" > "$iso2/.memovault/ledger.log"
printf '%s\n' "ts=${today}T04:00:00Z event=capture title=PERC SOP kind=atom domain=iso op=new" >> "$iso2/.memovault/ledger.log"
hw3="$(e2e_mm health 2>/dev/null || true)"
cam="$(printf '%s\n' "$hw3" | awk -F= '/^capture_after_miss_7d=/{print $2; exit}')"
case "$cam" in
  0|-*) e2e_fail "title overlap still counts capture_after_miss ($E2E_PHASE)" "out=$hw3" ;;
  *) e2e_pass "title overlap still counts capture_after_miss ($E2E_PHASE)" ;;
esac

iso3="$E2E_ROOT/iso-wide-query"
mkdir -p "$iso3/.memovault" "$iso3/brain/iso"
E2E_VAULT="$iso3"
today="$(date -u +%Y-%m-%d)"
{
  i=1
  while [ "$i" -le 5 ]; do
    sec="$(printf '%02d' "$i")"
    printf 'ts=%sT00:00:%sZ event=recall q=a_b_c_d hits=0 top= token_n=4\n' "$today" "$sec"
    i=$((i + 1))
  done
} > "$iso3/.memovault/ledger.log"
hwq="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hwq" "wide_query_7d=5" "wide_query_7d counts token_n>=4 ($E2E_PHASE)"
assert_contains "$hwq" "hint=wide_query" "hint=wide_query when recall_7d>=5 and wide_query_7d>=5 ($E2E_PHASE)"
assert_contains "$hwq" "recall_n4_7d=5" "recall_n4_7d counts token_n>=4 ($E2E_PHASE)"
assert_contains "$hwq" "read_7d=" "health prints read_7d ($E2E_PHASE)"
assert_contains "$hwq" "use_rate=" "health prints use_rate ($E2E_PHASE)"
assert_contains "$hwq" "moc_count=" "health prints moc_count ($E2E_PHASE)"
assert_contains "$hwq" "summary=" "health prints summary= ($E2E_PHASE)"
assert_contains "$hwq" "recall_hit_rate_prev7d=" "health prints recall_hit_rate_prev7d ($E2E_PHASE)"

iso4="$E2E_ROOT/iso-efficacy"
mkdir -p "$iso4/.memovault" "$iso4/brain/iso"
E2E_VAULT="$iso4"
today="$(date -u +%Y-%m-%d)"
if date -u -v-10d +%Y-%m-%d >/dev/null 2>&1; then
  prevd="$(date -u -v-10d +%Y-%m-%d)"
else
  prevd="$(date -u -d '10 days ago' +%Y-%m-%d)"
fi
{
  printf 'ts=%sT00:00:00Z event=recall q=oldwide hits=0 top= token_n=4\n' "$prevd"
  printf 'ts=%sT00:00:01Z event=recall q=oldwide hits=0 top= token_n=4\n' "$prevd"
  i=1
  while [ "$i" -le 5 ]; do
    sec="$(printf '%02d' "$i")"
    printf 'ts=%sT01:00:%sZ event=recall q=one hits=1 top=Leaf token_n=1\n' "$today" "$sec"
    i=$((i + 1))
  done
  printf 'ts=%sT02:00:00Z event=read title=Leaf kind=atom\n' "$today"
} > "$iso4/.memovault/ledger.log"
printf 'ts=2000-01-01T00:00:00Z recall_hit_rate=10 cite_7d=9 orphan_pct=40\n' > "$iso4/.memovault/health-snap.log"
hef="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hef" "recall_n1_7d=5" "n1 bucket this week ($E2E_PHASE)"
assert_contains "$hef" "recall_n1_hit_rate=100" "n1 hit rate 100 ($E2E_PHASE)"
assert_contains "$hef" "hint=low_use" "hint=low_use when hits but no cite ($E2E_PHASE)"
assert_contains "$hef" "read_7d=1" "read_7d counts ($E2E_PHASE)"
assert_contains "$hef" "read_uncited_7d=1" "read without cite ($E2E_PHASE)"
assert_contains "$hef" "use_rate=0" "use_rate 0 when cite_7d=0 ($E2E_PHASE)"
rhp="$(printf '%s\n' "$hef" | awk -F= '/^recall_hit_rate_prev7d=/{print $2; exit}')"
assert_eq "0" "$rhp" "prev window hit rate 0 ($E2E_PHASE)"
wqprev="$(printf '%s\n' "$hef" | awk -F= '/^wide_query_7d_prev=/{print $2; exit}')"
assert_eq "2" "$wqprev" "prev window wide_query ($E2E_PHASE)"
dhit="$(printf '%s\n' "$hef" | awk -F= '/^delta_recall_hit_rate=/{print $2; exit}')"
assert_eq "90" "$dhit" "delta_recall_hit_rate vs snap ($E2E_PHASE)"

E2E_VAULT="$old_vault"
