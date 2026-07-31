#!/bin/zsh
set -euo pipefail

repo_root="${0:A:h:h:h}"
source_strings="$repo_root/Sources/PalmierPro/Resources/Localization/en.lproj/Localizable.strings"
source_root="$repo_root/Sources/PalmierPro"
temporary_directory="$(mktemp -d /private/tmp/palmier-localization.XXXXXX)"
trap 'rm -rf "$temporary_directory"' EXIT

cd "$repo_root"
swift build \
  -Xswiftc -emit-localized-strings \
  -Xswiftc -emit-localized-strings-path \
  -Xswiftc "$temporary_directory"

typeset -A source_names
localized_source_names=()
stringsdata_arguments=()
while IFS= read -r source; do
  name="${source:t:r}"
  if [[ -n "${source_names[$name]-}" ]]; then
    print -u2 "Duplicate Swift filename prevents localization sync: $name.swift"
    exit 1
  fi
  source_names[$name]="$source"
  if grep -Eq 'L10n\.string\((#*)?"' "$source"; then
    localized_source_names+=("$name")
  fi
done < <(find "$source_root" -type f -name '*.swift' -print)

typeset -A dependency_names
while IFS= read -r source_list; do
  while IFS= read -r dependency_source; do
    [[ "$dependency_source" == "$source_root/"* ]] && continue
    dependency_names[${dependency_source:t:r}]="$dependency_source"
  done < "$source_list"
done < <(find "$repo_root/.build" -type f -name sources -path '*.build/sources' -print)

for name in "${localized_source_names[@]}"; do
  if [[ -n "${dependency_names[$name]-}" ]]; then
    print -u2 "Dependency Swift filename collides with localized app source: $name.swift"
    exit 1
  fi
  data="$temporary_directory/$name.stringsdata"
  if [[ ! -f "$data" ]]; then
    print -u2 "Missing compiler localization output for: $name.swift"
    exit 1
  fi
  stringsdata_arguments+=(--stringsdata "$data")
done

node scripts/localization/sync.mjs \
  --output "$source_strings" \
  "${stringsdata_arguments[@]}"
node scripts/localization/check.mjs
