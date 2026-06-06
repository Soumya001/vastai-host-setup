#!/bin/bash
# One-click git push for vastai-host-setup
# Usage: bash push.sh "optional commit message"

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'

cd "$(dirname "$0")"

# Check git initialized
if [[ ! -d .git ]]; then
  echo -e "${YELLOW}Initializing git repo...${RESET}"
  git init
  read -rp "GitHub repo URL (e.g. https://github.com/yourname/vastai-host-setup.git): " REMOTE_URL
  git remote add origin "$REMOTE_URL"
fi

# Check for remote
if ! git remote get-url origin &>/dev/null; then
  read -rp "GitHub repo URL: " REMOTE_URL
  git remote add origin "$REMOTE_URL"
fi

MSG="${1:-update: $(date '+%Y-%m-%d %H:%M')}"

echo -e "${CYAN}Staging all changes...${RESET}"
git add -A

if git diff --cached --quiet; then
  echo -e "${YELLOW}Nothing to commit.${RESET}"
  exit 0
fi

echo -e "${CYAN}Committing: ${MSG}${RESET}"
git commit -m "$MSG"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
echo -e "${CYAN}Pushing to origin/${BRANCH}...${RESET}"
git push -u origin "$BRANCH"

echo -e "${GREEN}Done! Pushed to $(git remote get-url origin)${RESET}"
