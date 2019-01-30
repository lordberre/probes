#!/bin/bash
# Break the firewall
# Only works with IPv4

# Defaults
chprobe_upnp=enable
chprobe_upnp_timer=1800

# Load configuration file
chprobe_configfile="/var/chprobe/chprobe.cfg"
source $chprobe_configfile

if [[ $chprobe_upnp = "enable" ]]; then
    ip="$(hostname -I | awk '{print $1}')"
    upnpc -e ch-probe -a "$ip" 5001 5001 tcp "$chprobe_upnp_timer"
    upnpc -e ch-probe -a "$ip" 5001 5001 udp "$chprobe_upnp_timer"
    upnpc -e ch-probe -a "$ip" 34521 34521 tcp "$chprobe_upnp_timer"
    upnpc -e ch-probe -a "$ip" 35631 35631 tcp "$chprobe_upnp_timer"
fi

# Always exit with status 0
exit 0

