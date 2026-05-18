{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      config = pkgs.writeText "sonicboom-dark-no-boom.omp.json" ''
        {
          "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
          "blocks": [
            {
              "alignment": "left",
              "segments": [
                {
                  "background": "#272727",
                  "foreground": "#00d0ff",
                  "options": {
                    "alpine": "",
                    "arch": "",
                    "centos": "",
                    "debian": "",
                    "elementary": "",
                    "fedora": "",
                    "gentoo": "",
                    "linux": "",
                    "macos": "",
                    "manjaro": "",
                    "mint": "",
                    "opensuse": "",
                    "raspbian": "",
                    "ubuntu": "",
                    "windows": ""
                  },
                  "style": "plain",
                  "template": " {{ if .WSL }}WSL at {{ end }}{{.Icon}} ",
                  "type": "os"
                },
                {
                  "background": "#272727",
                  "foreground": "#43CCEA",
                  "options": {
                    "folder_icon": "",
                    "folder_separator_icon": " <#000000> </>",
                    "home_icon": "",
                    "style": "agnoster_short"
                  },
                  "style": "plain",
                  "template": " {{ .Path }} ",
                  "type": "path"
                },
                {
                  "background": "#272727",
                  "foreground": "#00ff0d",
                  "options": {
                    "fetch_status": true
                  },
                  "style": "plain",
                  "template": "<#000000> </>{{ .HEAD }}{{ if .Staging.Changed }}<#FF6F00>  {{ .Staging.String }}</>{{ end }}{{ if and (.Working.Changed) (.Staging.Changed) }} |{{ end }}{{ if .Working.Changed }}  {{ .Working.String }}{{ end }}{{ if gt .StashCount 0 }}  {{ .StashCount }}{{ end }} ",
                  "type": "git"
                },
                {
                  "background": "#272727",
                  "foreground": "#ffffff",
                  "options": {
                    "style": "dallas",
                    "threshold": 0
                  },
                  "style": "diamond",
                  "template": "<#000000> </>{{ .FormattedMs }}s ",
                  "trailing_diamond": "",
                  "type": "executiontime"
                }
              ],
              "type": "prompt"
            },
            {
              "alignment": "right",
              "segments": [
                {
                  "background": "#272727",
                  "foreground": "#43CCEA",
                  "style": "diamond",
                  "template": " {{ if .SSHSession }} {{ end }}{{ .UserName }}<transparent> / </>{{ .HostName }}",
                  "type": "session"
                },
                {
                  "background": "#272727",
                  "foreground": "#43CCEA",
                  "options": {
                    "time_format": "3:04:05 PM"
                  },
                  "style": "diamond",
                  "template": "<#000000> </>{{ .CurrentDate | date .Format }} ",
                  "type": "time"
                }
              ],
              "type": "prompt"
            },
            {
              "alignment": "left",
              "newline": true,
              "segments": [
                {
                  "foreground": "#00ff0d",
                  "foreground_templates": [
                    "{{ if gt .Code 0 }}#ff0000{{ end }}"
                  ],
                  "options": {
                    "always_enabled": true
                  },
                  "style": "plain",
                  "template": " ",
                  "type": "status"
                }
              ],
              "type": "prompt"
            }
          ],
          "final_space": true,
          "version": 4
        }
      '';
    in
    {
      packages.oh-my-posh = inputs.wrappers.lib.makeWrapper {
        inherit pkgs;
        package = pkgs.oh-my-posh;
        env = {
          POSH_THEME = config;
        };
        passthru = {
          theme = config;
        };
      };
    };
}
