#!/usr/bin/env bash
#  
# A script to wrap and automate Wireguard functionality.
#
pname=${0##\/*}
version="v24.09.09"

config="${WG_MGR_CONFIG:-${HOME}/.config/wg-mgr.yaml}"
default_pubfile="${HOME}/.wg_pub.key"
default_pvtfile="${HOME}/.wg_pvt.key"

action=
tun=
arg=

yaml_schema="
## NOTES
# 'endpoint' is optional for client-side configs.
# 'allowed-ips' is optional and should not overlap across peers. 
#   defaults to the peer 'addr'/32
#   use 0.0.0.0/0 on client-side only for closed tunnel
# set 'default' to 'true' to add default route (clients only)
# set 'keepalive' to a positive value for client / nat situations
---
wireguard:
  wg0:
    addr: "10.200.8.1/24"
    port: "55820"
    privatekeyfile: "/root/.wg_pvt.key"
    publickeyfile: "/root/.wg_pub.key"

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
$pname [options] <action> [interface]

Options:
  -C|--create <yaml>  : Create base yaml config from template.
  -f|--file   <yaml>  : Path to yaml config file, 
                         default is '$config'
  -h|--help           : Show usage info and exit.
  -V|--version        : Show version info and exit.

  <action>            : Script action, require
   up                 : Enables wg interfaces as defined by the config.
   down               : Disables wg interfaces.
   genkey <pub> <pvt> : Generate a Wireguard key pair. Optionally takes
                         two file arguments, or uses the default locations 
                         of  '$default_pubkey' 
                         and '$default_pvtkey'

  [interface]         : Run action on the given interface only (optional).

 The yaml configuration can be set via \$WG_MGR_CONFIG to override
 the default location of '$config'.
"

# ---

function wg_gen_key() {
    pubfile="$1"
    pvtfile="$2"

    ( wg genkey | tee "$pvtfile" | wg pubkey > "$pubfile" )

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
    'help'|-h|--help)
        echo "$usage"
        exit 0
        ;;
    'version'|-V|--version)
        printf "${pname} $version \n"
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
    echo "$pname Error, Wireguard not found in path or not installed."
    exit 1
fi
if ! which yq >/dev/null 2>&1; then
    echo "$pname Error, yq is required but not found in path."
    echo "The golang yq is preferred: https://github.com/mikefarah/yq"
    exit 1
fi

# GENKEY
if [ "$action" == "genkey" ]; then
    pubfile="${tun:-${default_pubfile}}"
    pvtfile="${arg:-${default_pvtfile}}"

    if [ -e $pvtfile ]; then
        echo "$pname Error, key file already exists: '$pvtfile"
        exit 3
    fi

    ( wg genkey | tee $pvtfile | wg pubkey > $pubfile )

    if [ $? -ne 0 ]; then
        echo "$pname Error creating keypair"
        exit 3
    fi
    
    echo " -> Public Key: "
    cat $pubfile
    exit $?
fi

if [[ ! "$action" =~ ^(up|down)$ ]]; then
    echo "$pname Error: Action unrecognized: '$action'"
    exit 2
fi
  
if [[ ! -r "$config" ]]; then
    echo "$pname Error: Unable to read config $config"
    exit 1
fi

tunnels=$(yq -r '.wireguard | keys | .[]' ${config})
if [ -z "$tunnels" ]; then
    echo "$pname Error: No wireguard interfaces defined"
fi

for wg in $tunnels; do
    if [[ -n "$tun" && "$tun" != "$wg" ]]; then
        continue
    fi

    echo " -> Interface: $wg : $action"

    addr=$(yq -r ".wireguard.${wg}.addr" $config)
    port=$(yq -r ".wireguard.${wg}.port" $config)
    pvt=$(yq -r ".wireguard.${wg}.privatekeyfile" $config)
    pub=$(yq -r ".wireguard.${wg}.publickeyfile" $config)
    peers=$(yq -r ".wireguard.${wg}.peers | keys | .[]" $config)

    if [ "$action" == "down" ]; then
        ( ip link set $wg down )
        ( ip link del $wg )
        continue
    fi

    if [[ ! -e $pvt || ! -e $pub  ]]; then 
        echo "$pname Error in key pair, file(s) not found"
        break
    fi


    ( ip link add dev $wg type wireguard )
    ( ip address add dev $wg $addr )
    ( wg set $wg listen-port $port private-key $pvt )
    ( ip link set $wg up )


    for peer in $peers; do
        addr=$(yq -r ".wireguard.${wg}.peers.${peer}.addr" $config | awk -F'/' '{ print $1 }')
        peerkey=$(yq -r ".wireguard.${wg}.peers.${peer}.pubkey" $config)
        endpoint=$(yq -r ".wireguard.${wg}.peers.${peer}.endpoint" $config)
        default=$(yq -r ".wireguard.${wg}.peers.${peer}.default" $config)
        ping=$(yq -r ".wireguard.${wg}.peers.${peer}.keepalive" $config)
        ips=$(yq -r ".wireguard.${wg}.peers.${peer}.allowed_ips | .[]" $config | tr '\n' ',' | sed 's/,$//' )
        routes=$(yq -r ".wireguard.${wg}.peers.${peer}.routes | .[]" $config | tr '\n' ',' | sed 's/,$//' )
        
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
        wg set $wg ${args[@]}

        if [ $? -ne 0 ]; then 
            echo "$pname Error, Wireguard $wg failure to set peer $peer"
            continue
        fi

        for route in $routes; do 
            echo " -> ip route $route via $addr dev $wg"
            ( ip route add $route via $addr dev $wg )
        done

        if [[ "${default,,}" == "true"]]; then
            ( ip route add default via $addr dev $wg )
        fi
    done
done

exit 0

