#!/usr/bin/env bash
#
# A script to wrap and automate Wireguard functionality.
#
PNAME=${0##\/*}
AUTHOR="Timothy C. Arland <tcarland@gmail.com>"
VERSION="v26.02.20"

config="${WG_MGR_CONFIG:-${HOME}/.config/wg-mgr.yaml}"
default_pubfile="${WG_MGR_PUBKEY:-${HOME}/.wg_pub.key}"
default_pvtfile="${WG_MGR_PVTKEY:-${HOME}/.wg_pvt.key}"
default_pskfile="${WG_MGR_PSK:-${HOME}/.wg_psk.key}"

action=
tun=
arg=
nat=
uid=${UID}

wgcmd="wg"
ipcmd="ip"
shcmd="sh"
iptcmd="iptables"

yaml_schema="
## NOTES
# 'endpoint'    is optional for client-side configs.
# 'allowed-ips' is optional and should not overlap across peers.
#               defaults to the peer 'ipaddr'/32
# use a default route on client-side for a closed tunnel.
# set 'default' to 'true' to add default route (clients only)
# set 'keepalive' to a positive value for client NAT situations.
---
wireguard:
  wg0:
    addr: "10.200.8.1/24"
    port: "55820"
    privatekeyfile: "/root/.wg_pvt.key"
    publickeyfile: "/root/.wg_pub.key"
    presharedkeyfile: "/root/.wg_psk.key"

    peers:
      host1:
        addr: "10.200.8.2"
        pubkey: "somepubkey"
        endpoint: "remoteip:port"
        keepalive: 0
        default: false
        allowed_ips:
          - "10.200.8.2/32"
          - "172.18.0.0/24"
        routes:
          - "172.18.0.0/24"
"

usage="
A script for initializing, starting and stopping Wireguard tunnels
based on pre-defined YAML configuration.

Synopsis:
$PNAME [options] <action> [interface]

Options:
  -C|--create <yaml>  : Create a base yaml config from the template.
  -f|--file   <yaml>  : Yaml config path, default is '$config'
  -N|--nat   <extif>  : Enable/Disable NAT for traffic leaving <extif>
  -h|--help           : Show usage info and exit.
  -V|--version        : Show version info and exit.

  <action>            : Script action, require
   up                 : Enables wg interfaces as defined by the config.
   down               : Disables wg interfaces.
   genkey <pub> <pvt> : Generate a Wireguard key pair. Optionally takes
                        two file arguments, or uses the default locations
                          of  '$default_pubfile'
                          and '$default_pvtfile'
   genpsk  <pskfile>  : Create PreShared Key file, default '$default_pskfile'
   status             : Shows the current wg config and device info.

  [interface]         : Run action on the given interface only (optional).

 The yaml config location can be set via \$WG_MGR_CONFIG to override the
 default of '$config'.
 The default key pair can be set via \$WG_MGR_PUBKEY and \$WG_MGR_PVTKEY
 as well as \$WG_MGR_PSK for using a preshared key.
"

# ---

wg_gen_key() {
    local pubfile="$1"
    local pvtfile="$2"

    ( ${wgcmd} genkey | tee "$pvtfile" | wg pubkey > "$pubfile" )
    ( chmod 400 $pvtfile $pubfile )

    return $?
}


is_netif() {
    local eif="$1"
    ( ip link list $eif >/dev/null 2>&1 )
    return $?
}


ip_forwarding()
{
    local enable=$1
    local ipf="/proc/sys/net/ipv4/ip_forward"

    if [ -z "$enable" ]; then
        ( cat $ipf )
    elif [ $(cat $ipf) -ne 1 ]; then
        echo " -> Enable ip_forwarding"
        ( ${shcmd} -c "echo '1' > $ipf" ) 2>/dev/null
    fi

    return $?
}


## MAIN
# ---

while [ $# -gt 0 ]; do
    case "$1" in
    -C|--create)
        config="$2"
        echo "${yaml_schema}" > $config
        exit $?
        ;;
    -f|--file|--config)
        config="$2"
        shift
        ;;
    -n|--NAT|--nat)
        nat="$2"
        shift
        ;;
    'help'|-h|--help)
        echo "$usage"
        exit 0
        ;;
    'version'|-V|--version)
        printf "${PNAME} $VERSION \n"
        exit 0
        ;;
    *)
        action="${1,,}"
        tun="${2}"
        arg="${3}"
        shift $#
        ;;
    esac
    shift
done

if [ -z "$action" ]; then
    echo "$usage"
    exit 0
fi

if ! which wg >/dev/null 2>&1; then
    echo "$PNAME Error, Wireguard not found in path or not installed." >&2
    exit 1
fi

if ! which yq >/dev/null 2>&1; then
    echo "$PNAME Error, 'yq' is required but not found in path." >&2
    echo "The golang 'yq' is needed: https://github.com/mikefarah/yq" >&2
    exit 1
fi

if [ ${UID} -gt 0 ]; then
    wgcmd="sudo $wgcmd"
    ipcmd="sudo $ipcmd"
    shcmd="sudo $shcmd"
    iptcmd="sudo $iptcmd"
fi

rt=0

case "$action" in
# GENKEY
'genkey')
    pubfile="${tun:-${default_pubfile}}"
    pvtfile="${arg:-${default_pvtfile}}"

    if [ -e $pvtfile ]; then
        echo "$PNAME Error, key file already exists: '$pvtfile" >&2
        rt=3
        break
    fi

    ( $wgcmd genkey | tee $pvtfile | $wgcmd pubkey > $pubfile )

    rt=$?
    if [ $rt -ne 0 ]; then
        echo "$PNAME Error running 'genkey'" >&2
        break
    fi

    echo " -> Public Key: "
    cat $pubfile
    ;;

# GENPSK
'genpsk')
    pskfile="${tun:-${default_pskfile}}"

    if [ -e $pskfile ]; then
        echo "$PNAME Error, psk file already exists: '$pskfile'" >&2
        rt=3
        break
    fi

    ( $wgcmd genpsk > $pskfile )
    rt=$?
    ;;

# SHOW STATUS
'status'|'show'|'ls')
    ( sudo wg show )
    rt=$?
    ;;

# INTERFACE UP|DOWN
'up'|'start'|'down'|'stop')
    if [[ ! -r "$config" ]]; then
        echo "$PNAME Error: Unable to read config $config" >&2
        rt=1
        break
    fi

    tunnels=$(yq -r '.wireguard | keys | .[]' ${config})

    if [ -z "$tunnels" ]; then
        echo "$PNAME Error: No wireguard interfaces defined" >&2
        rt=1
        break
    fi

    for wg in $tunnels; do
        if [[ -n "$tun" && "$tun" != "$wg" ]]; then
            continue
        fi

        echo " -> Interface: $wg : $action"

        addr=$(yq -r ".wireguard.${wg}.addr" $config)
        port=$(yq -r ".wireguard.${wg}.port" $config)
        pub=$(yq -r ".wireguard.${wg}.publickeyfile" $config)
        pvt=$(yq -r ".wireguard.${wg}.privatekeyfile" $config)
        psk=$(yq -r ".wireguard.${wg}.presharedkeyfile" $config)
        peers=$(yq -r ".wireguard.${wg}.peers | keys | .[]" $config)

        if [[ "$action" == "down" || "$action" == "stop" ]]; then
            ( $ipcmd link set $wg down )
            ( $ipcmd link del $wg )
            continue
        fi

        if [[ ! -e $pvt || ! -e $pub  ]]; then
            echo "$PNAME Error in key pair, file(s) not found" >&2
            rt=2
            break
        fi

        ( $ipcmd link add dev $wg type wireguard 2>/dev/null )
        ( $ipcmd address add dev $wg $addr 2>/dev/null )
        ( $wgcmd set $wg listen-port $port private-key $pvt )
        ( $ipcmd link set $wg up )

        if [ $? -ne 0 ]; then
            echo "$PNAME Error configuring link for $wg" >&2
            rt=2
            break
        fi

        if [[ -e $pskfile ]]; then
            ( $wgcmd set $wg pre-shared-key $pskfile )
        fi

        for peer in $peers; do
            addr=$(yq -r ".wireguard.${wg}.peers.${peer}.addr" $config | awk -F'/' '{ print $1 }')
            peerkey=$(yq -r ".wireguard.${wg}.peers.${peer}.pubkey" $config)
            endpoint=$(yq -r ".wireguard.${wg}.peers.${peer}.endpoint" $config)
            default=$(yq -r ".wireguard.${wg}.peers.${peer}.default" $config)
            ping=$(yq -r ".wireguard.${wg}.peers.${peer}.keepalive" $config)
            ips=$(yq -r ".wireguard.${wg}.peers.${peer}.allowed_ips | .[]" $config | tr '\n' ',' | sed 's/,$//' )
            routes=$(yq -r ".wireguard.${wg}.peers.${peer}.routes | .[]" $config | tr '\n' ' ' | sed 's/ $//' )

            args=("peer" "$peerkey")

            # optional endpoint
            if [[ "$endpoint" != "null" ]]; then
                args+=("endpoint" "$endpoint")
            fi

            # optional keepalive
            if [[ "$ping" != "null" ]]; then
                args+=("persistent-keepalive" "$ping")
            fi

            # default allowed-ips to peer addr and routes
            if [[ -z "$ips" || "$ips" == "null" ]]; then
                ips="${addr}/32"
                for route in $routes; do
                    ips="${ips},${route}"
                done
            fi
            args+=("allowed-ips" "$ips")

            echo " -> wg set $wg ${args[@]}"
            $wgcmd set $wg ${args[@]}

            if [ $? -ne 0 ]; then
                echo "$PNAME Error, Wireguard $wg failure to set peer $peer" >&2
                continue
            fi

            for route in $routes; do
                echo " -> ip route $route via $addr dev $wg"
                ( $ipcmd route add $route via $addr dev $wg 2>/dev/null )
            done

            if [[ "${default,,}" == "true" ]]; then
                ( $ipcmd route add default via $addr dev $wg 2>/dev/null )
            fi
        done
    done

    if [ -n "$nat" ]; then
        if ! which iptables >/dev/null 2>&1; then
            echo "$PNAME Warning, 'iptables' not found in PATH, not setting NAT rules" >&2
        elif is_netif "$nat"; then
            if [ "$action" == "down" ]; then
                ( $iptcmd -D POSTROUTING -t nat -o $nat -j MASQUERADE )
            else
                ( $iptcmd -A POSTROUTING -t nat -o $nat -j MASQUERADE )
                ip_fowarding "1"
            fi
            rt=$?
            if [ $rt -ne 0 ]; then
                echo "$PNAME Warning, NAT setting failed" >&2
            fi
        else
            echo "$PNAME Warning, interface '$nat' does not appear valid." >&2
            rt=1
        fi
    fi
    ;;

# DEFAULT
*)
    if [[ ! "$action" =~ ^(up|down)$ ]]; then
        echo "$PNAME Error: Action unrecognized: '$action'" >&2
        rt=1
    fi
    ;;
esac

exit $rt
