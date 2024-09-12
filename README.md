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

### Creating key pairs

The *wg.sh* script relies a few defaults to simplify configuration.
As shown in the previous yaml examples, the tool uses the default
locations of `${HOME}/.wg_pvt.key` and `${HOME}/.wg_pub.key` for
the key pair.

Note that using `sudo` can confuse key locations
from the use of `$HOME`. Ensure the key file locations are referenced 
correctly, ideally using an an absolute path.

Using the *wg.sh* script with the `genkey` option will generate a key pair
in the default location.
```sh
wg.sh genkey
 -> Public Key: YvtFaaO/EOqizCxjJhIRSMtYoVj4NbGqpND0oukpK2A=
```

Alternate locations can also be provided.
```sh
wg.sh genkey "/path/to/publickey" "/path/to/privatekey"
```

### Config Generator *wg-config.sh*

An initial configuration can be generated using the *wg-config.sh* script.
The script also supports adding a peer to an existing config. The tools all
default to a config location of `${HOME}/.config/wg-mgr.yaml`. Again, 
*$HOME* can cause confusion when using `sudo`, so defining absolute paths 
for the config may be needed when not running as *root*.
```sh
./wg-config.sh create 10.0.0.1/24
 -> created config '/root/.config/wg-mgr.yaml'

./wg-config.sh addPeer client1 10.0.0.2 mypeerpublickey
 -> added peer config for 'client1'

./wg-config.sh createFrom client1 server1
 -> createFrom: creating config 'wg-mgr-client1.yaml' using peer 'client1'
```

Note that the *mypeerpublickey* above represents the client public key 
that was not created first in the above steps as *genkey* is generally 
ran on the client host directly.


The resulting Server config: `cat /root/.config/wg-mgr.yaml`
```yaml
---
wireguard:
  wg0:
    addr: 10.0.0.1/24
    port: 55820
    privatekeyfile: "/root/.wg_pvt.key"
    publickeyfile: "/root/.wg_pub.key"
    peers:
      mypeer:
        addr: 10.0.0.2
        pubkey: mypeerpublickey
        default: false
        allowed_ips:
          - 10.0.0.2/32
```

And the resulting Client Config: `cat ./wg-mgr-client1.yaml`
```yaml
---
wireguard:
  wg0:
    addr: "10.0.0.2"
    port: "55820"
    privatekeyfile: "/root/.wg_pvt.key"
    publickeyfile: "/root/.wg_pub.key"
    peers:
      myserver:
        addr: "10.0.0.1/24"
        pubkey: "serverpubkey"
        default: "false"
        endpoint: "myserver:55820"
        keepalive: 30
        allowed_ips:
          - 10.0.0.1/24/32
```

## Example

Another example using *wireconfig.sh* to build the examples found in this repo.
```sh
./wg.sh genkey
./wireconfig.sh -c example/wg-mgr-server.yaml create 10.0.0.1/24
./wireconfig.sh -c example/wg-mgr-server.yaml addPeer client1 10.0.0.2/24 client1pubkey
./wireconfig.sh -c example/wg-mgr-server.yaml addPeer client2 10.0.0.3/24 client2pubkey
./wireconfig.sh -c example/wg-mgr-server.yaml addNetwork wg1 10.0.1.1/24
./wireconfig.sh -c example/wg-mgr-server.yaml -i wg1 addPeer client3 10.0.1.2/24 client3pubkey
mv ./wg-mgr-client*.yaml example/
```

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
