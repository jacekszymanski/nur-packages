lib:
let
  inherit (lib) mkOption types;
in
rec {

  defStr = def: if def == null then "" else def;
  defSubst = def: subst: if def == null then "" else builtins.replaceStrings [ "@@" ] [ def ] subst;

  xor = a: b: (a || b) && !(a && b);

  nonEmpty = builtins.filter (x: x != null && x != "");

  ensureMsg = cond: msg: val: if cond then val else throw msg;

  ensure = cond: val: ensureMsg cond "Assertion failed" val;

  ensureTable = tbl: cfg:
    ensureMsg ((cfg.table.${tbl} or null) != null) "Table ${tbl} used but not defined" tbl;

  joinNonEmptySep = sep: strs: builtins.concatStringsSep sep (nonEmpty strs);

  joinNonEmpty = joinNonEmptySep " ";

  exactlyOne = preds: 1 == builtins.foldl (cnt: pred: if pred then cnt + 1 else cnt) 0 preds;
  exactlyOneNonNull = vals: exactlyOne (map (x: x != null) vals);

  envelopeType = env: t: with types; either t (attrTag (builtins.listToAttrs [{
    name = env;
    value = mkOption {
      type = t;
    };
  }]));

  strOrTable = envelopeType "table" types.str;
  regexable = t: envelopeType "regex" t;
  negatable = t: envelopeType "negate" t;

  /*
   * Unpack an "onion" of layers into a single attribute set, i.e.
   * { a = { b = { d = DATA; }; }; } when known layers are [ "a" "b" "c" "d" "e" ]
   * will be transformed into
   * { a = true; b = true; c = false; d = true; e = false; value = DATA; }
   *
   * DATA can be any type, including an attribute set, but if it has a single
   * attribute named as one of the layers, it will be unpacked as well.
   *
   * TODO: this does not take the order of layers into account, it should
   * not be a big problem as envelope types are strict on order.
   *
   * Check if it is indeed the case and if this can be played with, fix.
   */
  unpackOnion = layers: data: with builtins; let
    negLayers = listToAttrs (map (n: { name = n; value = false; }) layers);
    unpackOnionInt = dt:
      if (!isAttrs dt) then
        { value = dt; }
      else
        let as = attrNames dt; in
        if (length as == 1 && (elem (elemAt as 0) layers)) then
          let an = elemAt as 0; in
          (listToAttrs [{ name = an; value = true; }]) // unpackOnionInt (dt.${an})
        else
          { value = dt; };
  in
  negLayers // unpackOnionInt data;

  # transform { tagname = DATA; } to { tag = tagname; value = DATA; }
  unTag = data: with builtins; if (!isAttrs data) then
    throw "Expected tagged data, got ${toString data}"
  else
    let
      as = attrNames data;
    in
    if (length as != 1) then
      throw "Expected tagged data, got ${toString data}"
    else
      { tag = elemAt as 0; value = data.${elemAt as 0}; };

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

}
