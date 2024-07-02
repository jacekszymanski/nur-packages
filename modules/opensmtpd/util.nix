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

  mkOptionalTableCfg = optName: tblName: cfg:
    if tblName == null then ""
    else if (cfg.table.${tblName} or null) == null then
      throw "Table ${tblName} used but not defined"
    else "${optName} <${tblName}>";

  mkOptionalAttrCfg = optName: attrName: attrSet:
    if attrName == null then ""
    else if (attrSet.${attrName} or null) == null then
      throw "Attribute ${attrName} used but not defined"
    else "${optName} ${attrSet.${attrName}}";

  ensureMsg = cond: msg: val: if cond then val else throw msg;

  ensure = cond: val: ensureMsg cond "Assertion failed" val;
}
