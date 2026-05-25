#!/usr/bin/env python3
import json
import sys

try:
    import yaml
except ImportError:
    print("PyYAML is required: install python3-pyyaml", file=sys.stderr)
    sys.exit(3)


def load_config(path):
    try:
        with open(path, "r", encoding="utf-8") as handle:
            data = yaml.safe_load(handle)
            if data is None:
                data = {}
    except OSError as error:
        raise SystemExit(f"cannot read config {path}: {error}") from error
    except yaml.YAMLError as error:
        raise SystemExit(f"invalid YAML in {path}: {error}") from error

    if not isinstance(data, dict):
        raise SystemExit("config root must be a mapping")
    if "defaults" in data and data["defaults"] is not None and not isinstance(data["defaults"], dict):
        raise SystemExit("config defaults must be a mapping")
    if "sites" in data and data["sites"] is not None and not isinstance(data["sites"], list):
        raise SystemExit("config sites must be a list")

    data.setdefault("defaults", {})
    data.setdefault("sites", [])
    validate_config(data)
    return data


def validate_mapping(value, message):
    if value is not None and not isinstance(value, dict):
        raise SystemExit(message)


def validate_string_list(value, message):
    if value is None:
        return
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise SystemExit(message)


def validate_config(data):
    defaults = data.get("defaults") or {}
    validate_mapping(defaults.get("retention"), "config defaults.retention must be a mapping")

    for site in data.get("sites") or []:
        validate_mapping(site, "config site entries must be mappings")
        validate_mapping(site.get("retention"), "config site retention must be a mapping")
        validate_string_list(site.get("excludes"), "config site excludes must be a list of strings")


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

        for field in ("global_exclude_file", "global_env_file", "webhook_env_file"):
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


def print_scalar(value):
    if isinstance(value, (dict, list)):
        print_json(value)
    elif isinstance(value, bool):
        print("true" if value else "false")
    elif value is None:
        print("")
    else:
        print(value)


def main(argv):
    if len(argv) < 3:
        print("Usage: config-query.py <sites.yml> <command> [args...]", file=sys.stderr)
        return 2

    command = argv[2]
    expected_argc = {
        "enabled-site-codes": 3,
        "site-json": 4,
        "site-field": 5,
        "site-retention-field": 5,
        "site-excludes": 4,
    }
    if command not in expected_argc:
        print(f"unknown command: {command}", file=sys.stderr)
        return 2
    if len(argv) != expected_argc[command]:
        print("Usage: config-query.py <sites.yml> <command> [args...]", file=sys.stderr)
        return 2

    config = load_config(argv[1])

    if command == "enabled-site-codes":
        print("\n".join(enabled_site_codes(config)))
        return 0

    if command == "site-json":
        print_json(merged_site(config, argv[3]))
        return 0

    if command == "site-field":
        site = merged_site(config, argv[3])
        print_scalar(site.get(argv[4], ""))
        return 0

    if command == "site-retention-field":
        site = merged_site(config, argv[3])
        print_scalar(site.get("retention", {}).get(argv[4], ""))
        return 0

    if command == "site-excludes":
        site = merged_site(config, argv[3])
        print("\n".join(site.get("excludes") or []))
        return 0

    return 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
