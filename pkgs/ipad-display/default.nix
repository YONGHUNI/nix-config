{
  stdenv,
  cmake,
  qtbase,
  wrapQtAppsHook,
  kstatusnotifieritem,
  ipadDisplay,
}:

stdenv.mkDerivation {
  pname = "ipad-display-tray";
  version = "0.1.0";
  src = ./.;

  nativeBuildInputs = [
    cmake
    wrapQtAppsHook
  ];
  buildInputs = [
    qtbase
    kstatusnotifieritem
  ];

  cmakeFlags = [ "-DIPAD_DISPLAY_CLI=${ipadDisplay}/bin/ipad-display" ];
}
