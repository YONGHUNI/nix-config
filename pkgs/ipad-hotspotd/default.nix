{ stdenv, rustc }:
stdenv.mkDerivation {
  pname = "ipad-hotspotd";
  version = "0.2.0";
  src = ./.;
  nativeBuildInputs = [ rustc ];
  buildPhase = ''
    runHook preBuild
    rustc --edition=2021 -C opt-level=2 main.rs -o ipad-hotspotd
    runHook postBuild
  '';
  doCheck = true;
  checkPhase = ''
    rustc --edition=2021 --test main.rs -o tests
    ./tests
  '';
  installPhase = ''
    install -Dm755 ipad-hotspotd "$out/bin/ipad-hotspotd"
  '';
}
