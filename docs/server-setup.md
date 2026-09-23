# Server side / getting a client config

The router is a normal AmneziaWG **3.1** client. Any AWG 3.1 server works; the easiest is the official
Amnezia self-hosted server.

## Option A — Amnezia app (easiest)

1. Rent a small VPS close to where your traffic goes (e.g. Frankfurt for EU game servers).
2. In the **Amnezia VPN** app: *Add server → Self-hosted* → give it the VPS IP + root password.
   Pick the **AmneziaWG** protocol. The app installs a Docker container (`amnezia-awg2`).
3. In the app: *Share → AmneziaWG native format* for a **new** client (one per router).
   You get a normal `.conf` file.
4. Turn it into the router file:
   - note `Address = 10.8.1.X/32` → that is your `TUNNEL_ADDR` for `install.sh`
   - **delete** the `Address`, `DNS` and `MTU` lines (the kernel `awg setconf` rejects them)
   - optionally add `ListenPort = 40008` under `[Interface]` (see README, *Pinned ListenPort*)
   - `AllowedIPs = 0.0.0.0/0` in `[Peer]` (routing is done by `awg3-up`, not by AllowedIPs)

Compare with [`router-files/awg1.conf.example`](../router-files/awg1.conf.example).

> The app may rewrite the server's `awg0.conf` when you add/remove clients from it. If the router
> suddenly has no handshake, check the peer still exists on the server (Option B, `awg show`).

## Option B — add the peer by hand (no restart of the server)

On the router:

```sh
umask 077
awg genkey > awg1.key; awg pubkey < awg1.key > awg1.pub; awg genpsk > awg1.psk
cat awg1.pub awg1.psk
```

On the server (container `amnezia-awg2`; interface `awg0`; pick a free tunnel IP):

```sh
PUB=<router public key>; PSK=<preshared key>; IP=10.8.1.50/32
docker exec amnezia-awg2 sh -c "umask 077; echo $PSK > /tmp/p.psk"
docker exec amnezia-awg2 awg set awg0 peer $PUB preshared-key /tmp/p.psk allowed-ips $IP
docker exec amnezia-awg2 sh -c "printf '\n[Peer]\nPublicKey = $PUB\nPresharedKey = $PSK\nAllowedIPs = $IP\n' >> /opt/amnezia/awg/awg0.conf; rm /tmp/p.psk"
```

Then build `awg1.conf` from `awg1.conf.example`:

- `PrivateKey` = contents of `awg1.key`
- every obfuscation line (`Jc … H4`, `S3`, `S4`, `I1-I5` if present, `HeaderProtectionKey`,
  `ContentPaddingAddition`, `RandomTrailers`, …) copied **exactly** from the server's
  `[Interface]` in `/opt/amnezia/awg/awg0.conf`
- `PublicKey` = `/opt/amnezia/awg/wireguard_server_public_key.key`
- `Endpoint` = `<vps-ip>:<ListenPort of awg0.conf>`

To show the peer in the Amnezia app too, add an entry to `/opt/amnezia/awg/clientsTable`
(JSON; `clientId` = the router's public key).
