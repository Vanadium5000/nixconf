{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonApplication {
  pname = "office-powerpoint-mcp-server";
  version = "2.0.7";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "GongRzhe";
    repo = "Office-PowerPoint-MCP-Server";
    rev = "3631ba2ec0c24504476f78bf74d329c9be11caaa";
    hash = "sha256-KP0xQp4srcTLl12z4m9Mzz06C3e7KuVjydnQrDZHXv8=";
  };

  nativeBuildInputs = [
    python3Packages.hatchling
  ];

  propagatedBuildInputs = with python3Packages; [
    python-pptx
    mcp
    pillow
    fonttools
  ];

  pythonImportsCheck = [ "ppt_mcp_server" ];

  meta = with lib; {
    description = "MCP Server for PowerPoint manipulation using python-pptx";
    homepage = "https://github.com/GongRzhe/Office-PowerPoint-MCP-Server";
    license = licenses.mit;
    maintainers = [ ];
  };
}
