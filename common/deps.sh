#!/usr/bin/env bash
# deps.sh - dependency automation for the hand-pinned tools (the ones Dependabot/Renovate
# can't fully manage). Two modes:
#
#   deps.sh check                     report pinned vs latest upstream for every tool
#                                      (exit 3 if any are outdated; used by the weekly CI job)
#   deps.sh refresh-digests [tool...] recompute each tool's *_SHA256 from the artifact at its
#                                      CURRENTLY pinned version and rewrite it in place
#                                      (no args = all; e.g. `refresh-digests s6 composer`)
#
# Verifying digests has no separate mode: run `refresh-digests` then `git diff --exit-code`
# (the CI job does this) - a nonzero diff means a pinned digest drifted from upstream.
#
# Tools: s6-overlay, composer, pie, castor, goss (Renovate-managed versions) + gcloud,
# azure-cli (no standard Renovate datasource - reported here only). Needs curl + a sha256
# tool (sha256sum or shasum); portable across Linux CI and macOS.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/common/bin"
CI="$ROOT/.github/workflows/ci.yml"
LOCK="$ROOT/dind/azure-cli-requirements.txt"

# Each tool pins its versions/digests in its own standalone jarvis-* command file.
S6_FILE="$BIN/jarvis-install-s6-overlay"
COMPOSER_FILE="$BIN/jarvis-install-composer"
PIE_FILE="$BIN/jarvis-install-pie"
CASTOR_FILE="$BIN/jarvis-install-castor"
GCLOUD_FILE="$BIN/jarvis-install-gcloud"

# --- primitives --------------------------------------------------------------
sha256() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1; else shasum -a 256 "$1" | cut -d' ' -f1; fi; }
strip_v() { echo "${1#v}"; }

# pinned `VAR="${VAR:-value}"` default from a jarvis-* file: pin <VAR> <file>
pin() { sed -n "s/^$1=\"\${$1:-\(.*\)}\"\$/\1/p" "$2"; }
# pinned `  KEY: value` from ci.yml
ci_pin() { sed -n "s/^[[:space:]]*$1:[[:space:]]*\(.*\)\$/\1/p" "$CI" | head -1; }

# rewrite VAR's default in a jarvis-* file, in place: set_pin <VAR> <val> <file>. `cat >`
# rewrites the existing file's contents so its 0755 mode is preserved (unlike `mv tmp file`).
set_pin() {
    local var=$1 val=$2 file=$3 tmp; tmp=$(mktemp)
    awk -v v="$var" -v n="$val" 'index($0,v"=\"${"v":-")==1{sub(/:-[^}]*}/,":-"n"}")}1' "$file" >"$tmp"
    cat "$tmp" >"$file"; rm -f "$tmp"
}
# rewrite `  KEY: value` in ci.yml, in place (preserving indent)
set_ci() {
    local key=$1 val=$2 tmp; tmp=$(mktemp)
    awk -v k="$key" -v n="$val" '{ if ($0 ~ "^[[:space:]]*"k":") { match($0,/^[[:space:]]*/); print substr($0,1,RLENGTH) k ": " n } else print }' "$CI" >"$tmp"
    cat "$tmp" >"$CI"; rm -f "$tmp"
}

# latest-version lookups (each echoes a bare version)
gh_latest()   { curl -fsSL "https://api.github.com/repos/$1/releases/latest" | sed -n 's/.*"tag_name": *"\([^"]*\)".*/\1/p' | head -1; }
composer_latest() { curl -fsSL "https://getcomposer.org/versions" | sed -n 's/.*"version": *"\([0-9][^"]*\)".*/\1/p' | head -1; }
gcloud_latest()   { curl -fsSL "https://dl.google.com/dl/cloudsdk/channels/rapid/components-2.json" | sed -n 's/.*"version": *"\([0-9.]*\)".*/\1/p' | head -1; }
azure_latest()    { curl -fsSL "https://pypi.org/pypi/azure-cli/json" | sed -n 's/.*"version":"\([0-9][^"]*\)".*/\1/p' | head -1; }

# download <url> -> temp file path (echoed)
fetch() { local d; d=$(mktemp); curl -fsSL "$1" -o "$d"; echo "$d"; }

# --- check mode --------------------------------------------------------------
row() { printf '%-12s %-14s %-14s %s\n' "$1" "$2" "$3" "$4"; }

check() {
    local outdated=0
    printf '%-12s %-14s %-14s %s\n' "TOOL" "PINNED" "LATEST" "STATUS"
    check_one() { # name pinned latest
        local status="ok"
        if [ "$2" != "$3" ]; then status="OUTDATED"; outdated=1; fi
        row "$1" "$2" "$3" "$status"
    }
    check_one s6-overlay "$(pin S6_OVERLAY_VERSION "$S6_FILE")"  "$(strip_v "$(gh_latest just-containers/s6-overlay)")"
    check_one composer   "$(pin COMPOSER_VERSION "$COMPOSER_FILE")" "$(composer_latest)"
    check_one pie        "$(pin PIE_VERSION "$PIE_FILE")"        "$(strip_v "$(gh_latest php/pie)")"
    check_one castor     "$(pin CASTOR_VERSION "$CASTOR_FILE")"  "$(strip_v "$(gh_latest jolicode/castor)")"
    check_one goss       "$(strip_v "$(ci_pin GOSS_VERSION)")" "$(strip_v "$(gh_latest goss-org/goss)")"
    check_one gcloud     "$(pin GCLOUD_VERSION "$GCLOUD_FILE")" "$(gcloud_latest)"
    # azure-cli's effective version lives in the lockfile, not AZURE_CLI_VERSION
    local az_pinned; az_pinned=$(sed -n 's/^azure-cli==\([0-9][^ ]*\).*/\1/p' "$LOCK" | head -1)
    check_one azure-cli  "$az_pinned" "$(azure_latest)"
    echo
    if [ "$outdated" -ne 0 ]; then
        echo "Some pins are behind upstream. For s6/composer/pie/castor/goss, let Renovate open the"
        echo "bump PR (or edit the pin) then run 'make bump-digests'. For gcloud edit GCLOUD_VERSION +"
        echo "'make bump-digests'; for azure-cli bump the lockfile via 'dind/gen-azure-hashes.sh'."
        return 3
    fi
    echo "All pinned tools are current."
}

# --- refresh-digests mode ----------------------------------------------------
refresh_s6() {
    local v base d
    v=$(pin S6_OVERLAY_VERSION "$S6_FILE")
    base="https://github.com/just-containers/s6-overlay/releases/download/v${v}"
    d=$(fetch "$base/s6-overlay-noarch.tar.xz");  set_pin S6_OVERLAY_SHA256_NOARCH "$(sha256 "$d")" "$S6_FILE"; rm -f "$d"
    d=$(fetch "$base/s6-overlay-x86_64.tar.xz");  set_pin S6_OVERLAY_SHA256_AMD64  "$(sha256 "$d")" "$S6_FILE"; rm -f "$d"
    d=$(fetch "$base/s6-overlay-aarch64.tar.xz"); set_pin S6_OVERLAY_SHA256_ARM64  "$(sha256 "$d")" "$S6_FILE"; rm -f "$d"
    echo "  s6-overlay $v: refreshed"
}
refresh_composer() {
    local v d; v=$(pin COMPOSER_VERSION "$COMPOSER_FILE")
    d=$(fetch "https://getcomposer.org/download/${v}/composer.phar"); set_pin COMPOSER_SHA256 "$(sha256 "$d")" "$COMPOSER_FILE"; rm -f "$d"
    echo "  composer $v: refreshed"
}
refresh_pie() {
    local v d; v=$(pin PIE_VERSION "$PIE_FILE")
    d=$(fetch "https://github.com/php/pie/releases/download/${v}/pie.phar"); set_pin PIE_SHA256 "$(sha256 "$d")" "$PIE_FILE"; rm -f "$d"
    echo "  pie $v: refreshed"
}
refresh_castor() {
    local v d; v=$(pin CASTOR_VERSION "$CASTOR_FILE")
    d=$(fetch "https://github.com/jolicode/castor/releases/download/v${v}/castor.linux-amd64"); set_pin CASTOR_SHA256_AMD64 "$(sha256 "$d")" "$CASTOR_FILE"; rm -f "$d"
    d=$(fetch "https://github.com/jolicode/castor/releases/download/v${v}/castor.linux-arm64"); set_pin CASTOR_SHA256_ARM64 "$(sha256 "$d")" "$CASTOR_FILE"; rm -f "$d"
    echo "  castor $v: refreshed"
}
refresh_goss() {
    local v d; v=$(ci_pin GOSS_VERSION)
    d=$(fetch "https://github.com/goss-org/goss/releases/download/${v}/goss-linux-amd64"); set_ci GOSS_SHA256_AMD64 "$(sha256 "$d")"; rm -f "$d"
    d=$(fetch "https://github.com/goss-org/goss/releases/download/${v}/goss-linux-arm64"); set_ci GOSS_SHA256_ARM64 "$(sha256 "$d")"; rm -f "$d"
    d=$(fetch "https://raw.githubusercontent.com/goss-org/goss/${v}/extras/dgoss/dgoss");  set_ci DGOSS_SHA256      "$(sha256 "$d")"; rm -f "$d"
    echo "  goss/dgoss $v: refreshed"
}
refresh_gcloud() {
    local v d; v=$(pin GCLOUD_VERSION "$GCLOUD_FILE")
    echo "  gcloud $v: downloading tarballs (~150MB each) ..."
    d=$(fetch "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${v}-linux-x86_64.tar.gz"); set_pin GCLOUD_SHA256_AMD64 "$(sha256 "$d")" "$GCLOUD_FILE"; rm -f "$d"
    d=$(fetch "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads/google-cloud-cli-${v}-linux-arm.tar.gz");    set_pin GCLOUD_SHA256_ARM64 "$(sha256 "$d")" "$GCLOUD_FILE"; rm -f "$d"
    echo "  gcloud $v: refreshed"
}

refresh_digests() {
    local all="s6 composer pie castor goss gcloud" sel
    sel="$*"; [ -z "$sel" ] && sel="$all"
    echo "Refreshing digests for: $sel"
    for t in $sel; do
        case "$t" in
            s6)       refresh_s6 ;;
            composer) refresh_composer ;;
            pie)      refresh_pie ;;
            castor)   refresh_castor ;;
            goss)     refresh_goss ;;
            gcloud)   refresh_gcloud ;;
            *) echo "unknown tool: $t (want: $all)" >&2; return 2 ;;
        esac
    done
    echo "Done. Review 'git diff' and commit. (azure-cli digests are in the lockfile - regenerate via dind/gen-azure-hashes.sh.)"
}

# --- dispatch ----------------------------------------------------------------
cmd="${1:-}"; shift || true
case "$cmd" in
    check)           check ;;
    refresh-digests) refresh_digests "$@" ;;
    *) echo "usage: $0 {check | refresh-digests [tool...]}" >&2; exit 2 ;;
esac
