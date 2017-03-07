#!/bin/bash
target="$(curl -s project-mayhem.se/probes/ip.txt)"
#logevent='"$(logger -p info)"'

# Uncomment to use Iperf TCP Daemon (with random timer)
case "$(pgrep -f "iperf --client" | wc -w)" in

0)  echo "iperf tcp daemon not running, initiating random timer then restarting daemon:" | logger -p info
    sleep $[ ( $RANDOM % 10 )  + 4 ]s
    /bin/iperf --client $target -P 15 -y C 2>&1 | logger -t iperftcp -p local5.debug & echo "Timer stopped - tcp daemon started" | logger -p info &
    ;;
1)  echo "iperf tcp daemon running, all OK:" | logger -p info
    ;;
*)  echo "multiple instances of iperf udp daemon running. Stopping & restarting iperf:" | logger -p info
    kill $(pgrep -f "iperf --client" | awk '{print $1}')
    ;;
esac;


#iperf -c $target -u -d -y C 2>&1 | logger -t iperfudp -p local6.debug
#iperf -c $target -P 15 -y C 2>&1 | logger -t iperftcp -p local5.debug
