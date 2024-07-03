{ lib, config, ... }:

let
  inherit (lib) mkOption types mkEnableOption;
  inherit (import ./util.nix lib) joinNonEmpty unpackOnion traceVal ensureTable unTag ensureMsg;
  cfg = config.services.opensmtpd;

  envelopeType = env: t: with types; either t (attrTag (builtins.listToAttrs [{
    name = env;
    value = mkOption {
      type = t;
    };
  }]));

  strOrTable = envelopeType "table" types.str;
  regexable = t: envelopeType "regex" t;
  negatable = t: envelopeType "negate" t;

  # FIXME mk* functions' names, and probably this deserves own file
  mkStrOrTableOption = desc: mkOption {
    type = negatable (regexable strOrTable);
    description = desc;
  };

  mkBoolStrTableOption = desc: mkOption {
    type = with types; (negatable (either bool (regexable strOrTable)));
    description = desc;
  };

  mkNullStrOrTableOption = desc: mkOption {
    type = types.nullOr (negatable (regexable strOrTable));
    default = null;
    description = desc;
  };

  mkNullBoolStrTableOption = desc: mkOption {
    type = with types; nullOr (negatable (either bool (regexable strOrTable)));
    default = null;
    description = desc;
  };

  mkNullOrBoolOption = desc: mkOption {
    type = with types; nullOr bool;
    default = null;
    description = desc;
  };

  any = mkEnableOption "Rule matches all";
  local = mkEnableOption "Rule matches local";

  dstOpt = {
    inherit any local;

    domain = mkStrOrTableOption ''Domain name or { table = " table_name "; } to match this rule.'';

    rcptTo = mkStrOrTableOption ''Recipient or { table = " table_name "; } to match'';
  };


  srcOpt = {
    inherit any local;

    auth = mkBoolStrTableOption "Rule matches authenticated users";

    mailFrom = mkStrOrTableOption "Rule matches MAIL FROM";

    rdns = mkBoolStrTableOption "Rule matches reverse DNS";

    socket = mkEnableOption "Rule matches messages received from socket";

    src = mkStrOrTableOption "Rule matches source addresses";
  };

  /*
    miscOpts = {

    mailFrom = mkOption {
      type = with types; nullOr (submodule {
        options = matchOption {
          value = mkStrTableOption "String value or { table = " table_name "; }";
        };
      });
      default = null;
    };

    };
  */

  matchOpt = {
    options = {

      src = mkOption {
        type = with types; nullOr (attrTag srcOpt);
        default = null;
        description = ''
          Source specification; one of the options:
            - any: matches any source
            - local: matches local source
            - auth: matches authenticated users
            - mailFrom: matches MAIL FROM
            - rdns: matches reverse DNS
            - socket: matches messages received from socket
            - src: matches source addresses

            Options `any` and `local` are Boolean; if false, will be negated,
            i.e. will match any destination except the specified one.

            Other options are chainable attributes of `negate`, `regex` and `table`,
            (see the `dst` attribute for more details). `mailFrom` and `src` must
            be a string or a table, `auth` and `rdns` may also be set to `true`
            in which case they will match any authenticated user or available
            reverse DNS.

            `auth` and `rdns` can be negated both in attr chain and by setting to
            `false`, with the same effect; double negation is an error, e.g. both:
            ```
              src.auth.negate = true;
              src.auth = false;
            ```
            are valid and will generate "! from auth", but `src.auth.negate = false;`
            will signal double negation.
        '';
      };
      dst = mkOption {
        type = with types; nullOr (attrTag dstOpt);
        default = null;
        description = ''
          Destination specification; one of the options:
            - any: matches any destination
            - local: matches local destination
            - domain: matches destination domain
            - rcptTo: matches destination recipient

            Options `any` and `local` are Boolean; if false, will be negated,
            i.e. will match any destination except the specified one.

            Options `domain` and `rcptTo` are either a string or a table; they
            may be also marked as negated or regex, by chaining attributes, e.g.
            to match all domains except those listed in the table `excl_domains`
            use:
            ```
              dst.domain.negate.table = "excl_domains";
            ```
            If you want to exclude a domain by regex, use:
            ```
              dst.domain.negate.regex = "excluded\\.com";
            ```

            You may chain attributes `negate`, `regex` and `table`, in this order.
        '';
      };

      auth = mkNullBoolStrTableOption ''
        If this option is set, it matches authenticated users; similar to `src.auth`;
        also similarly it can be negated by setting to `false` or chaining `negate`,
        and chained with `regex` and `table`, e.g. every one of the following is valid:
        ```
          auth.negate.regex = "excluded\\.com";
          auth.negate.table = "excl_users";
          auth.table = "incl_users";
          auth = false;
        ```
        (but only one cannot be used in a single match).
      '';

    };
  };

  rawOrTable = table: str: if table then "<${ensureTable str cfg}>" else ''"${str}"'';

  genDir = isDst: if isDst then "for" else "from";

  genNullOrBoolDirCfg = nopt: isDst: vopt: lib.optionalString (vopt != null) (joinNonEmpty [
    (lib.optionalString (!vopt) "!")
    (if isDst then "for" else "from")
    nopt
  ]);

  genAnyCfg = genNullOrBoolDirCfg "any";
  genLocalCfg = genNullOrBoolDirCfg "local";
  genSocketCfg = genNullOrBoolDirCfg "socket" false;

  genStrOrTableCfg = nopt: isDst: vopt:
    with (unpackOnion [ "negate" "regex" "table" ] vopt); (joinNonEmpty [
      (lib.optionalString negate "!")
      (genDir isDst)
      nopt
      (lib.optionalString regex "regex")
      (rawOrTable table value)
    ]);

  genNullStrOrTableCfg = nopt: isDst: vopt:
    lib.optionalString (vopt != null) (genStrOrTableCfg nopt isDst vopt);

  genNullBoolStrOrTableCfg = nopt: isDst: vopt:
    lib.optionalString (vopt != null) (with (unpackOnion [ "negate" ] vopt);
    if (builtins.isBool value) then
      (ensureMsg (!(negate && !(value))) "double negation in ${nopt}"
        (joinNonEmpty [
          (lib.optionalString (negate || !value) "!")
          (genDir isDst)
          nopt
        ]))
    else genNullStrOrTableCfg nopt isDst vopt);

  dstCfgGenerator = {
    any = genAnyCfg true;
    local = genLocalCfg true;
    domain = genNullStrOrTableCfg "domain" true;
    rcptTo = genNullStrOrTableCfg "rcpt-to" true;
  };

  genDstCfg = dstTagged: lib.optionalString (dstTagged != null) (with (unTag dstTagged);
    ((dstCfgGenerator.${tag}) value));

  srcCfgGenerator = {
    any = genAnyCfg false;
    local = genLocalCfg false;
    auth = genNullBoolStrOrTableCfg "auth" false;
    mailFrom = genNullStrOrTableCfg "mail-from" false;
    rdns = genNullBoolStrOrTableCfg "rdns" false;
    socket = genSocketCfg;
    src = genNullStrOrTableCfg "src" false;
  };

  genSrcCfg = srcTagged: lib.optionalString (srcTagged != null) (with (unTag srcTagged);
    ((srcCfgGenerator.${tag}) value));

  genMatchCfg = match: joinNonEmpty [
    "match"
    (genDstCfg match.dst)
    (genSrcCfg match.src)
  ];

in
{
  options.services.opensmtpd = {
    match = mkOption {
      type = with types; listOf (submodule matchOpt);
      default = [ ];
    };

    _matchesConfig = mkOption {
      type = types.str;
      visible = false;
    };
  };


  config.services.opensmtpd._matchesConfig =
    (lib.concatStringsSep "\n" (map genMatchCfg cfg.match))

  ;

}
