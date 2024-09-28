#!/usr/bin/env bash
#  
# A script to wrap and automate Wireguard functionality.
#
PNAME=${0##\/*}
AUTHOR="Timothy C. Arland  <tcarland@gmail.com>"
VERSION="v24.09.25"

config="${WG_MGR_CONFIG:-${HOME}/.config/wg-mgr.yaml}"
default_pubfile="${WG_MGR_PUBKEY:-${HOME}/.wg_pub.key}"
default_pvtfile="${WG_MGR_PVTKEY:-${HOME}/.wg_pvt.key}"
default_pskfile="${WG_MGR_PSK:-${HOME}/.wg_psk.key}"

action=
tun=
arg=
nat=

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
  -C|--create <yaml>  : Create base yaml config from template.
  -f|--file   <yaml>  : Path to yaml config file, 
                         default is '$config'
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
   genpsk  <pskfile>  : Creates PreShared Key file, default as '$default_pskfile'

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

    ( wg genkey | tee "$pvtfile" | wg pubkey > "$pubfile" )
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
        echo " -> enable ip_forwarding"
        ( sh -c "echo '1' > $ipf" ) 2>/dev/null
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
    echo "$PNAME Error, Wireguard not found in path or not installed."
    exit 1
fi

if ! which yq >/dev/null 2>&1; then
    echo "$PNAME Error, 'yq' is required but not found in path."
    echo "The golang 'yq' is preferred: https://github.com/mikefarah/yq"
    exit 1
fi

# -------
# GENKEY
if [ "$action" == "genkey" ]; then
    pubfile="${tun:-${default_pubfile}}"
    pvtfile="${arg:-${default_pvtfile}}"

    if [ -e $pvtfile ]; then
        echo "$PNAME Error, key file already exists: '$pvtfile"
        exit 3
    fi

    ( wg genkey | tee $pvtfile | wg pubkey > $pubfile )

    if [ $? -ne 0 ]; then
        echo "$PNAME Error creating keypair"
        exit 3
    fi
    
    echo " -> Public Key: "
    cat $pubfile
    exit $?
elif [ "$action" == "genpsk" ]; then
    pskfile="${tun:-${default_pskfile}}"

    if [ -e $pskfile ]; then
        echo "$PNAME Error, psk file already exists: '$pskfile'"
        exit 3
    fi

    ( wg genpsk > $pskfile )
    exit $?
fi

if [[ ! "$action" =~ ^(up|down)$ ]]; then
    echo "$PNAME Error: Action unrecognized: '$action'"
    exit 2
fi
  
if [[ ! -r "$config" ]]; then
    echo "$PNAME Error: Unable to read config $config"
    exit 1
fi

# ----------------------------------------

tunnels=$(yq -r '.wireguard | keys | .[]' ${config})

if [ -z "$tunnels" ]; then
    echo "$PNAME Error: No wireguard interfaces defined"
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

    if [ "$action" == "down" ]; then
        ( ip link set $wg down )
        ( ip link del $wg )
        continue
    fi

    if [[ ! -e $pvt || ! -e $pub  ]]; then 
        echo "$PNAME Error in key pair, file(s) not found"
        break
    fi

    ( ip link add dev $wg type wireguard )
    ( ip address add dev $wg $addr )
    ( wg set $wg listen-port $port private-key $pvt )
    ( ip link set $wg up )

    if [ $? -ne 0 ]; then 
        echo "$PNAME Error configuring link for $wg"
        exit 2
    fi

    if [[ -e $pskfile ]]; then
        ( wg set $wg pre-shared-key $pskfile )
    fi

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
            echo "$PNAME Error, Wireguard $wg failure to set peer $peer"
            continue
        fi

        for route in $routes; do 
            echo " -> ip route $route via $addr dev $wg"
            ( ip route add $route via $addr dev $wg )
        done

        if [[ "${default,,}" == "true" ]]; then
            ( ip route add default via $addr dev $wg )
        fi
    done
done

if [ -n "$nat" ]; then
    if ! which iptables >/dev/null 2>&1; then
        echo "$PNAME Warning, 'iptables' not found in PATH, not setting NAT rules"
    elif is_netif "$nat"; then
        if [ "$action" == "down" ]; then
            ( iptables -D POSTROUTING -t nat -o $nat -j MASQUERADE )
        else
            ( iptables -A POSTROUTING -t nat -o $nat -j MASQUERADE )
            ip_fowarding "1"
        fi
        if [ $? -ne 0 ]; then
            echo "$PNAME Warning, NAT setting failed"
        fi
    else
        echo "$PNAME Warning, interface '$nat' does not appear valid."
    fi
fi 

exit 0

