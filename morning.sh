#!/bin/bash
set -euo pipefail
 
FILE="2025.md"
PROJECTS_FILE="projects.yml"

[[ -f "$FILE" ]] || { echo "Error: $FILE not found."; exit 1; }
[[ -f "$PROJECTS_FILE" ]] || { echo "Error: $PROJECTS_FILE not found."; exit 1; }

DATE=$(date +"%d-%m-%Y")
TIME_NOW=$(date +"%H:%M")
ISO_NOW=$(date --iso-8601=seconds)  

LOCATION=$(curl -s ipinfo.io | grep -E '"city"|"country"' | awk -F: '{gsub(/[",]/, "", $2); print $2}' | paste -sd ", ")
[[ -n "$LOCATION" ]] || LOCATION="Location unavailable"

HEADING="## $DATE - ToDo @ $LOCATION"

TODOS=$(grep -n '^- \[ \]' "$FILE" || true)
grep -v '^- \[ \]' "$FILE" > "$FILE.tmp" && mv "$FILE.tmp" "$FILE"

declare -A PROJECTS
declare -a ORDER
while IFS=":" read -r tag name; do
  tag=$(echo "$tag" | xargs)
  name=$(echo "$name" | xargs)
  [[ -n "$tag" && -n "$name" ]] || continue
  PROJECTS["$tag"]="$name"
  ORDER+=("$tag")
done < "$PROJECTS_FILE"

declare -A GROUPED
if [[ -n "$TODOS" ]]; then
  while IFS= read -r line; do
    todo=$(echo "$line" | cut -d ':' -f2- | xargs) # ohne Zeilennr.
    tag=$(echo "$todo" | sed -n 's/^- \[ \] \([A-Z0-9_]\+\):.*/\1/p')
    if [[ -n "$tag" ]]; then
      GROUPED["$tag"]+="$todo"$'\n'
    else
      GROUPED["MISC"]+="$todo"$'\n'
    fi
  done <<< "$TODOS"
fi

declare -A PRINTED

{
  echo ""
  echo "$HEADING"
  echo "<!-- START_AT:$ISO_NOW -->"
  echo "*Start:* $TIME_NOW"
  echo ""

  if [[ -n "$TODOS" ]]; then
    echo "### Backlog"

    for tag in "${ORDER[@]}"; do
      [[ -n "${GROUPED[$tag]:-}" ]] || continue
      project_name="${PROJECTS[$tag]}"
      echo "#### $project_name ($tag)"
      echo -n "${GROUPED[$tag]}"
      echo ""
      PRINTED["$tag"]=1
    done

    for tag in $(printf "%s\n" "${!GROUPED[@]}" | grep -v '^MISC$' | sort); do
      [[ -n "${PRINTED[$tag]:-}" ]] && continue
      project_name="${PROJECTS[$tag]:-$tag}"
      echo "#### $project_name ($tag)"
      echo -n "${GROUPED[$tag]}"
      echo ""
    done

    if [[ -n "${GROUPED[MISC]:-}" ]]; then
      echo "#### Miscellaneous (MISC)"
      echo -n "${GROUPED[MISC]}"
      echo ""
    fi
  else
    echo "No old ToDo's!"
  fi

  echo ""
  echo "### New ToDo's"
} >> "$FILE"

echo "Updated $FILE for $DATE at $LOCATION (Start $TIME_NOW)"
