{
  description = "Gala Engine: build iPhone and iPad apps on your Mac from another computer";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];
      eachSystem = function: nixpkgs.lib.genAttrs systems
        (system: function (import nixpkgs { inherit system; }));
      deviceTools = pkgs: pkgs.lib.optionals pkgs.stdenv.hostPlatform.isLinux [
        pkgs.libimobiledevice
        pkgs.ideviceinstaller
        pkgs.zsign
        pkgs.usbutils
      ];
    in {
      packages = eachSystem (pkgs: {
        default = pkgs.writeShellApplication {
          name = "gala";
          runtimeInputs = [ pkgs.openssh pkgs.rsync pkgs.python3 ] ++ deviceTools pkgs;
          text = ''exec ${pkgs.python3}/bin/python3 ${./bin/gala} "$@"'';
        };
      });

      devShells = eachSystem (pkgs: {
        default = pkgs.mkShell {
          packages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.default ] ++ deviceTools pkgs;
        };
      });
    };
}
