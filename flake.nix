{
  description = "A small nix function to generate pdfs from html";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/release-24.05";
  };

  outputs = { self, nixpkgs }:
  let
    lib = nixpkgs.lib;
    forAllSystems = lib.genAttrs lib.systems.flakeExposed;
  in
  {
    builders = forAllSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        html-to-pdf = pkgs.callPackage ./html-to-pdf.nix {};
      }
    );
  };
}
