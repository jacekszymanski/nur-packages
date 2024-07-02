{ lib, config, ... }:

let
  inherit (lib) mkOption types mkEnableOption;
  inherit (import ./util.nix lib) nonEmpty mkSelfCfg mkSelfTableCfg assertOptionalTable;
  cfg = config.services.opensmtpd;
  mboxOnlyOptions = {
    alias = mkOption {
      type = with types; nullOr str;
      default = null;
      description = "Name of the aliases table";
    };

    ttl = mkOption {
      type = with types; nullOr (strMatching "^\\d+[smhd]$");
      default = null;
      description = "TTL for the local queue";
    };

    virtual = mkOption {
      type = with types; nullOr str;
      default = null;
      description = "Name of the table to be used for delivery to virtual users.";
    };

  };
  localOptions = mboxOnlyOptions // {
    user = mkOption {
      type = with types; nullOr str;
      default = null;
      description = "Username to perform delivery, useful for virtual servers.";
    };
  };
  mdaOptions = localOptions // {
    command = mkOption {
      type = types.str;
      description = "Command to be used as the MDA";
    };

    wrapper = mkOption {
      type = with types; nullOr str;
      default = null;
      description = "Name of the wrapper specified in `services.opensmtpd.mda-wrappers`";
    };
  };
  maildirConfig = {
    options = localOptions // {
      path = mkOption {
        type = types.str;
        description = ''
          Absolute path to the maildir. May contain format specifiers, see smtpd.conf(5)
        '';
      };

      junk = mkEnableOption "Send messages marked as spam to the Junk folder";
    };
  };
  mboxConfig = {
    options = mboxOnlyOptions;
  };
  expand-onlyConfig.options = localOptions;
  mdaConfig.options = mdaOptions;

  mkAliasOpt = opts:
    lib.optionalString (assertOptionalTable cfg opts.alias) (mkSelfTableCfg opts "alias");

  genMboxOnlyOptions = opts: lib.concatStringsSep " " (nonEmpty [
    (mkAliasOpt opts)
    (mkSelfCfg opts "ttl")
    (mkSelfTableCfg opts "virtual")
  ]);

  genLocalOptions = opts: lib.concatStringsSep " " (nonEmpty [
    (genMboxOnlyOptions opts)
    (mkSelfCfg opts "user")
  ]);

  genMaildirOptions = opts: lib.concatStringsSep " " (nonEmpty [
    opts.path
    (lib.optionalString opts.junk "junk")
    (genLocalOptions opts)
  ]);

  genMdaOptions = opts: lib.concatStringsSep " " (nonEmpty [
    opts.command
    (genLocalOptions opts)
    (mkSelfCfg opts "wrapper") # TODO check if wrapper is defined
  ]);

  genTypeOptions = {
    maildir = genMaildirOptions;
    mbox = genMboxOnlyOptions;
    expand-only = genLocalOptions;
    mda = genMdaOptions;
  };

  genSingleAction = name: actionTagged:
    let
      tag = builtins.elemAt (lib.attrNames actionTagged) 0;
      action = actionTagged.${tag};
    in
    lib.concatStringsSep " " (nonEmpty [
      "action"
      name
      tag
      ((genTypeOptions.${tag}) action)
    ]);

  genAllActions = lib.concatStringsSep "\n"
    (builtins.map (n: genSingleAction n cfg.actions."${n}") (lib.attrNames cfg.actions));

in
{
  options.services.opensmtpd = {
    actions = mkOption {
      type = with types; attrsOf (attrTag {
        mbox = mkOption {
          type = submodule mboxConfig;
          description = "Delivers mail to mbox files";
        };
        maildir = mkOption {
          type = submodule maildirConfig;
          description = "Delivers mail to maildir directories";
        };
        expand-only = mkOption {
          type = submodule expand-onlyConfig;
          description = ''
            Only accept the message if a delivery method was specified in an aliases
            or .forward file.
          '';
        };
        mda = mkOption {
          type = submodule mdaConfig;
          description = "Delivers mail to a command";
        };
      });
      default = {
        local_users.mbox = { alias = "_sys_aliases"; };
      };
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
