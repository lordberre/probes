# Break the firewall
# Only works with IPv4
ip="$(hostname -I | awk '{print $1}')"
upnpc -e ch-probe -a $ip 5001 5001 tcp 1800
upnpc -e ch-probe -a $ip 5001 5001 udp 1800
upnpc -e ch-probe -a $ip 34521 34521 tcp 1800
upnpc -e ch-probe -a $ip 35631 35631 tcp 1800
