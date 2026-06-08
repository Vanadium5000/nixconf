# Waydroid Total Spoof - Device identity spoofing toolkit for Waydroid
# Spoofs device model, manufacturer, build fingerprint, and Android/GSF IDs
# to make Waydroid appear as a real physical device (bypass emulator detection)
# https://github.com/lil-xhris/Waydroid-total-spoof
{
  lib,
  stdenv,
  fetchFromGitHub,
  bash,
  makeWrapper,
  coreutils,
  gnused,
  gawk,
  openssl,
}:

stdenv.mkDerivation {
  pname = "waydroid-total-spoof";
  version = "0-unstable-2025-08-18"; # No releases/tags - tracks main branch

  src = fetchFromGitHub {
    owner = "lil-xhris";
    repo = "Waydroid-total-spoof";
    rev = "0941254b1bb608fce2751b58e5af2d2586a4d697";
    hash = "sha256-nTqUmwvuwDHNGUw1qDII6EgA5yQIty+mURw1aABybVQ=";
  };

  nativeBuildInputs = [ makeWrapper ];

  dontBuild = true;
  dontConfigure = true;

  installPhase = ''
        runHook preInstall

        mkdir -p $out/bin $out/share/waydroid-total-spoof

        # The upstream V2.0.sh currently ships with collapsed newlines in the pinned
        # revision, which turns comments/headings into commands and makes the script
        # fail before it can touch Waydroid state. Keep the upstream source for
        # reference, but install a small local wrapper that validates the environment
        # and writes the properties deterministically.
        install -Dm644 V2.0.sh $out/share/waydroid-total-spoof/V2.0.sh.upstream
        install -Dm644 waydroid.sh $out/share/waydroid-total-spoof/waydroid.sh.upstream

        cat > $out/share/waydroid-total-spoof/waydroid-total-spoof <<'EOF'
    #!${bash}/bin/bash
    set -euo pipefail

    WAYDROID_CFG="''${WAYDROID_CFG:-/var/lib/waydroid/waydroid.cfg}"
    WAYDROID_BASE_PROP="''${WAYDROID_BASE_PROP:-/var/lib/waydroid/waydroid_base.prop}"
    WAYDROID_ROOTFS="''${WAYDROID_ROOTFS:-/var/lib/waydroid/rootfs}"
    BACKUP_CFG="''${WAYDROID_CFG}.bak"
    BACKUP_BASE_PROP="''${WAYDROID_BASE_PROP}.bak"

    profiles=(
      "Pixel 5|google|Google|Pixel 5|redfin|google/redfin/redfin:11/RQ3A.211001.001/eng.electr.20230318.111310:user/release-keys"
      "Samsung Galaxy S24|samsung|Samsung|SM-S921B|dm1q|samsung/dm1qxx/dm1q:14/UP1A.231005.007/S921BXXU1AWM9:user/release-keys"
      "Samsung Galaxy S24 Ultra|samsung|Samsung|SM-S928B|e3q|samsung/e3qxx/e3q:14/UP1A.231005.007/S928BXXU1AWM9:user/release-keys"
      "RedMagic 8 Pro+|nubia|nubia|NX729J|NX729J|nubia/NX729J/NX729J:13/SKQ1.220201.001/20230822.123456:user/release-keys"
      "RedMagic 7S Pro|nubia|nubia|NX709S|NX709S|nubia/NX709S/NX709S:13/SKQ1.220201.001/20230822.123456:user/release-keys"
      "RedMagic 6 Pro|nubia|nubia|NX669J-P|NX669J-P|nubia/NX669J-P/NX669J-P:12/SKQ1.211019.001/20220822.123456:user/release-keys"
      "OnePlus 9 Pro|OnePlus|OnePlus|LE2123|lemonadep|OnePlus/OnePlus9Pro_EEA/OnePlus9Pro:13/LE2123_11_F.72/2309041234:user/release-keys"
      "OnePlus 11|OnePlus|OnePlus|CPH2449|salami|OnePlus/CPH2449EEA/OP595DL1:14/UKQ1.230924.001/S.23d57f1:user/release-keys"
      "OnePlus 12|OnePlus|OnePlus|CPH2581|waffle|OnePlus/CPH2581EEA/OP5A95L1:14/UKQ1.230924.001/V.18d4b1b:user/release-keys"
      "POCO X5 Pro|POCO|Xiaomi|22101320G|redwood|POCO/redwood_global/redwood:13/TKQ1.221114.001/V14.0.1.0.TMSMIXM:user/release-keys"
      "POCO F5|POCO|Xiaomi|23049PCD8G|marble|POCO/marble_global/marble:13/TKQ1.221114.001/V14.0.6.0.TMRMIXM:user/release-keys"
      "POCO F5 Pro|POCO|Xiaomi|23013RK75G|mondrian|POCO/mondrian_global/mondrian:13/TKQ1.221114.001/V14.0.4.0.TMNMIXM:user/release-keys"
      "Infinix Zero 30|Infinix|INFINIX MOBILITY LIMITED|X6731|X6731|Infinix/X6731-GL/X6731:13/TP1A.220624.014/231012V123:user/release-keys"
      "Infinix GT 10 Pro|Infinix|INFINIX MOBILITY LIMITED|X6739|X6739|Infinix/X6739-GL/X6739:13/TP1A.220624.014/230901V321:user/release-keys"
      "Infinix Zero Ultra|Infinix|INFINIX MOBILITY LIMITED|X6820|X6820|Infinix/X6820-GL/X6820:12/SP1A.210812.016/220930V456:user/release-keys"
      "Samsung Galaxy A54|samsung|Samsung|SM-A546B|a54x|samsung/a54xxx/a54x:14/UP1A.231005.007/A546BXXU5BXB1:user/release-keys"
      "Samsung Galaxy A74|samsung|Samsung|SM-A746B|a74x|samsung/a74xxx/a74x:14/UP1A.231005.007/A746BXXU3AWM1:user/release-keys"
      "Xiaomi 13|Xiaomi|Xiaomi|2211133G|fuxi|Xiaomi/fuxi_global/fuxi:14/UKQ1.230804.001/V816.0.7.0.UMCMIXM:user/release-keys"
      "Xiaomi 13T|Xiaomi|Xiaomi|2306EPN60G|aristotle|Xiaomi/aristotle_global/aristotle:14/UKQ1.230804.001/V816.0.12.0.UMFMIXM:user/release-keys"
      "Xiaomi 12T Pro|Xiaomi|Xiaomi|22081212UG|diting|Xiaomi/diting_global/diting:13/TKQ1.221114.001/V14.0.13.0.TLFMIXM:user/release-keys"
      "Tecno Camon 20 Premier|TECNO|Tecno|CK9n|CK9n|TECNO/CK9n/CK9n:13/TP1A.220624.014/230818V222:user/release-keys"
      "Realme GT 3|realme|realme|RMX3709|RE548D|realme/RMX3709EEA/RMX3709:14/UKQ1.230924.001/1705983494950:user/release-keys"
      "Vivo V27 Pro|vivo|vivo|V2230|PD2271|vivo/PD2271/PD2271:13/TP1A.220624.014/compiler07211544:user/release-keys"
      "Nothing Phone 2|Nothing|NOTHING|A065|Pong|Nothing/PongEEA/Pong:14/UP1A.231005.007/240119-1838:user/release-keys"
      "ROG Phone 7 Ultimate|asus|asus|AI2205_D|AI2205|asus/WW_AI2205/ASUS_AI2205:14/UKQ1.230917.001/34.1010.0820.99:user/release-keys"
    )

    glob_exists() {
      compgen -G "$1" >/dev/null
    }

    cfg_prop_value() {
      ${gawk}/bin/awk -v key="$1" '
        function trim(value) {
          sub(/^[[:space:]]*/, "", value)
          sub(/[[:space:]]*$/, "", value)
          return value
        }

        $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
          value = $0
          sub(/^[^=]*=/, "", value)
          found = trim(value)
        }

        END { print found }
      ' "$WAYDROID_CFG"
    }

    first_supported_dri_node() {
      local node driver
      for node in /dev/dri/renderD*; do
        [[ -e "$node" ]] || continue
        driver="$(sed -n 's/^DRIVER=//p' "/sys/class/drm/$(basename "$node")/device/uevent" 2>/dev/null || true)"
        # Upstream Waydroid skips the proprietary NVIDIA DRM node here: the
        # Android Mesa/minigbm stack has no matching NVIDIA userspace driver.
        [[ "$driver" == "nvidia" ]] && continue
        printf '%s|%s\n' "$node" "$driver"
        return 0
      done
      return 1
    }

    vulkan_driver_for_dri_driver() {
      case "$1" in
        i915 | xe) printf '%s\n' intel ;;
        amdgpu) printf '%s\n' radeon ;;
        panfrost) printf '%s\n' panfrost ;;
        msm | msm_dpu) printf '%s\n' freedreno ;;
        vc4) printf '%s\n' broadcom ;;
        nouveau) printf '%s\n' nouveau ;;
      esac
    }

    write_renderer_repairs() {
      local out="$1"
      local current_egl current_vulkan dri_info dri_node dri_driver vulkan_driver
      current_egl="$(cfg_prop_value ro.hardware.egl)"
      current_vulkan="$(cfg_prop_value ro.hardware.vulkan)"

      dri_info="$(first_supported_dri_node || true)"
      if [[ -n "$dri_info" ]] && glob_exists "$WAYDROID_ROOTFS/vendor/lib*/egl/libEGL_mesa.so"; then
        dri_node="''${dri_info%%|*}"
        dri_driver="''${dri_info#*|}"
        vulkan_driver="$(vulkan_driver_for_dri_driver "$dri_driver")"

        # This is the fast Waydroid path: minigbm + Mesa against the host DRM
        # render node. Angle/pastel boots here, but Roblox regresses badly under
        # ARM translation compared with the direct Mesa/i915 path.
        printf '%s\n' "gralloc.gbm.device=$dri_node" >> "$out"
        printf '%s\n' 'ro.hardware.gralloc=gbm' >> "$out"
        printf '%s\n' 'ro.hardware.egl=mesa' >> "$out"
        if [[ -n "$vulkan_driver" ]] && glob_exists "$WAYDROID_ROOTFS/vendor/lib*/hw/vulkan.$vulkan_driver.so"; then
          printf '%s\n' "ro.hardware.vulkan=$vulkan_driver" >> "$out"
        elif [[ -z "$current_vulkan" ]] && glob_exists "$WAYDROID_ROOTFS/vendor/lib*/hw/vulkan.pastel.so"; then
          printf '%s\n' 'ro.hardware.vulkan=pastel' >> "$out"
        fi
        printf '%s\n' 'debug.hwui.renderer=skiagl' >> "$out"
        printf '%s\n' 'debug.egl.hw=1' >> "$out"
        printf '%s\n' 'debug.composition.type=gpu' >> "$out"
        printf '%s\n' 'persist.sys.ui.hw=1' >> "$out"
        printf '%s\n' 'hwui.render_dirty_regions=false' >> "$out"
        printf '%s\n' 'persist.sys.gpu.force=1' >> "$out"
        # ARM translated Roblox can sit in nativeStart long enough to trip
        # Android's default 5s input-dispatch ANR during asset/flag startup.
        printf '%s\n' 'ro.hw_timeout_multiplier=12' >> "$out"
        printf '%s\n' 'ro.opengles.version=196610' >> "$out"
        printf '%s\n' 'persist.graphics.vulkan.disable=false' >> "$out"
        printf '%s\n' 'persist.vulkan.enabled=1' >> "$out"
        printf '%s\n' 'persist.waydroid.no_presentation=true' >> "$out"
        printf '%s\n' 'ro.surface_flinger.has_wide_color_display=false' >> "$out"
        # ConfigParser treats option names case-insensitively, so keep this key
        # lower-case in waydroid.cfg to avoid duplicate-option failures on repair.
        printf '%s\n' 'ro.surface_flinger.has_hdr_display=false' >> "$out"
        printf '%s\n' 'persist.sys.sf.color_mode=0' >> "$out"
        printf '%s\n' 'persist.sys.sf.native_mode=0' >> "$out"
        printf '%s\n' 'persist.sys.sf.color_saturation=1.0' >> "$out"
        return 0
      fi

      # Waydroid mainline images commonly ship Angle/Mesa EGL but no SwiftShader
      # EGL implementation; preserving an old ro.hardware.egl=swiftshader override
      # makes SurfaceFlinger/zygote fail before apps can render. Only rewrite the
      # known-bad override when the matching EGL library is absent.
      if [[ "$current_egl" == "swiftshader" ]] && ! glob_exists "$WAYDROID_ROOTFS/vendor/lib*/egl/libEGL_swiftshader.so"; then
        if glob_exists "$WAYDROID_ROOTFS/vendor/lib*/egl/libEGL_angle.so"; then
          printf '%s\n' 'ro.hardware.egl=angle' >> "$out"
        elif glob_exists "$WAYDROID_ROOTFS/vendor/lib*/egl/libEGL_mesa.so"; then
          printf '%s\n' 'ro.hardware.egl=mesa' >> "$out"
        fi
      fi

      if [[ -z "$current_vulkan" ]] && glob_exists "$WAYDROID_ROOTFS/vendor/lib*/hw/vulkan.pastel.so"; then
        printf '%s\n' 'ro.hardware.vulkan=pastel' >> "$out"
      fi
    }

    repair_native_bridge() {
      if ! command -v waydroid >/dev/null 2>&1; then
        echo "error: 'waydroid' is not in PATH. Install/enter an environment with Waydroid first." >&2
        exit 1
      fi

      if [[ ! -f "$WAYDROID_CFG" ]]; then
        echo "error: $WAYDROID_CFG does not exist. Initialize Waydroid first so its config is created." >&2
        exit 1
      fi

      tmp_cfg="$(mktemp)"
      tmp_cfg_properties="$(mktemp)"
      tmp_cfg_renderer_repairs="$(mktemp)"
      trap 'rm -f "$tmp_cfg" "$tmp_cfg_properties" "$tmp_cfg_renderer_repairs"' EXIT

      cp "$WAYDROID_CFG" "$BACKUP_CFG"
      write_renderer_repairs "$tmp_cfg_renderer_repairs"

      # Waydroid only exports Android props from [properties] (see upstream
      # tools/helpers/lxc.py writing cfg["properties"] into waydroid_base.prop).
      # casualsnek's libndk installer can leave native-bridge ABI keys elsewhere;
      # migrate them so ARM-only apps such as Roblox can start under libndk.
      ${gawk}/bin/awk -v preserved_props="$tmp_cfg_properties" -v repaired_props="$tmp_cfg_renderer_repairs" '
        BEGIN {
          while ((getline repair_line < repaired_props) > 0) {
            repair_option = repair_line
            sub(/^[[:space:]]*/, "", repair_option)
            sub(/[[:space:]]*=.*/, "", repair_option)
            renderer_repair[tolower(repair_option)] = 1
          }
          close(repaired_props)
        }

        function trim(value) {
          sub(/^[[:space:]]*/, "", value)
          sub(/[[:space:]]*$/, "", value)
          return value
        }

        function save_native_bridge(line, option) {
          option = line
          sub(/^[[:space:]]*/, "", option)
          sub(/[[:space:]]*=.*/, "", option)
          if (!native_bridge_seen[option]++) {
            native_bridge[option] = line
          }
        }

        /^[[:space:]]*(gralloc\.gbm\.device|ro\.hardware\.gralloc|ro\.hardware\.egl|ro\.hardware\.vulkan|debug\.hwui\.renderer|debug\.egl\.hw|debug\.composition\.type|persist\.sys\.ui\.hw|hwui\.render_dirty_regions|persist\.sys\.gpu\.force|ro\.hw_timeout_multiplier|ro\.opengles\.version|persist\.graphics\.vulkan\.disable|persist\.vulkan\.enabled|persist\.waydroid\.no_presentation|ro\.surface_flinger\.has_wide_color_display|ro\.surface_flinger\.has_HDR_display|ro\.surface_flinger\.has_hdr_display|persist\.sys\.sf\.color_mode|persist\.sys\.sf\.native_mode|persist\.sys\.sf\.color_saturation)[[:space:]]*=/ {
          option = $0
          sub(/^[[:space:]]*/, "", option)
          sub(/[[:space:]]*=.*/, "", option)
          if (tolower(option) in renderer_repair) next
        }

        /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
          header = trim($0)
          in_properties = (header == "[properties]")
          if (in_properties) next
        }

        /^[[:space:]]*(ro\.product\.cpu\.abilist|ro\.product\.cpu\.abilist32|ro\.product\.cpu\.abilist64|ro\.dalvik\.vm\.native\.bridge|ro\.enable\.native\.bridge\.exec|ro\.vendor\.enable\.native\.bridge\.exec|ro\.vendor\.enable\.native\.bridge\.exec64|ro\.ndk_translation\.version|ro\.dalvik\.vm\.isa\.arm|ro\.dalvik\.vm\.isa\.arm64)[[:space:]]*=/ {
          save_native_bridge($0)
          next
        }

        in_properties {
          if ($0 ~ /^[[:space:]]*[^#;[:space:]][^=]*=/) {
            option = $0
            sub(/^[[:space:]]*/, "", option)
            sub(/[[:space:]]*=.*/, "", option)
            if (seen_properties[option]++) next
          }
          print > preserved_props
          next
        }

        /^[[:space:]]*[^#;[:space:]][^=]*=/ {
          option = $0
          sub(/^[[:space:]]*/, "", option)
          sub(/[[:space:]]*=.*/, "", option)
          if (seen[header SUBSEP option]++) next
        }

        { print }

        END {
          for (idx = 1; idx <= split("ro.product.cpu.abilist ro.product.cpu.abilist32 ro.product.cpu.abilist64 ro.dalvik.vm.native.bridge ro.enable.native.bridge.exec ro.vendor.enable.native.bridge.exec ro.vendor.enable.native.bridge.exec64 ro.ndk_translation.version ro.dalvik.vm.isa.arm ro.dalvik.vm.isa.arm64", keys, " "); idx++) {
            key = keys[idx]
            if (!(key in native_bridge)) {
              if (key == "ro.product.cpu.abilist") native_bridge[key] = key "=x86_64,x86,arm64-v8a,armeabi-v7a,armeabi"
              else if (key == "ro.product.cpu.abilist32") native_bridge[key] = key "=x86,armeabi-v7a,armeabi"
              else if (key == "ro.product.cpu.abilist64") native_bridge[key] = key "=x86_64,arm64-v8a"
              else if (key == "ro.dalvik.vm.native.bridge") native_bridge[key] = key "=libndk_translation.so"
              else if (key == "ro.ndk_translation.version") native_bridge[key] = key "=0.2.3"
              else if (key == "ro.dalvik.vm.isa.arm") native_bridge[key] = key "=x86"
              else if (key == "ro.dalvik.vm.isa.arm64") native_bridge[key] = key "=x86_64"
              else native_bridge[key] = key "=1"
            }
            print native_bridge[key] >> preserved_props
          }
        }
      ' "$BACKUP_CFG" > "$tmp_cfg"

      cat "$tmp_cfg_renderer_repairs" >> "$tmp_cfg_properties"

      printf '[properties]\n' >> "$tmp_cfg"
      cat "$tmp_cfg_properties" >> "$tmp_cfg"
      install -m644 "$tmp_cfg" "$WAYDROID_CFG"

      echo "[+] Migrated native-bridge ABI properties into [properties]."
      if [[ -s "$tmp_cfg_renderer_repairs" ]]; then
        echo "[+] Repaired invalid renderer overrides for this Waydroid image."
      fi
      echo "[+] Backup: $BACKUP_CFG"
      echo "[+] Applying changes with: waydroid upgrade --offline"
      waydroid upgrade --offline
      echo "[+] Done. Restart the Waydroid session if it is already running."
    }

    if [[ "''${1:-}" == "--help" || "''${1:-}" == "-h" ]]; then
      cat <<'EOF_HELP'
    Usage: waydroid-total-spoof
           waydroid-total-spoof --repair-native-bridge

    Interactively choose a physical Android device profile, then update
    /var/lib/waydroid/waydroid.cfg and /var/lib/waydroid/waydroid_base.prop.
    Existing non-spoof properties in [properties] are preserved.

    --repair-native-bridge migrates libndk/native-bridge ABI properties into
    [properties] so ARM-only apps, including Roblox, can launch in Waydroid.
    It also restores Waydroid's fast minigbm/Mesa render path and raises the
    hardware timeout multiplier so translated Roblox startup does not trip the
    default 5s input-dispatch ANR. NVIDIA render nodes stay excluded because
    Android's Mesa userspace cannot drive the proprietary NVIDIA DRM node.
    EOF_HELP
      exit 0
    fi

    if [[ "''${1:-}" == "--repair-native-bridge" ]]; then
      repair_native_bridge
      exit 0
    fi

    if ! command -v waydroid >/dev/null 2>&1; then
      echo "error: 'waydroid' is not in PATH. Install/enter an environment with Waydroid first." >&2
      exit 1
    fi

    if [[ ! -f "$WAYDROID_CFG" ]]; then
      echo "error: $WAYDROID_CFG does not exist. Initialize Waydroid first so its config is created." >&2
      exit 1
    fi

    if [[ ! -f "$WAYDROID_BASE_PROP" ]]; then
      echo "error: $WAYDROID_BASE_PROP does not exist. Initialize Waydroid first so its base properties are created." >&2
      exit 1
    fi

    echo "[+] Waydroid Total Spoof"
    echo "Choose a device to spoof (1-''${#profiles[@]}):"
    for i in "''${!profiles[@]}"; do
      IFS='|' read -r name _ <<< "''${profiles[$i]}"
      printf '  %d) %s\n' "$((i + 1))" "$name"
    done

    read -rp "> " choice
    if ! [[ "$choice" =~ ^[0-9]+$ ]] || (( choice < 1 || choice > ''${#profiles[@]} )); then
      echo "error: invalid selection '$choice'." >&2
      exit 1
    fi

    IFS='|' read -r name brand manufacturer model device_name build_fingerprint <<< "''${profiles[$((choice - 1))]}"

    cp "$WAYDROID_CFG" "$BACKUP_CFG"
    cp "$WAYDROID_BASE_PROP" "$BACKUP_BASE_PROP"

    android_id="$(${openssl}/bin/openssl rand -hex 8)"
    gsf_id="$(${openssl}/bin/openssl rand -hex 8)"
    build_description="''${device_name}-user 14 UP1A.231005.007 release-keys"

    tmp_cfg="$(mktemp)"
    tmp_prop="$(mktemp)"
    tmp_cfg_properties="$(mktemp)"
    trap 'rm -f "$tmp_cfg" "$tmp_prop" "$tmp_cfg_properties"' EXIT

    # Waydroid reads this file with Python ConfigParser, which rejects duplicate
    # keys inside a section. Preserve non-spoof [properties] entries such as
    # renderer workarounds, strip only keys this script owns, and keep only the
    # first copy of any other duplicate key.
    ${gawk}/bin/awk -v preserved_props="$tmp_cfg_properties" '
      function trim(value) {
        sub(/^[[:space:]]*/, "", value)
        sub(/[[:space:]]*$/, "", value)
        return value
      }

      /^[[:space:]]*\[[^]]+\][[:space:]]*$/ {
        header = trim($0)
        in_properties = (header == "[properties]")
        if (in_properties) next
      }

      /^[[:space:]]*(ro\.product\.brand|ro\.product\.manufacturer|ro\.product\.model|ro\.product\.name|ro\.product\.device|ro\.system\.build\.product|ro\.build\.fingerprint|ro\.system\.build\.fingerprint|ro\.vendor\.build\.fingerprint|ro\.bootimage\.build\.fingerprint|ro\.odm\.build\.fingerprint|ro\.product\.build\.fingerprint|ro\.system_ext\.build\.fingerprint|ro\.vendor_dlkm\.build\.fingerprint|ro\.build\.display\.id|ro\.system\.build\.flavor|ro\.system\.build\.description|ro\.build\.description|ro\.build\.tags|ro\.vendor\.build\.id|ro\.vendor\.build\.tags|ro\.vendor\.build\.type|ro\.odm\.build\.tags|ro\.boot\.verifiedbootstate|ro\.boot\.flash\.locked|ro\.secure|ro\.debuggable|ro\.adb\.secure|ro\.build\.type|ro\.build\.selinux|ro\.boot\.selinux|ro\.kernel\.qemu|persist\.sys\.usb\.config)[[:space:]]*=/ { next }

      in_properties {
        if ($0 ~ /^[[:space:]]*[^#;[:space:]][^=]*=/) {
          option = $0
          sub(/^[[:space:]]*/, "", option)
          sub(/[[:space:]]*=.*/, "", option)
          if (seen_properties[option]++) next
        }
        print > preserved_props
        next
      }

      /^[[:space:]]*[^#;[:space:]][^=]*=/ {
        option = $0
        sub(/^[[:space:]]*/, "", option)
        sub(/[[:space:]]*=.*/, "", option)
        if (seen[header SUBSEP option]++) next
      }

      { print }
    ' "$BACKUP_CFG" > "$tmp_cfg"

    printf '[properties]\n' >> "$tmp_cfg"
    cat "$tmp_cfg_properties" >> "$tmp_cfg"
    cat >> "$tmp_cfg" <<EOF_CFG
    ro.product.brand=$brand
    ro.product.manufacturer=$manufacturer
    ro.product.model=$model
    ro.product.name=$device_name
    ro.product.device=$device_name
    ro.system.build.product=$device_name
    ro.build.fingerprint=$build_fingerprint
    ro.system.build.fingerprint=$build_fingerprint
    ro.vendor.build.fingerprint=$build_fingerprint
    ro.bootimage.build.fingerprint=$build_fingerprint
    ro.odm.build.fingerprint=$build_fingerprint
    ro.product.build.fingerprint=$build_fingerprint
    ro.system_ext.build.fingerprint=$build_fingerprint
    ro.vendor_dlkm.build.fingerprint=$build_fingerprint
    ro.build.display.id=$build_fingerprint
    ro.system.build.flavor=''${device_name}-user
    ro.system.build.description=$build_description
    ro.build.description=$build_description
    ro.build.tags=release-keys
    ro.vendor.build.id=UP1A.231005.007
    ro.vendor.build.tags=release-keys
    ro.vendor.build.type=user
    ro.odm.build.tags=release-keys
    ro.boot.verifiedbootstate=green
    ro.boot.flash.locked=1
    ro.secure=1
    ro.debuggable=0
    ro.adb.secure=1
    ro.build.type=user
    ro.build.selinux=1
    ro.boot.selinux=enforcing
    ro.kernel.qemu=0
    persist.sys.usb.config=none
    ro.hw_timeout_multiplier=12
    ro.surface_flinger.has_wide_color_display=false
    ro.surface_flinger.has_hdr_display=false
    persist.sys.sf.color_mode=0
    persist.sys.sf.native_mode=0
    persist.sys.sf.color_saturation=1.0
    EOF_CFG

    # Preserve Waydroid's base runtime properties (notably native-bridge ABI
    # mapping); replacing this file with only spoof keys makes ARM-only apps
    # fail with "Unsupported zygote ABI: arm64-v8a".
    ${gawk}/bin/awk '
      /^[[:space:]]*(ro\.product\.brand|ro\.product\.manufacturer|ro\.product\.model|ro\.product\.name|ro\.product\.device|ro\.system\.build\.product|ro\.build\.fingerprint|ro\.system\.build\.fingerprint|ro\.vendor\.build\.fingerprint|ro\.bootimage\.build\.fingerprint|ro\.odm\.build\.fingerprint|ro\.product\.build\.fingerprint|ro\.system_ext\.build\.fingerprint|ro\.vendor_dlkm\.build\.fingerprint|ro\.build\.display\.id|ro\.system\.build\.flavor|ro\.system\.build\.description|ro\.build\.description|ro\.build\.tags|ro\.vendor\.build\.id|ro\.vendor\.build\.tags|ro\.vendor\.build\.type|ro\.odm\.build\.tags|ro\.boot\.verifiedbootstate|ro\.boot\.flash\.locked|ro\.secure|ro\.debuggable|ro\.adb\.secure|ro\.build\.type|ro\.build\.selinux|ro\.boot\.selinux|ro\.kernel\.qemu|persist\.sys\.usb\.config|debug\.hwui\.renderer|debug\.egl\.hw|debug\.composition\.type|persist\.sys\.ui\.hw|hwui\.render_dirty_regions|persist\.sys\.gpu\.force|ro\.hw_timeout_multiplier|ro\.opengles\.version|persist\.graphics\.vulkan\.disable|persist\.vulkan\.enabled|ro\.surface_flinger\.has_wide_color_display|ro\.surface_flinger\.has_HDR_display|ro\.surface_flinger\.has_hdr_display|persist\.sys\.sf\.color_mode|persist\.sys\.sf\.native_mode|persist\.sys\.sf\.color_saturation|settings_secure_android_id|settings_secure_gsf_id)[[:space:]]*=/ { next }

      /^[[:space:]]*[^#;[:space:]][^=]*=/ {
        option = $0
        sub(/^[[:space:]]*/, "", option)
        sub(/[[:space:]]*=.*/, "", option)
        if (seen[option]++) next
      }

      { print }
    ' "$BACKUP_BASE_PROP" > "$tmp_prop"
    cat >> "$tmp_prop" <<EOF_PROP
    ro.product.brand=$brand
    ro.product.manufacturer=$manufacturer
    ro.product.model=$model
    ro.product.name=$device_name
    ro.product.device=$device_name
    ro.system.build.product=$device_name
    ro.build.fingerprint=$build_fingerprint
    ro.system.build.fingerprint=$build_fingerprint
    ro.vendor.build.fingerprint=$build_fingerprint
    ro.bootimage.build.fingerprint=$build_fingerprint
    ro.odm.build.fingerprint=$build_fingerprint
    ro.product.build.fingerprint=$build_fingerprint
    ro.system_ext.build.fingerprint=$build_fingerprint
    ro.vendor_dlkm.build.fingerprint=$build_fingerprint
    ro.build.display.id=$build_fingerprint
    ro.system.build.flavor=''${device_name}-user
    ro.system.build.description=$build_description
    ro.build.description=$build_description
    ro.build.tags=release-keys
    ro.vendor.build.id=UP1A.231005.007
    ro.vendor.build.tags=release-keys
    ro.vendor.build.type=user
    ro.odm.build.tags=release-keys
    ro.boot.verifiedbootstate=green
    ro.boot.flash.locked=1
    ro.secure=1
    ro.debuggable=0
    ro.adb.secure=1
    ro.build.type=user
    ro.build.selinux=1
    ro.boot.selinux=enforcing
    ro.kernel.qemu=0
    persist.sys.usb.config=none
    debug.hwui.renderer=skiagl
    debug.egl.hw=1
    debug.composition.type=gpu
    persist.sys.ui.hw=1
    hwui.render_dirty_regions=false
    persist.sys.gpu.force=1
    ro.hw_timeout_multiplier=12
    ro.opengles.version=196610
    persist.graphics.vulkan.disable=false
    persist.vulkan.enabled=1
    ro.surface_flinger.has_wide_color_display=false
    ro.surface_flinger.has_hdr_display=false
    persist.sys.sf.color_mode=0
    persist.sys.sf.native_mode=0
    persist.sys.sf.color_saturation=1.0
    settings_secure_android_id=$android_id
    settings_secure_gsf_id=$gsf_id
    EOF_PROP

    install -m644 "$tmp_cfg" "$WAYDROID_CFG"
    install -m644 "$tmp_prop" "$WAYDROID_BASE_PROP"

    echo "[+] Spoofed Waydroid as: $name"
    echo "[+] Backups: $BACKUP_CFG, $BACKUP_BASE_PROP"
    echo "[+] Applying changes with: waydroid upgrade --offline"
    waydroid upgrade --offline
    echo "[+] Done. Restart the Waydroid session if it is already running."
    EOF
        chmod +x $out/share/waydroid-total-spoof/waydroid-total-spoof

        makeWrapper $out/share/waydroid-total-spoof/waydroid-total-spoof $out/bin/waydroid-total-spoof \
          --prefix PATH : ${
            lib.makeBinPath [
              bash
              coreutils
              gnused
              gawk
              openssl
            ]
          }

        # Keep the legacy entrypoint for compatibility, but route it to the same
        # maintained wrapper so users do not hit the broken upstream scripts.
        makeWrapper $out/share/waydroid-total-spoof/waydroid-total-spoof $out/bin/waydroid-spoof-legacy \
          --prefix PATH : ${
            lib.makeBinPath [
              bash
              coreutils
              gnused
              gawk
              openssl
            ]
          }

        runHook postInstall
  '';

  meta = {
    description = "Device identity spoofing toolkit for Waydroid (bypass emulator detection)";
    homepage = "https://github.com/lil-xhris/Waydroid-total-spoof";
    platforms = lib.platforms.linux;
    mainProgram = "waydroid-total-spoof";
  };
}
