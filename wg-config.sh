#!/usr/bin/env bash
#
# wg-config.sh
PNAME=${0##*\/}
AUTHOR="Timothy C. Arland  <tcarland@gmail.com>"
VERSION="v24.09.12"

addr=
id=
net=wg0
port=55820
config="${HOME}/.config/wg-mgr.yaml"
pvtkeyfile="${HOME}/.wg_pvt.key"
pubkeyfile="${HOME}/.wg_pub.key"
endpoint=
peerkey=
keepalive=0

cidr_r="^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[12][0-9]|3[0-2])$"


usage="
Create or Updates a configuration for use with the Wireguard Manager.

Synopsis:
wg-config.sh [options] <action>

Options:
  -c|--config     <file>   : Path to the yaml config to create or add
  -E|--endpoint   <str>    : Set a peer endpoint when using 'addPeer'
  -i|--interface  <net>    : Sets the interface to use, default: $net
  -k|--keepalive  <val>    : Set the peer keepalive value, default: $keepalive
  -p|--port       <val>    : Set the UDP port number, default: $port

Actions:
  create  <ip>             : Create a new config using <ip> as CIDR.
  addPeer <id> <ip> <key>  : Adds a peer object to a config.
  createFrom <peer> <name> : Creates a client wg config from the server
                             <peer> is the name used for the new config
                             <name> is a name reference to the server
                             Note that endpoint should be set for clients.
                             Outputs the new config as ./wg-mgr-<peer>.yaml
"

# ----------------------------------------

add_peer() {
    local wg="$1"
    local name="$2"
    local ip="$3"
    local key="$4"
    local cfg="$5"

    ( yq ".wireguard.${wg}.peers.${name} = \
    { \"addr\": \"${ip}\", \"pubkey\": \"${key}\", \"default\": false }" -i $cfg )
    
    return $?
}

set_endpoint() {
    local wg="$1"
    local name="$2"
    local ep="$3"
    local cfg="$4"

    ( yq ".wireguard.${wg}.peers.${name}.endpoint = \"$ep\"" -i $cfg )
    ( yq '.. style="double"' -i $cfg )
}


set_keepalive() {
    local wg="$1"
    local name="$2"
    local ping="$3"
    local cfg="$4"

    ( yq ".wireguard.${wg}.peers.${name}.keepalive = $ping" -i $cfg )

    return $?
}

set_allowed_ips() {
    local wg="$1"
    local name="$2"
    local ip="$3"
    local cfg="$4"
    
    ( yq ".wireguard.${wg}.peers.${name}.allowed_ips = [ \"${ip}/32\" ]" -i $cfg )

    return $?
}


create_config() {
    local cfg="$1"

    if [ -z "$cfg" ]; then
        return 1
    elif [ -e "$cfg" ]; then
        return 2
    fi

    cat >$cfg <<EOF
---
wireguard:
  $net:
    addr: $addr
    port: $port
    privatekeyfile: "$pvtkeyfile"
    publickeyfile: "$pubkeyfile"
EOF
    return 0
}


# ----------------------------------------
# MAIN
rt=0

while [ $# -gt 0 ]; do
    case "$1" in
    -c|--config)
        config="$2"
        shift
        ;;
    -E|--endpoint)
        endpoint="$2"
        shift
        ;;
    'help'|-h|--help)
        echo "$usage"
        exit 0
        ;;
    -i|--int*)
        net="$2"
        shift
        ;;
    -k|--keepalive)
        keepalive=$2
        shift
        ;;
    -p|--port)
        port=$2
        shift
        ;;
    'version'|-V|--version)
        printf "$PNAME $VERSION \n"
        exit 0
        ;;
    *)
        action="$1"
        id="$2"
        addr="$3"
        peerkey="$4"
        shift $#
        ;;
    esac
    shift
done

if ! which yq >/dev/null 2>&1; then
    echo "$PNAME Error, 'yq' is required but not found in path."
    echo "The golang 'yq' is preferred: https://github.com/mikefarah/yq"
    exit 1
fi

if [ -z "$action" ]; then
    echo "$PNAME Error, action not provided"
    echo ""
    echo "$usage"
    exit 1
fi

# ----------------------------------------

case "$action" in

## CREATE NEW CONFIG
'create')
    addr="$id"

    if [ -e $config ]; then
        echo "$PNAME Error, config file already exists: '$config'"
        exit 1
    fi
    if [[ -z "$addr" ]]; then
        echo "$PNAME Error, 'create' requires CIDR Address"
        exit 1
    fi 
    if [[ ! $addr =~ $cidr_r ]]; then
        echo "$PNAME Error, address '$addr' must be a valid CIDR Address"
        exit 2
    fi
    if [[ "$net" =~ '^wg\d+' ]]; then
        echo "$PNAME Error, interface must follow wgX naming convention"
        exit 2
    fi

    create_config "$config"
    rt=$?

    if [ $rt -ne 0 ]; then
        echo "$PNAME Error in create_config()"
    else
        echo " -> created config '$config'"
    fi

    ;;

## ADD PEER
addPeer)
    name="$id"

    if [ -z "$net" ]; then
        echo "$PNAME Error, interface must be provided to addPeer"
        exit 2
    fi
    if [[ -z "$name" || -z "$addr" || -z "$peerkey" ]]; then
        echo "$PNAME Error, 'addPeer' missing arguments"
        exit 2
    fi

    add_peer "$net" "$name" "$addr" "$peerkey" "$config"
    rt=$?

    if [ $rt -ne 0 ]; then
        echo "$PNAME Error in addPeer for '$name'"
        exit $rt
    fi

    if [ -n "$endpoint" ]; then
        set_endpoint "$net" "$name" "$endpoint" "$config"
    fi
    if [ $keepalive -gt 0 ]; then
        set_keepalive "$net" "$name" "$keepalive" "$config"
    fi

    set_allowed_ips "$net" "$name" "$addr" "$config" 

    echo " -> addPeer added client '$name'"
    ;;

## CREATE PEER FROM CONFIG
createFrom)
    name="$addr"
    peerconfig="wg-mgr-${id}.yaml"
    addr=$(yq -r ".wireguard.${net}.peers.${id}.addr" $config | awk -F'/' '{ print $1 }')
    peeraddr=$(yq -r ".wireguard.${net}.addr" $config)
    peerkey=$(cat $pubkeyfile 2>/dev/null)

    if [ -e "$peerconfig" ]; then
        echo "$PNAME Error, peer config '$peerconfig' already exists"
        exit 1
    fi
    if [ -z "$name" ]; then
        echo "$PNAME Error, server name must be provided with 'createFrom'"
        exit 2
    fi
    if [[ -z "$addr" || "$addr" == "null" ]]; then
        echo "$PNAME Error determining config addr"
        exit 3
    fi
    if [[ -z "$peeraddr" || "$peeraddr" == "null" ]]; then
        echo "$PNAME Error determining the peer address from '$config' for $id"
        exit 3
    fi
    if [[ -z "$peerkey" ]]; then
        echo "$PNAME Error obtaining pubkey from '$pubkeyfile'"
        exit 3
    fi

    echo " -> createFrom: creating config '$peerconfig' using peer '$id'"

    create_config "$peerconfig"

    add_peer "$net" "$name" "$peeraddr" "$peerkey" "$peerconfig"
    rt=$?

    if [ $rt -ne 0 ]; then
        echo "$PNAME Error in addPeer for '$name'"
        exit $rt
    fi

    if [ -n "$endpoint" ]; then
        set_endpoint "$net" "$name" "$endpoint" "$peerconfig"
    fi
    if [ $keepalive -gt 0 ]; then
        set_keepalive "$net" "$name" "$keepalive" "$peerconfig"
    fi

    set_allowed_ips "$net" "$name" "$peeraddr" "$peerconfig" 
    ;;

*)
    echo "$PNAME Error, action not recognized"
    rt=1
    ;;
esac

exit $rt