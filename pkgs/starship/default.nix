{ pkgs, ... }:

pkgs.starship.overrideAttrs (final: prev: {
  postInstall = prev.postInstall + ''

    presetdir=$out/share/starship/presets/
    mkdir -p $presetdir
    cp docs/.vuepress/public/presets/toml/*.toml $presetdir

  '';

  doCheck = false;

})
