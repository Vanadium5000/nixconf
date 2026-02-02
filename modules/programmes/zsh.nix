{
  inputs,
  ...
}:
{
  perSystem =
    {
      pkgs,
      self',
      ...
    }:
    let
      # Create the .zshrc content
      zshrc =
        pkgs.writeText ".zshrc"
          # zsh
          ''
            # ══════════════════════════════════════════════════════════════════
            # History Configuration
            # ══════════════════════════════════════════════════════════════════
            HISTFILE=~/.zsh_history
            HISTSIZE=50000
            SAVEHIST=50000

            setopt HIST_IGNORE_SPACE      # Don't save commands starting with space (privacy)
            setopt HIST_IGNORE_DUPS       # Ignore duplicate commands
            setopt HIST_IGNORE_ALL_DUPS   # Remove older duplicate from history
            setopt HIST_FIND_NO_DUPS      # Don't show duplicates in search
            setopt HIST_REDUCE_BLANKS     # Remove superfluous blanks
            setopt EXTENDED_HISTORY       # Save timestamps (needed for correct history sharing)
            setopt SHARE_HISTORY          # Share history between all sessions

            zmodload zsh/parameter
            autoload -Uz add-zsh-hook

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
                if [[ $elapsed -ge 5 ]]; then
                  # Truncate command if it's too long for notification
                  local cmd_display=$last_command
                  if [[ ''${#cmd_display} -gt 50 ]]; then
                    cmd_display="''${cmd_display:0:47}..."
                  fi
                  notify-send "Task Completed" "$cmd_display\nDuration: $elapsed seconds" -i utilities-terminal
                fi
                unset command_start_time
              fi
            }

            add-zsh-hook preexec notify_long_command_preexec
            add-zsh-hook precmd notify_long_command_precmd

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
            setopt CORRECT                # Spelling correction for commands
            setopt COMPLETE_IN_WORD       # Complete from both ends of word
            setopt ALWAYS_TO_END          # Move cursor to end after completion

            # ══════════════════════════════════════════════════════════════════
            # Completion System
            # ══════════════════════════════════════════════════════════════════
            autoload -Uz compinit && compinit -d ~/.zcompdump

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
            zstyle ':completion:*' cache-path ~/.zsh/cache

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
              --preview 'bat --style=numbers,changes --color=always {} 2>/dev/null || cat {}'
              --preview-window=right:60%:wrap
              --bind='ctrl-y:execute-silent(echo {} | xclip -selection clipboard)'
            "

            # Alt+C: Directory navigation with tree preview
            export FZF_ALT_C_COMMAND='fd --type d --hidden --follow --exclude .git'
            export FZF_ALT_C_OPTS="
              --preview 'ls -la --color=always {} | head -50'
              --preview-window=right:50%:wrap
            "

            # Ctrl+R: History search
            export FZF_CTRL_R_OPTS="
              --preview 'echo {}'
              --preview-window=down:3:wrap
              --bind='ctrl-y:execute-silent(echo -n {2..} | xclip -selection clipboard)'
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
            # Preview directory's content with ls when completing cd
            zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls -la --color=always $realpath'
            # Preview file content with bat or icat for images
            zstyle ':fzf-tab:complete:*:*' fzf-preview 'mime=""; if [ -n "$realpath" ] && [ -f "$realpath" ]; then mime=$(file --mime-type -b $realpath 2>/dev/null); fi; if [[ $mime == image/* ]]; then kitty +kitten icat --clear --transfer-mode=memory --stdin=no $realpath; else kitty +kitten icat --clear --stdin=no --silent --transfer-mode=memory; bat --style=numbers --color=always $realpath 2>/dev/null || ls -la --color=always $realpath 2>/dev/null; fi'
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

            # ══════════════════════════════════════════════════════════════════
            # Aliases
            # ══════════════════════════════════════════════════════════════════
            # Clear screen + scrollback
            alias c="printf '\033[2J\033[3J\033[1;1H'"

            # System actions
            alias suspend="systemctl suspend"
            alias reboot="systemctl reboot"
            alias logout="hyprctl dispatch exit"
            alias poweroff="systemctl poweroff"

            # Utils
            alias ports="sudo ss -ltnup"

            # Better defaults with colors
            alias ls="ls --color=auto"
            alias ll="ls -lah --color=auto"
            alias la="ls -A --color=auto"
            alias grep="grep --color=auto"
            alias diff="diff --color=auto"

            # Quick navigation
            alias ..="cd .."
            alias ...="cd ../.."
            alias ....="cd ../../.."

            # Bat as cat replacement with better defaults
            alias cat="bat --style=plain --color=always --paging=never"
            alias less="bat --color=always --paging=always"

            # ══════════════════════════════════════════════════════════════════
            # Environment Setup
            # ══════════════════════════════════════════════════════════════════
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
            # Starship Prompt
            # ══════════════════════════════════════════════════════════════════
            eval "$(${self'.packages.starship}/bin/starship init zsh)"
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
