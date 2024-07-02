{
  defStr = def: if def == null then "" else def;
  defSubst = def: subst: if def == null then "" else builtins.replaceStrings [ "@@" ] [ def ] subst;
  xor = a: b: (a || b) && !(a && b);
}
