#!/bin/bash
# Version 0.95
target="$(curl -s project-mayhem.se/probes/ip.txt)"
count=$(( ( RANDOM % 9999 )  + 100 ))
#logevent='"$(logger -p info)"'

# Uncomment to use Iperf TCP Daemon (with random timer)
case "$(pgrep -f "iperf3 --client" | wc -w)" in

0)  echo "[chprobe_iperf3] iperf3 tcp daemon not running, initiating random timer then restarting daemon:" | logger -p info
    while iperf3 -c $target -t 1 | grep busy; do sleep $[ ( $RANDOM % 20 ) + 3]s  && echo '[chprobe_iperf3] waiting cuz server is busy' | logger -p info;done
    /bin/iperf3 --client $target -T Download -P 15 -R -w 1m 2>&1 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | logger -t iperf3tcp[$(echo $count)] -p local3.debug & echo "[chprobe_iperf3] Timer stopped - tcp daemon started" | logger -p info
    sleep 15
    rrdtool update /home/chprobe/tcpdb_$(hostname -d).rrd --template downstream N:$(tail /var/log/iperf3tcp.log | egrep $count | awk '{print $7}') ## debug ## & echo $(tail /var/log/iperf3tcp.log | egrep $count | awk '{print $7}') >> /home/chprobe/dbdebug.log
    ;;
1)  echo "[chprobe_iperf3] iperf tcp daemon running, all OK:" | logger -p info
    ;;
*)  echo "[chprobe_iperf3] multiple instances of iperf udp daemon running. Stopping & restarting iperf:" | logger -p info
    kill $(pgrep -f "iperf3 --client" | awk '{print $1}')
    ;;
esac;
