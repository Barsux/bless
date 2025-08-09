import yaml
import argparse
from urllib.parse import parse_qs
from pathlib import Path

def parse_args():
    parser = argparse.ArgumentParser(description="VLESS URL Parser and Config Generator")
    parser.add_argument("--vless-file", type=str, help="Path to the VLESS file")
    parser.add_argument("--output-file", type=str, default="config.yaml", help="Output configuration file")
    return parser.parse_args()

def parse_vless(vless_url: str) -> dict:
    assert vless_url.startswith("vless://"), "Not a VLESS URL"
    vless_url = vless_url[8:]
    userinfo, rest = vless_url.split("@")
    uuid = userinfo
    server, rest = rest.split(":", 1)
    port, rest = rest.split("?", 1)
    query = parse_qs(rest)

    def get_q(key):
        return query.get(key, [""])[0]

    name = "N/A"
    flow = get_q("flow") or "xtls-rprx-vision"
    if "#" in flow:
        flow, name = flow.split("#")

    proxy = {
        "name": "my-vless-node",
        "type": "vless",
        "server": server,
        "port": int(port),
        "uuid": uuid,
        "network": get_q("type") or "tcp",
        "reality-opts": {
            "public-key": get_q("pbk"),
            "short-id": get_q("sid"),
            "spider-x": get_q("spx") or "/",
        },
        "servername": get_q("sni") or get_q("host"),
        "tls": True,
        "flow": flow,
        "udp": True,
        "client-fingerprint": get_q("fp") or "chrome",
    }
    return proxy

def generate_config(proxy: dict) -> dict:
    # Абсолютный путь в безопасную директорию
    rules_path = Path.home() / ".config" / "mihomo" / "dat2rules" / "rules.yaml"

    return {
        "mixed-port": 7890,
        "allow-lan": True,
        "mode": "rule",
        "log-level": "info",
        "external-controller": "127.0.0.1:9090",
        "dns": {
            "enable": True,
            "listen": "0.0.0.0:53",
            "enhanced-mode": "fake-ip",
            "nameserver": ["1.1.1.1", "8.8.8.8"],
            "fake-ip-range": "198.18.0.1/16"
        },
        "tun": {
            "enable": True,
            "stack": "system",
            "dns-hijack": [
                "any:53",
                "tcp://any:53"
            ]
        },
        "proxies": [proxy],
        "proxy-groups": [{
            "name": "VLESS",
            "type": "select",
            "proxies": [proxy["name"]]
        }],
        "rule-providers": {
            "dat2rules": {
                "type": "file",
                "behavior": "classical",
                "path": str(rules_path)
            }
        },
        "rules": [
            "RULE-SET,dat2rules,VLESS",
            "MATCH,DIRECT"
        ]
    }

def save_config(config: dict, filename="config.yaml"):
    with open(filename, "w", encoding="utf-8") as f:
        yaml.dump(config, f, sort_keys=False, default_flow_style=False)

if __name__ == "__main__":
    args = parse_args()
    if not args.vless_file:
        print("Ошибка: Не указан файл VLESS. Используйте --vless-file для указания пути к файлу.")
        exit(1)
    else:
        with open(args.vless_file, "r", encoding="utf-8") as f:
            vless_link = f.read().strip()

    try:
        proxy = parse_vless(vless_link)
        config = generate_config(proxy)
        save_config(config, args.output_file)
    except Exception as e:
        print(f"Ошибка при обработке VLESS ссылки: {e}")
        exit(1)

    print(f"Конфиг сохранён в {args.output_file}")
