#!/usr/bin/env bash
#
# wg-config.sh



usage="
Creates or updates a configuration for use with the Wireguard wrapper.

Synopsis:
wg-config.sh [options] <action>

Options:
  -E|--endpoint
  -i|--interface
  -p|--peer
  -P|--peerkey

Actions:
  create   <if> <addr> <port>
  createFrom <config> <name>
  addPeer    <name> <addr> <key>
"


