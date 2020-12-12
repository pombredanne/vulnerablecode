{
  description =
    "Vulnerablecode - A free and open vulnerabilities database and the packages they impact.";

  inputs.nixpkgs = {
    type = "github";
    owner = "NixOS";
    repo = "nixpkgs";
    ref = "20.09";
  };

  inputs.machnix = {
    type = "github";
    owner = "DavHau";
    repo = "mach-nix";
    ref = "3.1.1";
  };

  outputs = { self, nixpkgs, machnix }:
    let

      vulnerablecode-src = ./../..;

      # Extract version from setup.py.
      version = builtins.head (builtins.match ''.*version=["']?([^"',]+).*''
        (builtins.readFile (vulnerablecode-src + "/setup.py")));

      libSh = ./lib.sh;

      # System types to support.
      supportedSystems = [ "x86_64-linux" ];

      # Helper function to generate an attrset '{ x86_64-linux = f "x86_64-linux"; ... }'.
      forAllSystems = f:
        nixpkgs.lib.genAttrs supportedSystems (system: f system);

      # Nixpkgs instantiated for supported system types.
      nixpkgsFor = forAllSystems (system:
        import nixpkgs {
          inherit system;
          overlays = [ self.overlay ];
        });

      # mach-nix instantiated for supported system types.
      machnixFor = forAllSystems (system:
        import machnix {
          pkgs = (nixpkgsFor.${system}).pkgs;
          python = "python38";
        });

    in {

      # A Nixpkgs overlay.
      overlay = final: prev:
        with final.pkgs; {

          pythonEnv = with machnixFor.${system};
            mkPython {
              requirements =
                builtins.readFile (vulnerablecode-src + "/requirements.txt");
            };

          vulnerablecode = stdenv.mkDerivation {
            inherit version;
            name = "vulnerablecode-${version}";
            src = vulnerablecode-src;
            dontConfigure = true; # do not use ./configure
            propagatedBuildInputs = [ pythonEnv postgresql ];

            postPatch = ''
              # Make sure the pycodestyle binary in $PATH is used.
              substituteInPlace vulnerabilities/tests/test_basics.py \
                --replace 'join(bin_dir, "pycodestyle")' '"pycodestyle"'
            '';

            installPhase = ''
              cp -r . $out
            '';
          };

        };

      # Provide a nix-shell env to work with vulnerablecode.
      devShell = forAllSystems (system:
        with nixpkgsFor.${system};
        mkShell {
          # will be available as env var in `nix develop` / `nix-shell`.
          VULNERABLECODE_INSTALL_DIR = vulnerablecode;
          buildInputs = [ vulnerablecode ];
          shellHook = ''
            alias vulnerablecode-manage.py=${vulnerablecode}/manage.py
              '';
        });

      # Provide some packages for selected system types.
      packages = forAllSystems
        (system: { inherit (nixpkgsFor.${system}) vulnerablecode; });

      # The default package for 'nix build'.
      defaultPackage =
        forAllSystems (system: self.packages.${system}.vulnerablecode);

      # Tests run by 'nix flake check' and by Hydra.
      checks = forAllSystems (system: {
        inherit (self.packages.${system})
        ;

        vulnerablecode-test = with nixpkgsFor.${system};
          stdenv.mkDerivation {
            name = "${vulnerablecode.name}-test";

            buildInputs = [ wget vulnerablecode ];

            # Used by pygit2.
            # See https://github.com/NixOS/nixpkgs/pull/72544#issuecomment-582674047.
            SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";

            unpackPhase = "true";

            buildPhase = ''
              source ${libSh}
              initPostgres $(pwd)
              export DJANGO_DEV=1
              ${vulnerablecode}/manage.py migrate
            '';

            doCheck = true;
            checkPhase = ''
              # Run pytest on the installed version. A running postgres
              # database server is needed.
              (cd ${vulnerablecode} && pytest)

              # Launch the webserver and call the API.
              ${vulnerablecode}/manage.py runserver &
              sleep 2
              wget http://127.0.0.1:8000/api/
              kill %1 # kill background task (i.e. webserver)
            '';

            installPhase =
              "mkdir -p $out"; # make this derivation return success
          };
      });
    };
}
