{
  self,
  inputs,
  lib,
  ...
}:
let
  inherit (lib)
    attrNames
    concatMapStringsSep
    escapeShellArg
    literalExpression
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  renderAlias = name: value: "alias ${escapeShellArg name}=${escapeShellArg value}";

  renderFunction = name: body: ''
    function ${name}() {
    ${body}
    }
  '';

  renderHistoryIgnoreFunction = patterns: ''
    function nixconf_zsh_history_should_ignore() {
      emulate -L zsh
      local line="$1"
      case "$line" in
    ${concatMapStringsSep "\n" (pattern: "    (${pattern}) return 0 ;;") patterns}
      esac
      return 1
    }
  '';

  renderConfig = cfg: ''
    ${renderHistoryIgnoreFunction cfg.history.ignorePatterns}

    ${concatMapStringsSep "\n" (name: renderAlias name cfg.aliases.${name}) (attrNames cfg.aliases)}

    ${concatMapStringsSep "\n" (name: renderFunction name cfg.functions.${name}) (
      attrNames cfg.functions
    )}

    ${cfg.initExtra}
  '';

  defaultZshPreferences = pkgs: {
    history = {
      size = 50000;
      save = 50000;
      share = true;
      ignorePatterns = [ ];
    };

    correction.enable = true;

    notifications = {
      enable = true;
      longCommandThresholdSeconds = 5;
    };

    aliases = {
      c = "printf '\\033[2J\\033[3J\\033[1;1H'";
      suspend = "systemctl suspend";
      reboot = "systemctl reboot";
      logout = "hyprctl dispatch exit";
      poweroff = "systemctl poweroff";
      ports = "sudo ss -ltnup";
      unlock-device = "unlock-host";
      ls = "eza --group-directories-first --icons=auto";
      ll = "eza -lah --group-directories-first --icons=auto --git";
      la = "eza -A --group-directories-first --icons=auto";
      tree = "eza --tree --group-directories-first --icons=auto";
      grep = "grep --color=auto";
      diff = "diff --color=auto";
      ".." = "cd ..";
      "..." = "cd ../..";
      "...." = "cd ../../..";
      cat = "bat --style=plain --color=always --paging=never";
      less = "bat --color=always --paging=always";
    };

    functions = {
      unlock-host = ''
        if [[ $# -lt 1 || $# -gt 2 ]]; then
          print -u2 "usage: unlock-host <host> [port]"
          return 2
        fi

        local host="$1"
        local port="''${2:-2222}"

        # The initrd unlock SSH daemon is separate from normal post-boot sshd;
        # connect as root on the stage-1 port declared by remote-unlock.nix.
        ssh -p "$port" root@"$host"
      '';

      killport = ''
        if [[ $# -ne 1 || ! $1 == <1-65535> ]]; then
          print -u2 "usage: killport {port}"
          return 2
        fi

        local port=$1
        local pids
        pids=($(${pkgs.lsof}/bin/lsof -t -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null))

        if (( ''${#pids[@]} == 0 )); then
          print "No TCP listener found on port $port"
          return 1
        fi

        # SIGTERM keeps this helper safe for everyday dev servers; use kill -9 manually if a process ignores it.
        kill "''${pids[@]}"
        print "Killed PID(s) on port $port: ''${(j: :)pids}"
      '';
    };

    initExtra = "";
  };
in
{
  flake.nixosModules.zsh =
    {
      config,
      pkgs,
      ...
    }:
    let
      cfg = config.preferences.zsh;
      renderedConfig = renderConfig cfg;
    in
    {
      options.preferences.zsh = {
        history = {
          size = mkOption {
            type = types.ints.positive;
            default = 50000;
            description = "Interactive zsh history size.";
          };
          save = mkOption {
            type = types.ints.positive;
            default = 50000;
            description = "Number of zsh history entries saved to disk.";
          };
          share = mkEnableOption "history sharing between live zsh sessions" // {
            default = true;
          };
          ignorePatterns = mkOption {
            type = types.listOf types.str;
            default = [ ];
            example = literalExpression ''[ "q(|[[:space:]]*)" ]'';
            description = "Zsh case patterns excluded from file and in-memory history.";
          };
        };

        correction.enable = mkEnableOption "zsh spelling correction" // {
          default = true;
        };

        notifications = {
          enable = mkEnableOption "desktop notifications for long-running shell commands" // {
            default = true;
          };
          longCommandThresholdSeconds = mkOption {
            type = types.ints.positive;
            default = 5;
            description = "Minimum runtime before zsh sends a command-complete notification.";
          };
        };

        aliases = mkOption {
          type = types.attrsOf types.str;
          default = (defaultZshPreferences pkgs).aliases;
          description = "Aliases rendered into the primary user's zsh startup file.";
        };

        functions = mkOption {
          type = types.attrsOf types.lines;
          default = (defaultZshPreferences pkgs).functions;
          description = "Shell functions rendered into the primary user's zsh startup file.";
        };

        initExtra = mkOption {
          type = types.lines;
          default = "";
          description = "Additional zsh source appended after generated aliases and functions.";
        };
      };

      config = mkIf config.preferences.enable {
        system.activationScripts.zsh-user-config = {
          text = self.lib.userFiles.mkActivationScript {
            user = config.preferences.user.username;
            inherit pkgs;
            homeDirectory = config.preferences.paths.homeDirectory;
            files = {
              ".config/nixconf/zsh/config.zsh" = {
                text = ''
                  export ZSH_HISTSIZE=${toString cfg.history.size}
                  export ZSH_SAVEHIST=${toString cfg.history.save}
                  export NIXCONF_ZSH_CORRECTION=${if cfg.correction.enable then "1" else "0"}
                  export NIXCONF_ZSH_NOTIFICATIONS=${if cfg.notifications.enable then "1" else "0"}
                  export NIXCONF_ZSH_LONG_COMMAND_SECONDS=${toString cfg.notifications.longCommandThresholdSeconds}
                  ${if cfg.history.share then "setopt SHARE_HISTORY" else "unsetopt SHARE_HISTORY"}

                  ${renderedConfig}
                '';
                type = "copy";
                permissions = "0644";
              };
            };
          };
          deps = [ "users" ];
        };
      };
    };

  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    let
      userPackageZshSetup = self.lib.userPackages.zshSetup;
      fallbackConfig = pkgs.writeText "nixconf-zsh-defaults.zsh" (
        renderConfig (defaultZshPreferences pkgs)
      );

      # Create the .zshrc content
      zshrc =
        pkgs.writeText ".zshrc"
          # zsh
          ''
            # ══════════════════════════════════════════════════════════════════
            # History Configuration
            # ══════════════════════════════════════════════════════════════════
            HISTFILE="''${ZSH_HISTORY_FILE:-$HOME/.zsh_history}"
            HISTSIZE="''${ZSH_HISTSIZE:-50000}"
            SAVEHIST="''${ZSH_SAVEHIST:-50000}"
            ZSH_CACHE_DIR="''${ZSH_CACHE_DIR:-''${XDG_CACHE_HOME:-$HOME/.cache}/zsh}"

            setopt HIST_IGNORE_SPACE      # Don't save commands starting with space (privacy)
            setopt HIST_IGNORE_DUPS       # Ignore duplicate commands
            setopt HIST_IGNORE_ALL_DUPS   # Remove older duplicate from history
            setopt HIST_FIND_NO_DUPS      # Don't show duplicates in search
            setopt HIST_REDUCE_BLANKS     # Remove superfluous blanks
            setopt HIST_EXPIRE_DUPS_FIRST # Drop duplicates before unique entries when trimming
            setopt HIST_NO_STORE          # Do not store history-manipulation commands
            setopt HIST_SAVE_NO_DUPS      # Rewrite history without duplicate commands
            setopt INC_APPEND_HISTORY_TIME # Append after execution with duration metadata
            setopt EXTENDED_HISTORY       # Save timestamps (needed for correct history sharing)
            setopt SHARE_HISTORY          # Share history between all sessions
            setopt HIST_FCNTL_LOCK        # Use robust file locking, better for shared history
            unsetopt HIST_SAVE_BY_COPY    # Don't use mv to rewrite history (breaks impermanence symlinks)
            ZSH_HISTORY_PRUNE_AFTER_DAYS="''${ZSH_HISTORY_PRUNE_AFTER_DAYS:-30}"
            ZSH_HISTORY_PRUNE_INTERVAL_SECONDS="''${ZSH_HISTORY_PRUNE_INTERVAL_SECONDS:-86400}"

            zmodload zsh/parameter
            zmodload zsh/stat
            autoload -Uz add-zsh-hook

            if [[ -r "$HOME/.config/nixconf/zsh/config.zsh" ]]; then
              source "$HOME/.config/nixconf/zsh/config.zsh"
            else
              source ${fallbackConfig}
            fi


            typeset -g NIXCONF_ZSH_LAST_HISTORY_LINE=""
            typeset -g NIXCONF_ZSH_LAST_HISTORY_ACCEPTED=0
            typeset -g NIXCONF_ZSH_HISTORY_PRUNED=0

            function nixconf_zsh_history_command_key() {
              emulate -L zsh
              setopt EXTENDED_GLOB
              local line="''${1%%$'\n'}"
              line="''${line#; }"
              if [[ "$line" == :[[:space:]]##<->:[0-9]#\;* ]]; then
                line="''${line#*;}"
              fi
              print -r -- "$line"
            }

            function nixconf_zsh_rewrite_history_file() {
              emulate -L zsh
              setopt EXTENDED_GLOB

              [[ -n "$HISTFILE" && -r "$HISTFILE" && -w "$HISTFILE" ]] || return 0

              local now cutoff tmp line key stamp keep drop_key="''${1:-}"
              local -A newest
              now=$EPOCHSECONDS
              cutoff=$(( now - ''${ZSH_HISTORY_PRUNE_AFTER_DAYS:-30} * 86400 ))
              tmp="''${HISTFILE}.nixconf-prune.$$"

              while IFS= read -r line; do
                key="$(nixconf_zsh_history_command_key "$line")"
                [[ -n "$key" && "$key" != "$drop_key" ]] || continue
                if [[ "$line" == :[[:space:]]##<->:[0-9]#\;* ]]; then
                  stamp="''${line#:[[:space:]]#}"
                  stamp="''${stamp%%:*}"
                else
                  stamp=$now
                fi
                if [[ -z "''${newest[$key]}" || $stamp -gt ''${newest[$key]} ]]; then
                  newest[$key]=$stamp
                fi
              done < "$HISTFILE"

              while IFS= read -r line; do
                key="$(nixconf_zsh_history_command_key "$line")"
                if [[ -z "$key" ]]; then
                  print -r -- "$line"
                  continue
                fi
                [[ "$key" == "$drop_key" ]] && continue
                keep="''${newest[$key]:-$now}"
                (( keep >= cutoff )) && print -r -- "$line"
              done < "$HISTFILE" >| "$tmp"

              if command cp -- "$tmp" "$HISTFILE"; then
                command rm -f -- "$tmp"
                fc -p -a "$HISTFILE" "$HISTSIZE" "$SAVEHIST"
                fc -R "$HISTFILE"
              else
                command rm -f -- "$tmp"
                return 1
              fi
            }

            function nixconf_zsh_prune_history_async() {
              emulate -L zsh
              setopt EXTENDED_GLOB NO_MONITOR

              [[ -n "$HISTFILE" && -r "$HISTFILE" && -w "$HISTFILE" ]] || return 0
              local stamp_file="''${ZSH_CACHE_DIR}/history-prune.stamp"
              local -A hist_stat stamp_stat
              local last_run=0
              zstat -H hist_stat -- "$HISTFILE" 2>/dev/null || return 0
              if zstat -H stamp_stat -- "$stamp_file" 2>/dev/null; then
                last_run=$stamp_stat[mtime]
              fi
              (( EPOCHSECONDS - last_run >= ''${ZSH_HISTORY_PRUNE_INTERVAL_SECONDS:-86400} )) || return 0

              {
                local tmp="''${HISTFILE}.nixconf-prune.$$"
                local now=$EPOCHSECONDS
                local cutoff=$(( now - ''${ZSH_HISTORY_PRUNE_AFTER_DAYS:-30} * 86400 ))
                local line key stamp keep
                local -A newest current_stat

                while IFS= read -r line; do
                  key="$(nixconf_zsh_history_command_key "$line")"
                  [[ -n "$key" ]] || continue
                  if [[ "$line" == :[[:space:]]##<->:[0-9]#\;* ]]; then
                    stamp="''${line#:[[:space:]]#}"
                    stamp="''${stamp%%:*}"
                  else
                    stamp=$now
                  fi
                  if [[ -z "''${newest[$key]}" || $stamp -gt ''${newest[$key]} ]]; then
                    newest[$key]=$stamp
                  fi
                done < "$HISTFILE"

                while IFS= read -r line; do
                  key="$(nixconf_zsh_history_command_key "$line")"
                  if [[ -z "$key" ]]; then
                    print -r -- "$line"
                    continue
                  fi
                  keep="''${newest[$key]:-$now}"
                  (( keep >= cutoff )) && print -r -- "$line"
                done < "$HISTFILE" >| "$tmp"

                zstat -H current_stat -- "$HISTFILE" 2>/dev/null \
                  && [[ "$current_stat[size]:$current_stat[mtime]" == "$hist_stat[size]:$hist_stat[mtime]" ]] \
                  && command cp -- "$tmp" "$HISTFILE"
                command rm -f -- "$tmp"
                print -r -- "$now" >| "$stamp_file"
              } &!
            }

            function nixconf_zsh_prune_history() {
              emulate -L zsh
              (( NIXCONF_ZSH_HISTORY_PRUNED )) && return 0
              NIXCONF_ZSH_HISTORY_PRUNED=1
              nixconf_zsh_prune_history_async
            }

            function nixconf_zshaddhistory() {
              emulate -L zsh
              local line="''${1%%$'\n'}"
              NIXCONF_ZSH_LAST_HISTORY_LINE="$line"
              NIXCONF_ZSH_LAST_HISTORY_ACCEPTED=0

              # Returning non-zero prevents both disk persistence and the live in-memory
              # history entry used by Up/Down and history-substring-search.
              [[ "$line" == [[:space:]]* ]] && return 1
              if (( $+functions[nixconf_zsh_history_should_ignore] )) && nixconf_zsh_history_should_ignore "$line"; then
                return 1
              fi

              NIXCONF_ZSH_LAST_HISTORY_ACCEPTED=1

              return 0
            }
            add-zsh-hook zshaddhistory nixconf_zshaddhistory

            function nixconf_zsh_history_preexec() {
              emulate -L zsh
              NIXCONF_ZSH_LAST_HISTORY_LINE="$1"
            }
            add-zsh-hook preexec nixconf_zsh_history_preexec

            function nixconf_zsh_history_precmd() {
              emulate -L zsh
              local command_status=$?
              nixconf_zsh_prune_history

              # zshaddhistory runs before execution; delete only commands that were first seen and failed.
              # If the same command succeeded before, pruning by last successful use keeps that older entry.
              if (( command_status != 0 && NIXCONF_ZSH_LAST_HISTORY_ACCEPTED )) && [[ -n "$NIXCONF_ZSH_LAST_HISTORY_LINE" ]]; then
                local key="$(nixconf_zsh_history_command_key "$NIXCONF_ZSH_LAST_HISTORY_LINE")"
                local existing=0 line
                if [[ -r "$HISTFILE" ]]; then
                  while IFS= read -r line; do
                    [[ "$(nixconf_zsh_history_command_key "$line")" == "$key" ]] && (( existing++ ))
                  done < "$HISTFILE"
                fi
                if (( existing <= 1 )); then
                  nixconf_zsh_rewrite_history_file "$key"
                fi
              fi

              NIXCONF_ZSH_LAST_HISTORY_ACCEPTED=0
              NIXCONF_ZSH_LAST_HISTORY_LINE=""
              return $command_status
            }
            add-zsh-hook precmd nixconf_zsh_history_precmd

            # ══════════════════════════════════════════════════════════════════
            # Long Command Notifications
            # ══════════════════════════════════════════════════════════════════
            # Timer for long commands (5s+)
            function notify_long_command_preexec() {
              command_start_time=$SECONDS
              last_command=$1
            }

            function notify_long_command_precmd() {
              if [[ -n $command_start_time ]]; then
                local elapsed=$(( SECONDS - command_start_time ))
                if [[ $elapsed -ge ''${NIXCONF_ZSH_LONG_COMMAND_SECONDS:-5} ]]; then
                  # Truncate command if it's too long for notification
                  local cmd_display=$last_command
                  if [[ ''${#cmd_display} -gt 50 ]]; then
                    cmd_display="''${cmd_display:0:47}..."
                  fi
                  ${pkgs.libnotify}/bin/notify-send "Task Completed" "$cmd_display\nDuration: $elapsed seconds" -i utilities-terminal
                fi
                unset command_start_time
              fi
            }

            if [[ "''${NIXCONF_ZSH_NOTIFICATIONS:-1}" == 1 ]]; then
              add-zsh-hook preexec notify_long_command_preexec
              add-zsh-hook precmd notify_long_command_precmd
            fi

            # Reset cursor style to prevent invisible cursor bug
            # (zsh-syntax-highlighting can corrupt cursor escape sequences)
            function reset_cursor_style() {
              printf '\e[5 q'  # 5 = blinking bar cursor
            }
            add-zsh-hook precmd reset_cursor_style

            setopt HIST_VERIFY            # Don't execute immediately on history expansion

            # ══════════════════════════════════════════════════════════════════
            # General Options
            # ══════════════════════════════════════════════════════════════════
            setopt AUTO_CD                # cd by typing directory name
            setopt AUTO_PUSHD             # Make cd push old directory onto stack
            setopt PUSHD_IGNORE_DUPS      # Don't push duplicates onto stack
            setopt PUSHD_MINUS            # Swap meaning of + and -
            setopt INTERACTIVE_COMMENTS   # Allow comments in interactive shell
            setopt NO_BEEP                # Don't beep on errors
            if [[ "''${NIXCONF_ZSH_CORRECTION:-1}" == 1 ]]; then
              setopt CORRECT                # Spelling correction for commands
            fi
            setopt COMPLETE_IN_WORD       # Complete from both ends of word
            setopt ALWAYS_TO_END          # Move cursor to end after completion

            # ══════════════════════════════════════════════════════════════════
            # Completion System
            # ══════════════════════════════════════════════════════════════════
            autoload -Uz compinit
            mkdir -p "$ZSH_CACHE_DIR"
            compinit -i -d "$ZSH_CACHE_DIR/zcompdump"

            # Case-insensitive, partial-word, and substring completion
            zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=*' 'l:|=* r:|=*'

            # Menu selection
            zstyle ':completion:*' menu select

            # Colorful completions
            zstyle ':completion:*' list-colors "''${(s.:.)LS_COLORS}"

            # Group completions by category
            zstyle ':completion:*' group-name '''
            zstyle ':completion:*:descriptions' format '%F{yellow}── %d ──%f'
            zstyle ':completion:*:warnings' format '%F{red}No matches found%f'

            # Cache completions for faster results
            zstyle ':completion:*' use-cache on
            zstyle ':completion:*' cache-path "$ZSH_CACHE_DIR/completion"

            # Complete . and .. special directories
            zstyle ':completion:*' special-dirs true

            # Process completion
            zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
            zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'



            # ══════════════════════════════════════════════════════════════════
            # FZF Configuration
            # ══════════════════════════════════════════════════════════════════
            export FZF_DEFAULT_OPTS="
              --height 50%
              --layout=reverse
              --border=rounded
              --info=inline
              --margin=1
              --padding=1
              --color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8
              --color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc
              --color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8
              --bind='ctrl-/:toggle-preview'
            "

            # Use fd for faster file finding
            export FZF_DEFAULT_COMMAND='fd --type f --hidden --follow --exclude .git'

            # Ctrl+T: File search with bat preview
            export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
            export FZF_CTRL_T_OPTS="
              --preview 'bat --style=numbers,changes --color=always {} 2>/dev/null || true'
              --preview-window=right:60%:wrap
              --bind='ctrl-y:execute-silent(printf %s {} | wl-copy --type text/plain)'
            "

            # Alt+C: Directory navigation with tree preview
            export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
            export FZF_ALT_C_OPTS="
              --preview 'eza -la --color=always --icons=auto --group-directories-first {} 2>/dev/null || true'
              --preview-window=right:50%:wrap
            "

            # Ctrl+R: History search
            export FZF_CTRL_R_OPTS="
              --preview 'echo {}'
              --preview-window=down:3:wrap
              --bind='ctrl-y:execute-silent(printf %s {2..} | wl-copy --type text/plain)'
            "

            # ══════════════════════════════════════════════════════════════════
            # Plugin Configuration
            # ══════════════════════════════════════════════════════════════════
            # Autosuggestions style
            ZSH_AUTOSUGGEST_STRATEGY=(history completion)
            ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#6c7086'
            ZSH_AUTOSUGGEST_BUFFER_MAX_SIZE=20

            # History substring search colors
            HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_FOUND='bg=#45475a,fg=#f5e0dc,bold'
            HISTORY_SUBSTRING_SEARCH_HIGHLIGHT_NOT_FOUND='bg=#f38ba8,fg=#1e1e2e,bold'

            # ══════════════════════════════════════════════════════════════════
            # Load Plugins
            # ══════════════════════════════════════════════════════════════════
            # Load fzf-tab BEFORE zsh-autosuggestions
            source ${pkgs.zsh-fzf-tab}/share/fzf-tab/fzf-tab.plugin.zsh

            # fzf-tab configuration
            # Disable sort when completing `git checkout`
            zstyle ':completion:*:git-checkout:*' sort false
            # Set descriptions format to enable group support
            zstyle ':completion:*:descriptions' format '[%d]'
            # Preview directory and file candidates without depending on GNU ls output.
            zstyle ':fzf-tab:complete:cd:*' fzf-preview 'eza -la --color=always --icons=auto --group-directories-first "$realpath"'
            zstyle ':fzf-tab:complete:*:*' fzf-preview 'mime=""; if [ -n "$realpath" ] && [ -f "$realpath" ]; then mime=$(file --mime-type -b "$realpath" 2>/dev/null); fi; if [[ $mime == image/* ]]; then kitty +kitten icat --clear --transfer-mode=memory --stdin=no "$realpath"; else kitty +kitten icat --clear --stdin=no --silent --transfer-mode=memory; bat --style=numbers --color=always "$realpath" 2>/dev/null || eza -la --color=always --icons=auto --group-directories-first "$realpath" 2>/dev/null; fi'
            # Switch group using `,` and `.`
            zstyle ':fzf-tab:*' switch-group ',' '.'
            # Use tmux popup if available (optional)
            zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup
            # Continuous trigger (stay in completion after selection)
            zstyle ':fzf-tab:*' continuous-trigger '/'

            source ${pkgs.zsh-autosuggestions}/share/zsh-autosuggestions/zsh-autosuggestions.zsh
            source ${pkgs.zsh-history-substring-search}/share/zsh-history-substring-search/zsh-history-substring-search.zsh

            # FZF shell integration
            source ${pkgs.fzf}/share/fzf/completion.zsh
            source ${pkgs.fzf}/share/fzf/key-bindings.zsh

            # ══════════════════════════════════════════════════════════════════
            # Key Bindings
            # ══════════════════════════════════════════════════════════════════
            # Use emacs keybindings (like bash/fish defaults)
            bindkey -e

            # History substring search bindings
            bindkey '^[[A' history-substring-search-up
            bindkey '^[[B' history-substring-search-down
            bindkey '^P' history-substring-search-up
            bindkey '^N' history-substring-search-down

            # Word navigation
            bindkey '^[[1;5C' forward-word      # Ctrl+Right
            bindkey '^[[1;5D' backward-word     # Ctrl+Left

            # Delete word
            bindkey '^H' backward-kill-word     # Ctrl+Backspace

            # Home/End keys
            bindkey '^[[H' beginning-of-line
            bindkey '^[[F' end-of-line
            bindkey '^[[1~' beginning-of-line
            bindkey '^[[4~' end-of-line

            # Delete key
            bindkey '^[[3~' delete-char

            # Syntax highlighting (must be loaded last)
            source ${pkgs.zsh-syntax-highlighting}/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

            # Syntax highlighting styles (must be set AFTER sourcing the plugin)
            ZSH_HIGHLIGHT_STYLES[comment]='fg=#7f849c'  # Visible gray for comments (Catppuccin overlay1)
            ZSH_HIGHLIGHT_STYLES[alias]='fg=#89b4fa,bold'  # Keep generated aliases visually distinct from unknown commands.

            # ══════════════════════════════════════════════════════════════════
            # Aliases and functions
            # ══════════════════════════════════════════════════════════════════
            # Loaded earlier from ~/.config/nixconf/zsh/config.zsh so zshaddhistory can
            # see per-host ignore rules before the first interactive command is accepted.

            # ══════════════════════════════════════════════════════════════════
            # Environment Setup
            # ══════════════════════════════════════════════════════════════════
            ${userPackageZshSetup}

            # Setup GPG_TTY for GPG-support
            export GPG_TTY=$(tty)
            gpg-connect-agent updatestartuptty /bye >/dev/null 2>&1 # Silent

            # Kitty shell integration
            if [[ -n "$KITTY_INSTALLATION_DIR" ]]; then
                export KITTY_SHELL_INTEGRATION="enabled"
                autoload -Uz "$KITTY_INSTALLATION_DIR/shell-integration/zsh/kitty-integration"
                kitty-integration
            fi

            # ══════════════════════════════════════════════════════════════════
            # Oh My Posh Prompt
            # ══════════════════════════════════════════════════════════════════
            export POSH_NO_TERM_QUERIES=1
            eval "$(${self'.packages.oh-my-posh}/bin/oh-my-posh init zsh --config ${self'.packages.oh-my-posh.theme})"
            _omp_config=${self'.packages.oh-my-posh.theme}
          '';

      # Create a directory with .zshrc file for ZDOTDIR
      zdotdir = pkgs.runCommand "zsh-config" { } ''
        mkdir -p $out
        cp ${zshrc} $out/.zshrc
      '';
    in
    {
      packages.zsh = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.zsh;
        runtimeInputs = with pkgs; [
          zsh-fzf-tab # fzf for all tab completions
          zsh-autosuggestions
          zsh-syntax-highlighting
          zsh-history-substring-search
          zsh-completions
          fzf
          fd
          bat
          eza
          wl-clipboard
          lsof # killport uses terse PID output instead of parsing ss columns.
          scc # Replaces the local loc helper with nixpkgs' maintained code counter.
          tokei # Provides an alternate maintained LOC view for cross-checking project stats.
          git-quick-stats # Keeps git repository statistics available without custom shell parsing.
          file
          libnotify # For notifications
          kitty # For icat image preview
        ];
        env = {
          ZDOTDIR = zdotdir;
        };
      };
    };
}
