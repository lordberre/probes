# Break the firewall
# Only works with IPv4

# Load config file
source /var/chprobe/$(hostname -d).cfg

ip="$(hostname -I | awk '{print $1}')"
echo -n "$(hostname -d) " > /home/chprobe/hostname-$(hostname -d) ;echo $(curl -s http://ping.eu | grep Your | awk '{print $4}' | tr -d '</b>') >> /home/chprobe/hostname-$(hostname -d)

if [ $chprobe_upnp = "enable" ]; then
upnpc -e ch-probe -a $ip 5001 5001 tcp 1800
upnpc -e ch-probe -a $ip 5001 5001 udp 1800
upnpc -e ch-probe -a $ip 34521 34521 tcp $chprobe_upnp_timer
upnpc -e ch-probe -a $ip 35631 35631 tcp 1800
fi
