{ lib, config, ... }:

let
  inherit (lib) mkOption types mkAssert;
  inherit (import ./util.nix lib) defStr defSubst xor;
  cfg = config.services.opensmtpd;
  tableConfig = { options, name, ... } @ args: {
    options = {
      name = mkOption {
        type = types.str;
        default = args.name;
        description = "Name of the table";
      };

      source = mkOption {
        type = with types; nullOr str;
        default = null;
        description = ''
          File with the table contents.

          Note: if a relative path like ./table.txt is used, it will be stored
          in the world-readable Nix store. If the file contains secrets, an
          absolute path should be used, and probably it should be managed with
          sops or agenix.

          Mutually exclusive with `contents`.
        '';
      };

      contents = mkOption {
        type = with types; nullOr (either (listOf str) (attrsOf str));
        default = null;
        description = ''
          Contents of the inline table, either a list of strings in which case
          a values table will be generated, or an attrset for a key-value table.

          The contents will be included in the smtpd.conf file and stored in the
          world-readable Nix store. Do not add any secrets with this option.

          Mutually exclusive with `source`.
        '';
      };
    };
  };

  tblCheck = tbl: xor (tbl.source == null) (tbl.contents == null);
  genTblSrc = tbl: defSubst tbl.source "file:@@";
  genTblContentRaw = tbl: with builtins;
    let cnt = tbl.contents; in
    if isList cnt then lib.concatStringsSep ", " cnt
    else lib.concatStringsSep ", " (builtins.map (n: "${n} = ${cnt.${n}}") (builtins.attrNames cnt));
  genTblContent = tbl: if tbl.contents == null then "" else "{ ${genTblContentRaw tbl} }";
  genSingleTable = tbl:
    if (tblCheck tbl) then ''
      table ${tbl.name} ${genTblSrc tbl} ${genTblContent tbl}
    ''
    else throw "Table ${tbl.name} must define either source or contents (but not both).";
  genAllTables = lib.concatStringsSep "\n"
    (builtins.map (n: genSingleTable cfg.table."${n}") (builtins.attrNames cfg.table));

in
{
  options.services.opensmtpd = {
    table = mkOption {
      type = with types; attrsOf (submodule tableConfig);
      default = { _sys_aliases.source = "/etc/mail/aliases"; };
      description = "Definitions for smtpd tables";
    };

    _tableConfig = mkOption {
      type = types.str;
      visible = false;
      description = "Internal option";
    };
  };


  config.services.opensmtpd._tableConfig = genAllTables;

}
