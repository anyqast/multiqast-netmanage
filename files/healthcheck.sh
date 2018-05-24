#!/usr/bin/env bash

# Check if BIRD routing daemon is responsive
birdc show status &> /dev/null || exit 1

# Check if iptables module is responsive
iptables -nL FORWARD &> /dev/null || exit 1

# Check if ipset lists exist
ipset save managed4 &> /dev/null || exit 1
ipset save managed6 &> /dev/null || exit 1
ipset save v4 &> /dev/null || exit 1
ipset save v6 &> /dev/null || exit 1

exit 0
