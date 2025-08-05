{ config, lib, pkgs, ... }:

let
  cfg = config.nyx.nyx-rebuild;
  logDirDefault = "/home/${toString cfg.username}/.nyx/nyx-rebuild/logs";
in

{
  options.nyx.nyx-rebuild = {
    enable = lib.mkEnableOption "Enable nyx-rebuild script";

    username = lib.mkOption {
      type = lib.types.str;
      description = "User this module applies to.";
    };

    nixDirectory = lib.mkOption {
      type = lib.types.path;
      description = "Path to NixOS flake configuration.";
    };
    logDir = lib.mkOption {
      type = lib.types.str;
      default = logDirDefault;
      description = "Directory for storing cleanup logs.";
    };
    editor = lib.mkOption {
      type = lib.types.str;
      default = "nvim";
      description = "Editor for manual editing step.";
    };

    formatter = lib.mkOption {
      type = lib.types.str;
      default = "alejandra";
      description = "Formatter to use before rebuild.";
    };

    startEditor = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start editor before rebuild.";
    };

    enableFormatting = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Format Nix files before rebuild.";
    };

    autoPushLog = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "If true, automatically push Git commits containing rebuild logs.";
    };

    autoPushNixDir = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "If true, push Git commits in nixDirectory (configuration repo) after rebuild.";
    };


    enableAlias = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add 'nr' alias for nyx-rebuild.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zsh.enable = lib.mkDefault true;

    home.packages =
      (lib.optional (cfg.enableFormatting && cfg.formatter == "alejandra") pkgs.alejandra)
      ++ [
        (pkgs.writeShellScriptBin "nyx-rebuild" ''
#!/usr/bin/env bash
set -euo pipefail

# === CONFIGURATION ===
nix_dir="${nixDirStr}"
log_dir="${toString cfg.logDir}"
start_editor="${if cfg.startEditor then "true" else "false"}"
enable_formatting="${if cfg.enableFormatting then "true" else "false"}"
editor_cmd="${cfg.editor}"
formatter_cmd="${cfg.formatter}"
auto_push_log="${if cfg.autoPushLog then "true" else "false"}"
auto_push_nixdir="${if cfg.autoPushNixDir then "true" else "false"}"
git_bin="${pkgs.git}/bin/git"

# === INITIAL SETUP ===
mkdir -p "$log_dir"
timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
build_log="$log_dir/rebuild-''${timestamp}.log"
repo_dir="$(dirname "$(dirname "$log_dir")")"

# === COLORS ===
if [[ -t 1 ]]; then
  RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'
  BLUE=$'\e[34m'; MAGENTA=$'\e[35m'; CYAN=$'\e[36m'
  BOLD=$'\e[1m'; RESET=$'\e[0m'
else
  RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""
  CYAN=""; BOLD=""; RESET=""
fi

# === LOGGING ===
console-log() {
  echo -e "$@" | tee -a "$build_log"
}

print_line() {
  console-log ""
  console-log "''${BOLD}==================================================''${RESET}"
  console-log ""
}

# === SCRIPT START ===
print_line
console-log "''${BLUE}''${BOLD}🚀 Starting Nyx Rebuild...''${RESET}"

cd "$nix_dir"

console-log "''${CYAN}''${BOLD}🔍 Checking Git status...''${RESET}"
if [[ -n $($git_bin status --porcelain) ]]; then
  console-log "''${YELLOW}⚠️  You have uncommitted changes. Pausing 5s...''${RESET}"
  sleep 5
fi

console-log "''${CYAN}''${BOLD}⬇️  Pulling latest changes...''${RESET}"
$git_bin pull --rebase | tee -a "$build_log"

if [[ "$start_editor" == "true" ]]; then
  print_line
  console-log "''${MAGENTA}''${BOLD}📝 Launching editor...''${RESET}"
  "$editor_cmd"
fi

if [[ "$enable_formatting" == "true" ]]; then
  print_line
  console-log "''${MAGENTA}''${BOLD}🎨 Formatting files...''${RESET}"
  "$formatter_cmd" . | tee -a "$build_log"
fi

print_line
console-log "''${CYAN}''${BOLD}🛠️ Rebuilding system with flake...''${RESET}"
sudo nixos-rebuild switch --flake "$nix_dir" | tee -a "$build_log"

if [[ $? -ne 0 ]]; then
  console-log "''${RED}''${BOLD}❌ Rebuild failed. See log: $build_log''${RESET}"
  $git_bin add "$build_log"
  $git_bin commit -m "chore(rebuild): failed rebuild on $(date)" || true
          if [[ "$auto_push_nixdir" == "true" ]]; then
            (
              cd "$nix_dir"
              if $git_bin remote | grep -q .; then
                $git_bin push && console-log "''${GREEN}✅ Nix config pushed to remote.''${RESET}"
              else
                console-log "''${YELLOW}⚠️ No Git remote configured in nixDirectory.''${RESET}"
              fi
            )
          fi
  exit 1
fi

print_line
console-log "''${GREEN}''${BOLD}✅ NixOS rebuild complete!''${RESET}"

# === LOG + GIT FINALIZATION ===
cd $log_dir
$git_bin add "$build_log"
$git_bin commit -m "chore(rebuild): successful rebuild on $(date)" || true

if [[ "$auto_push_log" == "true" ]]; then
  (
    cd "$repo_dir"
    if $git_bin remote | grep -q .; then
      $git_bin push && echo "''${GREEN}✅ Logs pushed to remote.''${RESET}"
    else
       echo "''${YELLOW}⚠️ No Git remote configured for logs repo.''${RESET}"
    fi
  )
fi


        '')
      ];

    home.shellAliases = lib.mkIf cfg.enableAlias {
      nr = "nyx-rebuild";
    };
  };
}
