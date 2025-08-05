{ config, lib, pkgs, ... }:

let
  cfg = config.nyx.nyx-rebuild;
in
{
  options.nyx.nyx-rebuild = {
    enable = lib.mkEnableOption "Enable nyx-rebuild Zsh function and Zsh shell";

    username = lib.mkOption {
      type = lib.types.str;
      description = "The name of the user this module applies to.";
    };

    nixDirectory = lib.mkOption {
      type = lib.types.path;
      description = "Path to the NixOS configuration directory.";
    };

    editor = lib.mkOption {
      type = lib.types.str;
      default = "nvim";
      description = "Editor used in nyx-rebuild.";
    };

    formatter = lib.mkOption {
      type = lib.types.str;
      default = "alejandra";
      description = "Formatter used for Nix files.";
    };

    startEditor = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Start editor before rebuilding.";
    };

    enableFormatting = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Format files before rebuild.";
    };

    autoPush = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Push changes to remote after rebuild.";
    };

    enableAlias = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Add 'nr' alias for 'nyx-rebuild'.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.zsh.enable = lib.mkDefault true;

    home.packages = [
      # The nyx-rebuild command itself
      (pkgs.writeShellScriptBin "nyx-rebuild" ''
        #!/usr/bin/env bash

        set -euo pipefail
        trap finish_nyx_rebuild EXIT

        version="1.3.0"
        nix_dir="${cfg.nixDirectory}"
        editor_cmd="${cfg.editor}"
        formatter_cmd="${cfg.formatter}"
        start_editor="${toString cfg.startEditor}"
        enable_formatting="${toString cfg.enableFormatting}"
        auto_push="${toString cfg.autoPush}"

        log_dir="$nix_dir/Misc/nyx/logs/$(hostname)"
        mkdir -p "$log_dir"
        timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
        build_log="$log_dir/build-${timestamp}.log"
        error_log="$log_dir/Current-Error-${timestamp}.txt"

        rebuild_success=false
        exit_code=1
        start_time=$(date +%s)
        start_human=$(date '+%Y-%m-%d %H:%M:%S')
        stats_gen="?"
        stats_errors=0
        stats_last_error_lines=""

        # Colors
        if [[ -t 1 ]]; then
          RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'
          BLUE=$'\e[34m'; MAGENTA=$'\e[35m'; CYAN=$'\e[36m'
          BOLD=$'\e[1m'; RESET=$'\e[0m'
        else
          RED=""; GREEN=""; YELLOW=""
          BLUE=""; MAGENTA=""; CYAN=""
          BOLD=""; RESET=""
        fi

        console-log() {
          echo -e "$@" | tee -a "$build_log"
        }

        run_with_log() {
          local output
          output=$(mktemp)
          (
            "$@" 2>&1
            echo $? > "$output"
          ) | tee -a "$build_log"
          local status
          status=$(<"$output")
          rm "$output"
          return "$status"
        }

        finish_nyx_rebuild() {
          local duration=$(( $(date +%s) - start_time ))
          echo
          if [[ "$rebuild_success" == true ]]; then
            echo "${GREEN}${BOLD}✅ NixOS Rebuild Complete!${RESET}"
            echo "${CYAN}Started: $start_human | Duration: ${duration}s | Gen: $stats_gen${RESET}"
          else
            echo "${RED}${BOLD}❌ NixOS Rebuild Failed!${RESET}"
            echo "${YELLOW}Started: $start_human | Duration: ${duration}s${RESET}"
            [[ -n "$stats_last_error_lines" ]] && echo "${YELLOW}Last Errors:\n$stats_last_error_lines${RESET}"
          fi
          return $exit_code
        }

        cd "$nix_dir" || exit 1

        console-log "${BLUE}${BOLD}📁 Checking Git status...${RESET}"
        if [[ -n $(git status --porcelain) ]]; then
          echo "${YELLOW}⚠️ Uncommitted changes! Waiting 5s to cancel...${RESET}"
          sleep 5
        fi

        console-log "\n${BLUE}⬇️ Pulling latest changes...${RESET}"
        run_with_log git pull --rebase || exit 1

        if [[ "$start_editor" == "true" ]]; then
          console-log "\n${BLUE}📝 Opening editor...${RESET}"
          run_with_log "$editor_cmd"
        fi

        if [[ "$enable_formatting" == "true" ]]; then
          console-log "\n${MAGENTA}🎨 Formatting files...${RESET}"
          run_with_log "$formatter_cmd" .
        fi

        console-log "\n${CYAN}🔍 Git diff summary:${RESET}"
        run_with_log git diff --compact-summary

        console-log "\n${BLUE}🔧 Starting system rebuild...${RESET}"
        run_with_log sudo -v
        run_with_log sudo nixos-rebuild switch --flake "$nix_dir"
        rebuild_status=$?

        if [[ $rebuild_status -ne 0 ]]; then
          echo "${RED}❌ Rebuild failed.${RESET}" | tee "$error_log"
          stats_errors=$(grep -Ei -A 1 'error|failed' "$build_log" | tee -a "$error_log" | wc -l)
          stats_last_error_lines=$(tail -n 10 "$error_log")
          git add "$log_dir"
          git commit -m "Rebuild failed: errors logged"
          [[ "$auto_push" == "true" ]] && git push
          exit_code=1
          return
        fi

        rebuild_success=true
        exit_code=0
        gen=$(nixos-rebuild list-generations | grep True | awk '{print $1}')
        stats_gen=$(printf "%04d" "$gen")
        final_log="$log_dir/nixos-gen_${stats_gen}-switch-${timestamp}.log"
        mv "$build_log" "$final_log"
        git add -u "$final_log"
        git commit -m "Rebuild: $gen" || true
        [[ "$auto_push" == "true" ]] && git push
        echo "${GREEN}🎉 Rebuild complete.${RESET}"
      '')
    ]
    ++ lib.optional (cfg.enableFormatting && cfg.formatter == "alejandra") pkgs.alejandra;

    home.shellAliases = lib.mkIf cfg.enableAlias {
      nr = "nyx-rebuild";
    };

    programs.zsh.initExtra = lib.mkIf cfg.enable ''
      # Nyx Rebuild Zsh Helper
      export NIX_REBUILD_DIR="${cfg.nixDirectory}"
    '';
  };
}
