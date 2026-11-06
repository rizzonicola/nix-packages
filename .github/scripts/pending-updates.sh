#!/usr/bin/env bash
# Print, as a compact JSON array, the packages whose upstream release differs
# from the version pinned in package.nix.
#
# This runs in a plain Ubuntu job without Nix and only queries the GitHub API,
# so the weekly workflow starts a Nix-enabled runner and nix-update only for
# packages that actually have a new release.
#
# The check is conservative: whenever the upstream version cannot be
# determined cheaply (src is not a GitHub release download, nix-update gets
# arguments that change where the version comes from, the GitHub API fails),
# the package is reported and nix-update makes the decision itself.
set -euo pipefail

root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"

log() { printf '%s\n' "$*" >&2; }

# Print the version captured by the nix-update --version-regex $2 from the tag
# $1, joining capture groups with dots exactly like nix-update does.
tag_version() {
  local tag=$1 regex=$2
  [[ $tag =~ $regex ]] || return 1
  local -a groups=()
  local i
  for ((i = 1; i < ${#BASH_REMATCH[@]}; i++)); do
    [[ -n ${BASH_REMATCH[i]} ]] && groups+=("${BASH_REMATCH[i]}")
  done
  ((${#groups[@]} > 0)) || return 1
  local IFS=.
  printf '%s\n' "${groups[*]}"
}

# Return 0 when nix-update should run for the package, 1 when the version in
# package.nix is already the latest upstream release.
needs_update() {
  local pkg=$1 dir="pkgs/$1" file="pkgs/$1/package.nix"
  local -a args=()
  if [[ -f $dir/nix-update-args ]]; then
    mapfile -t args <"$dir/nix-update-args"
  fi

  # These options change where or which version comes from: do not try to
  # guess, let nix-update decide.
  local arg
  for arg in "${args[@]}"; do
    case $arg in
      --url | --url=* | --version | --version=* | -vr | -vr=* | --branch | --branch=* | \
        --rev | --rev=* | -u | --use-update-script)
        log "$pkg: custom nix-update arguments, will run nix-update"
        return 0
        ;;
    esac
  done

  local current
  current=$(awk -F'"' '/^[[:space:]]*version[[:space:]]*=[[:space:]]*"/ { print $2; exit }' "$file")
  if [[ -z $current ]]; then
    log "$pkg: cannot read the version from package.nix, will run nix-update"
    return 0
  fi

  # A GitHub release download URL gives both the repository and the tag
  # layout, e.g.
  #   https://github.com/horizon-rust/horizon/releases/download/launcher@${finalAttrs.version}/...
  # yields repo "horizon-rust/horizon" and tag prefix "launcher@".
  local url repo tag_template prefix
  url=$(grep -m1 -oE 'github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/releases/download/[^/"]+' "$file" || true)
  if [[ -z $url ]]; then
    log "$pkg: src is not a GitHub release download, will run nix-update"
    return 0
  fi
  repo=$(sed -E 's#^.*github\.com/([^/]+/[^/]+)/releases/download/.*$#\1#' <<<"$url")
  tag_template=$(sed -E 's#^.*/releases/download/([^/]+).*$#\1#' <<<"$url")
  prefix=${tag_template%%\$\{*}

  # nix-update applies --version-regex to the whole tag, defaulting to taking
  # the numeric X.Y.Z part of the tag.
  local regex="" i
  for i in "${!args[@]}"; do
    case ${args[i]} in
      --version-regex=* | -vr=*) regex=${args[i]#*=} ;;
      --version-regex | -vr) regex=${args[i + 1]:-} ;;
    esac
  done

  local tags
  if ! tags=$(gh api "repos/$repo/releases?per_page=100" --paginate \
    --jq '.[] | select(.draft == false and .prerelease == false) | .tag_name' 2>/dev/null); then
    log "$pkg: cannot query the GitHub releases of $repo, will run nix-update"
    return 0
  fi

  local versions=() tag rest version
  while IFS= read -r tag; do
    [[ -n $tag && $tag == "$prefix"* ]] || continue
    if [[ -n $regex ]]; then
      version=$(tag_version "$tag" "$regex") || continue
    else
      rest=${tag#"$prefix"}
      version=$(tag_version "$rest" '^([0-9]+\.[0-9]+\.[0-9]+)$') || continue
    fi
    versions+=("$version")
  done <<<"$tags"

  if ((${#versions[@]} == 0)); then
    log "$pkg: no release matches the tag pattern, will run nix-update"
    return 0
  fi

  local latest
  latest=$(printf '%s\n' "${versions[@]}" | sort -V | tail -n1)
  if [[ $latest == "$current" ]]; then
    log "$pkg: $current is the latest release"
    return 1
  fi
  log "$pkg: $current -> $latest"
  return 0
}

pending=()
for dir in pkgs/*/; do
  pkg=$(basename "$dir")
  [[ -e "$dir/no-auto-update" ]] && continue
  if needs_update "$pkg"; then
    pending+=("$pkg")
  fi
done

# Package names are [a-z0-9-] only, so the JSON needs no escaping.
json="["
for pkg in "${pending[@]}"; do
  json+="\"$pkg\","
done
json="${json%,}]"
echo "$json"
