import json
from pathlib import Path

# Определяем путь до bless и до vlg_config
base = Path(__file__).resolve().parents[1]
vlg_config_path = base / "dat2rules" / "vlg_config.json"

# Целевой путь для rules.yaml — безопасный для mihomo
rules_yaml_path = Path.home() / ".config" / "mihomo" / "dat2rules" / "rules.yaml"
rules_yaml_dir = rules_yaml_path.parent

# Создаём директорию, если не существует
rules_yaml_dir.mkdir(parents=True, exist_ok=True)

# Обновляем vlg_config.json
with open(vlg_config_path, "r", encoding="utf-8") as f:
    config = json.load(f)

config["rules_filepath"] = str(rules_yaml_path)

with open(vlg_config_path, "w", encoding="utf-8") as f:
    json.dump(config, f, indent=2)

print(f"[+] rules_filepath updated to: {rules_yaml_path}")