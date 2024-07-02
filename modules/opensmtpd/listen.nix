{ lib, config, ... }:

let
  inherit (lib) mkOption types mkIf mkMerge;
  inherit (import ./util.nix lib) defStr defSubst;
  cfg = config.services.opensmtpd;
  myPort = name: cfg.listeners.${name}.port;
  listenerConfig = { options, name, ... }: {
    options = {

      family = mkOption {
        type = with types; nullOr (enum [ "inet" "inet6" ]);
        default = null;
        description = ''
          The address family to listen on. If not set, the service will listen on
          inet, and if networking.enableIPv6 is set, it will listen on inet6 as well.

        '';
      };

      interfaces = mkOption {
        type = with types; listOf str;
        default = [ "*" ];
        description = ''
          The interfaces to listen on. Use "*" to listen on 0.0.0.0, and, if networking.enableIPv6
          is set, also on :: (generate two listeners, one for each family).
        '';
      };

      port = mkOption {
        type = types.port;
        default = 25;
        description = ''
          The port to listen on. Must be set explicitly; it will usually be set by the
          enable{Smtp,Submission[s]} options.
        '';
      };

      auth = {
        policy = mkOption {
          type = types.enum [ "none" "permit" "require" ];
          default = let p = myPort name; in if p == 587 || p == 465 then "require" else "permit";
          description = ''
            The authentication policy for this listener. If set to "none", no
            authentication will be advertised. If set to "permit", authentication
            will be advertised but not required. If set to "require", authentication
            will be advertised and required.

            It will be set to "require" on port 587 or 465, and to "permit" on any
            other port.

            "none" should not be used except on relay-only servers.
          '';
        };

        credentials = mkOption {
          type = with types; nullOr str;
          default = null;
          description = ''
            Credentials to use for authentication. If null, the normal login credentials
            will be used; otherwise it must be set to an attribute name of the table
            to use for authentication.
          '';
        };
      };

      filter = mkOption {
        type = with types; nullOr str;
        default = null;
        description = ''
          The filter name to apply to this listener.
        '';
      };

      tls = {
        policy = mkOption {
          type = types.enum [ "none" "connect" "permit" "require" "verify" ];
          default = let p = myPort name; in
            if p == 587 then "require"
            else if p == 465 then "connect"
            else "permit";
          description = ''
            The TLS policy for this listener. If set to "none", no TLS will be used. If
            set to "connect", TLS will be required on connection (default on port 465).
            If set to "require", TLS will be advertised and required (default on
            port 587). If set to "permit", TLS will be advertised but not required
            (default on other ports). If set to "verify", TLS will be advertised, required
            and the client must present a valid certificate.

            NOTE: setting this to "none" is a bad practice and it will trigger a warning.
          '';
          # TODO add the warning
        };

        ca = mkOption {
          type = with types; nullOr str;
          default = null;
          description = ''
            The CA to use for verifying client certificates.
          '';
        };

        pki = mkOption {
          type = with types; listOf str;
          default = lib.flatten [ (config.services.opensmtpd.pki._default.name or [ ]) ];
          defaultText = ''
            If a PKI named "_default" is defined (usually from the defaultPki option),
            the default is one element list with that PKI; othwerwise it is an empty
            list, which will trigger an error if policy is not "none".
          '';
          description = ''
            The PKI names to use for this listener. Required non-empty if the
            policy is not "none" (which is a bad practice).
          '';
        };

      };
    };

  };

  genTlsConfig = tls: with tls;
    let
      polstr = {
        connect = "smtps";
        permit = "tls";
        require = "tls-require";
        verify = "tls-require verify";
      }.${policy};
      castr = defSubst ca "ca @@";
      pkistr =
        if builtins.length pki == 0 then throw "At least one PKI must be set for TLS"
        else builtins.concatStringsSep " " (map (p: "pki ${p}") pki);
    in
    if policy == "none" then ""
    else "${polstr} ${castr} ${pkistr}";

  genAuthConfig = auth: with auth;
    if policy == "none" then ""
    else
      let polstr = if policy == "require" then "auth" else "auth-optional";
      in "${polstr} ${defSubst credentials "<@@>"}";

  genListenerConfig = lst: iface:
    if "${iface}" == "*" then ''
      ${genListenerConfig lst "0.0.0.0"}
      ${if config.networking.enableIPv6 then genListenerConfig lst "::" else ""}
    ''
    else
      builtins.concatStringsSep " " [
        "listen on ${iface} ${defStr lst.family} port ${toString lst.port}"
        "${genTlsConfig lst.tls} ${genAuthConfig lst.auth}"
        "${defSubst lst.filter "filter @@"}"
      ];


in
{

  options.services.opensmtpd = {
    listeners = mkOption {
      type = with types; attrsOf (submodule listenerConfig);
      description = ''
        The listeners to configure for opensmtpd. Each listener must have a unique name.

        Usually they are automatically set by the enable{Smtp,Submission[s]} options.
      '';

    };

    _listenersConfig = mkOption {
      type = with types; uniq str;
      visible = false;
      description = ''
        Internal option to store the listeners configuration.
      '';
    };

  };

  config.services.opensmtpd = {
    _listenersConfig = with builtins; concatStringsSep "\n" (
      lib.flatten (
        map (lst: (map (iface: genListenerConfig lst iface) lst.interfaces))
          (attrValues cfg.listeners)
      )
    );

    listeners = mkMerge [
      (mkIf cfg.enableSmtp { _smtp = { }; })
      (mkIf cfg.enableSubmission { _submission.port = 587; })
      (mkIf cfg.enableSubmissions { _submissions.port = 465; })
    ];
  };


}
