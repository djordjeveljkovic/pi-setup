#!/usr/bin/env bash
#
# pi-setup — bootstrap installer for pi (the coding agent) configuration.
#
#   Clone this repo, then run ./install.sh to pick & install pi extensions,
#   skill libraries and config on any machine. Fully scripted — no AI needed.
#
#   The catalog of installable components lives in components.conf (a plain,
#   declarative file). Edit that file — or use ./install.sh --add — to add a
#   new repo. This script never needs editing for normal changes.
#
#   Usage:
#     ./install.sh                 # interactive menu (default, in a TTY)
#     ./install.sh --all           # install everything
#     ./install.sh --extensions    # all extensions
#     ./install.sh --only skill-manager,workflow
#     ./install.sh --list          # show the catalog
#     ./install.sh --check         # validate components.conf
#     ./install.sh --add id=foo type=extension repo=foo path=agent/extensions/foo desc=...
#     ./install.sh --self-update   # git pull this repo, then re-run with --update --all
#     ./install.sh --update --all  # git-pull already-installed component repos
#
#   Environment variables (override any of these):
#     PI_HOME            target directory          (default: ~/.pi)
#     PI_GH_USER         github user/org           (default: djordjeveljkovic)
#     PI_GIT_PROTOCOL    ssh | https               (default: ssh)
#     PI_NPM_INSTALL     1 = run npm install       (default: 1)
#     PI_MANIFEST        path to components.conf   (default: ./components.conf)
#
set -uo pipefail

# ============================================================================
# Configuration (overridable via env)
# ============================================================================
PI_HOME="${PI_HOME:-$HOME/.pi}"
PI_GH_USER="${PI_GH_USER:-djordjeveljkovic}"
PI_GIT_PROTOCOL="${PI_GIT_PROTOCOL:-ssh}"   # ssh | https
PI_NPM_INSTALL="${PI_NPM_INSTALL:-1}"       # 1 = run npm install for extensions

# ============================================================================
# Pretty printing & small helpers
# ============================================================================
if [[ -t 1 ]]; then
  C_RESET="\033[0m"; C_BOLD="\033[1m"; C_DIM="\033[2m"
  C_GREEN="\033[32m"; C_YELLOW="\033[33m"; C_RED="\033[31m"; C_CYAN="\033[36m"
else
  C_RESET=""; C_BOLD=""; C_DIM=""; C_GREEN=""; C_YELLOW=""; C_RED=""; C_CYAN=""
fi

log()  { printf "${C_BOLD}::${C_RESET} %s\n" "$*"; }
ok()   { printf "  ${C_GREEN}✓${C_RESET} %s\n" "$*"; }
warn() { printf "  ${C_YELLOW}⚠${C_RESET} %s\n" "$*"; }
err()  { printf "  ${C_RED}✗${C_RESET} %s\n" "$*"; }
info() { printf "  ${C_DIM}·${C_RESET} %s\n" "$*"; }
die()  { err "$*"; exit 1; }
has()  { command -v "$1" >/dev/null 2>&1; }

# trim leading/trailing whitespace
trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

# strip one matching pair of surrounding quotes (if any)
strip_quotes() {
  local v="$1"
  if (( ${#v} >= 2 )); then
    local first="${v:0:1}" last="${v:$((${#v}-1)):1}"
    if { [[ "$first" == '"' && "$last" == '"' ]] || [[ "$first" == "'" && "$last" == "'" ]]; }; then
      v="${v:1:$((${#v}-2))}"
    fi
  fi
  printf '%s' "$v"
}

# Resolve this script's directory (portable: works without GNU readlink -f).
script_dir() {
  local src="${BASH_SOURCE[0]:-$0}" dir
  if readlink -f "$src" >/dev/null 2>&1; then
    dir="$(dirname "$(readlink -f "$src")")"
  else
    dir="$(cd "$(dirname "$src")" >/dev/null 2>&1 && pwd)"
  fi
  printf '%s' "$dir"
}
SCRIPT_DIR="$(script_dir)"
MANIFEST="${PI_MANIFEST:-$SCRIPT_DIR/components.conf}"

# ============================================================================
# Registries (populated from components.conf)
# ============================================================================
declare -A C_TYPE C_REPO C_PATH C_DESC C_DEPS C_GROUP C_BUILTIN C_LINE
COMPONENT_ORDER=()        # ids in manifest order
GROUP_ORDER=()            # group labels in first-seen order
EXTENSION_IDS=()          # derived
SKILL_IDS=()              # derived
MANIFEST_ERRORS=0

# current record being parsed
declare -A CUR
CUR_ID=""
CUR_STARTLINE=0

# ============================================================================
# Builtin handlers (for type=step). Named builtin_<name>; name uses '-' or '_'.
# ============================================================================
builtin_install_pi() {
  log "[pi-core] @earendil-works/pi-coding-agent"
  has npm || { warn "npm not found — install Node.js first, then run: npm i -g @earendil-works/pi-coding-agent"; return 0; }
  if has pi; then
    ok "pi already installed ($(pi --version 2>/dev/null || echo present))"
  else
    if [[ "$DRY_RUN" == 1 ]]; then info "DRY-RUN: npm i -g @earendil-works/pi-coding-agent"; return 0; fi
    if npm install -g @earendil-works/pi-coding-agent >/dev/null 2>&1; then
      ok "pi installed globally"
    else
      warn "global install failed — you may need sudo or a node version manager"
      info "run manually: npm i -g @earendil-works/pi-coding-agent"
    fi
  fi
}

builtin_settings() {
  log "[settings] subagent model overrides"
  local target="$PI_HOME/settings.json"
  local tmpl="$SCRIPT_DIR/templates/settings.json"
  if [[ -f "$target" ]]; then
    ok "$target already exists — left untouched (merge desired keys by hand)"
  elif [[ -f "$tmpl" ]]; then
    if [[ "$DRY_RUN" == 1 ]]; then info "DRY-RUN: cp template -> $target"; return 0; fi
    mkdir -p "$PI_HOME" && cp "$tmpl" "$target" && ok "wrote $target" || warn "could not write $target"
    warn "template uses MiniMax models — set MINIMAX_API_KEY and configure the provider in pi"
  else
    warn "settings template not found: $tmpl"
  fi
}

# ============================================================================
# Manifest error helpers
# ============================================================================
merr()  { err "components.conf:$1: $2"; MANIFEST_ERRORS=$((MANIFEST_ERRORS+1)); }
mwarn() { warn "components.conf:$1: $2"; }

_default_group() {
  case "$1" in extension) printf 'Extensions';; skills) printf 'Skills';; *) printf 'Other';; esac
}

# Register the in-progress CUR record into the global registries (with checks).
_finalize_record() {
  local id="$CUR_ID"
  if [[ -z "$id" ]]; then
    (( ${#CUR[@]} > 0 )) && merr "$CUR_STARTLINE" "[[component]] block is missing 'id'"
    return 0
  fi
  if [[ ! "$id" =~ ^[a-z0-9][a-z0-9-]*$ ]]; then
    merr "$CUR_STARTLINE" "invalid id '$id' (use lowercase letters, digits, hyphens)"
    return 1
  fi
  if [[ -n "${C_TYPE[$id]:-}" ]]; then
    merr "$CUR_STARTLINE" "duplicate id '$id' (first seen at line ${C_LINE[$id]:-?})"
    return 1
  fi

  local type="${CUR[type]:-}"
  case "$type" in
    extension|skills|step) ;;
    "") merr "$CUR_STARTLINE" "component '$id' is missing 'type' (extension|skills|step)"; return 1 ;;
    *)  merr "$CUR_STARTLINE" "component '$id' has unknown type '$type' (use extension|skills|step)"; return 1 ;;
  esac

  if [[ "$type" == step ]]; then
    local b="${CUR[builtin]:-}"
    if [[ -z "$b" ]]; then merr "$CUR_STARTLINE" "step component '$id' needs 'builtin'"; return 1; fi
    if ! declare -F "builtin_${b//-/_}" >/dev/null 2>&1; then
      merr "$CUR_STARTLINE" "component '$id': unknown builtin '$b'"; return 1
    fi
  else
    if [[ -z "${CUR[repo]:-}" ]]; then merr "$CUR_STARTLINE" "component '$id' ($type) needs 'repo'"; return 1; fi
    if [[ -z "${CUR[path]:-}" ]]; then merr "$CUR_STARTLINE" "component '$id' ($type) needs 'path'"; return 1; fi
  fi

  C_TYPE[$id]="$type"
  C_REPO[$id]="${CUR[repo]:-}"
  C_PATH[$id]="${CUR[path]:-}"
  C_DESC[$id]="${CUR[desc]:-}"
  C_DEPS[$id]="${CUR[deps]:-}"
  C_BUILTIN[$id]="${CUR[builtin]:-}"
  C_GROUP[$id]="${CUR[group]:-$(_default_group "$type")}"
  C_LINE[$id]="$CUR_STARTLINE"
  COMPONENT_ORDER+=("$id")
}

# Cross-field validation: deps reference real ids; no dependency cycles.
_validate_cross() {
  local id d deps
  for id in "${COMPONENT_ORDER[@]}"; do
    deps="${C_DEPS[$id]:-}"; deps="${deps//,/ }"
    for d in $deps; do
      if [[ -z "${C_TYPE[$d]:-}" ]]; then
        merr "${C_LINE[$id]:-?}" "component '$id' depends on unknown id '$d'"
      fi
    done
  done
  # cycle detection (DFS)
  declare -A vstate=()
  _cycle_dfs() {
    local n="$1" dd ddeps
    vstate[$n]=1
    ddeps="${C_DEPS[$n]:-}"; ddeps="${ddeps//,/ }"
    for dd in $ddeps; do
      if [[ "${vstate[$dd]:-0}" == 1 ]]; then
        merr "${C_LINE[$n]:-?}" "dependency cycle: '$n' -> '$dd'"
        return 1
      fi
      if [[ "${vstate[$dd]:-0}" == 0 ]]; then _cycle_dfs "$dd" || return 1; fi
    done
    vstate[$n]=2
    return 0
  }
  for id in "${COMPONENT_ORDER[@]}"; do
    [[ "${vstate[$id]:-0}" == 0 ]] || continue
    _cycle_dfs "$id" || true
  done
}

# Known field names (used to warn on typos).
_KNOWN_KEYS=":id:type:repo:path:desc:deps:group:builtin:"

# Parse components.conf into the registries, then cross-validate.
load_manifest() {
  MANIFEST_ERRORS=0
  C_TYPE=(); C_REPO=(); C_PATH=(); C_DESC=(); C_DEPS=(); C_GROUP=(); C_BUILTIN=(); C_LINE=()
  COMPONENT_ORDER=()
  CUR=(); CUR_ID=""; CUR_STARTLINE=0

  [[ -f "$MANIFEST" ]] || die "manifest not found: $MANIFEST (set PI_MANIFEST or restore components.conf)"

  local line lineno=0 in_block=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno+1))
    line="${line%$'\r'}"                       # tolerate CRLF
    local trimmed; trimmed="$(trim "$line")"
    [[ -z "$trimmed" ]] && continue            # blank
    [[ "$trimmed" == \#* ]] && continue        # comment

    if [[ "$trimmed" == "[[component]]" ]]; then
      _finalize_record
      in_block=1; CUR=(); CUR_ID=""; CUR_STARTLINE="$lineno"
      continue
    fi
    if [[ "$in_block" != 1 ]]; then
      merr "$lineno" "content outside any [[component]] block: '$trimmed'"
      continue
    fi
    if [[ "$trimmed" != *=* ]]; then
      merr "$lineno" "expected 'key = value', got: '$trimmed'"
      continue
    fi
    local key val
    key="$(trim "${trimmed%%=*}")"
    val="$(strip_quotes "$(trim "${trimmed#*=}")")"
    if [[ "${_KNOWN_KEYS}" != *":$key:"* ]]; then
      mwarn "$lineno" "unknown key '$key' (typo?) in component block"
    fi
    [[ "$key" == id ]] && CUR_ID="$val"
    CUR[$key]="$val"
  done < "$MANIFEST"
  _finalize_record            # last block

  _validate_cross

  # derive extension/skill id lists (for --extensions / --skills shortcuts)
  EXTENSION_IDS=(); SKILL_IDS=()
  local id
  for id in "${COMPONENT_ORDER[@]}"; do
    case "${C_TYPE[$id]}" in
      extension) EXTENSION_IDS+=("$id") ;;
      skills)    SKILL_IDS+=("$id") ;;
    esac
  done

  # derive group order (first-seen)
  GROUP_ORDER=()
  for id in "${COMPONENT_ORDER[@]}"; do
    local g="${C_GROUP[$id]}"
    [[ " ${GROUP_ORDER[*]} " == *" $g "* ]] || GROUP_ORDER+=("$g")
  done

  return 0
}

# ============================================================================
# Install logic
# ============================================================================
url_for() {
  case "$PI_GIT_PROTOCOL" in
    https) echo "https://github.com/$PI_GH_USER/${1}.git" ;;
    *)     echo "git@github.com:$PI_GH_USER/${1}.git" ;;
  esac
}

post_install() {
  local id="$1" target="$2"
  if [[ "${C_TYPE[$id]}" == "extension" && "$PI_NPM_INSTALL" == 1 && -f "$target/package.json" ]]; then
    if has npm; then
      info "npm install …"
      if ( cd "$target" && npm install --no-fund --no-audit >/dev/null 2>&1 ); then
        ok "dependencies installed"
      else
        warn "npm install reported issues — you may need to run it manually in $target"
      fi
    else
      warn "npm not found — skipping dependency install for $id"
    fi
  fi
}

clone_repo() {
  local id="$1"
  local repo="${C_REPO[$id]}" rel="${C_PATH[$id]}"
  local target="$PI_HOME/$rel"
  local url; url="$(url_for "$repo")"
  log "[$id] ${repo} -> ${target/#$HOME/\~}"
  if [[ -d "$target/.git" ]]; then
    if [[ "$UPDATE_MODE" == 1 ]]; then
      info "existing repo; pulling latest"
      if git -C "$target" pull --ff-only >/dev/null 2>&1; then ok "updated $repo"; else warn "pull failed for $repo"; fi
      post_install "$id" "$target"
    else
      ok "already installed (use --update to refresh)"
    fi
  elif [[ -d "$target" && -n "$(ls -A "$target" 2>/dev/null)" ]]; then
    warn "$target exists and is not a git clone — skipping to avoid clobbering"
  else
    mkdir -p "$(dirname "$target")"
    if [[ "$DRY_RUN" == 1 ]]; then info "DRY-RUN: git clone $url $target"; return 0; fi
    if git clone --depth 1 "$url" "$target" >/dev/null 2>&1; then
      ok "cloned $repo"
    else
      err "clone failed: $url"
      info "check protocol (ssh needs a key; try --protocol https) and that the repo exists"
      return 1
    fi
    post_install "$id" "$target"
  fi
}

install_component() {
  case "${C_TYPE[$1]:-}" in
    step)          "builtin_${C_BUILTIN[$1]//-/_}" "$1" ;;
    extension|skills) clone_repo "$1" ;;
    *) die "no handler for component '$1' (type '${C_TYPE[$1]:-?}')" ;;
  esac
}

# Dependency resolution: deps are installed before dependents.
declare -gA _seen=()
SELECTED_FINAL=()
resolve() {
  local id="$1" d deps
  [[ -n "${_seen[$id]:-}" ]] && return
  deps="${C_DEPS[$id]:-}"; deps="${deps//,/ }"
  for d in $deps; do resolve "$d"; done
  _seen[$id]=1
  SELECTED_FINAL+=("$id")
}

# ============================================================================
# Display
# ============================================================================
print_catalog() {
  printf "%-16s %-10s %-24s %s\n" "ID" "TYPE" "REPO" "DESCRIPTION"
  local id
  for id in "${COMPONENT_ORDER[@]}"; do
    printf "%-16s %-10s %-24s %s\n" "$id" "${C_TYPE[$id]}" "${C_REPO[$id]:-—}" "${C_DESC[$id]}"
  done
}

usage() {
  cat <<'EOF'
pi-setup — bootstrap installer for pi config (catalog in components.conf).

Usage:
  ./install.sh [options]

Selection:
  (none)              interactive menu (when stdin is a TTY)
  --all               install everything in the catalog
  --extensions        install all extensions (deps auto-added)
  --skills            install all skill-library components
  --core              install/upgrade the pi CLI only
  --only A,B,C        install only the listed component ids (see --list)

Modifiers:
  --update            pull latest for already-installed repos instead of skipping
  --no-npm-install    skip `npm install` for extensions
  --protocol ssh|https  git protocol (default: ssh, env: PI_GIT_PROTOCOL)
  --user <user>       github user/org (default: djordjeveljkovic, env: PI_GH_USER)
  --pi-home <dir>     target directory (default: ~/.pi, env: PI_HOME)
  --dry-run           print what would happen, change nothing
  -y, --no-interaction  never prompt; if no selection given, install the default set

Catalog management:
  --list              print the component catalog and exit
  --check, --validate validate components.conf and exit
  --add key=val ...   append a new component to components.conf
                      (interactive if no key=val given)
  --self-update       git pull this repo, then run ./install.sh --update --all

Info:
  -h, --help          show this help

Examples:
  ./install.sh --all
  ./install.sh --only skill-manager,workflow
  ./install.sh --add id=my-ext type=extension repo=my-ext path=agent/extensions/my-ext desc="My ext"
  ./install.sh --self-update
  PI_GIT_PROTOCOL=https ./install.sh --extensions -y
EOF
}

# ============================================================================
# Interactive menu
# ============================================================================
declare -gA NUM2ID=()
show_menu() {
  printf "\n${C_BOLD}pi-setup${C_RESET} — select components to install.\n"
  printf "Installed clones are marked with ${C_GREEN}✓${C_RESET}.\n\n"
  local idx=1 g id mark
  for g in "${GROUP_ORDER[@]}"; do
    printf "${C_CYAN}%s:${C_RESET}\n" "$g"
    for id in "${COMPONENT_ORDER[@]}"; do
      [[ "${C_GROUP[$id]}" == "$g" ]] || continue
      NUM2ID[$idx]=$id
      mark=" "
      if [[ -n "${C_PATH[$id]:-}" && -d "$PI_HOME/${C_PATH[$id]}/.git" ]]; then mark="${C_GREEN}✓${C_RESET}"; fi
      local deps_note=""
      [[ -n "${C_DEPS[$id]:-}" ]] && deps_note="  ${C_DIM}(needs ${C_DEPS[$id]})${C_RESET}"
      printf "  ${C_BOLD}[%2d]%s %-16s${C_RESET} %s%s\n" "$idx" "$mark" "$id" "${C_DESC[$id]}" "$deps_note"
      idx=$((idx + 1))
    done
    echo
  done
  printf "Enter numbers (comma/space separated). Shortcuts: ${C_BOLD}a${C_RESET}=all  "
  printf "${C_BOLD}x${C_RESET}=extensions  ${C_BOLD}s${C_RESET}=skills  ${C_BOLD}c${C_RESET}=core  ${C_BOLD}q${C_RESET}=quit\n"
  printf "Selection: "
  read -r selection
  parse_menu "$selection"
}

parse_menu() {
  local input tok
  input="$(printf "%s" "$*" | tr ',' ' ' | tr '[:upper:]' '[:lower:]')"
  SELECTED=()
  for tok in $input; do
    case "$tok" in
      a|all)          SELECTED=("${COMPONENT_ORDER[@]}"); return ;;
      x|ext|extensions) SELECTED=("${EXTENSION_IDS[@]}"); return ;;
      s|skills)       SELECTED=("${SKILL_IDS[@]}"); return ;;
      c|core)         SELECTED=(pi-core); return ;;
      q|quit|exit|n)  echo "Aborted."; exit 0 ;;
    esac
    if [[ "$tok" =~ ^[0-9]+$ ]] && [[ -n "${NUM2ID[$tok]:-}" ]]; then
      SELECTED+=("${NUM2ID[$tok]}")
    elif [[ -n "$tok" ]]; then
      warn "ignoring unknown menu input: $tok"
    fi
  done
}

# ============================================================================
# --add : append a component to components.conf
# ============================================================================
ask() { # ask "Prompt" "default"  -> sets global $ans
  local prompt="$1" def="${2:-}"
  if [[ -n "$def" ]]; then printf "%s [%s]: " "$prompt" "$def"; else printf "%s: " "$prompt"; fi
  read -r ans
  [[ -z "$ans" ]] && ans="$def"
}

do_add() {
  local kv
  local -A a=()

  if (( $# > 0 )); then
    # non-interactive: key=value pairs
    for kv in "$@"; do
      [[ "$kv" == *=* ]] || { err "--add: expected key=value, got '$kv'"; exit 2; }
      local k="${kv%%=*}" v="${kv#*=}"
      case "$k" in
        id|type|repo|path|deps|group|builtin|desc) a[$k]="$v" ;;
        *) err "--add: unknown key '$k' (allowed: id type repo path deps group builtin desc)"; exit 2 ;;
      esac
    done
  else
    # interactive
    while true; do ask "id (lowercase, digits, hyphens)" ""; a[id]="$ans"
      [[ "${a[id]}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { warn "invalid id"; continue; }; break; done
    while true; do ask "type (extension/skills/step)" "extension"; a[type]="$ans"
      case "${a[type]}" in extension|skills|step) break;; *) warn "invalid type";; esac; done
    if [[ "${a[type]}" == step ]]; then
      while true; do ask "builtin handler" ""; a[builtin]="$ans"
        declare -F "builtin_${a[builtin]//-/_}" >/dev/null 2>&1 && break || warn "unknown builtin"; done
    else
      ask "github repo name" "${a[id]}"; a[repo]="$ans"
      local dp; [[ "${a[type]}" == skills ]] && dp="agent/skills/${a[id]}" || dp="agent/extensions/${a[id]}"
      ask "install path (under \$PI_HOME)" "$dp"; a[path]="$ans"
    fi
    ask "deps (ids, optional)" ""; a[deps]="$ans"
    ask "group (optional, blank=auto)" ""; a[group]="$ans"
    ask "description" ""; a[desc]="$ans"
  fi

  # validate required fields
  [[ -n "${a[id]:-}" ]]   || { err "--add: 'id' is required"; exit 2; }
  [[ "${a[id]}" =~ ^[a-z0-9][a-z0-9-]*$ ]] || { err "--add: invalid id '${a[id]}'"; exit 2; }
  case "${a[type]:-}" in
    extension|skills) [[ -n "${a[repo]:-}" ]] || { err "--add: 'repo' is required for ${a[type]}"; exit 2; }
                      [[ -n "${a[path]:-}" ]] || { err "--add: 'path' is required for ${a[type]}"; exit 2; } ;;
    step) [[ -n "${a[builtin]:-}" ]] || { err "--add: 'builtin' is required for step"; exit 2; } ;;
    *) err "--add: 'type' must be extension|skills|step (got '${a[type]:-}')"; exit 2 ;;
  esac

  # load existing manifest to check uniqueness & validity
  load_manifest
  if (( MANIFEST_ERRORS > 0 )); then die "fix existing manifest errors first (--check)"; fi
  [[ -z "${C_TYPE[${a[id]}]:-}" ]] || die "--add: id '${a[id]}' already exists in $MANIFEST"

  # append a clean block
  {
    printf '\n[[component]]\n'
    printf 'id   = %s\n' "${a[id]}"
    printf 'type = %s\n' "${a[type]}"
    [[ -n "${a[repo]:-}"    ]] && printf 'repo = %s\n' "${a[repo]}"
    [[ -n "${a[path]:-}"    ]] && printf 'path = %s\n' "${a[path]}"
    [[ -n "${a[builtin]:-}" ]] && printf 'builtin = %s\n' "${a[builtin]}"
    [[ -n "${a[deps]:-}"    ]] && printf 'deps = %s\n' "${a[deps]}"
    [[ -n "${a[group]:-}"   ]] && printf 'group = %s\n' "${a[group]}"
    [[ -n "${a[desc]:-}"    ]] && printf 'desc = %s\n' "${a[desc]}"
  } >> "$MANIFEST"
  ok "added '${a[id]}' to $MANIFEST"

  # re-validate
  load_manifest
  if (( MANIFEST_ERRORS > 0 )); then die "the resulting manifest is invalid — review $MANIFEST"; fi
  log "catalog now:"
  print_catalog
}

# ============================================================================
# --self-update : pull this repo, then refresh everything
# ============================================================================
self_update() {
  log "Updating pi-setup itself ($SCRIPT_DIR)…"
  if [[ ! -d "$SCRIPT_DIR/.git" ]]; then
    warn "$SCRIPT_DIR is not a git clone — skipping self-update"
    return 1
  fi
  if git -C "$SCRIPT_DIR" pull --ff-only 2>&1 | sed 's/^/  /'; then
    ok "pi-setup updated"
    if [[ "${1:-}" == "--rerun" ]]; then
      log "re-running with --update --all …"
      exec "$SCRIPT_DIR/install.sh" --update --all "${PI_RERUN_ARGS[@]:-}"
    fi
    info "now run: ./install.sh --update --all"
  else
    warn "could not pull (local changes or divergence?) — resolve and retry"
    return 1
  fi
}

# ============================================================================
# Argument parsing
# ============================================================================
SELECTION_MODE="none"
ONLY_IDS=()
DRY_RUN=0
UPDATE_MODE=0
INTERACTIVE_OK=1
DO_ADD=0
ADD_ARGS=()
DO_CHECK=0
DO_SELFUPDATE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)        usage; exit 0 ;;
    --list)           ACTION=list ;;
    --check|--validate) DO_CHECK=1 ;;
    --add)            DO_ADD=1; shift; while [[ $# -gt 0 ]]; do ADD_ARGS+=("$1"); shift; done ;;
    --self-update)    DO_SELFUPDATE=1 ;;
    --all)            SELECTION_MODE="all" ;;
    --extensions)     SELECTION_MODE="ext" ;;
    --skills)         SELECTION_MODE="skills" ;;
    --core)           SELECTION_MODE="core" ;;
    --only)           SELECTION_MODE="only"; shift; IFS=',' read -ra ONLY_IDS <<< "$1" ;;
    --update)         UPDATE_MODE=1 ;;
    --no-npm-install) PI_NPM_INSTALL=0 ;;
    --protocol)       shift; PI_GIT_PROTOCOL="$1" ;;
    --user)           shift; PI_GH_USER="$1" ;;
    --pi-home)        shift; PI_HOME="$1" ;;
    --dry-run)        DRY_RUN=1 ;;
    -y|--no-interaction) INTERACTIVE_OK=0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 2 ;;
  esac
  shift
done

# --- Actions that don't need full selection logic ---------------------------
if [[ "$DO_CHECK" == 1 ]]; then
  load_manifest
  if (( MANIFEST_ERRORS > 0 )); then
    err "components.conf has $MANIFEST_ERRORS error(s)."
    exit 1
  fi
  ok "components.conf is valid — ${#COMPONENT_ORDER[@]} component(s), ${#EXTENSION_IDS[@]} extension(s), ${#SKILL_IDS[@]} skill(s)."
  exit 0
fi

if [[ "$DO_SELFUPDATE" == 1 ]]; then
  self_update --rerun
  exit $?
fi

# Load + validate the manifest for everything else.
load_manifest
if (( MANIFEST_ERRORS > 0 )); then
  err "components.conf has $MANIFEST_ERRORS error(s). Fix them first (./install.sh --check)."
  exit 1
fi

if [[ "${ACTION:-}" == list ]]; then
  print_catalog
  exit 0
fi

if [[ "$DO_ADD" == 1 ]]; then
  do_add "${ADD_ARGS[@]}"
  exit $?
fi

# ============================================================================
# Build selection
# ============================================================================
SELECTED=()
case "$SELECTION_MODE" in
  all)    SELECTED=("${COMPONENT_ORDER[@]}") ;;
  ext)    SELECTED=("${EXTENSION_IDS[@]}") ;;
  skills) SELECTED=("${SKILL_IDS[@]}") ;;
  core)   SELECTED=(pi-core) ;;
  only)   SELECTED=("${ONLY_IDS[@]}") ;;
esac

if [[ ${#SELECTED[@]} -eq 0 ]]; then
  if [[ "$INTERACTIVE_OK" == 1 && -t 0 ]]; then
    show_menu
  else
    SELECTED=("${COMPONENT_ORDER[@]}")
    log "No selection and non-interactive — installing default set (see --help)"
  fi
fi

# validate ids
for id in "${SELECTED[@]}"; do
  [[ -n "${C_TYPE[$id]:-}" ]] || die "unknown component id: '$id' (run ./install.sh --list)"
done

# ============================================================================
# Run
# ============================================================================
echo
log "pi home   : $PI_HOME"
log "github    : $PI_GH_USER ($PI_GIT_PROTOCOL)"
log "npm install: $([[ $PI_NPM_INSTALL == 1 ]] && echo yes || echo no)$([[ $UPDATE_MODE == 1 ]] && echo "   (update mode)")$([[ $DRY_RUN == 1 ]] && echo "   (DRY RUN)")"
echo

mkdir -p "$PI_HOME/agent/extensions" "$PI_HOME/agent/skills" "$PI_HOME/agent/themes"

_seen=(); SELECTED_FINAL=()
for id in "${SELECTED[@]}"; do resolve "$id"; done

failures=0
for id in "${SELECTED_FINAL[@]}"; do
  install_component "$id" || failures=$((failures + 1))
done

echo
log "Processed ${#SELECTED_FINAL[@]} component(s), $failures failure(s)."
if [[ $failures -eq 0 ]]; then
  ok "All done. Start (or restart) pi and run /reload to activate extensions & skills."
fi
exit $failures
