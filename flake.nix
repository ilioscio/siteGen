{
  description = "siteGen - A static site generator written in Zig";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # Zig overlay for specific Zig versions
    zig-overlay = {
      url = "github:mitchellh/zig-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, zig-overlay }:
    let
      # Systems we support
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];

      # Helper to generate per-system outputs
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      # Package derivation (reusable across systems)
      mkSiteGen = pkgs: zig:
        pkgs.stdenv.mkDerivation {
          pname = "siteGen";
          version = "0.1.0";

          src = ./.;

          nativeBuildInputs = [ zig ];

          dontConfigure = true;
          dontInstall = true;

          buildPhase = ''
            runHook preBuild

            # Set up writable cache directories for Zig
            export ZIG_GLOBAL_CACHE_DIR=$(mktemp -d)
            export ZIG_LOCAL_CACHE_DIR=$(mktemp -d)

            # Build with Zig
            zig build \
              --release=safe \
              -Doptimize=ReleaseSafe \
              --prefix $out

            runHook postBuild
          '';

          meta = with pkgs.lib; {
            description = "A static site generator written in Zig";
            longDescription = ''
              siteGen is a fast, minimal static site generator that converts
              markdown files to HTML. It supports headers, lists, code blocks,
              blockquotes, links, images, and inline formatting. Generates
              index pages, post listings, and XML sitemaps automatically.
            '';
            homepage = "https://github.com/ilioscio/siteGen";
            license = licenses.mit;
            platforms = platforms.linux;
            maintainers = [];
            mainProgram = "siteGen";
          };
        };
    in
    {
      # ============================================================
      # OVERLAY - For users who want to add siteGen to their pkgs
      # ============================================================
      # Usage in user's flake.nix:
      #   nixpkgs.overlays = [ siteGen.overlays.default ];
      #   environment.systemPackages = [ pkgs.siteGen ];
      overlays.default = final: prev:
        let
          zig = zig-overlay.packages.${prev.system}."0.15.2";
          siteGenBin = mkSiteGen final zig;
        in {
          siteGen = siteGenBin;

          # The built website
          ilios-website = final.stdenv.mkDerivation {
            pname = "ilios-website";
            version = "0.1.0";
            src = ./site;

            nativeBuildInputs = [ siteGenBin ];

            buildPhase = ''
              cp -r $src/* .
              chmod -R u+w .
              siteGen .
            '';

            installPhase = ''
              mkdir -p $out
              cp -r * $out/
            '';
          };
        };

      # ============================================================
      # PACKAGES - Direct package access per system
      # ============================================================
      # Usage: siteGen.packages.x86_64-linux.default
      # Or: nix build github:ilioscio/siteGen
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ zig-overlay.overlays.default ];
          };
          zig = pkgs.zigpkgs."0.15.2";
          siteGenBin = mkSiteGen pkgs zig;
        in {
          default = siteGenBin;
          siteGen = siteGenBin;

          # The built website - runs siteGen on the site/ directory
          website = pkgs.stdenv.mkDerivation {
            pname = "ilios-website";
            version = "0.1.0";
            src = ./site;

            nativeBuildInputs = [ siteGenBin ];

            buildPhase = ''
              # Copy source to writable directory
              cp -r $src/* .
              chmod -R u+w .
              
              # Run siteGen to generate HTML from markdown
              siteGen .
            '';

            installPhase = ''
              mkdir -p $out
              cp -r * $out/
            '';

            meta = with pkgs.lib; {
              description = "ilios.dev website - built with siteGen";
            };
          };
        }
      );

      # ============================================================
      # APPS - For `nix run github:ilioscio/siteGen`
      # ============================================================
      apps = forAllSystems (system: {
        default = {
          type = "app";
          program = "${self.packages.${system}.default}/bin/siteGen";
        };
      });

      # ============================================================
      # DEV SHELLS - For contributors/developers
      # ============================================================
      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ zig-overlay.overlays.default ];
          };
          zig = pkgs.zigpkgs."0.15.2";
        in {
          default = pkgs.mkShell {
            buildInputs = [
              zig
            ];

            shellHook = ''
              echo "siteGen development environment"
              echo ""
              echo "Available commands:"
              echo "  zig build              - Build the project"
              echo "  zig build run -- <dir> - Run siteGen on a directory"
              echo "  zig build test         - Run tests"
              echo ""
              echo "Zig version: $(zig version)"
            '';
          };
        }
      );
    };
}

