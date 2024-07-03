{ lib, ... }:

let
  inherit (lib) mkOption types;
in
{
  protocols = mkOption {
    type = with types; nullOr str;
    default = null;
    description = ''
      List of protocols to use for TLS connections. The default depends on the
      opensmtpd build options etc.

      Unless you know what you are doing, it is recommended to leave this empty.
    '';
  };

  ciphers = mkOption {
    type = with types; nullOr str;
    default = null;
    description = ''
      List of ciphers to use for TLS connections. The default depends on the
      opensmtpd build options etc.

      Unless you know what you are doing, it is recommended to leave this empty.
    '';
  };

}
