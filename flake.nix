{
  description = "Pipforge: build iPhone and iPad apps on your Mac from another computer";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      eachSystem = function: nixpkgs.lib.genAttrs systems
        (system: function (import nixpkgs { inherit system; }));
    in {
      packages = eachSystem (pkgs: {
        default = pkgs.writeShellApplication {
          name = "pipforge";
          runtimeInputs = [ pkgs.openssh pkgs.rsync pkgs.python3 ];
          text = ''exec ${pkgs.python3}/bin/python3 ${./bin/pipforge} "$@"'';
        };
      });

      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.default ];
        };
      });
    };
}
