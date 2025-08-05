#!/usr/bin/env bash

set -euo pipefail

# === CONFIGURATION ===
nix_dir="${NIX_DIR:-$HOME/Nix}"  # override with env var
start_editor="${START_EDITOR:-false}"
enable_formatting="${ENABLE_FORMATTING:-false}"
editor_cmd="${EDITOR_CMD:-nvim}"
formatter_cmd="${FORMATTER_CMD:-alejandra}"
auto_push="${AUTO_PUSH:-false}"

# === INITIAL SETUP ===
version="1.3.0"
start_time=$(date +%s)
start_human=$(date '+%Y-%m-%d %H:%M:%S')
stats_duration=0
stats_gen="?"
stats_errors=0
stats_last_error_lines=""
rebuild_success=false
exit_code=1

# === COLORS ===
if [[ -t 1 ]]; then
  RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'
  BLUE=$'\e[34m'; MAGENTA=$'\e[35m'; CYAN=$'\e[36m'
  BOLD=$'\e[1m'; RESET=$'\e[0m'
else
  RED=""; GREEN=""; YELLOW=""
  BLUE=""; MAGENTA=""; CYAN=""
  BOLD=""; RESET=""
fi

# === LOGGING SETUP ===
hostname=$(hostname)
log_dir="$nix_dir/Misc/nyx/logs/$hostname"
mkdir -p "$log_dir"
timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
build_log="$log_dir/build-${timestamp}.log"
error_log="$log_dir/Current-Error-${timestamp}.txt"

# === HELPERS ===
console-log() {
  echo -e "$@" | tee -a "$build_log"
}

print_line() {
  console-log "${BOLD}$(printf '%*s\n' "${COLUMNS:-40}" '' | tr ' ' '=')${RESET}"
}

run_with_log() {
  local cmd_output
  cmd_output=$(mktemp)
  (
    "$@" 2>&1
    echo $? > "$cmd_output"
  ) | tee -a "$build_log"
  local status
  status=$(<"$cmd_output")
  rm "$cmd_output"
  return "$status"
}

run_with_log_rebuild() {
  local cmd_output
  cmd_output=$(mktemp)
  (
    "$@" 2>&1
    echo $? > "$cmd_output"
  ) | tee -a "$build_log" | nom
  local status
  status=$(<"$cmd_output")
  rm "$cmd_output"
  return "$status"
}

finish_nyx_rebuild() {
  stats_duration=$(( $(date +%s) - start_time ))
  echo
  if [[ "$rebuild_success" == true ]]; then
    echo "${GREEN}${BOLD}
##############################
# ✅ NixOS Rebuild Complete! #
##############################${RESET}"
    echo "${BOLD}${CYAN}🎯 Success Stats:${RESET}"
    echo "  🕒 Started:   $start_human"
    echo "  ⏱️  Duration: ${stats_duration} sec"
    echo "  📦 Gen:       $stats_gen"
  else
    echo "${RED}${BOLD}
##############################
# ❌ NixOS Rebuild Failed!   #
##############################${RESET}"
    echo "${BOLD}${RED}🚨 Error Stats:${RESET}"
    echo "  🕒 Started:   $start_human"
    echo "  ⏱️  Duration: ${stats_duration} sec"
    echo "  ❌ Error lines: ${stats_errors}"
    [[ -n "$stats_last_error_lines" ]] && echo -e "\n${YELLOW}🧾 Last few errors:${RESET}\n$stats_last_error_lines"
  fi
}

trap finish_nyx_rebuild EXIT

# === TOOL INFO ===
echo
nix-tool "Nyx" "nyx-rebuild" "$version" \
  "Smart NixOS configuration rebuilder" \
  "by Peritia-System" \
  "https://github.com/Peritia-System/Nyx-Tools" \
  "https://github.com/Peritia-System/Nyx-Tools/issues" \
  "Always up to date for you!"
echo

# === PROJECT PREP ===
cd "$nix_dir" || { exit_code=1; return $exit_code; }

console-log "\n${BOLD}${BLUE}📁 Checking Git status...${RESET}"
if [[ -n $(git status --porcelain) ]]; then
  echo "${YELLOW}⚠️  Uncommitted changes detected!${RESET}"
  echo "${RED}⏳ 5s to cancel...${RESET}"
  sleep 5
fi

# === GIT PULL ===
console-log "\n${BOLD}${BLUE}⬇️  Pulling latest changes...${RESET}"
if ! run_with_log git pull --rebase; then
  exit_code=1; return $exit_code
fi

# === OPTIONAL: OPEN EDITOR ===
if [[ "$start_editor" == "true" ]]; then
  console-log "\n${BOLD}${BLUE}📝 Editing configuration...${RESET}"
  console-log "Started editing: $(date)"
  run_with_log "$editor_cmd"
  console-log "Finished editing: $(date)"
fi

# === OPTIONAL: FORMAT FILES ===
if [[ "$enable_formatting" == "true" ]]; then
  console-log "\n${BOLD}${MAGENTA}🎨 Running formatter...${RESET}"
  run_with_log "$formatter_cmd" .
fi

# === GIT DIFF ===
console-log "\n${BOLD}${CYAN}🔍 Changes summary:${RESET}"
run_with_log git diff --compact-summary

# === SYSTEM REBUILD ===
console-log "\n${BOLD}${BLUE}🔧 Starting system rebuild...${RESET}"
print_line
console-log "🛠️  Removing old HM conf"
run_with_log find ~ -type f -name '*delme-HMbackup' -exec rm -v {} +
print_line
console-log "Getting sudo ticket (please enter your password)"
run_with_log sudo whoami > /dev/null
print_line
console-log "🛠️  Rebuild started: $(date)"
print_line

run_with_log_rebuild sudo nixos-rebuild switch --flake "$nix_dir"
rebuild_status=$?

if [[ $rebuild_status -ne 0 ]]; then
  echo "${RED}❌ Rebuild failed at $(date).${RESET}" > "$error_log"
  stats_errors=$(grep -Ei -A 1 'error|failed' "$build_log" | tee -a "$error_log" | wc -l)
  stats_last_error_lines=$(tail -n 10 "$error_log")
  git add "$log_dir"
  git commit -m "Rebuild failed: errors logged"
  if [[ "$auto_push" == "true" ]]; then
    run_with_log git push && console-log "${GREEN}✅ Error log pushed to remote.${RESET}"
  fi
  exit_code=1
  return $exit_code
fi

# === SUCCESS FLOW ===
rebuild_success=true
exit_code=0

gen=$(nixos-rebuild list-generations | grep True | awk '{$1=$1};1')
stats_gen=$(echo "$gen" | awk '{printf "%04d\n", $1}')
finish_nyx_rebuild >> "$build_log"

git add -u
if ! git diff --cached --quiet; then
  git commit -m "Rebuild: $gen"
  console-log "${BLUE}🔧 Commit message:${RESET}\n${GREEN}Rebuild: $gen${RESET}"
fi

final_log="$log_dir/nixos-gen_${stats_gen}-switch-${timestamp}.log"
mv "$build_log" "$final_log"
git add "$final_log"

if ! git diff --cached --quiet; then
  git commit -m "log for $gen"
  echo "${YELLOW}ℹ️  Added changes to git${RESET}"
else
  echo "${YELLOW}ℹ️  No changes in logs to commit.${RESET}"
fi

if [[ "$auto_push" == "true" ]]; then
  git push && echo "${GREEN}✅ Changes pushed to remote.${RESET}"
fi

echo -e "\n${GREEN}🎉 Nyx rebuild completed successfully!${R
