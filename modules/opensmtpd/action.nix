{ lib, config, ... }:

let
  inherit (lib) mkOption types;
  cfg = config.services.opensmtpd;
  mkNameOption = name: mkOption {
    type = types.str;
    default = name;
    description = "Name to be used in the smtpd.conf file";
  };
  localOptions = nm: {
    name = mkNameOption nm;

    alias = mkOption {
      type = with types; nullOr str;
      default = null;
      description = "Name of the aliases table";
    };

    ttl = mkOption {
      type = with types; nullOr strMatching "^\\d+[smhd]$";
      default = null;
      description = "TTL for the local queue";
    };
  };
  maildirConfig = { options, name, ... } @ args: {
    options = localOptions name // {
      path = mkOption {
        type = types.str;
        description = ''
          Absolute path to the maildir. May contain format specifiers, see smtpd.conf(5)
        '';
      };
    };
  };
  mboxConfig = { options, name, ... } @ args: {
    options = localOptions name;
  };
  localConfig = { options, name, ... }: {
    options = { };

  };
  genTypeOptions = {
    maildir = opts: "${opts.path}";
    mbox = _: "";
  };

  genSingleAction = name: actionTagged: let
    tag = builtins.elemAt (lib.attrNames actionTagged) 0;
    action = actionTagged.${tag};
  in
  lib.concatStringsSep " " [
    "action" name tag ((genTypeOptions.${tag}) action)
  ];

  genAllActions = lib.concatStringsSep "\n"
      (builtins.map (n: genSingleAction n cfg.actions."${n}") (lib.attrNames cfg.actions));

in
{
  options.services.opensmtpd = {
    actions = mkOption {
      type = with types; attrsOf (attrTag {
        mbox = mkOption {
          type = submodule mboxConfig;
        };
        maildir = mkOption {
          type = submodule maildirConfig;
        };
      });
      default = {};
      description = ''
        Actions to take when receiving mail
        '';
    };

    _actionsConfig = mkOption {
      type = types.str;
      visible = false;
      description = "Internal option.";
    };
  };

  config.services.opensmtpd._actionsConfig = genAllActions;
}
