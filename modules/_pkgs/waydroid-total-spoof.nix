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
  gnugrep,
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
    trap 'rm -f "$tmp_cfg" "$tmp_prop"' EXIT

    ${gnugrep}/bin/grep -v '^\[properties\]$' "$BACKUP_CFG" > "$tmp_cfg" || true
    cat >> "$tmp_cfg" <<EOF_CFG
    [properties]
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
    ro.opengles.version=196610
    persist.graphics.vulkan.disable=false
    persist.vulkan.enabled=1
    persist.sys.sf.color_saturation=1.1
    EOF_CFG

    cat > "$tmp_prop" <<EOF_PROP
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
    ro.opengles.version=196610
    persist.graphics.vulkan.disable=false
    persist.vulkan.enabled=1
    persist.sys.sf.color_saturation=1.1
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
              gnugrep
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
              gnugrep
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
