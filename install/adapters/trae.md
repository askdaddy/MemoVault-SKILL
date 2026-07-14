# MemoVault

Sink knowledge into a local Obsidian vault with bash. No Obsidian plugin required.
Uses the official Obsidian CLI when the desktop app is running; falls back to
plain filesystem operations otherwise.

This file is a pointer stub. The single source of truth is the SKILL.md below.
Before acting, READ that file with your file-read tool and follow it.

- Canonical skill: __MEMOVAULT_SOURCE__/SKILL.md
- Helper script:   __MEMOVAULT_HELPER__
- Vault path:      $AGENT_MEMO_VAULT (default __MEMOVAULT_VAULT__)
- Preflight:       `__MEMOVAULT_HELPER__ preflight` detects cli/fs mode.

Trigger when the user wants to capture, sink, search, link, promote, or maintain
notes and daily notes in their memo vault / second brain / Obsidian knowledge base.
