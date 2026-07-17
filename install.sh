#!/usr/bin/env bash
#
# pi-setup — bootstrap installer for pi (the coding agent) configuration.
#
#   Clone this repo, then run ./install.sh to pick & install pi extensions,
#   skill libraries and config on any machine. Fully scripted — no AI needed.
#
#   Usage:
#     ./install.sh                 # interactive menu (default, in a TTY)
#     ./install.sh --all           # install everything
#     ./install.sh --extensions    # all extensions
#     ./install.sh --only skill-manager,workflow
#     ./install.sh --list          # show the catalog
#     ./install.sh --update --all  # git-pull already-installed repos
#
#   Environment variables (override any of these):
#     PI_HOME            target directory          (default: ~/.pi)
#     PI_GH_USER         github user/org           (default: djordjeveljkovic)
#     PI_GIT_PROTOCOL    ssh | https               (default: ssh)
#     PI_NPM_INSTALL     1 = run npm install       (default: 1)
#
set -uo pipefail

# ----------------------------------------------------------------------------
# Configuration (overridable via env)
# ----------------------------------------------------------------------------
PI_HOME="${PI_HOME:-$HOME/.pi}"
PI_GH_USER="${PI_GH_USER:-djordjeveljkovic}"
PI_GIT_PROTOCOL="${PI_GIT_PROTOCOL:-ssh}"   # ssh | https
PI_NPM_INSTALL="${PI_NPM_INSTALL:-1}"       # 1 = run npm install for extensions

# ----------------------------------------------------------------------------
# Pretty printing
# ----------------------------------------------------------------------------
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

# ----------------------------------------------------------------------------
# Catalog  (edit this block to add/remove components)
# ----------------------------------------------------------------------------
# COMPONENT_ORDER also defines default install/display order.
COMPONENT_ORDER=(
  pi-core
  skills-library
  list-picker
  skill-manager
  image-workflow
  questionnaire
  workflow
  settings
)

declare -A C_TYPE C_REPO C_PATH C_DESC C_DEPS C_GROUP

# --- Core -------------------------------------------------------------------
C_GROUP[pi-core]="Core"
C_TYPE[pi-core]="step-pi"
C_DESC[pi-core]="Install the pi CLI (@earendil-works/pi-coding-agent) via npm"

# --- Skills -----------------------------------------------------------------
C_GROUP[skills-library]="Skills"
C_TYPE[skills-library]="skills"
C_REPO[skills-library]="pi-skills-library"
C_PATH[skills-library]="agent/skills-library"
C_DESC[skills-library]="Curated skills library (86 skills across 10 collections)"

# --- Extensions -------------------------------------------------------------
C_GROUP[list-picker]="Extensions"
C_TYPE[list-picker]="extension"
C_REPO[list-picker]="pi-list-picker"
C_PATH[list-picker]="agent/extensions/list-picker"
C_DESC[list-picker]="Reusable TUI list picker component"

C_GROUP[skill-manager]="Extensions"
C_TYPE[skill-manager]="extension"
C_REPO[skill-manager]="pi-skill-manager"
C_PATH[skill-manager]="agent/extensions/skill-manager"
C_DESC[skill-manager]="Browse, toggle and filter skill libraries"
C_DEPS[skill-manager]="list-picker"     # resolved via file:../list-picker

C_GROUP[image-workflow]="Extensions"
C_TYPE[image-workflow]="extension"
C_REPO[image-workflow]="pi-image-workflow"
C_PATH[image-workflow]="agent/extensions/image-workflow"
C_DESC[image-workflow]="Interactive image-collecting workflow"

C_GROUP[questionnaire]="Extensions"
C_TYPE[questionnaire]="extension"
C_REPO[questionnaire]="pi-questionnaire"
C_PATH[questionnaire]="agent/extensions/questionnaire"
C_DESC[questionnaire]="Interactive questionnaire component (single/multi/text/confirm/number)"

C_GROUP[workflow]="Extensions"
C_TYPE[workflow]="extension"
C_REPO[workflow]="pi-workflow"
C_PATH[workflow]="agent/extensions/workflow"
C_DESC[workflow]="/quick, /plan and /ask slash commands"

# --- Config -----------------------------------------------------------------
C_GROUP[settings]="Config"
C_TYPE[settings]="step-settings"
C_DESC[settings]="Subagent model overrides (MiniMax) template -> settings.json"

GROUP_ORDER=("Core" "Skills" "Extensions" "Config")

EXTENSION_IDS=(list-picker skill-manager image-workflow questionnaire workflow)
SKILL_IDS=(skills-library)

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
url_for() {
  case "$PI_GIT_PROTOCOL" in
    https) echo "https://github.com/$PI_GH_USER/${1}.git" ;;
    *)     echo "git@github.com:$PI_GH_USER/${1}.git" ;;
  esac
}

script_dir() {
  local d; d="$(readlink -f "${BASH_SOURCE[0]:-$0}" 2>/dev/null)"; echo "${d%/*}"
}

print_catalog() {
  printf "%-16s %-12s %-22s %s\n" "ID" "TYPE" "REPO" "DESCRIPTION"
  for id in "${COMPONENT_ORDER[@]}"; do
    printf "%-16s %-12s %-22s %s\n" "$id" "${C_TYPE[$id]}" "${C_REPO[$id]:-—}" "${C_DESC[$id]}"
  done
}

usage() {
  cat <<'EOF'
pi-setup — bootstrap installer for pi config.

Usage:
  ./install.sh [options]

Selection (mutually understood in order: explicit flags > interactive menu):
  (none)              interactive menu (when stdin is a TTY)
  --all               install everything in the catalog
  --extensions        install all extensions
  --skills            install the skills library
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

Info:
  --list              print the component catalog and exit
  -h, --help          show this help

Examples:
  ./install.sh --all
  ./install.sh --only skill-manager,workflow
  PI_GIT_PROTOCOL=https ./install.sh --extensions -y
  ./install.sh --update --all        # keep everything up to date
EOF
}

# ----------------------------------------------------------------------------
# Dependency resolution  (deps are installed before dependents)
# ----------------------------------------------------------------------------
declare -gA _seen=()
SELECTED_FINAL=()
resolve() {
  local id="$1" d
  [[ -n "${_seen[$id]:-}" ]] && return
  for d in ${C_DEPS[$id]:-}; do resolve "$d"; done
  _seen[$id]=1
  SELECTED_FINAL+=("$id")
}

# ----------------------------------------------------------------------------
# Installers per type
# ----------------------------------------------------------------------------
step_pi() {
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

step_settings() {
  log "[settings] subagent model overrides"
  local target="$PI_HOME/settings.json"
  local tmpl; tmpl="$(script_dir)/templates/settings.json"
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
    if [[ "$DRY_RUN" == 1 ]]; then
      info "DRY-RUN: git clone $url $target"
      return 0
    fi
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

install_component() {
  case "${C_TYPE[$1]:-}" in
    step-pi)       step_pi "$1" ;;
    step-settings) step_settings "$1" ;;
    extension|skills) clone_repo "$1" ;;
    *) die "unknown component type for '$1'" ;;
  esac
}

# ----------------------------------------------------------------------------
# Interactive menu
# ----------------------------------------------------------------------------
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
      printf "  ${C_BOLD}[%2d]%s %-16s${C_RESET} %s\n" "$idx" "$mark" "$id" "${C_DESC[$id]}"
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
      a|all)        SELECTED=("${COMPONENT_ORDER[@]}"); return ;;
      x|ext|extensions) SELECTED=("${EXTENSION_IDS[@]}"); return ;;
      s|skills)     SELECTED=("${SKILL_IDS[@]}"); return ;;
      c|core)       SELECTED=(pi-core); return ;;
      q|quit|exit|n) echo "Aborted."; exit 0 ;;
    esac
    if [[ "$tok" =~ ^[0-9]+$ ]] && [[ -n "${NUM2ID[$tok]:-}" ]]; then
      SELECTED+=("${NUM2ID[$tok]}")
    elif [[ -n "$tok" ]]; then
      warn "ignoring unknown menu input: $tok"
    fi
  done
}

# ----------------------------------------------------------------------------
# Argument parsing
# ----------------------------------------------------------------------------
SELECTION_MODE="none"
ONLY_IDS=()
DRY_RUN=0
UPDATE_MODE=0
INTERACTIVE_OK=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)        usage; exit 0 ;;
    --list)           print_catalog; exit 0 ;;
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
    SELECTED=(pi-core skills-library list-picker skill-manager image-workflow questionnaire workflow settings)
    log "No selection and non-interactive — installing default set (see --help)"
  fi
fi

# validate
for id in "${SELECTED[@]}"; do
  [[ -n "${C_TYPE[$id]:-}" ]] || die "unknown component id: '$id' (run ./install.sh --list)"
done

# ----------------------------------------------------------------------------
# Run
# ----------------------------------------------------------------------------
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
