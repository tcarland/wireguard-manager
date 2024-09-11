#!/usr/bin/env bash
#
# wg-config.sh
PNAME=${0##*\/}
AUTHOR="Timothy C. Arland  <tcarland@gmail.com>"
VERSION="v24.09.11"

addr=
id=
iface=wg0
port=55820
config="${HOME}/.config/wg-mgr.yaml"
pvtkeyfile="${HOME}/.wg_pvt.key"
pubkeyfile="${HOME}/.wg_pub.key"
endpoint=
peerkey=
keepalive=0


usage="
Create or Updates a configuration for use with the Wireguard Manager.

Synopsis:
wg-config.sh [options] <action>

Options:
  -c|--config     <file>   : Path to the yaml config to create or add
  -E|--endpoint   <str>    : Set a peer endpoint when using 'addPeer'
  -i|--interface  <iface>  : Sets the interface to use, default: $iface
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
        iface="$2"
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
    exit 1
fi

# ----------------------------------------

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
  $iface:
    addr: $addr
    port: $port
    privatekeyfile: "$pvtkeyfile"
    publickeyfile: "$pubkeyfile"
EOF
    return 0
}

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
        echo "$PNAME Error, 'create' missing address"
        exit 1
    fi

    if [[ "$iface" =~ '^wg\d+' ]]; then
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
    if [ -z "$iface" ]; then
        echo "$PNAME Error, interface must be provided to addPeer"
        exit 2
    fi

    if [[ -z "$id" || -z "$addr" || -z "$peerkey" ]]; then
        echo "$PNAME Error, 'addPeer' missing arguments"
        exit 2
    fi

    ( yq eval ".wireguard.${iface}.peers.${id} = { \"addr\": \"${addr}\", \"pubkey\": \"${peerkey}\" }" -i $config )
    rt=$?

    if [ -n "$endpoint" ]; then
        ( yq eval ".wireguard.${iface}.peers.${id}.endpoint = $endpoint" -i $config )
    fi

    if [ $keepalive -gt 0 ]; then
        ( yq eval ".wireguard.${iface}.peers.${id}.keepalive = $keepalive" -i $config )
    fi
    
    ( yq eval ".wireguard.${iface}.peers.${id}.default = false" -i $config )
    ( yq eval ".wireguard.${iface}.peers.${id}.allowed_ips = [ \"${addr}/32\" ]" -i $config )

    echo " -> addPeer added client '$id'"
    ;;

createFrom)
    name="$addr"
    peerconfig="wg-mgr-${id}.yaml"
    addr=$(yq -r ".wireguard.${iface}.peers.${id}.addr" $config | awk -F'/' '{ print $1 }')
    peeraddr=$(yq -r ".wireguard.${iface}.addr" $config)
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

    ( yq eval ".wireguard.${iface}.peers.${name} = { \"addr\": \"${peeraddr}\", \"pubkey\": \"${peerkey}\" }" -i $peerconfig )
    rt=$?

    if [ -n "$endpoint" ]; then
        ( yq eval ".wireguard.${iface}.peers.${name}.endpoint = \"$endpoint\"" -i $peerconfig )
    fi

    if [ $keepalive -gt 0 ]; then
        ( yq eval ".wireguard.${iface}.peers.${name}.keepalive = $keepalive" -i $peerconfig )
    fi
    
    ( yq eval ".wireguard.${iface}.peers.${name}.default = false" -i $peerconfig )
    ( yq eval ".wireguard.${iface}.peers.${name}.allowed_ips = [ \"${peeraddr}/32\" ]" -i $peerconfig )
    ;;

*)
    echo "$PNAME Error, action not recognized"
    rt=1
    ;;
esac

exit $rt