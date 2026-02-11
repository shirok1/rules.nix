## Usage

Add following to your flake input:

```nix
inputs = {
  rules.url = "github:shirok1/rules.nix";
  rules.inputs.nixpkgs.follows = "nixpkgs";
};
```

Add overlay to your nixpkgs:

```nix
nixpkgs.overlays = [
  (final: prev: {
    rules = inputs.rules.packages.${final.stdenv.hostPlatform.system};
  })
];
```

Use it in your configuration:

```nix
services.daed = {
  enable = true;
  listen = "0.0.0.0:2023";
  openFirewall = {
    enable = true;
    port = 2023;
  };
  assetsPaths =
    let
      combined = pkgs.rules.combined."elysias123/geosite";
    in
    [
      # "${pkgs.v2ray-geoip}/share/v2ray/geoip.dat"
      # "${pkgs.v2ray-domain-list-community}/share/v2ray/geosite.dat"
      "${combined}/share/v2ray/geoip.dat"
      "${combined}/share/v2ray/geosite.dat"
    ];
};
```
