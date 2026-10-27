<!-- @format -->

# systemd-service

Enable or disable systemd units and check they run.

Part of [`tomgrv/scripts`](https://github.com/tomgrv/scripts) — installed
and linked onto `PATH` as `systemd-service`.

## Usage

```sh
systemd-service [-r] <up|down> <unit>...

systemd-service up tailscaled
systemd-service -r up fail2ban      # restart too, to load a new config
systemd-service down cloudflared.service svc-cloudflare-private.service
```

`up` runs `systemctl enable --now` on each unit (`-r`: then `restart`) and exits 1, naming the unit, when it is not active afterwards. `down` runs `systemctl disable --now` on all the units at once and never fails (a unit that is not there is fine).

## Tests

```sh
bats test.bats
```
