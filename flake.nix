{
  description = "Fetchurl derivations generated from hashes.json";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      hashes = builtins.fromJSON (builtins.readFile ./hashes.json);

      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];

      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f system);

      mkDat =
        pkgs':
        let
          lib = pkgs'.lib;
        in
        lib.mapAttrs (
          repoName: repoData:
          lib.mapAttrs (
            assetName: assetData:
            pkgs'.fetchurl {
              name = "${repoName}-${assetName}-${repoData.release}";
              url = "https://github.com/${repoName}/releases/download/${repoData.release}/${assetName}";
              hash = assetData.sha256_sri;
            }
          ) repoData.assets
        ) hashes.repos;

      mkCombined =
        pkgs':
        {
          name,
          geoip,
          geosite,
        }:
        pkgs'.runCommandLocal name { } ''
          mkdir -p $out/share/v2ray
          ln -s ${geoip} $out/share/v2ray/geoip.dat
          ln -s ${geosite} $out/share/v2ray/geosite.dat
        '';
    in
    {
      packages = forAllSystems (
        system:
        let
          pkgs = import nixpkgs { inherit system; };
          lib = pkgs.lib;

          dat = mkDat pkgs;

          combined = lib.mapAttrs (
            repoName: repoAssets:
            mkCombined pkgs {
              name = lib.replaceStrings [ "/" ] [ "-" ] repoName;
              geoip = repoAssets."geoip.dat";
              geosite = repoAssets."geosite.dat";
            }
          ) dat;
        in
        {
          inherit dat combined;

          default =
            let
              firstRepo = builtins.head (builtins.attrNames combined);
            in
            combined.${firstRepo};

          tool = combined;
        }
      );

      lib = {
        inherit hashes mkDat mkCombined;
      };
    };
}
