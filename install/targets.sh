#!/usr/bin/env bash
# install/targets.sh - mapping of supported agents to their install locations.
# Sourced by install.sh. Bash 3.2 compatible (no associative arrays).
#
# kind:
#   native - self-contained skill folder under the shared ~/.agents/skills/
#            (auto-discovered by pi, Trae, and the npx-skills ecosystem); no stub
#   skill  - drop a SKILL.md (with frontmatter) into an agent skills directory
#   rules  - drop a rules file into an agent rules directory
#   agents - append an instruction block to an AGENTS.md / GEMINI.md style file

# Print all supported agent names, one per line.
mm_target_list() {
  printf '%s\n' claude pi codex opencode crush gemini cline cursor trae copilot
}

# Echo the absolute install path for an agent.
mm_target_path() {
  case "$1" in
    claude)  printf '%s/.claude/skills/memovault/SKILL.md' "$HOME" ;;
    pi|trae) printf '%s/.agents/skills/memovault' "$HOME" ;;
    codex)   printf '%s/.codex/AGENTS.md' "$HOME" ;;
    opencode) printf '%s/.config/opencode/AGENTS.md' "$HOME" ;;
    crush)   printf '%s/.config/crush/AGENTS.md' "$HOME" ;;
    gemini)  printf '%s/.gemini/GEMINI.md' "$HOME" ;;
    cline)   printf '%s/.cline/rules/memovault.md' "$HOME" ;;
    cursor)  printf '%s/.cursor/rules/memovault.mdc' "$HOME" ;;
    copilot) printf '%s/.config/github-copilot/instructions.md' "$HOME" ;;
    *) return 1 ;;
  esac
}

# Echo the kind for an agent: native | skill | rules | agents.
mm_target_kind() {
  case "$1" in
    pi|trae) printf 'native' ;;
    claude) printf 'skill' ;;
    cline|cursor) printf 'rules' ;;
    codex|opencode|crush|gemini|copilot) printf 'agents' ;;
    *) return 1 ;;
  esac
}

# Echo the adapter template file name (relative to install/adapters/).
mm_target_adapter() {
  case "$1" in
    cursor) printf 'cursor.mdc' ;;
    *) printf '%s.md' "$1" ;;
  esac
}
