#!/bin/bash
# Version 0.65
direction="upstream"
target="$(curl -s project-mayhem.se/probes/ip-udp.txt)"
count=$(( ( RANDOM % 9999 )  + 1 ))
logfacility=local4.debug

### WiFi stuff
phy=ht # What PHY?
#phy=$1 # Use argument instead
iwnic=$(ifconfig | grep wl | awk '{print $1}' | tr -d ':')
iwdetect="$(grep up /sys/class/net/wl*/operstate | wc -l)"
wififreq="$(iw $iwnic link | grep freq | awk '{print $2}')"

#### HT TEMPLATE
htparse="iw \$iwnic station dump | egrep 'tx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | logger -t tx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'rx bitrate|signal:' | xargs | sed 's/\[.*\]//' | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$7,\$10,\$11,\$12,\$13}' | tr -d 'MHz' | logger -t rx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | logger -t iw_counters[\$(echo \$count)] -p \$logfacility"
####

#### VHT TEMPLATE
vhtparse="iw \$iwnic station dump | egrep 'tx bitrate|signal:' | xargs | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$15,\$18,\$19,\$20}' | tr -d 'MHz' | logger -t tx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'rx bitrate|signal:' | xargs | tr -d 'short|GI' | sed 's/\<VHT-NSS\>//g' | sed -e \"s/^/\$direction /\" | awk '{print \$1,\$3,\$15,\$18,\$19,\$20}' | tr -d 'MHz' | logger -t rx_linkstats_\$phy[\$(echo \$count)] -p \$logfacility && iw \$iwnic station dump | egrep 'bytes|packets|retries|failed' | xargs | tr -d 'rx|tx|bytes|packets|retries|failed:' | tr -s ' ' | logger -t iw_counters[\$(echo \$count)] -p \$logfacility"
####

data=$(tail /var/log/iperf3udp.log | egrep $count | awk '{print $11,$14,$9}' | tr -d '(%)' | sed 's/ /,/g')
arr[0]="5m"
arr[1]="10m"
arr[2]="20m"
rand=$[ $RANDOM % 3 ]

# Uncomment to use Iperf UDP Daemon (with random timer)
case "$(pgrep -f "iperf3 --client" | wc -w)" in

0)  echo "[chprobe_iperf3] Let's see if we can start the udp daemon" | logger -p info
    while iperf3 -c $target -t 1 | grep busy; do sleep $[ ( $RANDOM % 5 ) + 3]s && echo '[chprobe_iperf3] waiting cuz server is busy' | logger -p info;done
    echo "[chprobe_iperf3] Starting the udp daemon - $direction" | logger -p info
    /usr/bin/iperf3 --client $target -u -T $direction -b ${arr[$rand]} -t 60 | egrep 'iperf Done' -B 3 | egrep 0.00-60.00 | awk '{print $1,$6,$8,$10,$13,$14.$15,$16,$17,$18}' | tr -d '(%)|:' | logger -t iperf3udp[$(echo $count)] -p local4.debug &
        if [ $iwdetect -gt 0 ]; then
            if [ $wififreq -lt 2500 ]; then phy=ht & eval $htparse;else
                    if [ $phy = vht ]; then eval $vhtparse;else eval $htparse;fi;fi
            else echo 'No WiFi NIC detected'>/dev/stdout;fi
    ;;
1)  echo "[chprobe_iperf3] iperf daemon already running" | logger -p info
    while pgrep -f "iperf3 --client" | wc -w | grep 1;do sleep $[ ( $RANDOM % 5 ) + 3]s && echo '[chprobe_iperf3] waiting cuz a daemon is running' | logger -p info;done
    echo "[chprobe_iperf3] Starting the udp daemon - $direction" | logger -p info
        /usr/bin/iperf3 --client $target -u -T $direction -b ${arr[$rand]} -t 60 | egrep 'iperf Done' -B 3 | egrep 0.00-60.00 | awk '{print $1,$6,$8,$10,$13,$14.$15,$16,$17,$18}' | tr -d '(%)|:' | logger -t iperf3udp[$(echo $count)] -p local4.debug &
	    if [ $iwdetect -gt 0 ]; then
            if [ $wififreq -lt 2500 ]; then phy=ht & eval $htparse;else
                    if [ $phy = vht ]; then eval $vhtparse;else eval $htparse;fi;fi
            else echo 'No WiFi NIC detected'>/dev/stdout;fi
	;;
*)  echo "[chprobe_iperf3] multiple instances of iperf udp daemon running. Stopping & restarting iperf:" | logger -p info
    kill $(pgrep -f "iperf3 --client" | awk '{print $1}')
    ;;
esac;
