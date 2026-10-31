{ lib
, stdenv
, libx11
}:

stdenv.mkDerivation {
  pname = "sigils-pluggo";
  version = "0.1.0";
  src = ./.;
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libx11 ];
  makeFlags = [ "PREFIX=$(out)" ];
  doCheck = true;
  # fixupPhase, which usually does this, runs after checkPhase.
  preCheck = "patchShebangs tests";
  meta.mainProgram = "sigils";
}
