{
  description = "Latchsoil — a holding sim on a heavy world. Godot presents, Rust decides.";

  # One nixpkgs for the whole toolchain. The engine and the binding are pinned in
  # rust/Cargo.toml (godot 0.5.5, api-4-7) and in docs/06-architecture.md: Godot
  # 4.7.2 at every end, because the editor is the end a human opens.
  #
  # `nixos-unstable` (frozen by flake.lock) rather than a release branch: the
  # release branch that ships Godot 4.7.2 is the one this tree follows, and the
  # lock makes the choice reproducible. Bump deliberately, with the editor.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" ];
      forAll = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Everything the headless checks need, on PATH for the app scripts.
      tools =
        pkgs:
        [
          pkgs.godot_4_7
          pkgs.cargo
          pkgs.rustc
          pkgs.coreutils
          pkgs.bash
        ]
        ++ [ pkgs.rustfmt pkgs.clippy ];

      appScript =
        pkgs: name: script:
        pkgs.writeShellScript name ''
          export PATH="${pkgs.lib.makeBinPath (tools pkgs)}:$PATH"
          export GODOT4_BIN="${pkgs.godot_4_7}/bin/godot"
          ${builtins.readFile script}
        '';
    in
    {
      devShells = forAll (pkgs: {
        default = pkgs.mkShell {
          packages = tools pkgs;
          # gdext codegen prefers the editor binary next to the binding when a
          # custom API dump is used; harmless when the crate ships prebuilt JSON.
          GODOT4_BIN = "${pkgs.godot_4_7}/bin/godot";
          shellHook = ''
            mkdir -p godot/bin
            echo "Latchsoil devshell"
            echo "  engine  $(godot --headless --version)"
            echo "  rustc   $(rustc --version)"
            echo "  cargo   $(cargo --version)"
          '';
        };
      });

      apps = forAll (pkgs: {
        test = {
          type = "app";
          program = appScript pkgs "latchsoil-test" ./scripts/test.sh;
        };
        smoke = {
          type = "app";
          program = appScript pkgs "latchsoil-smoke" ./scripts/smoke.sh;
        };
      });
    };
}
