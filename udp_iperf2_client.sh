#!/bin/bash
target="$(curl -s project-mayhem.se/probes/ip.txt)"
#logevent='"$(logger -p info)"'

# Uncomment to use Iperf UDP Daemon
case "$(pgrep -f "iperf -u" | wc -w)" in

0)  echo "iperf udp daemon not running, restarting daemon:" | logger -p info
    sleep $[ ( $RANDOM % 240 )  + 60 ]s
    /bin/iperf -u -c $target -d -t 300 -b 2m -y C 2>&1 | logger -t iperfudp -p local6.debug &
    ;;
1)  echo "iperf udp daemon running, all OK:" | logger -p info
    ;;
*)  echo "multiple instances of iperf udp daemon running. Stopping & restarting iperf:" | logger -p info
    kill $(pgrep -f "iperf -u" | awk '{print $1}')
    ;;
esac;
