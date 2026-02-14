{
  description = "Fetchurl derivations generated from hashes.json";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-parts.url = "github:hercules-ci/flake-parts";
  };

  outputs =
    inputs@{ nixpkgs, flake-parts, ... }:
    # https://flake.parts/module-arguments.html
    flake-parts.lib.mkFlake { inherit inputs; } (
      top@{
        config,
        withSystem,
        moduleWithSystem,
        ...
      }:
      {
        imports = [
          # Optional: use external flake logic, e.g.
          inputs.flake-parts.flakeModules.easyOverlay
        ];
        flake = {
          # Put your original flake attributes here.
          hashes = builtins.fromJSON (builtins.readFile ./hashes.json);
        };
        systems =
          # systems for which you want to build the `perSystem` attributes
          nixpkgs.lib.systems.flakeExposed;
        perSystem =
          {
            config,
            pkgs,
            lib,
            ...
          }:
          let
            dat = lib.mapAttrs (
              repoName: repoData:
              lib.mapAttrs (
                assetName: assetData:
                pkgs.fetchurl {
                  name = "${repoName}-${assetName}-${repoData.release}";
                  url = "https://github.com/${repoName}/releases/download/${repoData.release}/${assetName}";
                  hash = assetData.sha256_sri;
                }
              ) repoData.assets
            ) top.config.flake.hashes.repos;
            combined = lib.mapAttrs (
              repoName: repoAssets:
              pkgs.runCommandLocal (lib.replaceStrings [ "/" ] [ "-" ] repoName) { } ''
                mkdir -p $out/share/v2ray
                ln -s ${repoAssets."geoip.dat"} $out/share/v2ray/geoip.dat
                ln -s ${repoAssets."geosite.dat"} $out/share/v2ray/geosite.dat
              ''
            ) dat;
          in
          {
            overlayAttrs.rules = config.legacyPackages;
            legacyPackages = {
              inherit dat combined;
            };
          };
      }
    );
}
