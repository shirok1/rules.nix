{
  description = "Fetchurl derivations generated from hashes.json";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
  };

  outputs =
    { nixpkgs, ... }:
    let
      hashes = builtins.fromJSON (builtins.readFile ./hashes.json);
      system = builtins.currentSystem;
      pkgs = import nixpkgs { inherit system; };
      lib = pkgs.lib;

      mkDat =
        pkgs':
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
        {
          name,
          geoip,
          geosite,
        }:
        pkgs.runCommandLocal "${name}" { } ''
          mkdir -p $out/share/v2ray

          ln -s ${geoip} $out/share/v2ray/geoip.dat
          ln -s ${geosite} $out/share/v2ray/geosite.dat
        '';

      dat = mkDat pkgs;
      combined = lib.mapAttrs (
        repoName: repoAssets:
        mkCombined {
          name = lib.replaceStrings [ "/" ] [ "-" ] repoName;
          geoip = repoAssets."geoip.dat";
          geosite = repoAssets."geosite.dat";
        }
      ) dat;
    in
    {
      inherit dat combined;
      tool = combined;

      lib = {
        inherit hashes;
        mkDat = mkDat;
        mkCombined = mkCombined;
      };
    };
}
