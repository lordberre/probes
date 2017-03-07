#!/bin/bash
# Version 0.6
target="$(curl -s project-mayhem.se/probes/ip-udp.txt)"
count=$(( ( RANDOM % 9999 )  + 1 ))
iwnic=$(ifconfig | grep wl | awk '{print $1}' | tr -d ':')
data=$(tail /var/log/iperf3udp.log | egrep $count | awk '{print $11,$14,$9}' | tr -d '(%)' | sed 's/ /,/g')
arr[0]="5m"
arr[1]="10m"
arr[2]="20m"
rand=$[ $RANDOM % 3 ]

# Uncomment to use Iperf UDP Daemon (with random timer)
case "$(pgrep -f "iperf3 --client" | wc -w)" in

0)  echo "[chprobe_iperf3] Let's see if we can start the udp daemon" | logger -p info
    while iperf3 -c $target -t 1 | grep busy; do sleep $[ ( $RANDOM % 5 ) + 3]s && echo '[chprobe_iperf3] waiting cuz server is busy' | logger -p info;done
    echo "[chprobe_iperf3] Starting the udp daemon - upstream" | logger -p info
    /usr/bin/iperf3 --client $target -u -T upstream -b ${arr[$rand]} -t 60 | egrep 'iperf Done' -B 3 | egrep 0.00-60.00 | awk '{print $1,$6,$7,$8,$9,$10,$11,$12,$13}' | logger -t iperf3udp[$(echo $count)] -p local4.debug
    sleep 1
    rrdtool update /home/chprobe/udpdb-us_$(hostname -d).rrd  --template us_jitter:us_pl:us_bitrate N:$(tail /var/log/iperf3udp.log | egrep $count | egrep up | awk '{print $11}'):$(tail /var/log/iperf3udp.log | egrep $count | egrep up  | awk '{print $14}' | tr -d '(%)'):$(tail /var/log/iperf3udp.log | egrep $count | egrep up | awk '{print $9}')
    ;;
1)  echo "[chprobe_iperf3] iperf daemon already running" | logger -p info
    while pgrep -f "iperf3 --client" | wc -w | grep 1;do sleep $[ ( $RANDOM % 5 ) + 3]s && echo '[chprobe_iperf3] waiting cuz a daemon is running' | logger -p info;done
    echo "[chprobe_iperf3] Starting the udp daemon - upstream" | logger -p info
    /usr/bin/iperf3 --client $target -u -T upstream -b ${arr[$rand]} -t 60 | egrep 'iperf Done' -B 3 | egrep 0.00-60.00 | awk '{print $1,$6,$7,$8,$9,$10,$11,$12,$13}' | logger -t iperf3udp[$(echo $count)] -p local4.debug
    sleep 1
    rrdtool update /home/chprobe/udpdb-us_$(hostname -d).rrd  --template us_jitter:us_pl:us_bitrate N:$(tail /var/log/iperf3udp.log | egrep $count | egrep up | awk '{print $11}'):$(tail /var/log/iperf3udp.log | egrep $count | egrep up  | awk '{print $14}' | tr -d '(%)'):$(tail /var/log/iperf3udp.log | egrep $count | egrep up | awk '{print $9}')
    ;;
*)  echo "[chprobe_iperf3] multiple instances of iperf udp daemon running. Stopping & restarting iperf:" | logger -p info
    kill $(pgrep -f "iperf3 --client" | awk '{print $1}')
    ;;
esac;
