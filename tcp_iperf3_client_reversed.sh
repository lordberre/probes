#!/bin/bash
target="$(curl -s project-mayhem.se/probes/ip.txt)"
#logevent='"$(logger -p info)"'

# Uncomment to use Iperf TCP Daemon (with random timer)
case "$(pgrep -f "iperf3 --client" | wc -w)" in

0)  echo "iperf3 tcp daemon not running, initiating random timer then restarting daemon:" | logger -p info
    sleep $[ ( $RANDOM % 240 )  + 60 ]s
    /bin/iperf3 --client $target -T Download -P 15 -R -w 1m 2>&1 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | logger -t iperf3tcp -p local3.debug & echo "Timer stopped - tcp daemon started" | logger -p info &
    ;;
1)  echo "iperf tcp daemon running, all OK:" | logger -p info
    ;;
*)  echo "multiple instances of iperf udp daemon running. Stopping & restarting iperf:" | logger -p info
    kill $(pgrep -f "iperf3 --client" | awk '{print $1}')
    ;;
esac;
