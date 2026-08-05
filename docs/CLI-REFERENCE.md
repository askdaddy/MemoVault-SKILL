# Obsidian CLI quick reference

> **Not a runtime dependency.** MemoVault's helper does not call the Obsidian
> CLI and does not require the Obsidian desktop app to be running. This page is
> an optional reference for humans who already use Obsidian and want to browse
> or edit the vault with its CLI by hand. The helper's own behavior is
> documented in `SKILL.md` and `docs/ARCHITECTURE.md`.

Curated subset of the official Obsidian CLI (https://obsidian.md/cli). The full
reference is at `help.obsidian.md` under "Extending Obsidian / Obsidian CLI".

## Prerequisites (for human-side use only)

- Obsidian installer 1.12.7 or newer.
- Settings -> General -> enable "Command line interface", then register to PATH.
- The Obsidian app must be running; the CLI connects to the running instance.
- macOS manual register: `sudo ln -sf /Applications/Obsidian.app/Contents/MacOS/obsidian-cli /usr/local/bin/obsidian`
- Linux: binary copied to `~/.local/bin/obsidian` (ensure it is on PATH).

None of the above is needed for the MemoVault helper. If you only want the
helper, you can ignore this entire page.

## Syntax

```
obsidian <command> param=value --flag
```

- Parameter: `name=value`; quote values with spaces: `content="hello world"`.
- Flag: boolean switch, no value (e.g. `open`, `overwrite`).
- Multiline content: use `\n` for newline, `\t` for tab.
- Target a vault: `vault=<name>` or `vault=<id>` as the FIRST parameter, or run
  from inside the vault folder (cwd). This skill uses cwd.
- Target a file: `file=<name>` (wikilink style resolution) or `path=<path>`
  (exact path from vault root).
- Any command: add `--copy` to copy output to clipboard.
- Many commands accept `format=json|tsv|csv|md|text` and `total`.

## Files and folders

| Command | Purpose |
|---|---|
| `create name= path= content= template= overwrite open newtab` | Create or overwrite a file. |
| `read file= path=` | Read file contents (default: active file). |
| `append file= path= content= inline` | Append (default: active file). |
| `prepend file= path= content= inline` | Prepend after frontmatter. |
| `move file= path= to=` | Move/rename; auto updates internal links. |
| `rename file= path= name=` | Rename; auto updates links. |
| `delete file= path= permanent` | Delete (trash by default). |
| `open file= path= newtab` | Open a file. |
| `files folder= ext= total` | List files. |
| `folders folder= total` | List folders. |

## Daily notes

| Command | Purpose |
|---|---|
| `daily` | Open today's daily note. |
| `daily:path` | Print daily note path (file may not exist yet). |
| `daily:read` | Read daily note contents. |
| `daily:append content= inline open` | Append to daily note. |
| `daily:prepend content= inline open` | Prepend to daily note. |

## Search

| Command | Purpose |
|---|---|
| `search query= path= limit= format=text|json total case` | Search; returns matching file paths. |
| `search:context query= path= limit= format= case` | Search with `path:line: text` context. |
| `search:open query=` | Open the search view. |

## Tags and properties

| Command | Purpose |
|---|---|
| `tags file= path= sort=count total counts format= active` | List tags. |
| `tag name= total verbose` | Tag info. |
| `properties name= sort=count format= total counts active` | List properties. |
| `property:set name= value= type= file= path=` | Set a property. `type` one of text, list, number, checkbox, date, datetime. |
| `property:remove name= file= path=` | Remove a property. |
| `property:read name= file= path=` | Read a property value. |
| `aliases file= path= total verbose active` | List aliases. |

## Links (backlinks are the core feature)

| Command | Purpose |
|---|---|
| `backlinks file= path= counts total format=json|tsv|csv` | Notes linking TO a file. |
| `links file= path= total` | Outgoing links from a file. |
| `unresolved total counts verbose format=` | `[[links]]` pointing nowhere. |
| `orphans total` | Files with no incoming links. |
| `deadends total` | Files with no outgoing links. |

## Tasks

| Command | Purpose |
|---|---|
| `tasks file= path= status= done todo verbose daily total active` | List tasks. |
| `task ref=path:line file= path= line= status= toggle daily done todo` | Show/update a task. |

## Templates

| Command | Purpose |
|---|---|
| `templates total` | List templates. |
| `template:read name= title= resolve` | Read template; `resolve` expands `{{date}}`/`{{time}}`/`{{title}}`. |
| `template:insert name=` | Insert template into active file. |

## Vault

| Command | Purpose |
|---|---|
| `vault info=name|path|files|folders|size` | Vault info. |
| `vaults total verbose` | List known vaults. |

## Outline, history, misc

| Command | Purpose |
|---|---|
| `outline file= path= format=tree|md|json total` | Headings of a file. |
| `diff file= path= from= to= filter=local|sync` | Compare file versions. |
| `help` / `version` / `reload` / `restart` | General. |

## Common recipes used by this skill

```bash
cd "$AGENT_MEMO_VAULT"

# Create a note with body (multiline via \n)
obsidian create path="brain/engineering/Async Rust.md" \
  content="---\ntitle: Async Rust\ndomain: engineering\nheat: seedling\n---\n# Async Rust\n"

# Append a wikilinked paragraph
obsidian append file="Async Rust" content="\nSee [[Tokio runtime]]."

# Full text search with context, JSON
obsidian search:context query="runtime" format=json

# Promote heat
obsidian property:set name=heat value=growing file="Async Rust"

# Backlinks with counts
obsidian backlinks file="Async Rust" counts format=json