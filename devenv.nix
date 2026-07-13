{
  pkgs,
  config,
  lib,
  ...
}:
let

  packages = with pkgs; [
    bashInteractive
  ];

  devPackages = with pkgs; [
    # Common
    convco
    figlet
    git
    gnutar
    hello
    jq
    just
    libxml2
    mermaid-cli
    openssl
    sshuttle
    wget
    yq-go

    # Security
    trivy

    # Secrets
    age
    ssh-to-age
    ssh-to-pgp

    # Terraform/OpenTofu
    packer
    terraform-docs
    terraform-providers.ciscodevnet_aci
    terraform-providers.dmacvicar_libvirt
    terraform-providers.f5networks_bigip
    terraform-providers.gavinbunney_kubectl
    terraform-providers.hashicorp_dns
    terraform-providers.hashicorp_http
    terraform-providers.hashicorp_local
    terraform-providers.hashicorp_null
    terraform-providers.hashicorp_random
    terraform-providers.hashicorp_time
    terraform-providers.hashicorp_tls
    terraform-providers.hashicorp_vault
    terraform-providers.integrations_github
    terraform-providers.jfrog_artifactory
    terraform-providers.loafoe_ssh
    terraform-providers.numtide_secret
    terraform-providers.nutanix_nutanix
    terraform-providers.scottwinkler_shell
    terraform-providers.carlpett_sops
    terraform-providers.sysdiglabs_sysdig
    terraform-providers.tenstad_remote
    tflint
    vault
  ];

in
{
  name = "tf-template";

  env = {
    PROJECT = config.name;
  };
  cachix = {
    enable = true;
    pull = [
      "bingamon-lab-tf-modules"
    ];
    push = "bingamon-lab-tf-modules";
  };

  devenv = {
    warnOnNewVersion = true;
  };

  dotenv = {
    enable = true;
    disableHint = false;
  };

  difftastic = {
    enable = true;
  };

  packages =
    packages ++ lib.optionals (!config.container.isBuilding || config.name == "devenv") devPackages;

  enterShell = ''
    figlet -f starwars -w 180 $PROJECT

    hello --greeting="Hello ''${USER:-user}, welcome to the $PROJECT project!"

    echo ""
    echo "#########################"
    echo "#### Helper scripts #####"
    echo "#########################"
    echo ""
    ${pkgs.gnused}/bin/sed -e 's| |••|g' -e 's|=| |' <<EOF | ${pkgs.util-linuxMinimal}/bin/column -t | ${pkgs.gnused}/bin/sed -e 's|^|🦾 |' -e 's|••| |g'
    ${lib.generators.toKeyValue { } (lib.mapAttrs (_name: value: value.description) config.scripts)}
    EOF
    echo ""
    echo "#########################"
  '';

  languages = {
    nix = {
      enable = true;
    };
    shell = {
      enable = true;
    };
    opentofu = {
      enable = true;
    };
  };

  git-hooks = {
    excludes = [ ];
    hooks = {
      actionlint.enable = true;
      action-validator.enable = true;
      check-json.enable = true;
      check-merge-conflicts.enable = true;
      check-shebang-scripts-are-executable.enable = true;
      check-symlinks.enable = true;
      check-yaml.enable = true;
      commitizen.enable = true;
      convco.enable = true;
      cspell = {
        enable = true;
        args = [
          "lint"
          "--no-must-find-files"
        ];
      };
      deadnix.enable = true;
      dialyzer.enable = true;
      editorconfig-checker.enable = true;
      gofmt.enable = true;
      golangci-lint.enable = true;
      golines.enable = true;
      gotest.enable = true;
      govet.enable = true;
      gptcommit.enable = true;
      markdownlint = {
        enable = true;
        excludes = [
          "module/README.md"
        ];
        settings = {
          configuration = {
            MD013 = {
              line_length = 500;
            };
            MD033 = {
              allowed_elements = [
                "a"
                "br"
                "nobr"
                "pre"
                "sup"
              ];
            };
          };
        };
      };
      mixed-line-endings.enable = true;
      nixfmt-rfc-style.enable = true;
      pre-commit-hook-ensure-sops.enable = true;
      prettier = {
        enable = true;
        excludes = [
          "module/README.md"
        ];
      };
      # Use prettier instead.
      pretty-format-json.enable = false;
      revive = {
        enable = true;
        fail_fast = false;
      };
      ripsecrets.enable = true;
      shellcheck.enable = true;
      shfmt.enable = true;
      staticcheck.enable = true;
      statix.enable = true;
      terraform-format.enable = true;
      terraform-validate.enable = false; # NOTE: Doesn't support nested directories.
      # Custom Terraform Module validation
      tofu-validate-module = {
        enable = true;
        name = "tofu-validate-module";
        entry = "tofu-validate-module";
        files = "^module/.*\\.*$";
        pass_filenames = false;
      };
      tflint.enable = true;
      trim-trailing-whitespace.enable = true;
      trufflehog.enable = false;
      yamllint = {
        enable = true;
        settings = {
          configuration = ''
            extends: relaxed
            rules:
              line-length: disable
              indentation: enable
          '';
        };
      };
    };
  };

  starship = {
    enable = true;
    config = {
      enable = false;
    };
  };

  devcontainer = {
    enable = true;
    settings = {
      customizations = {
        vscode = {
          extensions = [
            "arrterian.nix-env-selector"
            "astro-build.astro-vscode"
            "bradlc.vscode-tailwindcss"
            "brettm12345.nixfmt-vscode"
            "dotenv.dotenv-vscode"
            "esbenp.prettier-vscode"
            "github.vscode-github-actions"
            "github.vscode-pull-request-github"
            "gruntfuggly.todo-tree"
            "hediet.vscode-drawio"
            "jnoortheen.nix-ide"
            "johnpapa.vscode-peacock"
            "mkhl.direnv"
            "ms-kubernetes-tools.vscode-kubernetes-tools"
            "nhoizey.gremlins"
            "pinage404.nix-extension-pack"
            "redhat.vscode-yaml"
            "skellock.just"
            "streetsidesoftware.code-spell-checker"
            "tamasfe.even-better-toml"
            "timonwong.shellcheck"
            "tuxtina.json2yaml"
            "vscodevim.vim"
            "waderyan.gitblame"
            "wakatime.vscode-wakatime"
            "yzhang.markdown-all-in-one"
          ];
        };
      };
    };
  };

  scripts = {
    tofu-validate-module = {
      package = pkgs.bash;
      description = "Validate Terraform Module";
      exec = ''
        MODULE_HOME="$(pwd)/module"
        if [ ! -d "''${MODULE_HOME}" ];
        then
          echo "Directory ''${MODULE_HOME} does not exist. Please run this script from the root of the repository."
          exit 1
        fi
        echo "Checking Terraform Module for ''${MODULE_HOME}"
        tofu-format "''${MODULE_HOME}" || exit 1
        tofu-init "''${MODULE_HOME}" || exit 1
        tofu-validate "''${MODULE_HOME}" || exit 1
        tofu-docs "''${MODULE_HOME}" || exit 1
      '';
    };

    tofu-format = {
      package = pkgs.bash;
      description = "Format OpenTofu code in a given directory";
      exec = ''
        DIR="''${1:-}"
        if [ "''${DIR:-EMPTY}" == "EMPTY" ];
        then
          echo "Usage: $0 <directory>"
          exit 1
        fi
        if [ ! -d "''${DIR}" ];
        then
          echo "Directory ''${DIR} does not exist"
          exit 1
        fi
        echo "Formatting OpenTofu code in ''${DIR}"
        pushd "''${DIR}"
        tofu fmt -write=true "''${DIR}" || {
          echo "Failed to format OpenTofu code in ''${DIR}"
          exit 1
        }
        popd
      '';
    };

    tofu-init = {
      package = pkgs.bash;
      description = "Initialise OpenTofu providers for a given directory";
      exec = ''
        DIR="''${1:-}"
        if [ "''${DIR:-EMPTY}" == "EMPTY" ];
        then
          echo "Usage: $0 <directory>"
          exit 1
        fi
        if [ ! -d "''${DIR}" ];
        then
          echo "Directory ''${DIR} does not exist"
          exit 1
        fi
        echo "Initialising OpenTofu providers in ''${DIR}"
        pushd "''${DIR}"
        tofu init -backend=false || {
          echo "Failed to initialise OpenTofu providers in ''${DIR}"
          exit 1
        }
        popd
      '';
    };

    tofu-validate = {
      package = pkgs.bash;
      description = "Validate OpenTofu code in a given directory";
      exec = ''
        DIR="''${1:-}"
        if [ "''${DIR:-EMPTY}" == "EMPTY" ];
        then
          echo "Usage: $0 <directory>"
          exit 1
        fi
        if [ ! -d "''${DIR}" ];
        then
          echo "Directory ''${DIR} does not exist"
          exit 1
        fi
        echo "Validating OpenTofu code in ''${DIR}"
        pushd "''${DIR}"
        tofu validate || {
          echo "Failed to validate OpenTofu code in ''${DIR}"
          exit 1
        }
        popd
      '';
    };

    tofu-docs = {
      package = pkgs.bash;
      description = "Generate Terraform documentation for a given directory";
      exec = ''
        DIR="''${1:-}"
        if [ "''${DIR:-EMPTY}" == "EMPTY" ];
        then
          echo "Usage: $0 <directory>"
          exit 1
        fi
        if [ ! -d "''${DIR}" ];
        then
          echo "Directory ''${DIR} does not exist"
          exit 1
        fi
        echo "Generating Terraform documentation in ''${DIR}"
        terraform-docs --config .terraform-docs.yml "''${DIR}" || {
          echo "Failed to generate Terraform documentation in ''${DIR}"
          exit 1
        }
      '';
    };
  };

  enterTest = ''
    echo "Running devenv tests..."
  '';

  outputs = {
  };

}
