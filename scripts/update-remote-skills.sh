#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${APM_MANIFEST:-$ROOT/apm.yml}"
DRY_RUN=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    -h|--help)
      printf 'Usage: %s [--dry-run]\n' "$(basename "$0")"
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$arg" >&2
      exit 2
      ;;
  esac
done

for command in git ruby apm; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

if [[ ! -f "$MANIFEST" ]]; then
  printf 'Manifest not found: %s\n' "$MANIFEST" >&2
  exit 1
fi

next_version="$(ruby -ryaml -e '
  version = YAML.safe_load(File.read(ARGV.fetch(0))).fetch("version").to_s
  match = version.match(/\A(\d+)\.(\d+)\.(\d+)\z/) || abort("Expected a numeric MAJOR.MINOR.PATCH version, got: #{version}")
  puts "#{match[1]}.#{match[2]}.#{match[3].to_i + 1}"
' "$MANIFEST")"

packages="$(ruby -ryaml -e '
  manifest = YAML.safe_load(File.read(ARGV.fetch(0)))
  packages = manifest.dig("marketplace", "packages") || abort("No marketplace.packages in manifest")
  packages.each do |package|
    source = package["source"]
    ref = package["ref"]
    name = package.fetch("name")
    unless source.is_a?(String) && !source.start_with?("./")
      puts ["local", name, source].join("\t")
      next
    end

    repo = source.sub(%r{\Ahttps://github\.com/}, "").sub(%r{\.git\z}, "").sub(%r{/\z}, "")
    unless repo.match?(%r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z}) && ref
      puts ["skipped", name, source].join("\t")
      next
    end

    puts ["remote", name, repo, ref].join("\t")
  end
' "$MANIFEST")"

if [[ -z "$packages" ]]; then
  printf 'No pinned GitHub packages found in %s\n' "$MANIFEST"
  exit 0
fi

replace_ref() {
  local package_name="$1"
  local new_ref="$2"
  local temp_file

  temp_file="$(mktemp "${MANIFEST}.XXXXXX")"
  if ! awk -v target="$package_name" -v new_ref="$new_ref" '
    /^    - name: / { in_target = ($0 == "    - name: " target) }
    in_target && /^      ref: / {
      print "      ref: " new_ref
      replaced = 1
      next
    }
    { print }
    END { if (!replaced) exit 1 }
  ' "$MANIFEST" > "$temp_file"; then
    rm -f "$temp_file"
    printf 'Could not locate ref for package: %s\n' "$package_name" >&2
    return 1
  fi

  chmod 644 "$temp_file"
  mv "$temp_file" "$MANIFEST"
}

bump_version() {
  local new_version="$1"
  local temp_file

  temp_file="$(mktemp "${MANIFEST}.XXXXXX")"
  if ! awk -v version="$new_version" '
    /^version: / && !replaced { print "version: " version; replaced = 1; next }
    { print }
    END { if (!replaced) exit 1 }
  ' "$MANIFEST" > "$temp_file"; then
    rm -f "$temp_file"
    printf 'Could not update the top-level version in %s\n' "$MANIFEST" >&2
    return 1
  fi

  chmod 644 "$temp_file"
  mv "$temp_file" "$MANIFEST"
}

changed=0
pending=0
failed=0
while IFS=$'\t' read -r package_type package_name repo old_ref; do
  [[ -n "$package_name" ]] || continue

  if [[ "$package_type" == "local" ]]; then
    printf 'Skipping local package: %s (%s)\n' "$package_name" "$repo"
    continue
  fi
  if [[ "$package_type" == "skipped" ]]; then
    printf 'Skipping non-GitHub or unpinned package: %s (%s)\n' "$package_name" "$repo"
    continue
  fi

  if ! remote="$(git ls-remote --symref "https://github.com/${repo}.git" HEAD 2>/dev/null)"; then
    printf 'Could not query GitHub for %s (%s); continuing.\n' "$package_name" "$repo" >&2
    failed=1
    continue
  fi
  new_ref="$(printf '%s\n' "$remote" | awk '$2 == "HEAD" && $1 !~ /^ref:/ { print $1; exit }')"
  if [[ ! "$new_ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
    printf 'Could not resolve default-branch HEAD for %s (%s); continuing.\n' "$package_name" "$repo" >&2
    failed=1
    continue
  fi

  if [[ "$new_ref" == "$old_ref" ]]; then
    printf 'Up to date: %s (%s)\n' "$package_name" "$new_ref"
    continue
  fi

  printf '%s: %s -> %s\n' "$package_name" "$old_ref" "$new_ref"
  pending=1
  if (( DRY_RUN )); then
    continue
  fi

  replace_ref "$package_name" "$new_ref"
  changed=1
done <<< "$packages"

if (( changed )); then
  bump_version "$next_version"
  printf 'Marketplace version bumped to %s\n' "$next_version"
  (cd "$ROOT" && apm pack)
elif (( DRY_RUN )); then
  if (( pending )); then
    printf 'Would bump marketplace version to %s\n' "$next_version"
  else
    printf 'No remote pins changed; marketplace version stays unchanged.\n'
  fi
  printf 'Dry run complete; no files changed.\n'
fi

if (( failed )); then
  exit 1
fi