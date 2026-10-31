#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MANIFEST="${APM_MANIFEST:-$ROOT/apm.yml}"
DRY_RUN=0
args=()
name_override=""
description_override=""

while (( $# )); do
  case "$1" in
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --name)
      (( $# >= 2 )) || { printf 'Missing value for --name\n' >&2; exit 2; }
      name_override="$2"
      shift 2
      ;;
    --description)
      (( $# >= 2 )) || { printf 'Missing value for --description\n' >&2; exit 2; }
      description_override="$2"
      shift 2
      ;;
    -h|--help)
      printf 'Usage: %s <repository-url> [subdir] [--name NAME] [--description TEXT] [--dry-run]\n' "$(basename "$0")"
      printf 'Legacy: %s <name> <description> <repository-url> [subdir] [--dry-run]\n' "$(basename "$0")"
      exit 0
      ;;
    *)
      args+=("$1")
      shift
      ;;
  esac
done

if [[ "${#args[@]}" -eq 1 || "${#args[@]}" -eq 2 ]]; then
  repo_input="${args[0]}"
  subdir="${args[1]:-}"
elif [[ "${#args[@]}" -eq 3 || "${#args[@]}" -eq 4 ]]; then
  name_override="${name_override:-${args[0]}}"
  description_override="${description_override:-${args[1]}}"
  repo_input="${args[2]}"
  subdir="${args[3]:-}"
else
  printf 'Expected a repository URL, with optional subdir and name/description overrides.\n' >&2
  printf 'Run %s --help for usage.\n' "$(basename "$0")" >&2
  exit 2
fi

for command in git ruby apm; do
  if ! command -v "$command" >/dev/null 2>&1; then
    printf 'Required command not found: %s\n' "$command" >&2
    exit 1
  fi
done

parsed_source="$(ruby -ruri -e '
  input = ARGV.fetch(0)
  if input.match?(%r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z})
    host = "github.com"
    path = input
  else
    begin
      uri = URI.parse(input)
    rescue URI::InvalidURIError
      abort("Invalid repository URL: #{input}")
    end
    unless uri.is_a?(URI::HTTPS) && %w[github.com gitlab.com].include?(uri.host) && !uri.userinfo && !uri.query && !uri.fragment
      abort("Use an HTTPS repository URL hosted on github.com or gitlab.com")
    end
    host = uri.host
    path = uri.path.sub(%r{\A/}, "").sub(%r{/\z}, "")
  end

  parts = path.split("/")
  parts[-1] = parts[-1].sub(/\.git\z/, "") if parts.any?
  route_index = if host == "github.com"
    %w[tree blob].include?(parts[2]) ? 2 : nil
  else
    parts.each_index.find { |index| parts[index] == "-" && %w[tree blob].include?(parts[index + 1]) }
  end

  if route_index
    repo_parts = parts[0...route_index]
    route_kind = parts[route_index + (host == "github.com" ? 0 : 1)]
    branch_index = route_index + (host == "github.com" ? 1 : 2)
    abort("Expected branch name after #{route_kind} in URL") unless parts[branch_index]
    skill_parts = parts[(branch_index + 1)..] || []
    skill_parts.pop if skill_parts.last == "SKILL.md"
  else
    repo_parts = parts
    skill_parts = []
  end

  valid_parts = (repo_parts + skill_parts).all? { |part| part.match?(%r{\A[A-Za-z0-9_.-]+\z}) && part != "." && part != ".." }
  valid_depth = host == "github.com" ? repo_parts.length == 2 : repo_parts.length >= 2
  abort("Expected a repository URL, not a file or directory URL") unless valid_parts && valid_depth

  repo_path = repo_parts.join("/")
  inferred_subdir = skill_parts.join("/")
  source = host == "github.com" ? repo_path : "https://#{host}/#{repo_path}.git"
  remote = "https://#{host}/#{repo_path}.git"
  puts [source, repo_path, remote, inferred_subdir].join("\t")
' "$repo_input")" || {
  printf 'Could not parse GitHub/GitLab repository or skill URL: %s\n' "$repo_input" >&2
  exit 2
}
IFS=$'\t' read -r source repo_path remote_url inferred_subdir <<< "$parsed_source"
if [[ -z "$source" || -z "$remote_url" ]]; then
  printf 'Could not parse repository input: %s\n' "$repo_input" >&2
  exit 2
fi
if [[ -z "$subdir" ]]; then
  subdir="$inferred_subdir"
fi

name="$name_override"
if [[ -z "$name" ]]; then
  name="$(ruby -e '
  value = ARGV.fetch(0).split("/").last.to_s.downcase.gsub(/[^a-z0-9._-]+/, "-").gsub(/\A[-.]+|[-.]+\z/, "")
  abort("Could not infer a valid skill name from URL") if value.empty?
  print value
' "${subdir:-$repo_path}")"
fi
description="$description_override"
if [[ -z "$description" ]]; then
  description="$(ruby -e '
  label = ARGV.fetch(0).split("/").last.to_s.tr("_-", "  ").split.map(&:capitalize).join(" ")
  print "#{label} skill from #{ARGV.fetch(1)}."
' "$name" "$repo_path")"
fi

if [[ ! "$name" =~ ^[a-z0-9][a-z0-9._-]*$ ]]; then
  printf 'Invalid package name: %s\n' "$name" >&2
  exit 2
fi

if [[ -n "$subdir" && ! "$subdir" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  printf 'Subdirectory must be a relative path using letters, numbers, ., _, /, and -.\n' >&2
  exit 2
fi

if [[ ! -f "$MANIFEST" ]]; then
  printf 'Manifest not found: %s\n' "$MANIFEST" >&2
  exit 1
fi

next_version="$(ruby -ryaml -e '
  version = YAML.safe_load(File.read(ARGV.fetch(0))).fetch("version").to_s
  match = version.match(/\A(\d+)\.(\d+)\.(\d+)\z/) || abort("Expected a numeric MAJOR.MINOR.PATCH version, got: #{version}")
  puts "#{match[1]}.#{match[2]}.#{match[3].to_i + 1}"
' "$MANIFEST")"

if ruby -ryaml -e '
  manifest = YAML.safe_load(File.read(ARGV.fetch(0)))
  packages = manifest.dig("marketplace", "packages") || abort("No marketplace.packages in manifest")
  exit(packages.any? { |package| package["name"] == ARGV.fetch(1) } ? 0 : 1)
' "$MANIFEST" "$name"; then
  printf 'Package already exists: %s\n' "$name" >&2
  exit 1
fi

if ! remote="$(git ls-remote --symref "$remote_url" HEAD)"; then
  printf 'Could not query remote repository: %s\n' "$remote_url" >&2
  exit 1
fi
ref="$(printf '%s\n' "$remote" | awk '$2 == "HEAD" && $1 !~ /^ref:/ { print $1; exit }')"
if [[ ! "$ref" =~ ^[0-9a-fA-F]{40}$ ]]; then
  printf 'Could not resolve default-branch HEAD for %s\n' "$repo_input" >&2
  exit 1
fi

quoted_description="$(ruby -rjson -e 'print JSON.generate(ARGV.fetch(0))' "$description")"
package="    - name: ${name}
      description: ${quoted_description}
      source: ${source}
"
if [[ -n "$subdir" ]]; then
  package+="      subdir: ${subdir}
"
fi
package+="      ref: ${ref}"

printf 'Package: %s\nRepository: %s\nManifest source: %s\n' "$name" "$repo_path" "$source"
if [[ -n "$subdir" ]]; then
  printf 'Subdirectory: %s\n' "$subdir"
fi
printf 'Pinned commit: %s\n' "$ref"
printf 'Marketplace version: %s -> %s\n' "$(ruby -ryaml -e 'print YAML.safe_load(File.read(ARGV.fetch(0))).fetch("version")' "$MANIFEST")" "$next_version"
if (( DRY_RUN )); then
  printf 'Dry run; manifest and catalogs unchanged.\n'
  exit 0
fi

printf '\n%s\n' "$package" >> "$MANIFEST"
temp_file="$(mktemp "${MANIFEST}.XXXXXX")"
if ! awk -v version="$next_version" '
  /^version: / && !replaced { print "version: " version; replaced = 1; next }
  { print }
  END { if (!replaced) exit 1 }
' "$MANIFEST" > "$temp_file"; then
  rm -f "$temp_file"
  printf 'Could not update the top-level version in %s\n' "$MANIFEST" >&2
  exit 1
fi
chmod 644 "$temp_file"
mv "$temp_file" "$MANIFEST"
(cd "$ROOT" && apm pack)