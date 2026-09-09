{
  lib,
  python313Packages,
  fetchFromGitHub,
  openconnect,
}:

python313Packages.buildPythonApplication rec {
  pname = "openconnect-saml";
  version = "0.25.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "mschabhuettl";
    repo = "openconnect-saml";
    rev = "0c488a1";
    hash = "sha256-ae90r41QRGRqBAirOsPaw50lVweFnxZwDaMlZUsoOL8=";
  };

  build-system = with python313Packages; [
    hatchling
  ];

  dependencies = with python313Packages; [
    attrs
    colorama
    keyring
    lxml
    prompt-toolkit
    pyotp
    pysocks
    pyxdg
    requests
    structlog
    toml

    pyqt6
    pyqt6-webengine
  ];

  nativeCheckInputs = [ openconnect ];

  meta = {
    description = "OpenConnect wrapper with SAML SSO support";
    homepage = "https://github.com/mschabhuettl/openconnect-saml";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
