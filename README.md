# xkmod

**xkmod** — a Termux toolkit that installs xray-knife and sets up helper scripts to fetch, filter, validate, and run free VLESS/VMess/Trojan proxy configurations with automatic rotation.

## Install
```bash
git clone https://github.com/1mpsb1/xkmod.git
cd xkmod
chmod +x termux-install.sh
./termux-install.sh
```

## Usage
- `xkmod-u` - Fetch configs from a list of URLs
- `xkmod-c` - Validate and filter configs with xray-knife
- `xkmod-s` - Run a SOCKS proxy on localhost
- `xkmod-pw` - Route a session through the local proxy
