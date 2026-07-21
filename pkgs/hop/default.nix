{
  lib,
  stdenv,
  fetchurl,
  dpkg,
  autoPatchelfHook,
  makeWrapper,
  makeDesktopItem,

  glib,
  gtk3,
  webkitgtk_4_1,
  libsoup_3,
  openssl,
  cairo,
  pango,
  gdk-pixbuf,
  atk,
  dbus,
  libayatana-appindicator,

  gst_all_1,
}:

let
  desktopItem = makeDesktopItem {
    name = "hop";
    desktopName = "HOP";
    genericName = "HWP/HWPX Editor";
    comment = "Open and edit HWP and HWPX documents";

    exec = "hop-desktop %F";
    icon = "accessories-text-editor";
    terminal = false;

    categories = [
      "Office"
      "WordProcessor"
    ];
  };
in

stdenv.mkDerivation rec {
  pname = "hop";
  version = "0.4.1";

  src = fetchurl {
    url = "https://github.com/golbin/hop/releases/download/v${version}/HOP-linux-x64.deb";
    hash = "sha256-p4wOSzwBXI/2NRTZTIqh/ZGvnTufK554CJVl5cfYHQg=";
  };

  nativeBuildInputs = [
    dpkg
    autoPatchelfHook
    makeWrapper
  ];

  buildInputs = [
    glib
    gtk3
    webkitgtk_4_1
    libsoup_3
    openssl
    cairo
    pango
    gdk-pixbuf
    atk
    dbus
    libayatana-appindicator

    gst_all_1.gstreamer
    gst_all_1.gst-plugins-base
  ];

  unpackPhase = ''
    runHook preUnpack

    dpkg-deb -x "$src" .

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p "$out"
    cp -r usr/* "$out/"

    if [ -d opt ]; then
      mkdir -p "$out/opt"
      cp -r opt/* "$out/opt/"
    fi

    # Short command alias
    ln -s "$out/bin/hop-desktop" "$out/bin/hop"

    # KDE/GNOME application menu entry
    install -Dm644 \
      "${desktopItem}/share/applications/hop.desktop" \
      "$out/share/applications/hop.desktop"

    runHook postInstall
  '';

  postFixup = ''
    wrapProgram "$out/bin/hop-desktop" \
      --prefix GST_PLUGIN_SYSTEM_PATH_1_0 : \
        "${gst_all_1.gst-plugins-base}/lib/gstreamer-1.0" \
      --set GDK_BACKEND x11 \
      --set WEBKIT_DISABLE_DMABUF_RENDERER 1 \
      --set WEBKIT_DISABLE_COMPOSITING_MODE 1
  '';

  meta = {
    description = "Open-source HWP and HWPX desktop editor";
    homepage = "https://github.com/golbin/hop";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "hop-desktop";
  };
}
