#!/bin/bash
set -euo pipefail

FILE="2025.md"
CSV="work_log.csv"

[[ -f "$FILE" ]] || { echo "Error: $FILE not found."; exit 1; }

DATE=$(date +"%d-%m-%Y")
NOW_ISO=$(date --iso-8601=seconds)
END_TIME=$(date +"%H:%M")

SECTION=$(
  sed -n "/^## $DATE - ToDo @ /,/^## /p" "$FILE"
)

START_ISO=$(
  printf "%s\n" "$SECTION" | sed -n 's/.*<!-- START_AT:\([^>]*\) -->.*/\1/p' | head -n1
)

if [[ -z "${START_ISO:-}" ]]; then
  echo "Error: START_AT marker for $DATE not found in $FILE."
  exit 1
fi

START_EPOCH=$(date -d "$START_ISO" +%s)
END_EPOCH=$(date -d "$NOW_ISO" +%s)
if (( END_EPOCH < START_EPOCH )); then
  echo "Error: End time earlier than start time."
  exit 1
fi

MINUTES=$(( (END_EPOCH - START_EPOCH) / 60 ))
HOURS=$(printf "%.2f" "$(echo "$MINUTES / 60" | bc -l)")
START_TIME=$(date -d "$START_ISO" +"%H:%M")

if [[ ! -f "$CSV" ]]; then
  echo "date,start_time,end_time,minutes,hours" > "$CSV"
fi

if grep -q "^$DATE," "$CSV"; then
  tmp="$(mktemp)"
  sed -E "s|^$DATE,.*|$DATE,$START_TIME,$END_TIME,$MINUTES,$HOURS|" "$CSV" > "$tmp"
  mv "$tmp" "$CSV"
else
  echo "$DATE,$START_TIME,$END_TIME,$MINUTES,$HOURS" >> "$CSV"
fi

echo "Logged: $DATE → $MINUTES min ($HOURS h) to $CSV"
