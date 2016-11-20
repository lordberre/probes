#!/bin/bash
target="$(curl -s project-mayhem.se/probes/ip.txt)"
#logevent='"$(logger -p info)"'

# Uncomment to use Iperf UDP Daemon (with random timer)
case "$(pgrep -f "iperf3 -u" | wc -w)" in

0)  echo "iperf udp daemon not running, initiating random timer then restarting daemon:" | logger -p info
    sleep $[ ( $RANDOM % 10 )  + 4 ]s
    /bin/iperf3 -u -c $target -J 2>&1 | tr --delete '\n,\t' | logger -t iperf3udp -p local4.debug & echo "Time
r stopped - udp daemon started" | logger -p info &
    ;;
1)  echo "iperf udp daemon running, all OK:" | logger -p info
    ;;
*)  echo "multiple instances of iperf udp daemon running. Stopping & restarting iperf:" | logger -p info
    kill $(pgrep -f "iperf3 -u" | awk '{print $1}')
    ;;
esac;










# (iperf3) Server-side iperf. Logs to local syslog with "local6.debug" and tags with iperf for remote syslog
#iperf3 -i 10 -c $ip -J 2>&1 | tr --delete '\n,\t' | logger -t iperftcp -p local6.debug

