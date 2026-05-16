{ python3Packages }:

let
  inherit (python3Packages)
    arrow
    beautifulsoup4
    buildPythonApplication
    buildPythonPackage
    chardet
    cookies
    cryptography
    distro
    fetchPypi
    gevent
    gevent-websocket
    gipc
    greenlet
    itsdangerous
    jinja2
    legacy-cgi
    lxml
    passlib
    pexpect
    pillow
    psutil
    pyopenssl
    pyotp
    pyte
    python-daemon
    python-engineio
    python-socketio
    pyyaml
    qrcode
    requests
    setproctitle
    setuptools
    simplejson
    six
    termcolor
    zope-event
    ;

  pyproject = true;
  dontCheck = true;
  dontCheckRuntimeDeps = true;

  mkAjentiPlugin =
    pname: version: hash: dependencies:
    buildPythonPackage {
      inherit
        pname
        version
        pyproject
        dontCheck
        dontCheckRuntimeDeps
        ;
      src = fetchPypi { inherit pname version hash; };
      build-system = [ setuptools ];
      propagatedBuildInputs = dependencies;
    };

  mkAjentiPluginFromPypi =
    pname: pypiPname: version: hash: dependencies: extraAttrs:
    buildPythonPackage (
      {
        inherit
          pname
          version
          pyproject
          dontCheck
          dontCheckRuntimeDeps
          ;
        src = fetchPypi {
          pname = pypiPname;
          inherit version hash;
        };
        build-system = [ setuptools ];
        propagatedBuildInputs = dependencies;
      }
      // extraAttrs
    );

  jadi = buildPythonPackage {
    inherit pyproject dontCheck dontCheckRuntimeDeps;
    pname = "jadi";
    version = "1.0.3";
    src = fetchPypi {
      pname = "jadi";
      version = "1.0.3";
      hash = "sha256-YyH/iup7Teeiedhmuq2p+zfa98rwGYFRdHz3i5rJbR8=";
    };
    build-system = [ setuptools ];
  };

  reconfigure = buildPythonPackage {
    inherit pyproject dontCheck dontCheckRuntimeDeps;
    pname = "reconfigure";
    version = "0.1.82";
    src = fetchPypi {
      pname = "reconfigure";
      version = "0.1.82";
      hash = "sha256-ad3tn98vBg+0b9IB/vduKvabSs5dY3l838jEMIhq6/8=";
    };
    build-system = [ setuptools ];
    propagatedBuildInputs = [ chardet ];
  };

  aj = buildPythonPackage {
    inherit pyproject dontCheck dontCheckRuntimeDeps;
    pname = "aj";
    version = "2.2.15";
    src = fetchPypi {
      pname = "aj";
      version = "2.2.15";
      hash = "sha256-CCEla0enyN2B6ktvc6g9+4x1IXHBTSbXJMjBF/8JQs4=";
    };
    build-system = [ setuptools ];
    propagatedBuildInputs = [
      arrow
      beautifulsoup4
      cookies
      cryptography
      distro
      gevent
      gevent-websocket
      gipc
      greenlet
      itsdangerous
      jadi
      jinja2
      legacy-cgi
      lxml
      passlib
      pexpect
      psutil
      pyopenssl
      pyotp
      python-daemon
      python-engineio
      python-socketio
      pyyaml
      qrcode
      reconfigure
      requests
      setproctitle
      simplejson
      six
      termcolor
      zope-event
    ];
  };

  pluginAce =
    mkAjentiPlugin "ajenti.plugin.ace" "0.32" "sha256-+QzKjlwjfxu3H+wlIZ3vA9e4SVgbjsMUzNGLnkA9iu8="
      [ aj ];
  pluginCore =
    mkAjentiPluginFromPypi "ajenti.plugin.core" "ajenti_plugin_core" "0.114"
      "sha256-P9UtxOKstpEkrM1iyNPkXrlcZiP6qAUS3mOehWHVs38="
      [ aj ]
      { };
  pluginDashboard =
    mkAjentiPlugin "ajenti.plugin.dashboard" "0.42"
      "sha256-QZ7ZRDNaRL/AouHMrXJLQEtiT0uhyLNV9o5f/2NmGYY="
      [ aj ];
  pluginFilesystem =
    mkAjentiPlugin "ajenti.plugin.filesystem" "0.50"
      "sha256-OA5Q+KerpNBdJHz7zfDpLkSgkO3HtOmgyRcPeXL73WQ="
      [ aj ];
  pluginPasswd =
    mkAjentiPlugin "ajenti.plugin.passwd" "0.27" "sha256-1UWHZaquHQIDPXtnHonTObSdog1AjlUaFLwM7302pG4="
      [ aj ];
  pluginServices =
    mkAjentiPlugin "ajenti.plugin.services" "0.35" "sha256-R5MtYFAgGePdflSacnu784DqlJi2vuUjAg7lwq4auHM="
      [ aj ];
  pluginSettings =
    mkAjentiPluginFromPypi "ajenti.plugin.settings" "ajenti_plugin_settings" "0.35"
      "sha256-POopP+V4tECh2tqG/WBOTxMVrgRaB2+mkHDZBa+TYzA="
      [
        aj
        pluginCore
        pluginFilesystem
        pluginPasswd
      ]
      { };
  pluginTerminal =
    mkAjentiPlugin "ajenti.plugin.terminal" "0.42" "sha256-iWrTRxGMl+WYJ5j+EKojwCADJ3z/aItdWUMMwgMmB8I="
      [ aj ];
  pluginPlugins =
    mkAjentiPluginFromPypi "ajenti.plugin.plugins" "ajenti_plugin_plugins" "0.54"
      "sha256-9pCmcG6ldl2mc9tF07F/2IcGM4Q8ciqxhdk/Im2ZdA4="
      [
        aj
        pluginCore
        pluginSettings
      ]
      {
        postInstall = ''
          site="$out/lib/python3.13/site-packages/ajenti_plugin_plugins"

          substituteInPlace "$site/views.py" \
            --replace-fail "for l in subprocess.check_output([sys.executable, '-m', 'pip', 'freeze']).splitlines():" "for l in []:" \
            --replace-fail "page = requests.get('https://pypi.org/simple')" "page = None" \
            --replace-fail "official = requests.get('https://raw.githubusercontent.com/ajenti/ajenti/master/official_plugins.json').json()['plugins']" "official = []" \
            --replace-fail "pypi_plugin_list = fromstring(page.content).xpath(\"//a[starts-with(text(),'ajenti.plugin')]/text()\")" "pypi_plugin_list = []"

          substituteInPlace "$site/tasks.py" \
            --replace-fail "subprocess.check_output([sys.executable, '-m', 'pip', 'install', self.spec])" "return None" \
            --replace-fail "subprocess.check_output([sys.executable, '-m', 'pip', 'uninstall', '-y', self.spec])" "raise RuntimeError('Ajenti plugins are managed declaratively by NixOS; edit modules/_pkgs/ajenti.nix instead of uninstalling via pip at runtime.')" \
            --replace-fail "subprocess.check_output(['ajenti-upgrade'])" "return None" \
            --replace-fail "subprocess.check_output(['/usr/local/bin/ajenti-upgrade'])" "return None"

          # Keep the old plugin manager page from exposing unsupported runtime pip actions.
          substituteInPlace "$site/main.py" \
            --replace-fail "'name': _('Plugins')," "'name': _('Nix Plugins')," \
            --replace-fail "'url': '/view/plugins'," "'url': '/view/settings',"
        '';
      };
in
buildPythonApplication {
  inherit pyproject dontCheck dontCheckRuntimeDeps;
  pname = "ajenti";
  version = "2.2.15";
  src = fetchPypi {
    pname = "ajenti_panel";
    version = "2.2.15";
    hash = "sha256-Vc1wBPD4YosPKUQFZnNqVOvEFkMErDQREem9qOhkurI=";
  };
  build-system = [ setuptools ];
  propagatedBuildInputs = [
    aj
    pluginAce
    pluginCore
    pluginDashboard
    pluginFilesystem
    pluginPasswd
    pluginPlugins
    pluginServices
    pluginSettings
    pluginTerminal
    pillow
    pyte
    pyyaml
    requests
  ];
  pythonImportsCheck = [ "aj" ];
  meta.mainProgram = "ajenti-panel";
}
