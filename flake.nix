{
  description = "Shared release tooling for gleam-dream repositories";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: {
        # Opens the version-bump pull request for a Gleam package. Nix
        # supplies every tool it calls and runs ShellCheck on it at build.
        release = pkgs.writeShellApplication {
          name = "release";
          runtimeInputs = with pkgs; [
            git
            gh
            perl
            gnused
            gnugrep
            coreutils
          ];
          text = builtins.readFile ./release/release.sh;
        };

        # Checks a release tag and uploads the package it names. The shared
        # workflow runs it; `nix` itself is the runner's, and Gleam comes
        # from the caller's flake.
        hex-publish = pkgs.writeShellApplication {
          name = "hex-publish";
          runtimeInputs = with pkgs; [
            git
            curl
            gnused
            gnugrep
            coreutils
          ];
          text = builtins.readFile ./hex-publish/hex-publish.sh;
        };
      });

      apps = forAllSystems (pkgs: {
        release = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.release}/bin/release";
          meta.description = "Open the version-bump pull request for a Gleam package";
        };
        hex-publish = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.hex-publish}/bin/hex-publish";
          meta.description = "Check a release tag and publish its Gleam package to Hex";
        };
      });
    };
}
