{
  description = "Names the windows on the screen with a character each";
  inputs = {
    flake-utils.url = "github:numtide/flake-utils";
  };
  outputs = { self, nixpkgs, flake-utils }:
    (flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
        sigils-pluggo = pkgs.callPackage ./derivation.nix {};
      in {
        packages = {
          default = sigils-pluggo;
          inherit sigils-pluggo;
        };
        checks = {
          inherit sigils-pluggo;
        };
        devShells.default = pkgs.mkShell {
          inputsFrom = [ sigils-pluggo ];
          nativeBuildInputs = [ pkgs.nats-server ];
        };
    })) // {
      overlays.default = final: prev: {
        sigils-pluggo = prev.callPackage ./derivation.nix {};
      };
    };
}
