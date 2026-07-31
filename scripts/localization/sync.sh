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
stringsdata_arguments=()
while IFS= read -r source; do
  name="${source:t:r}"
  if [[ -n "${source_names[$name]-}" ]]; then
    print -u2 "Duplicate Swift filename prevents localization sync: $name.swift"
    exit 1
  fi
  source_names[$name]="$source"
  data="$temporary_directory/$name.stringsdata"
  [[ -f "$data" ]] && stringsdata_arguments+=(--stringsdata "$data")
done < <(rg --files "$source_root" -g '*.swift')

node scripts/localization/sync.mjs \
  --output "$source_strings" \
  "${stringsdata_arguments[@]}"
node scripts/localization/check.mjs
