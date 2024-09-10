Wireguard Manager
=================

A tool wrapping the Wireguard CLI for creating and managing 
Wireguard tunnels.

Why the wrapper?   

Wireguard tunnels are easy to create and the CLI easily scriptable. 
This wrapper defines a declaritive configuration (yaml) to represent 
wireguard tunnels. This allows for defining more complex meshes
and automation of wireguard tunnels in a clean and consistent manner.


## Requirements

- bash 4+
- wireguard (obviously)
- [yq](https://github.com/mikefarah/yq) v4+


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

### Config Generator *wg-config.sh*

An initial configuration can be generated using the *wg-config.sh* script.
The script also supports adding a peer to an existing config. The tools all
default to a config location of `${HOME}/.config/wg-mgr.yaml`. Note that 
*$HOME* can cause confusion when using `sudo`, so defining absolute paths 
for the config may be needed when not running as *root*.
```sh
$ wg-config.sh create 10.0.0.1/24
wg-config.sh created config '/home/user/.config/wg-mgr.yaml'

$ wg-config.sh addPeer mypeer 10.0.0.2 mypeerpublickey
wg-config.sh added peer config for 'mypeer'

$ cat ~/.config/wg-mgr.yaml
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

Note that, as mentioned above, using `sudo` can confuse key locations
from the use of `$HOME`. Ensure the key file locations are referenced 
correctly, ideally using an an absolute path.


## Starting Wireguard tunnels

Once the configuration is set, the tunnels can be created by running the 
`up` action.
```sh
wg.sh up
```

If multiple interfaces are in use, they can be individually targeted as well.
```sh
wg.sh up wg1
```
