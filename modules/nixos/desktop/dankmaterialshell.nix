{ self, ... }:
{
  flake.nixosModules.dankmaterialshell =
    {
      config,
      pkgs,
      ...
    }:

    let
      inherit (self) colors theme;

      # Derive user and home directory from config
      user = config.preferences.user.username;

      style = {
        name = "Nix Cyberpunk Electric Dark";
        # Primary color scheme based on bright blue accent for cyberpunk neon feel
        primary = colors.accent; # #5454fc - bright blue
        primaryText = colors.base00; # #000000 - black for contrast on bright primary
        primaryContainer = colors.background-alt; # #0d0d0d - subtle dark variant for containers
        secondary = colors.base0E; # #fc54fc - bright magenta
        surface = colors.background; # #000000 - pure black base
        surfaceText = colors.foreground; # #a8a8a8 - mid-gray for readability
        surfaceVariant = colors.base02; # #383838 - brightish black
        surfaceVariantText = colors.base04; # #7e7e7e - darker white for variant text
        surfaceTint = colors.accent; # #5454fc - blue tint overlay
        background = colors.background; # #000000 - black
        backgroundText = colors.base07; # #fcfcfc - bright white for high contrast
        outline = colors.border-color-inactive; # #545454 - bright black
        surfaceContainer = colors.background-alt; # #0d0d0d - low elevation
        surfaceContainerHigh = colors.base02; # #383838 - mid elevation
        surfaceContainerHighest = colors.base03; # #545454 - high elevation
        error = colors.base08; # #fc5454 - bright red
        warning = colors.base0A; # #fcfc54 - bright yellow
        info = colors.accent-alt; # #54fcfc - bright cyan
        matugen_type = "scheme-expressive";
      };

      settings = builtins.toJSON {
        # Theme and Colors
        currentThemeName = "custom";
        customThemeFile = pkgs.writeText "theme.json" (builtins.toJSON style);
        matugenScheme = "scheme-tonal-spot";
        runUserMatugenTemplates = true;
        matugenTargetMonitor = "";
        widgetBackgroundColor = "sch";
        surfaceBase = "s";

        # Transparency
        dankBarTransparency = 1;
        dankBarWidgetTransparency = 1;
        popupTransparency = 1;
        dockTransparency = 1;
        notepadTransparencyOverride = -1;
        notepadLastCustomTransparency = 0.7;

        # Appearance and Layout
        cornerRadius = theme.rounding;
        animationSpeed = 1;
        customAnimationDuration = 500;
        fontFamily = theme.font;
        monoFontFamily = theme.font;
        fontWeight = 400;
        fontScale = 0.8;
        dankBarFontScale = 1;
        notepadFontFamily = theme.font;
        notepadFontSize = 14;
        iconTheme = "System Default";

        # Time and Date
        use24HourClock = true;
        showSeconds = false;
        clockDateFormat = "";
        lockDateFormat = "";
        clockCompactMode = false;

        # Weather
        useFahrenheit = false;
        showWeather = true;
        weatherLocation = "Hailsham, England";
        weatherCoordinates = "50.8628229,0.2730609";
        useAutoLocation = false;
        weatherEnabled = true;

        # Modes and Effects
        nightModeEnabled = false;
        blurredWallpaperLayer = false;
        blurWallpaperOnOverview = false;
        wallpaperFillMode = "Fill";
        modalDarkenBackground = true;

        # Widget Visibility
        showLauncherButton = true;
        showWorkspaceSwitcher = true;
        showFocusedWindow = true;
        showMusic = true;
        showClipboard = true;
        showCpuUsage = true;
        showMemUsage = true;
        showCpuTemp = true;
        showGpuTemp = true;
        showSystemTray = true;
        showClock = true;
        showNotificationButton = true;
        showBattery = true;
        showControlCenterButton = true;
        controlCenterShowNetworkIcon = true;
        controlCenterShowBluetoothIcon = true;
        controlCenterShowAudioIcon = true;

        # Control Center Widgets
        controlCenterWidgets = [
          {
            id = "volumeSlider";
            enabled = true;
            width = 50;
          }
          {
            id = "brightnessSlider";
            enabled = true;
            width = 50;
          }
          {
            id = "wifi";
            enabled = true;
            width = 50;
          }
          {
            id = "bluetooth";
            enabled = true;
            width = 50;
          }
          {
            id = "audioOutput";
            enabled = true;
            width = 50;
          }
          {
            id = "audioInput";
            enabled = true;
            width = 50;
          }
          {
            id = "nightMode";
            enabled = true;
            width = 50;
          }
          {
            id = "darkMode";
            enabled = true;
            width = 50;
          }
        ];

        # Workspace Settings
        showWorkspaceIndex = false;
        showWorkspacePadding = false;
        workspaceScrolling = false;
        showWorkspaceApps = false;
        maxWorkspaceIcons = 3;
        workspacesPerMonitor = true;
        dwlShowAllTags = false;
        workspaceNameIcons = { };

        # Widget Modes
        waveProgressEnabled = true;
        focusedWindowCompactMode = false;
        runningAppsCompactMode = true;
        keyboardLayoutNameCompactMode = false;
        runningAppsCurrentWorkspace = false;
        runningAppsGroupByApp = false;
        mediaSize = 1;

        # Bar Layout
        dankBarLeftWidgets = [
          "launcherButton"
          "workspaceSwitcher"
          "focusedWindow"
        ];
        dankBarCenterWidgets = [
          "music"
          "clock"
          "weather"
        ];
        dankBarRightWidgets = [
          "systemTray"
          "clipboard"
          "cpuUsage"
          "memUsage"
          "notificationButton"
          "battery"
          "controlCenterButton"
        ];
        dankBarWidgetOrder = [ ];

        # Launcher Settings
        appLauncherViewMode = "list";
        spotlightModalViewMode = "list";
        sortAppsAlphabetically = false;
        launcherLogoMode = "apps";
        launcherLogoCustomPath = "";
        launcherLogoColorOverride = "";
        launcherLogoColorInvertOnMode = false;
        launcherLogoBrightness = 0.5;
        launcherLogoContrast = 1;
        launcherLogoSizeOffset = 0;

        # Notepad Settings
        notepadUseMonospace = true;
        notepadShowLineNumbers = false;

        # Sounds
        soundsEnabled = true;
        useSystemSoundTheme = false;
        soundNewNotification = true;
        soundVolumeChanged = true;
        soundPluggedIn = true;

        # Power Management
        acMonitorTimeout = 0;
        acLockTimeout = 0;
        acSuspendTimeout = 0;
        acSuspendBehavior = 0;
        batteryMonitorTimeout = 0;
        batteryLockTimeout = 0;
        batterySuspendTimeout = 0;
        batterySuspendBehavior = 0;
        lockBeforeSuspend = false;
        loginctlLockIntegration = true;

        # Theming Integration
        gtkThemingEnabled = false;
        qtThemingEnabled = false;
        syncModeWithPortal = true;

        # Dock Settings
        showDock = false;
        dockAutoHide = false;
        dockGroupByApp = false;
        dockOpenOnOverview = false;
        dockPosition = 1;
        dockSpacing = 4;
        dockBottomGap = 0;
        dockIconSize = 40;
        dockIndicatorStyle = "circle";

        # Bar Settings
        dankBarAutoHide = false;
        dankBarOpenOnOverview = false;
        dankBarVisible = true;
        dankBarSpacing = theme.gaps-out;
        dankBarBottomGap = 0;
        dankBarInnerPadding = 4;
        dankBarPosition = 0;
        dankBarSquareCorners = false;
        dankBarNoBackground = false;
        dankBarGothCornersEnabled = true;
        dankBarGothCornerRadiusOverride = true;
        dankBarGothCornerRadiusValue = theme.rounding;
        dankBarBorderEnabled = true;
        dankBarBorderColor = "primary";
        dankBarBorderOpacity = 1;
        dankBarBorderThickness = 1;

        # Popups and Gaps
        popupGapsAuto = true;
        popupGapsManual = 4;

        # Lock Screen
        lockScreenShowPowerActions = true;
        enableFprint = false;
        maxFprintTries = 3;

        # Notifications
        notificationOverlayEnabled = false;
        notificationTimeoutLow = 5000;
        notificationTimeoutNormal = 5000;
        notificationTimeoutCritical = 0;
        notificationPopupPosition = 0;

        # OSD and Sliders
        hideBrightnessSlider = false;
        osdAlwaysShowValue = false;

        # Power Actions
        powerActionConfirm = true;
        customPowerActionLock = "";
        customPowerActionLogout = "";
        customPowerActionSuspend = "";
        customPowerActionHibernate = "";
        customPowerActionReboot = "";
        customPowerActionPowerOff = "";

        # Updater
        updaterUseCustomCommand = false;
        updaterCustomCommand = "";
        updaterTerminalAdditionalParams = "";

        # Hardware and Network
        selectedGpuIndex = 0;
        enabledGpuPciIds = [ ];
        brightnessDevicePins = { };
        networkPreference = "auto";
        vpnLastConnected = "";

        # Misc
        launchPrefix = "";
        screenPreferences = { };
        showOnLastDisplay = { };
        configVersion = 1;
      };
    in
    {
      hjem.users.${user}.files = {
        ".config/DankMaterialShell/settings.json".text = settings;
      };
      home.programs.dankMaterialShell = {
        enable = true;
        systemd.enable = true;
      };
    };
}
