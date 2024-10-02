{ config, lib, pkgs, ... }:
let

  pkg = pkgs.cjdns;

  cfg = config.services.cjdns;

  connectToSubmodule =
  { ... }:
  { options =
    { password = lib.mkOption {
        type = lib.types.str;
        description = "Authorized password to the opposite end of the tunnel.";
      };
      login = lib.mkOption {
        default = "";
        type = lib.types.str;
        description = "(optional) name your peer has for you";
      };
      peerName = lib.mkOption {
        default = "";
        type = lib.types.str;
        description = "(optional) human-readable name for peer";
      };
      publicKey = lib.mkOption {
        type = lib.types.str;
        description = "Public key at the opposite end of the tunnel.";
      };
      hostname = lib.mkOption {
        default = "";
        example = "foobar.hype";
        type = lib.types.str;
        description = "Optional hostname to add to /etc/hosts; prevents reverse lookup failures.";
      };
    };
  };

  # Additional /etc/hosts entries for peers with an associated hostname
  cjdnsExtraHosts = pkgs.runCommand "cjdns-hosts" {} ''
    exec >$out
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v:
        lib.optionalString (v.hostname != "")
          "echo $(${pkgs.cjdns}/bin/publictoip6 ${v.publicKey}) ${v.hostname}")
        (cfg.ETHInterface.connectTo // cfg.UDPInterface.connectTo))}
  '';

  parseModules = x:
    x // { connectTo = lib.mapAttrs (name: value: { inherit (value) password publicKey; }) x.connectTo; };

  cjdrouteConf = builtins.toJSON ( lib.recursiveUpdate {
    admin = {
      bind = cfg.admin.bind;
      password = "@CJDNS_ADMIN_PASSWORD@";
    };
    authorizedPasswords = map (p: { password = p; }) cfg.authorizedPasswords;
    interfaces = {
      ETHInterface = if (cfg.ETHInterface.bind != "") then [ (parseModules cfg.ETHInterface) ] else [ ];
      UDPInterface = if (cfg.UDPInterface.bind != "") then [ (parseModules cfg.UDPInterface) ] else [ ];
    };

    privateKey = "@CJDNS_PRIVATE_KEY@";

    resetAfterInactivitySeconds = 100;

    router = {
      interface = { type = "TUNInterface"; };
      ipTunnel = {
        allowedConnections = [];
        outgoingConnections = [];
      };
    };

    security = [ { exemptAngel = 1; setuser = "nobody"; } ];

  } cfg.extraConfig);

in

{
  options = {

    services.cjdns = {

      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to enable the cjdns network encryption
          and routing engine. A file at /etc/cjdns.keys will
          be created if it does not exist to contain a random
          secret key that your IPv6 address will be derived from.
        '';
      };

      extraConfig = lib.mkOption {
        type = lib.types.attrs;
        default = {};
        example = { router.interface.tunDevice = "tun10"; };
        description = ''
          Extra configuration, given as attrs, that will be merged recursively
          with the rest of the JSON generated by this module, at the root node.
        '';
      };

      confFile = lib.mkOption {
        type = lib.types.nullOr lib.types.path;
        default = null;
        example = "/etc/cjdroute.conf";
        description = ''
          Ignore all other cjdns options and load configuration from this file.
        '';
      };

      authorizedPasswords = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [
          "snyrfgkqsc98qh1y4s5hbu0j57xw5s0"
          "z9md3t4p45mfrjzdjurxn4wuj0d8swv"
          "49275fut6tmzu354pq70sr5b95qq0vj"
        ];
        description = ''
          Any remote cjdns nodes that offer these passwords on
          connection will be allowed to route through this node.
        '';
      };

      admin = {
        bind = lib.mkOption {
          type = lib.types.str;
          default = "127.0.0.1:11234";
          description = ''
            Bind the administration port to this address and port.
          '';
        };
      };

      UDPInterface = {
        bind = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "192.168.1.32:43211";
          description = ''
            Address and port to bind UDP tunnels to.
          '';
         };
        connectTo = lib.mkOption {
          type = lib.types.attrsOf ( lib.types.submodule ( connectToSubmodule ) );
          default = { };
          example = lib.literalExpression ''
            {
              "192.168.1.1:27313" = {
                hostname = "homer.hype";
                password = "5kG15EfpdcKNX3f2GSQ0H1HC7yIfxoCoImnO5FHM";
                publicKey = "371zpkgs8ss387tmr81q04mp0hg1skb51hw34vk1cq644mjqhup0.k";
              };
            }
          '';
          description = ''
            Credentials for making UDP tunnels.
          '';
        };
      };

      ETHInterface = {
        bind = lib.mkOption {
          type = lib.types.str;
          default = "";
          example = "eth0";
          description = ''
              Bind to this device for native ethernet operation.
              `all` is a pseudo-name which will try to connect to all devices.
            '';
        };

        beacon = lib.mkOption {
          type = lib.types.int;
          default = 2;
          description = ''
            Auto-connect to other cjdns nodes on the same network.
            Options:
              0: Disabled.
              1: Accept beacons, this will cause cjdns to accept incoming
                 beacon messages and try connecting to the sender.
              2: Accept and send beacons, this will cause cjdns to broadcast
                 messages on the local network which contain a randomly
                 generated per-session password, other nodes which have this
                 set to 1 or 2 will hear the beacon messages and connect
                 automatically.
          '';
        };

        connectTo = lib.mkOption {
          type = lib.types.attrsOf ( lib.types.submodule ( connectToSubmodule ) );
          default = { };
          example = lib.literalExpression ''
            {
              "01:02:03:04:05:06" = {
                hostname = "homer.hype";
                password = "5kG15EfpdcKNX3f2GSQ0H1HC7yIfxoCoImnO5FHM";
                publicKey = "371zpkgs8ss387tmr81q04mp0hg1skb51hw34vk1cq644mjqhup0.k";
              };
            }
          '';
          description = ''
            Credentials for connecting look similar to UDP credientials
            except they begin with the mac address.
          '';
        };
      };

      addExtraHosts = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to add cjdns peers with an associated hostname to
          {file}`/etc/hosts`.  Beware that enabling this
          incurs heavy eval-time costs.
        '';
      };

    };

  };

  config = lib.mkIf cfg.enable {

    boot.kernelModules = [ "tun" ];

    # networking.firewall.allowedUDPPorts = ...

    systemd.services.cjdns = {
      description = "cjdns: routing engine designed for security, scalability, speed and ease of use";
      wantedBy = [ "multi-user.target" "sleep.target"];
      after = [ "network-online.target" ];
      bindsTo = [ "network-online.target" ];

      preStart = lib.optionalString (cfg.confFile == null) ''
        [ -e /etc/cjdns.keys ] && source /etc/cjdns.keys

        if [ -z "$CJDNS_PRIVATE_KEY" ]; then
            shopt -s lastpipe
            ${pkg}/bin/makekeys | { read private ipv6 public; }

            install -m 600 <(echo "CJDNS_PRIVATE_KEY=$private") /etc/cjdns.keys
            install -m 444 <(echo -e "CJDNS_IPV6=$ipv6\nCJDNS_PUBLIC_KEY=$public") /etc/cjdns.public
        fi

        if [ -z "$CJDNS_ADMIN_PASSWORD" ]; then
            echo "CJDNS_ADMIN_PASSWORD=$(tr -dc A-Za-z0-9 </dev/urandom | head -c 32)" \
                >> /etc/cjdns.keys
        fi
      '';

      script = (
        if cfg.confFile != null then "${pkg}/bin/cjdroute < ${cfg.confFile}" else
          ''
            source /etc/cjdns.keys
            (cat <<'EOF'
            ${cjdrouteConf}
            EOF
            ) | sed \
                -e "s/@CJDNS_ADMIN_PASSWORD@/$CJDNS_ADMIN_PASSWORD/g" \
                -e "s/@CJDNS_PRIVATE_KEY@/$CJDNS_PRIVATE_KEY/g" \
                | ${pkg}/bin/cjdroute
         ''
      );

      startLimitIntervalSec = 0;
      serviceConfig = {
        Type = "forking";
        Restart = "always";
        RestartSec = 1;
        CapabilityBoundingSet = "CAP_NET_ADMIN CAP_NET_RAW CAP_SETUID";
        ProtectSystem = true;
        # Doesn't work on i686, causing service to fail
        MemoryDenyWriteExecute = !pkgs.stdenv.hostPlatform.isi686;
        ProtectHome = true;
        PrivateTmp = true;
      };
    };

    networking.hostFiles = lib.mkIf cfg.addExtraHosts [ cjdnsExtraHosts ];

    assertions = [
      { assertion = ( cfg.ETHInterface.bind != "" || cfg.UDPInterface.bind != "" || cfg.confFile != null );
        message = "Neither cjdns.ETHInterface.bind nor cjdns.UDPInterface.bind defined.";
      }
      { assertion = config.networking.enableIPv6;
        message = "networking.enableIPv6 must be enabled for CJDNS to work";
      }
    ];

  };

}
