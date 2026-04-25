{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  makeBinaryWrapper,
  playwright-driver,
  versionCheckHook,
  writeShellScript,
}:

buildNpmPackage (finalAttrs: {
  pname = "playwright-cli";
  version = "0.1.1";

  src = fetchFromGitHub {
    owner = "microsoft";
    repo = "playwright-cli";
    tag = "v${finalAttrs.version}";
    hash = "sha256-Ao3phIPinliFDK04u/V3ouuOfwMDVf/qBUpQPESziFQ=";
  };

  npmDepsHash = "sha256-4x3ozVrST6LtLoHl9KtmaOKrkYwCK84fwEREaoNaESc=";

  dontNpmBuild = true;

  # Playwright stores the browser revision in a versioned directory name, so we
  # resolve it at evaluation time and pin the CLI to the exact Chromium binary
  # shipped by nixpkgs. This avoids the upstream default Chrome channel lookup
  # under /opt that fails on NixOS.
  # Ref: https://playwright.dev/docs/browsers
  passthru.chromiumExecutablePath =
    let
      chromiumDir = builtins.head (
        builtins.filter (x: builtins.match "chromium-.*" x != null) (
          builtins.attrNames (builtins.readDir playwright-driver.browsers)
        )
      );
    in
    "${playwright-driver.browsers}/${chromiumDir}/chrome-linux/chrome";

  # The local skills.sh Playwright skill shells out to a real `playwright-cli`
  # binary. Package it declaratively here so the skill works on fresh systems
  # without mutable global npm installs.
  # Ref: .agents/skills/playwright-cli/SKILL.md
  nativeBuildInputs = [
    makeBinaryWrapper
  ];

  postInstall = ''
    mkdir -p $out/share/playwright-cli
    cat > $out/share/playwright-cli/playwright-cli.json <<EOF
    {
      "browser": {
        "browserName": "chromium",
        "launchOptions": {
          "executablePath": "${finalAttrs.passthru.chromiumExecutablePath}",
          "headless": true
        }
      }
    }
    EOF
  '';

  postFixup = ''
    wrapProgram $out/bin/playwright-cli \
      --set-default PLAYWRIGHT_MCP_CONFIG $out/share/playwright-cli/playwright-cli.json \
      --set-default PLAYWRIGHT_BROWSERS_PATH ${playwright-driver.browsers} \
      --set-default PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD 1 \
      --set-default PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS true
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgram = writeShellScript "version-check" ''
    "$1" --version >/dev/null
    echo "${finalAttrs.version}"
  '';
  versionCheckProgramArg = "${placeholder "out"}/bin/playwright-cli";

  meta = {
    description = "Playwright CLI for browser automation";
    homepage = "https://github.com/microsoft/playwright-cli";
    changelog = "https://github.com/microsoft/playwright-cli/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.asl20;
    platforms = lib.platforms.linux;
    mainProgram = "playwright-cli";
  };
})
