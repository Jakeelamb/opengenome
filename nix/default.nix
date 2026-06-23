{
  lib,
  rustPlatform,
}:

let
  p = (lib.importTOML ../Cargo.toml).workspace.package;
  pTUI = (lib.importTOML ../tui/Cargo.toml).package;
in
rustPlatform.buildRustPackage {
  pname = "opengenome";
  inherit (p) version;

  src = ../.;

  cargoLock.lockFile = ../Cargo.lock;

  meta = {
    inherit (pTUI) description;
    homepage = pTUI.documentation;
    license = lib.licenses.mit;
    mainProgram = "opengenome";
  };
}
