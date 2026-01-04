Wireguard Manager
=================
Copyright (c) 2024-2026 Timothy C. Arland <tcarland at gmail dot com>


A tool wrapping the Wireguard CLI for creating and managing 
Wireguard tunnels using YAML for descriptive configs and ease 
of automation.

Why this wrapper?   

Wireguard tunnels are easy to create and the CLI easily scriptable. 
This wrapper defines a declaritive YAML configuration to represent 
wireguard tunnels. This allows for defining more complex meshes
and automating wireguard tunnels in a clean and consistent manner
(and no I did not use anything to generate that description).


## Requirements

- bash v4+
- wireguard 
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

The *wg.sh* script relies on a few defaults to simplify configuration, 
though all values can be overwritten. As shown in the previous yaml 
example, the tool uses the default locations of `${HOME}/.wg_pvt.key` 
and `${HOME}/.wg_pub.key` for the key pair.

Note that using `sudo` can confuse key locations given the use of `$HOME`. 
Ensure the key file locations are referenced correctly, ideally using an 
absolute path to avoid this confusion.

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

<br>
    
## Config Generator
### wireconfig.sh

An initial configuration can be generated using the *wireconfig.sh* script.
The script also supports adding a peer to an existing config. The tools all
default to a config location of `${HOME}/.config/wg-mgr.yaml`. Again, use of
`$HOME` can cause confusion when using `sudo`, so defining absolute paths 
for the config may be necessary.
```sh
./wg-config.sh create 10.0.0.1/24
 -> created config '/root/.config/wg-mgr.yaml'

./wg-config.sh addPeer client1 10.0.0.2 client1pubkey
 -> added peer config for 'client1'

./wg-config.sh createFrom client1 server1
 -> createFrom: creating config 'wg-mgr-client1.yaml' using peer 'client1'
```

Note that the *client1pubkey* above represents the public key of 
the peer being added which is typically created on the remote host via
`genkey` though all files could be created locally first as the *genkey* 
command supports optional filenames as arguments.

The resulting (local) config as the server: `cat /root/.config/wg-mgr.yaml`
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
        pubkey: client1pubkey
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

### WireConfig Example

This example uses *wireconfig.sh* to build the example files found in this repo.
```sh
./wg.sh genkey
mkdir test
./wireconfig.sh -c test/wg-mgr-server.yaml -o test create 10.0.0.1/24
./wireconfig.sh -c test/wg-mgr-server.yaml -o test addPeer client1 10.0.0.2/24 client1pubkey
./wireconfig.sh -c test/wg-mgr-server.yaml -o test addPeer client2 10.0.0.3/24 client2pubkey
./wireconfig.sh -c test/wg-mgr-server.yaml -o test addNetwork wg1 10.0.1.1/24
./wireconfig.sh -c test/wg-mgr-server.yaml -o test -i wg1 addPeer client3 10.0.1.2/24 client3pubkey
./wireconfig.sh -c test/wg-mgr-server.yaml -o test -E server:55820 -k 30 createFrom client1 server1
./wireconfig.sh -c test/wg-mgr-server.yaml -o test -E server:55820 -k 30 createFrom client2 server1
./wireconfig.sh -c test/wg-mgr-server.yaml -o test -E server:55820 -k 30 -i wg1 createFrom client3 server1
```

## Starting Wireguard tunnels

Once the configuration is set, the tunnels can be created by running the 
`up` action.
```sh
./bin/wg.sh up
```

If multiple interfaces are in use, they can be individually targeted as well.
```sh
./bin/wg.sh up wg1
```
