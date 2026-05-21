#!/usr/bin/env python3
import json
import sys

try:
    import yaml
except ImportError:
    print("PyYAML is required: install python3-pyyaml", file=sys.stderr)
    sys.exit(3)


def load_config(path):
    with open(path, "r", encoding="utf-8") as handle:
        data = yaml.safe_load(handle) or {}
    data.setdefault("defaults", {})
    data.setdefault("sites", [])
    return data


def merged_site(config, code):
    defaults = config.get("defaults") or {}
    for site in config.get("sites") or []:
        if site.get("code") != code:
            continue

        merged = dict(site)

        retention = dict(defaults.get("retention") or {})
        retention.update(site.get("retention") or {})
        if retention:
            merged["retention"] = retention

        if "default_excludes" not in merged:
            merged["default_excludes"] = defaults.get("default_excludes", True)

        for field in ("global_exclude_file", "webhook_env_file"):
            if field not in merged and field in defaults:
                merged[field] = defaults[field]

        return merged

    raise SystemExit(f"site not found: {code}")


def enabled_site_codes(config):
    return [
        site["code"]
        for site in config.get("sites") or []
        if site.get("enabled", True) and "code" in site
    ]


def print_json(value):
    print(json.dumps(value, ensure_ascii=False, sort_keys=True))


def main(argv):
    if len(argv) < 3:
        print("Usage: config-query.py <sites.yml> <command> [args...]", file=sys.stderr)
        return 2

    config = load_config(argv[1])
    command = argv[2]

    if command == "enabled-site-codes":
        print("\n".join(enabled_site_codes(config)))
        return 0

    if command == "site-json":
        if len(argv) != 4:
            print("Usage: config-query.py <sites.yml> site-json <code>", file=sys.stderr)
            return 2
        print_json(merged_site(config, argv[3]))
        return 0

    if command == "site-field":
        if len(argv) != 5:
            print("Usage: config-query.py <sites.yml> site-field <code> <field>", file=sys.stderr)
            return 2
        site = merged_site(config, argv[3])
        value = site.get(argv[4], "")
        if isinstance(value, (dict, list)):
            print_json(value)
        else:
            print(value)
        return 0

    if command == "site-excludes":
        if len(argv) != 4:
            print("Usage: config-query.py <sites.yml> site-excludes <code>", file=sys.stderr)
            return 2
        site = merged_site(config, argv[3])
        print("\n".join(site.get("excludes") or []))
        return 0

    print(f"unknown command: {command}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
