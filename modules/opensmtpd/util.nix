lib: {
  defStr = def: if def == null then "" else def;
  defSubst = def: subst: if def == null then "" else builtins.replaceStrings [ "@@" ] [ def ] subst;
  xor = a: b: (a || b) && !(a && b);
  nonEmpty = builtins.filter (x: x != null && x != "");
  mkSelfCfg = opts: name:
    lib.optionalString (builtins.hasAttr name opts && opts.${name} != null)
      "${name} ${opts.${name}}";
  mkSelfTableCfg = opts: name:
    lib.optionalString (builtins.hasAttr name opts && opts.${name} != null)
      "${name} <${opts.${name}}>";

  # throw error it tbl is named but not defined in services.opensmtpd.tables
  # TODO adapt for use with pkis, actions etc. for all sanity checks
  assertOptionalTable = cfg: tbl:
    if tbl != null && (cfg.table.${tbl} or null) == null then
      throw "Table ${tbl} used but not defined"
    else
      tbl != null;
}
