# MemoVault

A pure local filesystem skill that teaches coding agents how to sink knowledge into an
Obsidian vault using bash. No Obsidian plugin is required. The skill depends on the official
Obsidian CLI (https://obsidian.md/cli) when the desktop app is running, and degrades
gracefully to plain filesystem operations when it is not.

- Skill name: `memovault`
- Canonical skill source (after install): `~/.agent-memo-vault-skill/`
- Knowledge vault (Obsidian vault, data): `~/.agent-memo-vault/`
- Vault path override env var: `AGENT_MEMO_VAULT` (default `~/.agent-memo-vault`)
- Heat tiers: `seedling` / `growing` / `evergreen`

## What it does

- Layered notes: classify by domain and by heat (popularity/maturity).
- Retrieval: full text search, tag based search, and backlink graph traversal.
- Backlinks: first class. Wikilinks (`[[Note]]`) and aliases are the backbone.

Vector search is intentionally deferred to a later phase; see `docs/DEVELOPMENT.md`.

## Quick start (for humans)

1. Update Obsidian to installer 1.12.7 or newer.
2. In Obsidian: Settings -> General -> enable Command line interface, then register it.
3. From this repo:

   ```bash
   ./install/install.sh --all            # install source + inject adapters for every supported agent
   ./install/install.sh --agent claude   # ...or one agent at a time
   ./install/install.sh --register-vault # register ~/.agent-memo-vault into Obsidian
   ```

4. Restart your terminal and your agent. See `docs/INSTALL.md` for details.

## Layout

See `AGENTS.md` for the project entry point and `docs/` for specifications.

## License

Provided as-is for personal use.
