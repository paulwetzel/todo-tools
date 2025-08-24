#!/bin/bash
set -euo pipefail

FILE="2025.md"
PROJECTS_FILE="projects.yml"

usage() {
  echo "Usage: $0 -p <PROJECT_TAG> -t <TASK_TEXT>" >&2
  exit 1
}

[[ -f "$FILE" ]] || { echo "Error: $FILE not found."; exit 1; }
[[ -f "$PROJECTS_FILE" ]] || { echo "Error: $PROJECTS_FILE not found."; exit 1; }

# Parse flags
PROJECT_TAG=""
TASK_TEXT=""
while getopts ":p:t:" opt; do
  case "$opt" in
    p) PROJECT_TAG="$OPTARG" ;;
    t) TASK_TEXT="$OPTARG" ;;
    *) usage ;;
  esac
done
shift $((OPTIND - 1))

[[ -n "$PROJECT_TAG" && -n "$TASK_TEXT" ]] || usage

# Load projects.yml (TAG -> Project Name mapping)
declare -A PROJECTS
while IFS=":" read -r tag name; do
  tag=$(echo "$tag" | xargs)
  name=$(echo "$name" | xargs)
  [[ -n "$tag" && -n "$name" ]] || continue
  PROJECTS["$tag"]="$name"
done < "$PROJECTS_FILE"

# Validate project tag
RESOLVED_TAG="$PROJECT_TAG"
PROJECT_NAME=""
if [[ -n "${PROJECTS[$PROJECT_TAG]:-}" ]]; then
  PROJECT_NAME="${PROJECTS[$PROJECT_TAG]}"
else
  echo "Warning: Tag '$PROJECT_TAG' not found in $PROJECTS_FILE. Task will be added under MISC." >&2
  RESOLVED_TAG="MISC"
  PROJECT_NAME="Miscellaneous"
fi

# Determine today's section header and target subheader
DATE=$(date +"%d-%m-%Y")
SECTION_HEADER="## $DATE - ToDo @ "
if [[ "$RESOLVED_TAG" == "MISC" ]]; then
  TARGET_SUBHEADER="#### Miscellaneous (MISC)"
else
  TARGET_SUBHEADER="#### $PROJECT_NAME ($RESOLVED_TAG)"
fi

# Task line format
TODO_LINE="- [ ] $RESOLVED_TAG: $TASK_TEXT"

# Locate today's section start
START_LINE=$(grep -nE "^${SECTION_HEADER//\//\\/}" "$FILE" | head -n1 | cut -d: -f1 || true)
if [[ -z "${START_LINE:-}" ]]; then
  echo "Error: Today's section ('$SECTION_HEADER …') not found in $FILE. Run morning.sh first." >&2
  exit 1
fi

# Locate today's section end (next '## ' or end of file)
NEXT_HEADER_OFFSET=$(tail -n +"$((START_LINE+1))" "$FILE" | grep -nE "^## " | head -n1 | cut -d: -f1 || true)
if [[ -n "${NEXT_HEADER_OFFSET:-}" ]]; then
  END_LINE=$((START_LINE + NEXT_HEADER_OFFSET - 1))
else
  TOTAL_LINES=$(wc -l < "$FILE")
  END_LINE=$((TOTAL_LINES))
fi

# Extract today's section
SECTION=$(sed -n "${START_LINE},${END_LINE}p" "$FILE")

# Ensure that Backlog section exists
if ! printf "%s\n" "$SECTION" | grep -q "^### Backlog"; then
  if printf "%s\n" "$SECTION" | grep -q "^No old ToDo's!"; then
    SECTION=$(printf "%s\n" "$SECTION" | sed 's/^No old ToDo'\''s!$/### Backlog\n/')
  else
    SECTION=$(printf "%s\n" "$SECTION" | sed '/^### New ToDo'\''s$/i\
### Backlog\
')
  fi
fi

# Insert task
if printf "%s\n" "$SECTION" | grep -qF "$TARGET_SUBHEADER"; then
  # Subheader exists -> insert at the end of that block (before next #### / ### New ToDo's / section end)
  HLINE=$(printf "%s\n" "$SECTION" | nl -ba | grep -F "$TARGET_SUBHEADER" | head -n1 | awk '{print $1}')
  TAIL_FROM=$((HLINE+1))
  NEXT_REL=$(
    printf "%s\n" "$SECTION" | tail -n +$TAIL_FROM | \
      awk '/^#### / || /^### New ToDo'\''s$/ { print NR; exit }'
  )
  if [[ -n "${NEXT_REL:-}" ]]; then
    INSERT_REL=$((TAIL_FROM + NEXT_REL - 1))
  else
    SECTION_LINES=$(printf "%s\n" "$SECTION" | wc -l)
    INSERT_REL=$((SECTION_LINES + 1))
  fi
  SECTION=$(printf "%s\n" "$SECTION" | awk -v ins="$INSERT_REL" -v line="$TODO_LINE" '
    NR==ins { print line }
    { print }
  ')
else
  # Subheader does not exist -> create it before "### New ToDo's" or at section end
  if printf "%s\n" "$SECTION" | grep -q "^### New ToDo's$"; then
    SECTION=$(printf "%s\n" "$SECTION" | sed "/^### New ToDo's$/i\\
$TARGET_SUBHEADER\\
$TODO_LINE\\
")
  else
    SECTION=$(printf "%s\n" "$SECTION"$'\n'"$TARGET_SUBHEADER"$'\n'"$TODO_LINE"$'\n')
  fi
fi

# Rebuild file (prefix + modified section + suffix)
{
  if (( START_LINE > 1 )); then sed -n "1,$((START_LINE-1))p" "$FILE"; fi
  printf "%s\n" "$SECTION"
  if (( END_LINE < $(wc -l < "$FILE") )); then sed -n "$((END_LINE+1)),\$p" "$FILE"; fi
} > "$FILE.tmp"

mv "$FILE.tmp" "$FILE"

echo "Added: [$RESOLVED_TAG] $TASK_TEXT"
