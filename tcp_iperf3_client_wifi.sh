#!/bin/bash
# Version 0.96b (WiFi)
target="$(curl -s project-mayhem.se/probes/ip-wifi.txt)"
# logtarget="$(curl -s project-mayhem.se/probes/ip-logtarget.txt)" # Not used for US
count=$(( ( RANDOM % 9999 )  + 100 ))
iwnic=$(ifconfig | grep wl | awk '{print $1}' | tr -d ':')
#logevent='"$(logger -p info)"'

# Uncomment to use Iperf TCP Daemon (with random timer)
case "$(pgrep -f "iperf3 --client" | wc -w)" in

0)  echo "[chprobe_iperf3] Let's see if we can start the tcp daemon" | logger -p info
    while iperf3 -c $target -t 1 | grep busy; do sleep $[ ( $RANDOM % 5 ) + 3]s  && echo '[chprobe_iperf3] waiting cuz server is busy' | logger -p info;done
    echo "[chprobe_iperf3] Starting the tcp daemon - upstream" | logger -p info
    /bin/iperf3 --client $target -T upload -P 15 -w 1m 2>&1 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | tr -d ':' | logger -t iperf3tcp[$(echo $count)] -p local3.debug & echo "[chprobe_iperf3] tcp daemon started" | logger -p info & iw $iwnic link | egrep 'flags|bitrate|signal' | xargs | awk '{print $2,$6,$9,$10,$11}' | tr -d MHz | logger -t linkstats[$(echo $count)] -p local4.debug
    sleep 15
    rrdtool update /home/chprobe/tcpdb_$(hostname -d).rrd --template upstream N:$(tail /var/log/iperf3tcp.log | egrep $count | awk '{print $7}') ## debug ## & echo $(tail /var/log/iperf3tcp.log | egrep $count | awk '{print $7}') >> /home/chprobe/dbdebug.log
    ;;
1)  echo "[chprobe_iperf3] iperf tcp daemon is already running" | logger -p info
    while pgrep -f "iperf3 --client" | wc -w | grep 1; do sleep $[ ( $RANDOM % 5 ) + 3]s && echo '[chprobe_iperf3] waiting cuz a daemon is running' | logger -p info;done
    echo "[chprobe_iperf3] Starting the tcp daemon - upstream" | logger -p info
    /bin/iperf3 --client $target -T upload -P 15 -w 1m 2>&1 | egrep 'SUM.*rece' | awk '/Mbits\/sec/ {print $1,$7}' | tr -d ':' | logger -t iperf3tcp[$(echo $count)] -p local3.debug & echo "[chprobe_iperf3] Okey the daemon seems to be finished - starting our tcp daemon" | logger -p info & iw $iwnic link | egrep 'flags|bitrate|signal' | xargs | awk '{print $2,$6,$9,$10,$11}' | tr -d MHz | logger -t linkstats[$(echo $count)] -p local4.debug
    sleep 15
    rrdtool update /home/chprobe/tcpdb_$(hostname -d).rrd --template upstream N:$(tail /var/log/iperf3tcp.log | egrep $count | awk '{print $7}')
;;
*)  echo "[chprobe_iperf3] multiple instances of iperf udp daemon running. Stopping & restarting iperf:" | logger -p info
    kill $(pgrep -f "iperf3 --client" | awk '{print $1}')
    ;;
esac;
