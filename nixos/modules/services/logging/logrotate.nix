{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.logrotate;

  pathOpts = {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to enable log rotation for this path. This can be used to explicitly disable
          logging that has been configured by NixOS.
        '';
      };

      path = mkOption {
        type = types.str;
        description = ''
          The path to log files to be rotated.
        '';
      };

      user = mkOption {
        type = with types; nullOr str;
        default = null;
        description = ''
          The user account to use for rotation.
        '';
      };

      group = mkOption {
        type = with types; nullOr str;
        default = null;
        description = ''
          The group to use for rotation.
        '';
      };

      frequency = mkOption {
        type = types.enum [ "hourly" "daily" "weekly" "monthly" "yearly" ];
        default = "daily";
        description = ''
          How often to rotate the logs.
        '';
      };

      keep = mkOption {
        type = types.int;
        default = 20;
        description = ''
          How many rotations to keep.
        '';
      };

      extraConfig = mkOption {
        type = types.lines;
        default = "";
        description = ''
          Extra logrotate config options for this path. Refer to
          <link xlink:href="https://linux.die.net/man/8/logrotate"/> for details.
        '';
      };

      priority = mkOption {
        type = types.int;
        default = 1000;
        description = ''
          Order of this logrotate block in relation to the others. The semantics are
          the same as with `lib.mkOrder`. Smaller values have a greater priority.
        '';
      };
    };

    config.extraConfig = ''
      missingok
      notifempty
    '';
  };

  mkConf = pathOpts: ''
    # generated by NixOS using the `services.logrotate.paths.${pathOpts.name}` attribute set
    "${pathOpts.path}" {
      ${optionalString (pathOpts.user != null || pathOpts.group != null) "su ${pathOpts.user} ${pathOpts.group}"}
      ${pathOpts.frequency}
      rotate ${toString pathOpts.keep}
      ${pathOpts.extraConfig}
    }
  '';

  paths = sortProperties (mapAttrsToList (name: pathOpts: pathOpts // { name = name; }) (filterAttrs (_: pathOpts: pathOpts.enable) cfg.paths));
  configFile = pkgs.writeText "logrotate.conf" (concatStringsSep "\n" ((map mkConf paths) ++ [ cfg.extraConfig ]));

in
{
  imports = [
    (mkRenamedOptionModule [ "services" "logrotate" "config" ] [ "services" "logrotate" "extraConfig" ])
  ];

  options = {
    services.logrotate = {
      enable = mkEnableOption "the logrotate systemd service";

      paths = mkOption {
        type = with types; attrsOf (submodule pathOpts);
        default = {};
        description = ''
          Attribute set of paths to rotate. The order each block appears in the generated configuration file
          can be controlled by the <link linkend="opt-services.logrotate.paths._name_.priority">priority</link> option
          using the same semantics as `lib.mkOrder`. Smaller values have a greater priority.
        '';
        example = literalExample ''
          {
            httpd = {
              path = "/var/log/httpd/*.log";
              user = config.services.httpd.user;
              group = config.services.httpd.group;
              keep = 7;
            };

            myapp = {
              path = "/var/log/myapp/*.log";
              user = "myuser";
              group = "mygroup";
              frequency = "weekly";
              keep = 5;
              priority = 1;
            };
          }
        '';
      };

      extraConfig = mkOption {
        default = "";
        type = types.lines;
        description = ''
          Extra contents to append to the logrotate configuration file. Refer to
          <link xlink:href="https://linux.die.net/man/8/logrotate"/> for details.
        '';
      };
    };
  };

  config = mkIf cfg.enable {
    assertions = mapAttrsToList (name: pathOpts:
      { assertion = (pathOpts.user != null) == (pathOpts.group != null);
        message = ''
          If either of `services.logrotate.paths.${name}.user` or `services.logrotate.paths.${name}.group` are specified then *both* must be specified.
        '';
      }
    ) cfg.paths;

    systemd.services.logrotate = {
      description = "Logrotate Service";
      wantedBy = [ "multi-user.target" ];
      startAt = "hourly";
      script = ''
        exec ${pkgs.logrotate}/sbin/logrotate ${configFile}
      '';

      serviceConfig = {
        Restart = "no";
        User = "root";
      };
    };
  };
}
