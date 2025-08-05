{ config, lib, pkgs, ... }:

let
  cfg = config.nyx.nyx-rebuild;
in
{
  options.nyx.nyx-rebuild = {
    enable = lib.mkEnableOption "Enable nyx-rebuild script";

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
      description = "If true, starts editor before rebuild.";
    };

    enableFormatting = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "If true, format Nix files before rebuild.";
    };

    autoPush = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "If true, push commits to Git remote after rebuild.";
    };

    enableAlias = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "If true, add `nr` alias for `nyx-rebuild`.";
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

          nix_dir="${nixDirectory}"
          start_editor="${toString cfg.startEditor}"
          enable_formatting="${toString cfg.enableFormatting}"
          editor_cmd="${cfg.editor}"
          formatter_cmd="${cfg.formatter}"
          auto_push="${toString cfg.autoPush}"
          version="beta-2.0.0"

          start_time=$(date +%s)
          start_human=$(date '+%Y-%m-%d %H:%M:%S')
          stats_duration=0
          stats_gen="?"
          stats_errors=0
          stats_last_error_lines=""
          rebuild_success=false
          exit_code=1

          if [[ -t 1 ]]; then
            RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'
            BLUE=$'\e[34m'; MAGENTA=$'\e[35m'; CYAN=$'\e[36m'
            BOLD=$'\e[1m'; RESET=$'\e[0m'
          else
            RED=""; GREEN=""; YELLOW=""
            BLUE=""; MAGENTA=""; CYAN=""
            BOLD=""; RESET=""
          fi

          hostname=$(hostname)
          log_dir="\${nix_dir}/Misc/nyx/logs/\${hostname}"
          mkdir -p "\${log_dir}"
          timestamp=$(date '+%Y-%m-%d_%H-%M-%S')
          build_log="\${log_dir}/build-\${timestamp}.log"
          error_log="\${log_dir}/Current-Error-\${timestamp}.txt"

          console-log() {
            echo -e "\$@" | tee -a "\${build_log}"
          }

          print_line() {
            console-log "\n"
            console-log "\${BOLD}==================================================\${RESET}"
            console-log "\n"
          }

          run_with_log() {
            local cmd_output
            cmd_output=$(mktemp)
            (
              "\$@" 2>&1
              echo \$? > "\${cmd_output}"
            ) | tee -a "\${build_log}"
            local status
            status=$(<"\${cmd_output}")
            rm "\${cmd_output}"
            return "\${status}"
          }

          finish_nyx_rebuild() {
            stats_duration=$(( \$(date +%s) - start_time ))
            echo
            if [[ "\${rebuild_success}" == true ]]; then
              echo "\${GREEN}\${BOLD}
##############################
# ✅ NixOS Rebuild Complete! #
##############################\${RESET}"
              echo "\${BOLD}\${CYAN}🎯 Success Stats:\${RESET}"
              echo "  🕒 Started:   \${start_human}"
              echo "  ⏱️  Duration: \${stats_duration} sec"
              echo "  📦 Gen:       \${stats_gen}"
            else
              echo "\${RED}\${BOLD}
##############################
# ❌ NixOS Rebuild Failed!   #
##############################\${RESET}"
              echo "\${BOLD}\${RED}🚨 Error Stats:\${RESET}"
              echo "  🕒 Started:   \${start_human}"
              echo "  ⏱️  Duration: \${stats_duration} sec"
              echo "  ❌ Error lines: \${stats_errors}"
              [[ -n "\${stats_last_error_lines}" ]] && echo -e "\n\${YELLOW}🧾 Last few errors:\${RESET}\n\${stats_last_error_lines}"
            fi
          }

          trap finish_nyx_rebuild EXIT

          echo
          echo "\${CYAN}\${BOLD}🔧 Starting Nyx Rebuild v\${version}\${RESET}"
          echo

          cd "\${nix_dir}" || exit 1

          console-log "\n\${BOLD}\${BLUE}📁 Checking Git status...\${RESET}"
          if [[ -n \$(git status --porcelain) ]]; then
            echo "\${YELLOW}⚠️  Uncommitted changes detected!\${RESET}"
            echo "\${RED}⏳ 5s to cancel...\${RESET}"
            sleep 5
          fi

          console-log "\n\${BOLD}\${BLUE}⬇️  Pulling latest changes...\${RESET}"
          if ! run_with_log git pull --rebase; then
            exit 1
          fi

          if [[ "\${start_editor}" == "true" ]]; then
            console-log "\n\${BOLD}\${BLUE}📝 Opening editor...\${RESET}"
            run_with_log "\${editor_cmd}"
          fi

          if [[ "\${enable_formatting}" == "true" ]]; then
            console-log "\n\${BOLD}\${MAGENTA}🎨 Formatting Nix files...\${RESET}"
            run_with_log "\${formatter_cmd}" .
          fi

          console-log "\n\${BOLD}\${CYAN}🔍 Git changes summary:\${RESET}"
          run_with_log git diff --compact-summary

          console-log "\n\${BOLD}\${BLUE}🔧 Starting system rebuild...\${RESET}"
          run_with_log sudo nixos-rebuild switch --flake "\${nix_dir}"
          rebuild_status=\$?

          if [[ \${rebuild_status} -ne 0 ]]; then
            echo "\${RED}❌ Rebuild failed at \$(date).\${RESET}" > "\${error_log}"
            stats_errors=\$(grep -Ei -A 1 'error|failed' "\${build_log}" | tee -a "\${error_log}" | wc -l)
            stats_last_error_lines=\$(tail -n 10 "\${error_log}")
            git add "\${log_dir}"
            git commit -m "Rebuild failed: errors logged"
            if [[ "\${auto_push}" == "true" ]]; then
              run_with_log git push
            fi
            exit 1
          fi

          rebuild_success=true
          gen=\$(nixos-rebuild list-generations | grep True | awk '{\$1=\$1};1')
          stats_gen=\$(echo "\${gen}" | awk '{printf "%04d\\n", \$1}')
          finish_nyx_rebuild >> "\${build_log}"

          git add -u
          if ! git diff --cached --quiet; then
            git commit -m "Rebuild: \${gen}"
            console-log "\${BLUE}🔧 Commit message:\${RESET}\n\${GREEN}Rebuild: \${gen}\${RESET}"
          fi

          final_log="\${log_dir}/nixos-gen_\${stats_gen}-switch-\${timestamp}.log"
          mv "\${build_log}" "\${final_log}"
          git add "\${final_log}"

          if ! git diff --cached --quiet; then
            git commit -m "log for \${gen}"
          else
            echo "\${YELLOW}ℹ️  No changes in logs to commit.\${RESET}"
          fi

          if [[ "\${auto_push}" == "true" ]]; then
            git push && echo "\${GREEN}✅ Changes pushed to remote.\${RESET}"
          fi

          echo -e "\n\${GREEN}🎉 Nyx rebuild completed successfully!\${RESET}"
          exit 0
        '')
      ];

    home.shellAliases = lib.mkIf cfg.enableAlias {
      nr = "nyx-rebuild";
    };
  };
}
