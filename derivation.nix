{ lib
, stdenv
, libx11
, nats-server
}:

stdenv.mkDerivation {
  pname = "sigils-pluggo";
  version = "0.1.0";
  src = ./.;
  buildInputs = lib.optionals stdenv.hostPlatform.isLinux [ libx11 ];
  nativeCheckInputs = [ nats-server ];
  makeFlags = [ "PREFIX=$(out)" ];
  doCheck = true;
  # fixupPhase, which usually does this, runs after checkPhase.
  preCheck = "patchShebangs tests";
  meta.mainProgram = "sigils";
}
