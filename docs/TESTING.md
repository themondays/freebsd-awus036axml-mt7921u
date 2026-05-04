# Testing

Use controlled tests and keep Ethernet or a known-good internal Wi-Fi path
available while testing the WIP driver.

## Baseline Capture

```sh
sudo ./scripts/capture-awus036axml.sh
```

Save the output directory before changing kernel modules or routes.

## Module Load

```sh
sudo kldload mt76_core
sudo kldload if_mt7921
sudo usbconfig list
sysctl net.wlan.devices
dmesg | tail -100
```

## Station Smoke Test

```sh
sudo ifconfig wlan1 create wlandev device
sudo ifconfig wlan1 up
sudo ifconfig wlan1 scan
sudo wpa_supplicant -B -i wlan1 -c /etc/wpa_supplicant.conf -D bsd
wpa_cli -i wlan1 status
sudo dhclient wlan1
```

Prefer source-bound or host-route tests before moving the default route:

```sh
ping -c 5 -S <wlan1-address> <gateway>
```

## Monitor Smoke Test

Create a monitor VAP beside the station VAP:

```sh
sudo ifconfig wlan2 create wlandev device wlanmode monitor
sudo ifconfig wlan2 channel <associated-channel>
sudo ifconfig wlan2 up
sudo tcpdump -ni wlan2 -y IEEE802_11_RADIO -s 512 -c 20 -vv
```

Destroy the monitor VAP after capture:

```sh
sudo ifconfig wlan2 destroy
```

## Kismet

Legacy Kismet may need the BSD radiotap source type:

```sh
sudo timeout 45 kismet_server --no-plugins --no-line-wrap \
  -f /usr/local/etc/kismet.conf \
  -c wlan2:type=radiotap_bsd_a,name=awus,hop=false,channel=<channel> \
  -p /tmp/kismet-awus-rxguard -t awus-rxguard -T pcapdump,nettxt
```

Timeout exit status is expected when using `timeout`. Confirm the kernel did
not reboot and no new crash dump appeared.

## Crash Data

For panics, collect:

```sh
ls -ltr /var/crash
cat /var/crash/info.N
grep -i 'panic\\|mt76\\|mt7921\\|linuxkpi\\|wlan' /var/log/messages
```

Keep the exact kernel/module build identifiers with the crash report.
