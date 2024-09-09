Wireguard Manager
=================

A tool wrapping the Wireguard CLI for creating and managing 
Wireguard tunnels.

Why the wrapper?   

Wireguard tunnels are easy to create and the CLI easily scriptable. 
This wrapper defines a declaritive configuration (yaml) to represent 
wireguard tunnels. This allows for defining more complex meshes
and automation of wireguard tunnels in a clean and consistent manner.


## Configuration

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

An initial configuration can be generated using the *wg-config.sh* script.
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

## Key Pairs

The *wg.sh* script relies a few defaults to simplify configuration.
As shown in the previous yaml examples, the tool uses the default
locations of `${HOME}/.wg_pvt.key` and `${HOME}/.wg_pub.key` for
the key pair. A key pair can be created as those files easily by
running `wg.sh genkey`, though the default locations can be changed.

Note that when *not* running directly as root, such as using `sudo`, the 
default locations can be confused as *$HOME* is used to create them and 
the key files should be referenced accordingly, ideally using an
an absolute path in the yaml config.

## Creating tunnels

Once the configuration is set, the tunnels can be created by running the 
`up` action.
```sh
wg.sh up
```
if multiple interfaces are in use, they can be individually targeted as well.
```sh
wg.sh up wg1
```
