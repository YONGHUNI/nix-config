{
  stdenv,
  cmake,
  qtbase,
  wrapQtAppsHook,
  kstatusnotifieritem,
  ipadDisplay,
  defaultMode ? "shared",
}:

stdenv.mkDerivation {
  pname = "ipad-display-tray";
  version = "0.2.0";
  src = ./.;

  nativeBuildInputs = [
    cmake
    wrapQtAppsHook
  ];
  buildInputs = [
    qtbase
    kstatusnotifieritem
  ];

  cmakeFlags = [ "-DIPAD_DISPLAY_CLI=${ipadDisplay}/bin/ipad-display" "-DIPAD_DEFAULT_MODE=${defaultMode}" ];
}
