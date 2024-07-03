{ lib, config, ... }:

let
  inherit (lib) mkOption types mkEnableOption;
  inherit (import ./util.nix lib) joinNonEmpty unpackOnion traceVal ensureTable;
  cfg = config.services.opensmtpd;
  strOrTable = with types; either str (attrTag {
    table = mkOption {
      type = str;
    };
  });

  exactlyOne = preds: 1 == builtins.foldl (cnt: pred: if pred then cnt + 1 else cnt) 0 preds;
  exactlyOneNonNull = vals: exactlyOne (map (x: x != null) vals);

  regexable = tp: with types; either tp (attrTag {
    regex = mkOption {
      type = tp;
    };
  });

  negatable = tp: with types; either tp (attrTag {
    negate = mkOption {
      type = tp;
    };
  });

  matchable = tp: negatable (regexable tp);

  mkNullStrOrTableOption = desc: mkOption {
    type = types.nullOr (matchable strOrTable);
    default = null;
    description = desc;
  };

  mkNullBoolStrTableOption = desc: mkOption {
    type = with types; nullOr matchable ((either bool strOrTable));
    default = null;
    description = desc;
  };

  mkNullOrBoolOption = desc: mkOption {
    type = with types; nullOr bool;
    default = null;
    description = desc;
  };


  /*
    match1.dst = {
      negate = false;
      regex = true;
      domain.table = "domains";
    }


    {
      dst.domain.regex.table =
      dst.negate.regex.domain =
      dst.
  */

  any = mkNullOrBoolOption "Rule matches all";
  local = mkNullOrBoolOption "Rule matches local";

  dstOpt.options = {
    inherit any local;

    domain = mkNullStrOrTableOption ''Domain name or { table = " table_name "; } to match this rule.'';

    rcptTo = mkNullStrOrTableOption ''Recipient or { table = " table_name "; } to match'';
  };

  checkDstOpt = dst: with dst; exactlyOneNonNull [
    any
    local
    domain
    rcptTo
  ] || throw "Exactly one of `all`, `local`, `domain` or `rcptTo` must be set on `dest`";

  srcOpt.options = {
    inherit any local;

    auth = mkNullBoolStrTableOption "Rule matches authenticated users";

    mailFrom = mkNullStrOrTableOption "Rule matches MAIL FROM";

    rdns = mkNullBoolStrTableOption "Rule matches reverse DNS";

    socket = mkNullOrBoolOption "Rule matches messages received from socket";

    src = mkNullStrOrTableOption "Rule matches source addresses";
  };

  checkSrcOpt = src: with src; exactlyOneNonNull [
    any
    auth
    local
    mailFrom
    rdns
    socket
    src
  ] ||
  throw ("Exactly one of `all`, `auth`, `local`, `mailFrom`, `rdns`, " +
    "`socket` or `src` must be set on `src`");

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
        type = with types; nullOr (submodule srcOpt);
        default = { };
      };
      dst = mkOption {
        type = with types; nullOr (submodule dstOpt);
        default = { };
      };

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

  genNullStrOrTableCfg = nopt: isDst: vopt:
    lib.optionalString (vopt != null) (with (unpackOnion [ "negate" "regex" "table" ] vopt); (joinNonEmpty [
      (lib.optionalString negate "!")
      (genDir isDst)
      nopt
      (lib.optionalString regex "regex")
      (rawOrTable table value)
    ]));

  genDstCfg = dst: lib.optionalString (dst != null) (joinNonEmpty [
    (genAnyCfg true dst.any)
    (genLocalCfg true dst.local)
    (genNullStrOrTableCfg "domain" true dst.domain)
    (genNullStrOrTableCfg "rcpt-to" true dst.rcptTo)
  ]);

  genMatchCfg = match: joinNonEmpty [
    "match"
    (genDstCfg match.dst)
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
