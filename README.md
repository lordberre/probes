# Bash framework for automatic performance tests and network monitoring

- What is this?
 
A series of scripts that will run network performance tests at the assigned intervals, then parse it and send it to your backend. I use cron to automate the tests, and my backend is an ELK stack with Grafana creating the graphs. The scripts are supposed to coexist with each other, mainly so critical tests don't collide with each other, for example TCP Throughput tests.

The scripts doesn't run the tests, it's done by for example iperf3 (http://software.es.net/iperf/) and common unix binarys such as ping and dig.

- How to install/use?
 
The code is not really optimized for "general use", although it will be, hopefully.

# Monitor/passive mode
Current features:

- TCP Throughput using either iperf,iperf3 or BBK (Bredbandskollen).
- ICMP Ping echos with larger packets or shorter interval, rtt and packetloss
- DNS querys (AAAA,A,cname,txt,mx) rtt
- HTTPS (SSL/TLS) rtt and packetloss
- HTTP Benchmark/Performance 100-5000 sessions, rtt,various socket errors,http response classification
- UDP Tests, 5,10 and 20 Mbit/s bitrates, jitter and packetloss
- PHY-Agnostic monitoring of per-client WiFi metrics
- Benchmark mode:

# Example
 
![alt](http://project-mayhem.se/files/dashboard1.png)
 
![alt](http://project-mayhem.se/files/dashboard2.PNG)
 
![alt](http://project-mayhem.se/files/dashboard3.PNG)
