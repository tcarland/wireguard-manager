Wireguard Manager
=================

A tool wrapping the Wireguard CLI for creating and managing 
Wireguard tunnels.

Why the wrapper?   

Wireguard tunnels are easy to create and the CLI easily scriptable. 
This wrapper defines a declaritive configuration (yaml) to represent 
wireguard tunnels. This allows for defining more complex meshes
and automation of wireguard tunnels in a clean and consistent manner.


# Configuration

The script uses a YAML Configuration to define a host configuration 
with the following schema:
```yaml
---
wireguard:
  wg0:
    addr: 10.200.8.1/24
    port: 55820
    privatekeyfile: "/root/.wg_pvt.key"
    publickeyfile: "/root/.wg_pub.key"

    peers:
      host1:
        addr: 10.200.8.2
        pubkey: "somepubkey"
        endpoint: "remoteip:port"
        keepalive: 0
        default: false
        allowed_ips:
          - 10.200.8.2/32
          - 172.18.0.0/24
        routes:
          - 172.18.0.0/24
```

An initial configuration can be created using the *wg-config.sh* script.
The script also supports adding a peer to an existing config.
```sh
$ wg-config.sh -a 10.0.0.1/24 -p 55820 -i wg0 -c hostcfg.yaml create
wg-config.sh created config 'hostcfg2.yaml'

$ wg-config.sh -a 10.0.0.2 -i wg0 -c hostcfg.yaml addPeer mypeer mypeerpublickey
wg-config.sh added peer config for 'mypeer'

$ cat hostcfg.yaml
---
wireguard:
  wg0:
    addr: 10.0.0.1/24
    port: 55820
    privatekeyfile: "/home/tca/.wg_pvt.key"
    publickeyfile: "/home/tca/.wg_pub.key"
    peers:
      mypeer:
        addr: 10.0.0.2
        pubkey: mypeerpublickey
        allowed_ips:
          - 10.0.0.2/32
```
