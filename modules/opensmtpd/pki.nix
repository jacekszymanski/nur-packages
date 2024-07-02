{ lib, config, ... }:

let
  inherit (lib) mkOption types mkIf;
  cfg = config.services.opensmtpd;
  myDir = name: cfg.pki."${name}".directory;
  pkiConfig = { options, name, ... } @ args: {
    options = {
      name = mkOption {
        type = types.str;
        default = args.name;
        description = "The name of the PKI";
      };

      directory = mkOption {
        type = with types; nullOr str;
        default = null;
        description = "Directory for the PKI files";
      };

      cert = mkOption {
        type = types.str;
        default = "${myDir name}/cert.pem";
        defaultText = "cert.pem in the PKI directory";
        description = "The certificate file.";
      };

      key = mkOption {
        type = types.str;
        default = "${myDir name}/key.pem";
        defaultText = "key.pem in the PKI directory";
        description = "The private key file";
      };

      dhe = mkOption {
        type = types.enum [ "none" "legacy" "auto" ];
        default = "none";
        description = "DHE parameters; see smtpd.conf(5)";
      };
    };
  };

  genSinglePkiCfg = name: pkidef: ''
    pki ${name} cert ${pkidef.cert}
    pki ${name} key ${pkidef.key}
  ''
  + lib.optionalString (pkidef.dhe != "none") ''
    pki ${name} dhe ${pkidef.dhe}
  '';

  genAllPkis =
    let
      inherit (cfg) pki;
    in
    builtins.concatStringsSep "\n"
      (map (n: genSinglePkiCfg n pki."${n}") (builtins.attrNames pki));

in
{
  options.services.opensmtpd = {
    pki = mkOption {
      type = with types; attrsOf (submodule pkiConfig);
      description = "PKI configuration";
    };

    _pkiConfig = mkOption {
      type = types.str;
      visible = false;
      description = "Internal option";
    };
  };

  config.services.opensmtpd = {
    _pkiConfig = genAllPkis;

    pki = mkIf (cfg.defaultPki != null) {
      _default.directory = cfg.defaultPki;
    };
  };
}
