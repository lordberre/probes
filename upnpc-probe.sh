# Break the firewall
# Only works with IPv4

# Load configuration file
probe="`cut -d "." -f 2 <<< $(hostname)`"
chprobe_configfile="/var/chprobe/${probe}.cfg"
source $chprobe_configfile

ip="$(hostname -I | awk '{print $1}')"
echo -n "${probe} " > /home/chprobe/hostname-${probe} ;echo $(curl -s http://ping.eu | grep Your | awk '{print $4}' | tr -d '</b>') >> /home/chprobe/hostname-${probe}

if [ $chprobe_upnp = "enable" ]; then
upnpc -e ch-probe -a $ip 5001 5001 tcp $chprobe_upnp_timer
upnpc -e ch-probe -a $ip 5001 5001 udp $chprobe_upnp_timer
upnpc -e ch-probe -a $ip 34521 34521 tcp $chprobe_upnp_timer
upnpc -e ch-probe -a $ip 35631 35631 tcp $chprobe_upnp_timer
fi
