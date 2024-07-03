{ lib, config, ... }:

let
  inherit (lib) mkOption types mkEnableOption;
  cfg = config.services.opensmtpd;
  strOrTable = with types; either str (attrTag {
    table = mkOption {
      type = str;
    };
  });

  exactlyOne = preds: 1 == builtins.foldl (cnt: pred: if pred then cnt + 1 else cnt) 0 preds;

  negatable.negate = mkEnableOption "Negate option";
  regexable.regex = mkEnableOption "Treat as regex";
  matchOption = negatable // regexable;

  mkNullStrOrTableOption = desc: mkOption {
    type = types.nullOr strOrTable;
    default = null;
    description = desc;
  };

  mkNullBoolStrTableOption = desc: mkOption {
    type = with types; nullOr (either bool strOrTable);
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
  */

  all = mkEnableOption "Rule matches all";
  local = mkEnableOption "Rule matches local";

  dstOpt = matchOption // {
    inherit all local;

    domain = mkNullStrOrTableOption "Domain name or { table = " table_name "; } to match this rule.";

    rcptTo = mkNullStrOrTableOption "Recipient or { table = " table_name "; } to match";
  };

  checkDstOpt = dst: exactlyOne [
    all
    local
    (domain != null)
    (rcptTo != null)
  ] || throw "Exactly one of `all`, `local`, `domain` or `rcptTo` must be set on `dest`";

  srcOpt = matchOption // {
    inherit all local;

    auth = mkNullBoolStrTableOption "Rule matches authenticated users";

    mailFrom = mkNullStrOrTableOption "Rule matches MAIL FROM";

    rdns = mkNullBoolStrTableOption "Rule matches reverse DNS";

    socket = mkEnableOption "Rule matches messages received from socket";

    src = mkNullStrOrTableOption "Rule matches source addresses";
  };

  checkSrcOpt = src: exactlyOne [
    all
    (auth != null)
    local
    (mailFrom != null)
    (rdns != null)
    socket
    (src != null)
  ] || throw "Exactly one of `all`, `auth`, `local`, `mailFrom`, `rdns`, `socket` or `src` must be set on `src`";

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


in
{ }
