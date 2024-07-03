{ lib, config, ... }:

let
  inherit (lib) mkOption types;
  cfg = config.services.opensmtpd;
in
{

  imports = [
    ./listen.nix
    ./pki.nix
    ./table.nix
    ./action.nix
    ./match.nix
  ];

  options.services.opensmtpd = {

    enableSmtp = mkOption {
      type = types.bool;
      default = true;
      description = "Enable the SMTP service on port 25 on all interfaces.";
    };

    enableSubmission = mkOption {
      type = types.bool;
      default = true;
      description = "Enable the Submission service on port 587 on all interfaces.";
    };

    enableSubmissions = mkOption {
      type = types.bool;
      default = true;
      description = "Enable the Submissions service on port 465 on all interfaces.";
    };

    defaultPki = mkOption {
      type = with types; nullOr str;
      default = with config.security.acme;
        let names = lib.attrNames certs;
        in if (length names == 1) then certs."${builtins.elem names 0}".directory else null;
      defaultText = "The only ACME cert configuration or null";
      description = ''
        The default PKI to use with listeners; it should be set to the directory where
        there are two files: key.pem and cert.pem. If set to null, all the liteners must
        either have a PKI set manually or their TLS policy set to "none" (which is not
        recommended).

        The simplest way to use this is to setup an ACME configuration and then set this
        option to the directory where the ACME certificated are stored, e.g.
        `services.opensmtpd.defaultPki = config.security.acme.certs."example.com".directory;`

        Note: if there's only one ACME cert configuration defined, it will be used
        as the default automatically.

        This option, if enabled, will set `services.opensmtpd.pki._default.{key,cert}`.
      '';
    };


  };

  config = {
    services.opensmtpd = {
      serverConfiguration = with config.services.opensmtpd; ''
        ${_tableConfig}
        ${_pkiConfig}
        ${_listenersConfig}
        ${_actionsConfig}
        ${_matchesConfig}
      '';
    };
  };
}
