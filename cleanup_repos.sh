#!/usr/bin/env bash
set -euo pipefail

# Make sure GH CLI picks up the token
export GH_TOKEN="${GH_TOKEN}"

# -------------------------------
# Configuration
# -------------------------------

# List of repositories in "owner/repo" format
REPOS=(
  "demoshu23/githubactions"
  "demoshu23/MavenHelloWorld"
  "demoshu23/Lab"
)

# Dry-run mode: set to "false" to actually delete branches
DRY_RUN="${DRY_RUN:-true}"

# Branch age threshold in days
DAYS="${DAYS:-90}"
NOW_TS=$(date +%s)
CUTOFF=$(date -d "-$DAYS days" +%s)

# Branches to never delete
PROTECTED_BRANCHES="^(main|develop/)"

# -------------------------------
# Initialize report arrays
# -------------------------------
REPORT_REPO=()
REPORT_BRANCH=()
REPORT_AGE=()
REPORT_ACTION=()

# -------------------------------
# Start cleanup
# -------------------------------
echo ""
echo "📊 Stale Branch Cleanup Report"
echo "-----------------------------------------------"
printf "%-35s %-30s %-10s %-10s\n" "REPO" "BRANCH" "AGE(days)" "ACTION"
echo "-----------------------------------------------"

for REPO in "${REPOS[@]}"; do
  echo "🔍 Processing $REPO"

  # Check if repo is accessible
  if ! gh api repos/"$REPO" --quiet >/dev/null 2>&1; then
    echo "❌ Cannot access $REPO — skipping"
    continue
  fi

  # Get branches, ignore protected branches
  BRANCHES=$(gh api repos/"$REPO"/branches --paginate \
              -H "Accept: application/vnd.github.v3+json" \
              | jq -r '.[].name' \
              | grep -vE "$PROTECTED_BRANCHES") || continue

  for BRANCH in $BRANCHES; do
    LAST_COMMIT_DATE=$(gh api repos/"$REPO"/commits/"$BRANCH" \
                        | jq -r '.commit.committer.date')
    LAST_TS=$(date -d "$LAST_COMMIT_DATE" +%s)
    AGE_DAYS=$(( (NOW_TS - LAST_TS) / 86400 ))

    if [ "$LAST_TS" -lt "$CUTOFF" ]; then
      if [ "$DRY_RUN" = "true" ]; then
        ACTION="DRY-RUN"
      else
        ACTION="DELETED"
        gh api -X DELETE repos/"$REPO"/git/refs/heads/"$BRANCH" || true
      fi

      # Store in report arrays
      REPORT_REPO+=("$REPO")
      REPORT_BRANCH+=("$BRANCH")
      REPORT_AGE+=("$AGE_DAYS")
      REPORT_ACTION+=("$ACTION")

      printf "%-35s %-30s %-10s %-10s\n" "$REPO" "$BRANCH" "$AGE_DAYS" "$ACTION"
    fi
  done
done

echo "-----------------------------------------------"
echo "✅ Cleanup complete (dry-run=$DRY_RUN)"
echo ""

# Safe summary
if [ "${#REPORT_REPO[@]}" -eq 0 ] 2>/dev/null || [ -z "${REPORT_REPO+x}" ]; then
  echo "No branches matched the stale criteria or all repos were inaccessible."
else
  echo "Summary of branches processed:"
  printf "%-35s %-30s %-10s %-10s\n" "REPO" "BRANCH" "AGE(days)" "ACTION"
  for i in "${!REPORT_REPO[@]}"; do
    printf "%-35s %-30s %-10s %-10s\n" \
      "${REPORT_REPO[$i]}" "${REPORT_BRANCH[$i]}" "${REPORT_AGE[$i]}" "${REPORT_ACTION[$i]}"
  done
fi

