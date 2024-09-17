{
  description = "Rflxt On-chain Scripts";

  nixConfig = {
    bash-prompt = "\\[\\e[0m\\][\\[\\e[0;2m\\]nix \\[\\e[0;1m\\]bet-ref Aiken \\[\\e[0;93m\\]\\w\\[\\e[0m\\]]\\[\\e[0m\\]$ \\[\\e[0m\\]";
    cores = "1";
    max-jobs = "auto";
    auto-optimise-store = "true";
  };

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
    aiken = {
      type = "github";
      owner = "aiken-lang";
      repo = "aiken";
    };
  };

  outputs = inputs @ { flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      debug = true;
      systems = [ "x86_64-linux" ];
      imports = [
        inputs.pre-commit-hooks.flakeModule
      ];

      perSystem =
        { config
        , inputs'
        , pkgs
        , ...
        }: {
          devShells.default =
            pkgs.mkShell
              {
                buildInputs = [
                  inputs'.aiken.packages.aiken
                ];
                shellHook = config.pre-commit.installationScript;
              };

          pre-commit.check.enable = true;
          pre-commit.settings = {
            hooks = {
              nixpkgs-fmt.enable = true;
              deadnix.enable = true;
              aiken = {
                enable = true;
                name = "aiken";
                entry = "aiken fmt";
                files = "\\.ak$";
                pass_filenames = false;
              };
            };
          };
        };
    };
}
