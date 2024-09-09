#!/usr/bin/env bash
#
# wg-config.sh
PNAME=${0##*\/}
AUTHOR="Timothy C. Arland  <tcarland@gmail.com>"
VERSION="v24.09.09"

addr=
iface=
port=55820
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
  -a|--addr   <addr>        : The iface or peer IP Address
  -c|--config <file>        : Path to the yaml config to create or add
  -E|--endpoint <host:port> : Set a peer endpoint when using 'addPeer'
  -i|--interface <iface>    : Sets the interface to create or add to.
  -k|--keepalive <val>      : Set the peer keepalive value (default: 0)

Actions:
  create                    : Creates a new yaml config
  addPeer <name> <key>      : Adds a peer object to a config
"



# ----------------------------------------
# MAIN
rt=0

if [ -f /etc/${configname} ]; then
    config="/etc/${config}"
    echo "$PNAME using system config '$config'"
fi

while [ $# -gt 0 ]; do
    case "$1" in
    -a|--addr)
        addr="$2"
        shift
        ;;
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
        name="$2"
        peerkey="$3"
        shift $#
        ;;
    esac
    shift
done


if [ -z "$action" ]; then
    echo "$PNAME Error, action not provided"
    exit 1
fi

if [ -z "$config" ]; then
    echo "$PNAME Error, config file not provided"
    exit 1
fi

case "$action" in

'create')
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

    cat >$config <<EOF
---
wireguard:
  $iface:
    addr: $addr
    port: $port
    privatekeyfile: "$pvtkeyfile"
    publickeyfile: "$pubkeyfile"
EOF

    echo "$PNAME created config '$config'"
    ;;

addPeer)
    if [ -z "$iface" ]; then
        echo "$PNAME Error, interface must be provided to addPeer"
        exit 2
    fi
    if [[ -z "$addr" || -z "$peerkey" ]]; then
        echo "$PNAME Error, 'addPeer' missing arguments"
        exit 2
    fi
    echo "foo"
    ( yq eval ".wireguard.${iface}.peers.$name = { \"addr\": \"$addr\", \"pubkey\": \"$peerkey\" }" -i $config )

    if [ -n "$endpoint" ]; then
        ( yq eval ".wireguard.${iface}.peers.$name.endpoint = $endpoint" -i $config )
    fi
    if [ $keepalive -gt 0 ]; then
        ( yq eval ".wireguard.${iface}.peers.$name.keepalive = $keepalive" -i $config )
    fi
    
    ( yq eval ".wireguard.${iface}.peers.$name.default = false" -i $config )
    ( yq eval ".wireguard.${iface}.peers.$name.allowed_ips = [ \"${addr}/32\" ]" -i $config )

    echo "$PNAME added peer config for '$name'"
    ;;

*)
    echo "$PNAME Error, action not recognized"
    rt=1
    ;;
esac

exit $rt