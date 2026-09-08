#!/usr/bin/env bash
# Sourced by run.sh. Uses e2e_mm, E2E_STEM, E2E_VAULT, E2E_PHASE, E2E_REPO, assert_*.
# Spec: docs/superpowers/specs/2026-09-04-snippet-library-design.md section 10.

tok="snptok$(printf '%s' "$E2E_STEM" | tr -cd '0-9')"
t_ssl="${E2E_STEM} SSL expiry"
t_dup="${E2E_STEM} SSL expiry"
t_path="${E2E_STEM} List path"
t_tag="${E2E_STEM} Ping dns"
cmd_ssl="echo | openssl s_client -connect <host=example.com>:443 2>/dev/null | openssl x509 -dates -noout ${tok}"
cmd_path="ls <path>"
cmd_tag="ping -c 1 8.8.8.8"

# 13. helper must not exec stored commands
if [ -f "$E2E_REPO/scripts/lib/snip.sh" ] \
  && grep -E 'eval |sh -c|bash -c' "$E2E_REPO/scripts/lib/snip.sh" >/dev/null 2>&1; then
  e2e_fail "snip.sh has no eval/sh -c/bash -c ($E2E_PHASE)" "matched exec pattern"
else
  if [ -f "$E2E_REPO/scripts/lib/snip.sh" ]; then
    e2e_pass "snip.sh has no eval/sh -c/bash -c ($E2E_PHASE)"
  else
    e2e_fail "snip.sh has no eval/sh -c/bash -c ($E2E_PHASE)" "missing scripts/lib/snip.sh"
  fi
fi

h_before="$(e2e_mm health 2>/dev/null || true)"
other_before="$(printf '%s\n' "$h_before" | awk -F= '/^kind_other=/ { print $2; exit }')"
[ -n "$other_before" ] || other_before=0

# 1 / 12. snip new writes kind/domain/heat/fence; empty --command fails
empty_rc=0
e2e_mm snip new "${E2E_STEM} Empty" --command "" >/dev/null 2>&1 || empty_rc=$?
if [ "$empty_rc" -ne 0 ]; then
  e2e_pass "snip new empty command nonzero ($E2E_PHASE)"
else
  e2e_fail "snip new empty command nonzero ($E2E_PHASE)" "exit 0"
fi

nout="$(e2e_mm snip new "$t_ssl" --command "$cmd_ssl" --tags ssl,openssl 2>/dev/null || true)"
assert_contains "$nout" "path=brain/snippets/" "snip new path ($E2E_PHASE)"
assert_contains "$nout" "title=$t_ssl" "snip new title ($E2E_PHASE)"
sf="$E2E_VAULT/brain/snippets/${t_ssl}.md"
assert_file "$sf" "snip new file ($E2E_PHASE)"
assert_grep '^kind: snippet$' "$sf" "snip kind ($E2E_PHASE)"
assert_grep '^domain: snippets$' "$sf" "snip domain ($E2E_PHASE)"
assert_grep '^heat: growing$' "$sf" "snip heat growing ($E2E_PHASE)"
assert_grep '^```bash$' "$sf" "snip bash fence ($E2E_PHASE)"
assert_grep "$tok" "$sf" "snip command token ($E2E_PHASE)"

# 2. duplicate title does not overwrite
echo marker-keep >> "$sf"
dup_rc=0
e2e_mm snip new "$t_dup" --command "echo overwritten" >/dev/null 2>&1 || dup_rc=$?
if [ "$dup_rc" -ne 0 ]; then
  e2e_pass "snip new duplicate title fails ($E2E_PHASE)"
else
  e2e_fail "snip new duplicate title fails ($E2E_PHASE)" "exit 0"
fi
assert_grep 'marker-keep' "$sf" "snip new duplicate does not overwrite ($E2E_PHASE)"

e2e_mm snip new "$t_path" --command "$cmd_path" >/dev/null 2>&1 || true
e2e_mm snip new "$t_tag" --command "$cmd_tag" --tags network,dns >/dev/null 2>&1 || true

# 3 / 4 / 5. list / search / --tag
lout="$(e2e_mm snip list 2>/dev/null || true)"
assert_contains "$lout" "title=$t_ssl" "snip list title ($E2E_PHASE)"
assert_contains "$lout" "tags=ssl,openssl" "snip list tags ($E2E_PHASE)"
assert_contains "$lout" "command=" "snip list command field ($E2E_PHASE)"
assert_contains "$lout" "$tok" "snip list command token ($E2E_PHASE)"

sout="$(e2e_mm snip search "$tok" 2>/dev/null || true)"
assert_contains "$sout" "title=$t_ssl" "snip search hits command body ($E2E_PHASE)"
case "$sout" in
  *"title=$t_path"*) e2e_fail "snip search does not list unrelated ($E2E_PHASE)" "out=$sout" ;;
  *) e2e_pass "snip search does not list unrelated ($E2E_PHASE)" ;;
esac

tagout="$(e2e_mm snip list --tag dns 2>/dev/null || true)"
assert_contains "$tagout" "title=$t_tag" "snip list --tag dns hits ($E2E_PHASE)"
case "$tagout" in
  *"title=$t_ssl"*) e2e_fail "snip list --tag dns excludes ssl ($E2E_PHASE)" "out=$tagout" ;;
  *) e2e_pass "snip list --tag dns excludes ssl ($E2E_PHASE)" ;;
esac

# 6 / 7. get expand
got="$(e2e_mm snip get "$t_ssl" 2>/dev/null || true)"
case "$got" in
  title=*|"path="*) e2e_fail "snip get is command only ($E2E_PHASE)" "out=$got" ;;
  *) e2e_pass "snip get is command only ($E2E_PHASE)" ;;
esac
assert_contains "$got" "example.com" "snip get fills default host ($E2E_PHASE)"
case "$got" in
  *"<host="*) e2e_fail "snip get default removes placeholder ($E2E_PHASE)" "out=$got" ;;
  *) e2e_pass "snip get default removes placeholder ($E2E_PHASE)" ;;
esac

got_set="$(e2e_mm snip get "$t_ssl" --set host=example.org 2>/dev/null || true)"
assert_contains "$got_set" "example.org" "snip get --set host ($E2E_PHASE)"
case "$got_set" in
  *example.com*) e2e_fail "snip get --set replaces default ($E2E_PHASE)" "out=$got_set" ;;
  *) e2e_pass "snip get --set replaces default ($E2E_PHASE)" ;;
esac

got_path="$(e2e_mm snip get "$t_path" 2>/dev/null || true)"
assert_contains "$got_path" "<path>" "snip get keeps nameless placeholder ($E2E_PHASE)"

# 8 / 9. default recall/search hide snippet; include flags show it
rec="$(e2e_mm recall "$tok" --limit 5 2>/dev/null || true)"
case "$rec" in
  *"$tok"*|*"title=$t_ssl"*) e2e_fail "recall hides snippet ($E2E_PHASE)" "out=$rec" ;;
  *) e2e_pass "recall hides snippet ($E2E_PHASE)" ;;
esac
sdef="$(e2e_mm search "$tok" 2>/dev/null || true)"
case "$sdef" in
  *"$tok"*|*"$t_ssl"*) e2e_fail "search hides snippet ($E2E_PHASE)" "out=$sdef" ;;
  *) e2e_pass "search hides snippet ($E2E_PHASE)" ;;
esac
sinc="$(e2e_mm search "$tok" --include-snippet 2>/dev/null || true)"
assert_contains "$sinc" "$t_ssl" "search --include-snippet ($E2E_PHASE)"
skind="$(e2e_mm search "$tok" --kind snippet 2>/dev/null || true)"
assert_contains "$skind" "$t_ssl" "search --kind snippet ($E2E_PHASE)"

# 10. health kind_snippet; not kind_other
hout="$(e2e_mm health 2>/dev/null || true)"
assert_contains "$hout" "kind_snippet=" "health prints kind_snippet ($E2E_PHASE)"
snip_n="$(printf '%s\n' "$hout" | awk -F= '/^kind_snippet=/ { print $2; exit }')"
case "$snip_n" in
  ''|0) e2e_fail "health kind_snippet counts notes ($E2E_PHASE)" "kind_snippet=$snip_n" ;;
  *) e2e_pass "health kind_snippet counts notes ($E2E_PHASE)" ;;
esac
other_after="$(printf '%s\n' "$hout" | awk -F= '/^kind_other=/ { print $2; exit }')"
[ -n "$other_after" ] || other_after=0
if [ "$other_after" -le "$other_before" ]; then
  e2e_pass "snippet does not raise kind_other ($E2E_PHASE)"
else
  e2e_fail "snippet does not raise kind_other ($E2E_PHASE)" "before=$other_before after=$other_after"
fi

# 11. rm requires --yes
rm_rc=0
rm_out="$(e2e_mm snip rm "$t_path" 2>/dev/null)" || rm_rc=$?
if [ "$rm_rc" -eq 2 ]; then
  e2e_pass "snip rm without --yes exit 2 ($E2E_PHASE)"
else
  e2e_fail "snip rm without --yes exit 2 ($E2E_PHASE)" "rc=$rm_rc"
fi
assert_file "$E2E_VAULT/brain/snippets/${t_path}.md" "snip rm without --yes keeps file ($E2E_PHASE)"
e2e_mm snip rm "$t_path" --yes >/dev/null 2>&1 || true
if [ -f "$E2E_VAULT/brain/snippets/${t_path}.md" ]; then
  e2e_fail "snip rm --yes deletes file ($E2E_PHASE)" "still present"
else
  e2e_pass "snip rm --yes deletes file ($E2E_PHASE)"
fi
