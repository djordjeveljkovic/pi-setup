# pi-setup

A bootstrap hub for [**pi**](https://github.com/badlogic/pi) — the coding agent.

`pi-setup` is a tiny, dependency-free shell script that installs **pi** and wires up
its extensions, skill libraries and config on any machine. Clone this one repo and
you can recreate your whole pi environment, picking exactly what you want.

```
┌─────────────────────────────────────────────────────────────┐
│  pi-setup                                                   │
│    └── install.sh   ← you run this                          │
│          │                                                  │
│          ├── installs  pi CLI            (npm, global)      │
│          │                                                  │
│          └── clones these repos into ~/.pi:                 │
│                ├── pi-skills-library  → agent/skills-library│
│                ├── pi-list-picker     → agent/extensions/.. │
│                ├── pi-skill-manager   → agent/extensions/.. │
│                ├── pi-image-workflow  → agent/extensions/.. │
│                ├── pi-questionnaire   → agent/extensions/.. │
│                └── pi-workflow        → agent/extensions/.. │
└─────────────────────────────────────────────────────────────┘
```

Everything is plain bash + git + npm. **No AI, no magic, no network beyond git/npm.**

---

## Quick start

```bash
git clone git@github.com:djordjeveljkovic/pi-setup.git
cd pi-setup
./install.sh                 # interactive menu
```

Or, fully unattended:

```bash
./install.sh --all -y
```

Then start (or restart) pi and run `/reload` to activate everything.

---

## Prerequisites

| Tool  | Why                              | Check            |
|-------|----------------------------------|------------------|
| `bash`≥4 | the installer                | `bash --version` |
| `git`  | cloning the component repos     | `git --version`  |
| `node`+`npm` | pi itself + extension deps | `node -v && npm -v` |
| SSH key on GitHub **or** HTTPS access | cloning | see *Protocols* below |

> On macOS, `bash` 4+ must be installed (`brew install bash`) — the system
> `bash` is 3.2 and lacks associative arrays. Linux is fine out of the box.

---

## The catalog

These are the components `install.sh` knows about. Run `./install.sh --list` to
print this from the script itself.

| ID               | Type     | Repo                                  | Installs to                            | Notes |
|------------------|----------|---------------------------------------|----------------------------------------|-------|
| `pi-core`        | step     | —                                     | global npm                             | installs `@earendil-works/pi-coding-agent` |
| `skills-library` | skills   | `pi-skills-library`                   | `agent/skills-library`                 | 86 skills across 10 collections |
| `list-picker`    | extension| `pi-list-picker`                      | `agent/extensions/list-picker`         | reusable TUI list picker |
| `skill-manager`  | extension| `pi-skill-manager`                   | `agent/extensions/skill-manager`       | browse/toggle/filter skills; **needs `list-picker`** |
| `image-workflow` | extension| `pi-image-workflow`                  | `agent/extensions/image-workflow`      | interactive image-collecting workflow |
| `questionnaire`  | extension| `pi-questionnaire`                   | `agent/extensions/questionnaire`       | single/multi/text/confirm/number questions |
| `workflow`       | extension| `pi-workflow`                        | `agent/extensions/workflow`            | `/quick`, `/plan`, `/ask` commands |
| `settings`       | step     | —                                     | `settings.json`                        | subagent model overrides (MiniMax) template |

All repos live under [`djordjeveljkovic`](https://github.com/djordjeveljkovic?tab=repositories).

**Dependencies are handled automatically:** selecting `skill-manager` also
installs `list-picker` (it depends on it via `file:../list-picker`), and
dependencies are always installed *before* the things that need them.

---

## Usage

### Interactive menu (default in a terminal)

```bash
./install.sh
```

You get a numbered, grouped list with a `✓` next to anything already installed:

```
pi-setup — select components to install.
Installed clones are marked with ✓.

Core:
  [ 1]  pi-core           Install the pi CLI (@earendil-works/pi-coding-agent) via npm

Skills:
  [ 2]✓ skills-library    Curated skills library (86 skills across 10 collections)

Extensions:
  [ 3]✓ list-picker       Reusable TUI list picker component
  [ 4]  skill-manager      Browse, toggle and filter skill libraries
  ...

Enter numbers (comma/space separated). Shortcuts: a=all  x=extensions  s=skills  c=core  q=quit
Selection: 1,4,7
```

### Flags

| Flag                     | Meaning |
|--------------------------|---------|
| _(none, in a TTY)_       | interactive menu |
| `--all`                  | install everything in the catalog |
| `--extensions`           | all extensions (incl. deps) |
| `--skills`               | the skills library |
| `--core`                 | install/upgrade the pi CLI only |
| `--only A,B,C`           | install only the listed ids (see `--list`) |
| `--update`               | `git pull` already-installed repos instead of skipping |
| `--no-npm-install`       | skip `npm install` for extensions |
| `--protocol ssh\|https`  | git protocol (default `ssh`) |
| `--user <user>`          | GitHub user/org (default `djordjeveljkovic`) |
| `--pi-home <dir>`        | target dir (default `~/.pi`) |
| `--dry-run`              | show what would happen, change nothing |
| `-y`, `--no-interaction` | never prompt; defaults to the full set if nothing chosen |
| `--list`                 | print the catalog and exit |
| `-h`, `--help`           | help |

### Examples

```bash
./install.sh --all                         # everything
./install.sh --only skill-manager,workflow # just these (deps auto-added)
./install.sh --extensions -y               # all extensions, no prompts
./install.sh --core                        # (re)install just the pi CLI
./install.sh --update --all                # pull latest for everything
PI_GIT_PROTOCOL=https ./install.sh --all -y# use HTTPS (no SSH key needed)
./install.sh --dry-run --all               # preview only
```

### Environment variables

| Variable         | Default            | Purpose |
|------------------|--------------------|---------|
| `PI_HOME`        | `~/.pi`            | where pi config lives |
| `PI_GH_USER`     | `djordjeveljkovic` | GitHub user/org to clone from |
| `PI_GIT_PROTOCOL`| `ssh`              | `ssh` or `https` |
| `PI_NPM_INSTALL` | `1`                | set `0` to skip `npm install` |

---

## What it creates

```
~/.pi/
├── settings.json                 ← from templates/settings.json (if not present)
└── agent/
    ├── extensions/
    │   ├── list-picker/          ← git clone
    │   ├── skill-manager/        ← git clone  (resolves list-picker via file:../list-picker)
    │   ├── image-workflow/       ← git clone
    │   ├── questionnaire/        ← git clone
    │   └── workflow/             ← git clone
    ├── skills-library/           ← git clone (the curated collection)
    ├── skills/                   ← your own custom skills (left untouched)
    └── themes/                   ← themes (left untouched)
```

The installer **never deletes** existing files. If a target directory already
exists and isn't a git clone, it is skipped with a warning. `settings.json` is
only written if it doesn't already exist.

---

## Configuration: settings & MiniMax

The optional `settings` step copies [`templates/settings.json`](templates/settings.json)
to `~/.pi/settings.json`. That template assigns **MiniMax** models to pi's
subagents (scout, planner, worker, delegate, researcher, reviewer,
context-builder).

To make those models work you need:

1. A MiniMax API key, exported in your shell:
   ```bash
   export MINIMAX_API_KEY="your-key-here"
   ```
   (Add it to `~/.bashrc` / `~/.zshrc` so it persists.)
2. The MiniMax provider configured in pi. From within pi, run the provider/model
   setup (pi will guide you), or set it in your pi config so models like
   `minimax/MiniMax-M2.7-highspeed` resolve.

If you use a different provider, just edit `~/.pi/settings.json` after install —
the template only seeds a sensible starting point and is never overwritten.

---

## Keeping things up to date

```bash
cd pi-setup
git pull                       # update the installer itself
./install.sh --update --all    # pull latest for every installed component
```

`--update` runs `git pull --ff-only` on each installed clone and re-runs
`npm install` for extensions. It only touches repos the installer created.

---

## Uninstalling

`pi-setup` only clones and copies — removal is just deletion:

```bash
# Remove a single component
rm -rf ~/.pi/agent/extensions/workflow

# Remove everything pi-setup installed
rm -rf ~/.pi/agent/skills-library
rm -rf ~/.pi/agent/extensions/{list-picker,skill-manager,image-workflow,questionnaire,workflow}
# (only delete ~/.pi/settings.json if you're sure you don't want it)
npm uninstall -g @earendil-works/pi-coding-agent   # remove pi itself
```

Then `/reload` in pi.

---

## Manual install (no script)

Prefer raw commands? This is exactly what the installer does — clone into the
right place under `~/.pi`, then `npm install` extensions:

```bash
mkdir -p ~/.pi/agent/extensions ~/.pi/agent/skills ~/.pi/agent/themes
cd ~/.pi/agent

# Skills library (contains 86 skills)
git clone git@github.com:djordjeveljkovic/pi-skills-library.git

# Extensions — note: skill-manager needs list-picker as a sibling dir
cd extensions
for r in pi-list-picker pi-skill-manager pi-image-workflow pi-questionnaire pi-workflow; do
  git clone "git@github.com:djordjeveljkovic/$r.git"
  (cd "$r" && npm install --no-fund --no-audit)
done
```

For HTTPS instead of SSH, swap the URLs to
`https://github.com/djordjeveljkovic/<repo>.git`.

---

## Troubleshooting

- **`clone failed` / permission denied (publickey)** — you need an SSH key on
  GitHub. Quickest fix: `./install.sh --protocol https --all`.
- **`npm install` fails in an extension** — make sure Node ≥ 18 is active. Some
  machines need `sudo`; consider a node version manager (nvm/fnm) to avoid that.
- **skill-manager can't find list-picker** — list-picker must be cloned as a
  sibling at `~/.pi/agent/extensions/list-picker`. The installer does this
  automatically; for manual installs, keep them side by side.
- **bash 3.2 (macOS)** — install bash 4+: `brew install bash`, then run
  `/opt/homebrew/bin/bash install.sh`.
- **Menu didn't appear** — stdin wasn't a TTY (e.g. piped). Pass an explicit
  selection, e.g. `./install.sh --all -y`.

---

# For AI assistants: how to set up pi

> This section is written for an **AI agent** that has been asked to set up pi
> (the coding agent) on a machine. Follow it top to bottom. It uses this repo so
> the result is reproducible and matches the user's environment. All commands are
> safe to re-run (idempotent).

## Goal
Install the pi CLI and the user's extensions, skill library and config under
`~/.pi`, then verify it loads.

## 0. Preflight checks
Run these and **report the results** before changing anything:
```bash
uname -a                       # OS / arch
bash --version | head -1       # need >= 4 (assoc arrays)
git --version
node -v && npm -v              # need Node >= 18
test -d ~/.pi && echo "~/.pi EXISTS" || echo "~/.pi absent"
command -v pi && pi --version  # is pi already installed?
```
If bash < 4 (stock macOS), install it first: `brew install bash`.
If Node is missing or < 18, install Node 18+ (use nvm/fnm, or the system
package manager). **Do not proceed until preflight passes.**

## 1. Get pi-setup
```bash
cd ~
if [ -d ~/pi-setup/.git ]; then git -C ~/pi-setup pull --ff-only;
else git clone git@github.com:djordjeveljkovic/pi-setup.git; fi
```
If SSH fails (no key), use HTTPS:
```bash
git clone https://github.com/djordjeveljkovic/pi-setup.git
```

## 2. Decide the protocol
Check whether the user has SSH access to GitHub:
```bash
ssh -T git@github.com 2>&1 | grep -q 'successfully authenticated' \
  && echo "ssh OK" || echo "use https"
```
Pass `--protocol https` to the installer in step 3 if SSH is not set up.

## 3. Install
Install **everything** non-interactively:
```bash
cd ~/pi-setup
./install.sh --all -y            # add --protocol https if needed
```
If the user wants a subset, use the menu (`./install.sh`) or
`--only <ids>` (run `./install.sh --list` for ids). Always include `list-picker`
whenever `skill-manager` is selected — the installer enforces this, but if you
install manually, do the same.

## 4. Configure the model provider
The user's `settings.json` template uses **MiniMax** models. For those to work:
- Ensure `MINIMAX_API_KEY` is exported in the user's shell rc
  (`~/.bashrc` / `~/.zshrc`). Ask the user for the key; **never** hardcode a
  secret into a committed file.
- Make sure pi knows the MiniMax provider (pi's own setup flow, or its config).
If the user prefers a different provider, edit `~/.pi/settings.json`
`subagents.agentOverrides.*.model` entries accordingly. Don't overwrite an
existing `settings.json` — merge keys by hand if needed.

## 5. Verify
```bash
command -v pi && pi --version
ls ~/.pi/agent/extensions
ls ~/.pi/agent/skills-library | head
test -f ~/.pi/settings.json && echo "settings.json present"
```
Then launch pi and run `/reload`. Confirm the extensions and skills appear
(e.g. the `/quick`, `/plan`, `/ask` commands from `pi-workflow`, and the skill
manager).

## 6. Report back
Tell the user, concisely:
- what was installed (ids) and where,
- which protocol was used and why,
- whether `MINIMAX_API_KEY` is set (yes/no — not its value),
- any warnings from the installer and how to resolve them,
- the single command to stay updated: `cd ~/pi-setup && git pull && ./install.sh --update --all`.

## Guardrails for the AI
- **Never commit secrets.** `MINIMAX_API_KEY` and any API key go in environment
  variables / shell rc, never in tracked files.
- **Don't delete** existing `~/.pi` content. The installer skips existing dirs;
  mirror that behavior if acting manually.
- **Idempotency:** every step above is safe to re-run.
- If something fails, stop and surface the exact error rather than guessing.

---

## Repository layout

```
pi-setup/
├── install.sh              # the installer (interactive + CLI)
├── templates/
│   └── settings.json       # subagent model overrides seed file
├── README.md               # you are here
├── LICENSE                 # MIT
└── .gitignore
```

To add a new component, edit the **Catalog** block near the top of
`install.sh` (the `COMPONENT_ORDER` array plus the `C_*` associative arrays).
That's the only place that needs changing.

## License

MIT — see [LICENSE](LICENSE).
