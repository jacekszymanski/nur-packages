{ lib, config, ... }:

let
  inherit (lib) mkOption types mkEnableOption;
  inherit (import ./util.nix lib)
    nonEmpty mkSelfCfg mkSelfTableCfg mkOptionalTableCfg ensureMsg
    joinNonEmpty defSubst defStr;
  cfg = config.services.opensmtpd;

  # Local options for all delivery methods
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
  mboxConfig.options = mboxOnlyOptions;
  expand-onlyConfig.options = localOptions;
  forward-onlyConfig.options = localOptions;
  mdaConfig.options = mdaOptions;

  lmtpConfig.options = localOptions // {
    rcptTo = mkEnableOption ''
      Use the recipient email address (after expansion) instead of the local user
      in the LMTP session as RCPT TO.
    '';
  };

  genMboxOnlyOptions = opts: lib.concatStringsSep " " (nonEmpty [
    (mkOptionalTableCfg "alias" opts.alias cfg)
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

  genLmtpOptions = opts: joinNonEmpty [
    (genLocalOptions opts)
    (lib.optionalString opts.rcptTo "rcpt-to")
  ];

  # Remote options for all delivery methods
  remoteOptions = {
    backup = {
      enabled = mkEnableOption "Act as a backup MX";

      priorityFrom = mkOption {
        type = with types; nullOr str;
        default = null;
        descrtiption = ''
          Act as a backup MX; deliver to MX with priority higher than MX identified
          in this option.
        '';
      };
    };

    helo = {
      name = mkOption {
        type = with types; nullOr str;
        default = null;
        description = "Name to use in the HELO/EHLO command. Mutually exclusive with `source`";
      };

      source = mkOption {
        type = with types; nullOr str;
        default = null;
        description = "Table to lookup for HELO/EHLO strings. Mutually exclusive with `name`";
      };
    };

    domain = mkOption {
      type = with types; nullOr str;
      default = null;
      description = "Table to lookup for relays instead of querying for MX records.";
    };

    smarthost = mkOption {
      type = with types; nullOr (submodule {
        options = {
          lmtp = mkEnableOption "Use LMTP for the smarthost";

          authAs = mkOption {
            type = with types; nullOr str;
            default = null;
            descrtiption = "Label in the auth table to use for authentication.";
          };

          authTable = mkOption {
            type = with types; nullOr str;
            default = null;
            description = "Table to lookup for authentication credentials.";
          };

          port = mkOption {
            type = with types; nullOr port;
            default = null;
            description = ''
              Port to connect on the smarthost. The default depends on the TLS policy
              configuration (465 for connect, otherwise 25); if `lmtp` is enabled on
              the smarthost, port must be specified explicitly.
            '';
          };

          host = mkOption {
            type = types.str;
            description = "Hostname of the smarthost";
          };
        };
      });
      default = null;
      description = "Relay host specification.";
    };

    tls = {
      policy = mkOption {
        type = types.enum [ "none" "permit" "connect" "require" ];
        default = "permit";
        description = ''
          The TLS policy; mostly self-explanatory. The options "none" and "connect"
          make sense only when `smarthost` is specified, otherwise it is an error
          to use them.

        '';
      };

      acceptSelfSigned = mkEnableOption "Accept self-signed certificates";

      pki = mkOption {
        type = with types; nullOr str;
        default = null;
        description = ''
          Name of the PKI to be used for TLS connections.

          Note: it is NOT an error to leave `null` here even if the TLS policy is
          not "none"; the only case when it is required is when the smarthost requires
          a client certificate. This, however, cannot be known at build time.
        '';
      };

      protocols = mkOption {
        type = with types; nullOr str;
        default = null;
        description = ''
          List of protocols to use for TLS connections. The default depends on the
          opensmtpd build options etc.

          Unless you know what you are doing, it is recommended to leave this empty.
        '';
      };

      ciphers = mkOption {
        type = with types; nullOr str;
        default = null;
        description = ''
          List of ciphers to use for TLS connections. The default depends on the
          opensmtpd build options etc.

          Unless you know what you are doing, it is recommended to leave this empty.
        '';
      };
    };

    srs = mkEnableOption ''
      When relaying a mail resulting from a forward, use the Sender Rewriting
      Scheme to rewrite sender address.
    '';


    mailFrom = mkOption {
      type = with types; nullOr str;
      default = null;
      description = ''
        Use mailaddr as the MAIL FROM address within the SMTP transaction.
      '';
    };

    src = {
      address = mkOption {
        type = with types; nullOr str;
        default = null;
        description = ''
          Use the specified IP address as the source address for the connection.

          Mutually exclusive with `addrTable`.
        '';
      };

      addrTable = mkOption {
        type = with types; nullOr str;
        default = null;
        description = ''
          Use the specified table to lookup the source address for the connection.

          Mutually exclusive with `address`.
        '';
      };
    };
  };

  relayConfig.options = remoteOptions;

  genBackupOptions = opts: lib.concatStringsSep " " (nonEmpty [
    (lib.optionalString opts.backup.enabled "backup")
    (defSubst opts.backup.priorityFrom "mx @@")
  ]);

  genHeloOptions = opts: with opts.helo;
    if name != null && source != null then
      throw "Only one of `name` and `source` can be specified"
    else
      lib.concatStringsSep " " (nonEmpty [
        (defSubst name "helo @@")
        (mkOptionalTableCfg "helo-src" source cfg)
      ]);

  genDomainOptions = opts: mkOptionalTableCfg "domain" opts.domain cfg;

  genSmarthostUrl = opts:
    let
      sh = opts.smarthost;
      tlspol = opts.tls.policy;
      portNum =
        if sh.port != null then sh.port
        else if sh.lmtp then throw "Port must be specified explicitly when using LMTP"
        else if tlspol == "connect" then 465
        else 25;
      proto = if sh.lmtp then "lmtp" else {
        none = "smtp+notls";
        permit = "smtp";
        connect = "smtps";
        require = "smtp+tls";
      }.${tlspol};
      portStr = if portNum == 25 then "" else ":${builtins.toString portNum}";
      authAsStr =
        if sh.authAs != null
        then ensureMsg (sh.authTable != null) "authAs requires authTable" "${sh.authAs}@"
        else "";
      hostStr = sh.host;
    in
    "${proto}://${authAsStr}${hostStr}:${portStr}";

  genSmarthostOptions = opts:
    lib.optionalString (opts.smarthost != null) (lib.concatStringsSep " " (nonEmpty [
      "host"
      (genSmarthostUrl opts)
      (mkOptionalTableCfg "auth" opts.smarthost.authTable cfg)
    ]));

  genTlsOptions = opts: with opts.tls; joinNonEmpty [
    (lib.optionalString (builtins.elem policy [ "connect" "require" ]) (joinNonEmpty [
      "tls"
      (lib.optionalString acceptSelfSigned "no-verify")
    ]))
    (mkOptionalAttrCfg "pki" pki cfg.pki)
    (defSubst protocols ''protocols "@@"'')
    (defSubst ciphers ''ciphers "@@"'')
  ];

  genSrcOptions = opts: with opts.src;
    if address != null && addrTable != null then
      throw "Only one of `address` and `addrTable` can be specified"
    else
      joinNonEmpty [
        (defSubst address "src @@")
        (mkOptionalTableCfg "src" addrTable cfg)
      ];

  genRemoteOptions = opts: joinNonEmpty [
    (genBackupOptions opts)
    (genHeloOptions opts)
    (genDomainOptions opts)
    (genSmarthostOptions opts)
    (genTlsOptions opts)
    (lib.optionalString opts.srs "srs")
    (defSubst opts.mailFrom "mail-from @@")
    (genSrcOptions opts)
  ];

  genTypeOptions = {
    maildir = genMaildirOptions;
    mbox = genMboxOnlyOptions;
    expand-only = genLocalOptions;
    forward-only = genLocalOptions;
    mda = genMdaOptions;
    lmtp = genLmtpOptions;
    relay = genRemoteOptions;
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
        forward-only = mkOption {
          type = submodule forward-onlyConfig;
          description = ''
            Only accept the message if the recipient results in a remote address after
            the processing of aliases or forward file.
          '';
        };
        mda = mkOption {
          type = submodule mdaConfig;
          description = "Delivers mail to a command";
        };
        lmtp = mkOption {
          type = submodule lmtpConfig;
          description = "Delivers mail to LMTP servers";
        };
        relay = mkOption {
          type = submodule relayConfig;
          description = "Relays mail to remote servers";
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
