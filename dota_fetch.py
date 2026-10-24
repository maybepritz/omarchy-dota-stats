#!/usr/bin/env python3
"""Fetch Dota 2 stats for every configured account from OpenDota and print one JSON object."""

import argparse
import datetime
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.opendota.com/api"
CDN = "https://cdn.cloudflare.steamstatic.com"
STEAM64_BASE = 76561197960265728
RANKED_LOBBY = 7
MEDALS = ["", "Herald", "Guardian", "Crusader", "Archon", "Legend", "Ancient", "Divine", "Immortal"]
DEFAULT_SETTINGS = {"refreshMinutes": 10, "matches": 20, "notify": True, "barMode": "winrate"}
CHOICES = {
    "refreshMinutes": [5, 10, 30, 60],
    "matches": [10, 20, 50],
    "notify": [True, False],
    "barMode": ["winrate", "rank", "last"],
}
# Seconds a cached answer stays fresh. Results that depend on the period, lobby or
# the newest matches are never cached, so the widget always shows current games.
TTL = {"profile": 3600, "ratings": 3600, "heroes": 1800}


def default_config_path():
    base = os.environ.get("XDG_CONFIG_HOME") or os.path.expanduser("~/.config")
    return os.path.join(base, "omarchy", "dota-stats", "accounts.json")


def default_cache_dir():
    base = os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache")
    return os.path.join(base, "omarchy", "dota-stats")


def load_json(path, fallback):
    if not os.path.exists(path):
        return fallback
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def save_json(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    temporary = "%s.%d.tmp" % (path, os.getpid())
    with open(temporary, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
    os.replace(temporary, path)


def load_config(path):
    if not os.path.exists(path):
        save_json(path, {"accounts": []})
        return {"accounts": []}
    return load_json(path, {"accounts": []})


def load_settings(config_path):
    stored = load_json(os.path.join(os.path.dirname(config_path), "settings.json"), {})
    settings = dict(DEFAULT_SETTINGS)
    for key in CHOICES:
        if key in stored and stored[key] in CHOICES[key]:
            settings[key] = stored[key]
    return settings


def parse_setting(key, raw):
    if key not in CHOICES:
        raise ValueError("Неизвестная настройка: %s" % key)
    if key == "notify":
        value = str(raw).lower() in ("1", "true", "yes", "on")
    elif key == "barMode":
        value = str(raw)
    else:
        value = int(raw)
    if value not in CHOICES[key]:
        raise ValueError("Недопустимое значение для %s" % key)
    return value


def account_id(value):
    """Accept a 32-bit account id or a 64-bit SteamID and return the 32-bit id."""
    number = int(value)
    return number - STEAM64_BASE if number > STEAM64_BASE else number


def get(path, params=None):
    query = "?" + urllib.parse.urlencode(params) if params else ""
    request = urllib.request.Request(API + path + query, headers={"User-Agent": "omarchy-dota-stats"})
    with urllib.request.urlopen(request, timeout=10) as response:
        return json.loads(response.read().decode("utf-8"))


def cached(cache_dir, key, ttl, path, params=None):
    """Return a cached answer while it is fresh; fall back to a stale copy if OpenDota fails."""
    target = os.path.join(cache_dir, "api", key + ".json")
    fresh = ttl and os.path.exists(target) and time.time() - os.path.getmtime(target) < ttl
    if fresh:
        return load_json(target, None)
    try:
        data = get(path, params)
    except OSError:
        if os.path.exists(target):
            return load_json(target, None)
        raise
    save_json(target, data)
    return data


def download(remote, target):
    """Save a remote image once and return its local path, or '' when it cannot be fetched."""
    if not remote:
        return ""
    if os.path.exists(target) and os.path.getsize(target) > 0:
        return target
    url = CDN + remote.rstrip("?") if remote.startswith("/") else remote
    os.makedirs(os.path.dirname(target), exist_ok=True)
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "omarchy-dota-stats"})
        with urllib.request.urlopen(request, timeout=10) as response:
            data = response.read()
    except OSError:
        return ""
    with open(target + ".%d.part" % os.getpid(), "wb") as f:
        f.write(data)
    os.replace(target + ".%d.part" % os.getpid(), target)
    return target


class Heroes:
    """Hero names and images, loaded from OpenDota constants and kept in the cache."""

    def __init__(self, cache_dir):
        self.cache_dir = cache_dir
        self.info = {}
        path = os.path.join(cache_dir, "heroes-v2.json")
        fresh = os.path.exists(path) and time.time() - os.path.getmtime(path) < 7 * 24 * 3600
        if not fresh:
            raw = get("/constants/heroes")
            info = {str(v["id"]): {"name": v.get("localized_name", ""), "img": v.get("img", ""), "icon": v.get("icon", "")}
                    for v in raw.values()}
            save_json(path, info)
        self.info = load_json(path, {})

    def name(self, hero_id):
        return self.info.get(str(hero_id), {}).get("name") or "Герой %s" % hero_id

    def portrait(self, hero_id):
        item = self.info.get(str(hero_id), {})
        return download(item.get("img", ""), os.path.join(self.cache_dir, "heroes", "%s.png" % hero_id))

    def icon(self, hero_id):
        item = self.info.get(str(hero_id), {})
        return download(item.get("icon", ""), os.path.join(self.cache_dir, "heroes", "%s-icon.png" % hero_id))


def parse_time(value):
    if isinstance(value, (int, float)):
        return value
    try:
        return datetime.datetime.fromisoformat(str(value).replace("Z", "+00:00")).timestamp()
    except ValueError:
        return 0


def rank_label(tier, leaderboard):
    if not tier:
        return "Без ранга"
    medal, stars = divmod(int(tier), 10)
    if medal >= 8:
        return "Immortal #%s" % leaderboard if leaderboard else "Immortal"
    name = MEDALS[medal] if 0 < medal < len(MEDALS) else "?"
    return "%s %d" % (name, stars)


def summarize(matches):
    count = len(matches)
    if not count:
        return None

    def average(key):
        return round(sum(m[key] or 0 for m in matches) / count, 1)

    kills, deaths, assists = average("kills"), average("deaths"), average("assists")
    return {
        "games": count,
        "kills": kills,
        "deaths": deaths,
        "assists": assists,
        "kda": round((kills + assists) / max(deaths, 1), 2),
        "gpm": round(average("gpm")),
        "xpm": round(average("xpm")),
        "duration": round(average("duration")),
    }


def hero_kda(matches):
    """Average K/D/A per hero over the matches already loaded for the account."""
    totals = {}
    for m in matches:
        row = totals.setdefault(m["heroId"], [0, 0, 0, 0])
        row[0] += m["kills"]
        row[1] += m["deaths"]
        row[2] += m["assists"]
        row[3] += 1
    result = {}
    for hero_id, (k, d, a, games) in totals.items():
        result[hero_id] = round((k + a) / max(d, 1), 2)
    return result


def match_row(row, heroes):
    radiant = int(row.get("player_slot") or 0) < 128
    hero_id = row.get("hero_id") or 0
    return {
        "matchId": row.get("match_id"),
        "heroId": hero_id,
        "hero": heroes.name(hero_id),
        "icon": heroes.icon(hero_id),
        "win": bool(row.get("radiant_win")) == radiant,
        "kills": row.get("kills") or 0,
        "deaths": row.get("deaths") or 0,
        "assists": row.get("assists") or 0,
        "gpm": row.get("gold_per_min") or 0,
        "xpm": row.get("xp_per_min") or 0,
        "duration": row.get("duration") or 0,
        "startTime": row.get("start_time") or 0,
    }


def notify_new_matches(account, name, recent, heroes, cache_dir, avatar, settings):
    """Send a desktop notification for games that finished since the last run."""
    state_path = os.path.join(cache_dir, "state.json")
    state = load_json(state_path, {})
    key = str(account)
    rows = sorted(recent, key=lambda r: r.get("match_id") or 0)
    if not rows:
        return
    newest = rows[-1]["match_id"]
    seen = state.get(key)
    state[key] = newest
    save_json(state_path, state)
    # The first run only records the baseline, so old games do not all pop up at once.
    if seen is None or not settings["notify"]:
        return
    for row in [r for r in rows if r["match_id"] > seen][-3:]:
        game = match_row(row, heroes)
        headline = "%s: %s" % (name, "победа" if game["win"] else "поражение")
        body = "%s · %d/%d/%d · %d мин" % (game["hero"], game["kills"], game["deaths"], game["assists"],
                                          round(game["duration"] / 60))
        command = ["omarchy-notification-send", "--app-name", "Dota 2", headline, body]
        if avatar:
            command[3:3] = ["--image", avatar]
        try:
            subprocess.run(command, timeout=5, check=False)
        except (OSError, subprocess.SubprocessError):
            pass


def fetch_account(entry, options, settings, heroes, cache_dir):
    account = account_id(entry["id"])
    base = {"date": options.days} if options.days else {}
    if options.lobby == "ranked":
        base["lobby_type"] = RANKED_LOBBY
    else:
        base["significant"] = 0

    result = {"id": account, "label": entry.get("label") or str(account), "error": ""}
    try:
        profile = cached(cache_dir, "profile-%d" % account, TTL["profile"], "/players/%d" % account)
        if not profile or not profile.get("profile"):
            result["error"] = "Профиль не найден или приватный"
            return result
        result["name"] = profile["profile"].get("personaname") or result["label"]
        result["avatar"] = download(profile["profile"].get("avatarfull", ""),
                                    os.path.join(cache_dir, "avatars", "%d.jpg" % account))
        result["rank"] = rank_label(profile.get("rank_tier"), profile.get("leaderboard_rank"))
        result["mmr"] = (profile.get("mmr_estimate") or {}).get("estimate")

        wins_losses = get("/players/%d/wl" % account, base)
        result["wins"] = wins_losses.get("win", 0)
        result["losses"] = wins_losses.get("lose", 0)

        matches = [match_row(row, heroes)
                   for row in get("/players/%d/matches" % account, dict(base, limit=settings["matches"]))]
        result["matches"] = matches
        result["summary"] = summarize(matches)

        kda_by_hero = hero_kda(matches)
        heroes_rows = []
        for row in cached(cache_dir, "heroes-%d-%s-%s" % (account, options.days, options.lobby), TTL["heroes"],
                          "/players/%d/heroes" % account, base):
            if row.get("games"):
                heroes_rows.append({
                    "heroId": row["hero_id"],
                    "hero": heroes.name(row["hero_id"]),
                    "portrait": heroes.portrait(row["hero_id"]),
                    "games": row["games"],
                    "wins": row["win"],
                    "kda": kda_by_hero.get(row["hero_id"]),
                })
        heroes_rows.sort(key=lambda h: h["games"], reverse=True)
        result["heroes"] = heroes_rows[:10]

        ratings = cached(cache_dir, "ratings-%d" % account, TTL["ratings"], "/players/%d/ratings" % account) or []
        cutoff = time.time() - options.days * 86400 if options.days else 0
        history = [{"t": parse_time(r.get("time")), "tier": r.get("rank_tier")} for r in ratings if r.get("rank_tier")]
        result["rankHistory"] = [h for h in history if h["t"] >= cutoff][-40:]

        recent = get("/players/%d/recentMatches" % account)
        notify_new_matches(account, result["name"], recent, heroes, cache_dir, result["avatar"], settings)
    except Exception as error:
        result["error"] = str(error)
    return result


def add_account(config, path, raw, label):
    try:
        account = account_id(parse_id(raw))
    except ValueError as error:
        return {"ok": False, "error": str(error)}
    if any(account_id(entry["id"]) == account for entry in config["accounts"]):
        return {"ok": False, "error": "Этот аккаунт уже добавлен"}
    try:
        profile = get("/players/%d" % account)
    except urllib.error.HTTPError as error:
        if error.code != 404:
            return {"ok": False, "error": "OpenDota ответил ошибкой %d" % error.code}
        profile = None
    except OSError as error:
        return {"ok": False, "error": "OpenDota недоступен: %s" % error}
    if not profile or not profile.get("profile"):
        return {"ok": False, "error": "Профиль не найден. Проверь ID и публичность профиля"}
    name = profile["profile"].get("personaname") or str(account)
    config["accounts"].append({"id": account, "label": label.strip() or name})
    save_json(path, config)
    return {"ok": True, "id": account, "name": name}


def remove_account(config, path, raw):
    try:
        account = account_id(parse_id(raw))
    except ValueError as error:
        return {"ok": False, "error": str(error)}
    kept = [entry for entry in config["accounts"] if account_id(entry["id"]) != account]
    if len(kept) == len(config["accounts"]):
        return {"ok": False, "error": "Аккаунт не найден в списке"}
    config["accounts"] = kept
    save_json(path, config)
    return {"ok": True, "id": account}


def parse_id(raw):
    text = str(raw or "").strip()
    if not text.isdigit() or int(text) <= 0:
        raise ValueError("Steam ID — положительное число")
    return text


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", default=default_config_path())
    parser.add_argument("--cache", default=default_cache_dir())
    parser.add_argument("--days", type=int, default=7, help="0 means all time")
    parser.add_argument("--lobby", choices=["ranked", "all"], default="ranked")
    parser.add_argument("--add", metavar="STEAM_ID", help="check the account on OpenDota and save it")
    parser.add_argument("--label", default="", help="name to show for the account added with --add")
    parser.add_argument("--remove", metavar="STEAM_ID", help="remove the account from the config")
    parser.add_argument("--set", nargs=2, metavar=("KEY", "VALUE"), help="save one setting")
    options = parser.parse_args()

    try:
        config = load_config(options.config)
    except (OSError, ValueError) as error:
        print(json.dumps({"ok": False, "error": "Не читается конфиг: %s" % error}, ensure_ascii=False))
        return

    if options.add is not None:
        print(json.dumps(add_account(config, options.config, options.add, options.label), ensure_ascii=False))
        return
    if options.remove is not None:
        print(json.dumps(remove_account(config, options.config, options.remove), ensure_ascii=False))
        return
    if options.set is not None:
        try:
            key, raw = options.set
            settings = load_settings(options.config)
            settings[key] = parse_setting(key, raw)
            save_json(os.path.join(os.path.dirname(options.config), "settings.json"), settings)
            print(json.dumps({"ok": True, "settings": settings}, ensure_ascii=False))
        except ValueError as error:
            print(json.dumps({"ok": False, "error": str(error)}, ensure_ascii=False))
        return

    settings = load_settings(options.config)
    entries = config.get("accounts") or []
    if not entries:
        print(json.dumps({"ok": True, "updated": int(time.time()), "days": options.days,
                          "lobby": options.lobby, "settings": settings, "accounts": []}, ensure_ascii=False))
        return

    try:
        heroes = Heroes(options.cache)
    except Exception as error:
        print(json.dumps({"ok": False, "error": "Не загрузился список героев: %s" % error}, ensure_ascii=False))
        return

    accounts = [fetch_account(entry, options, settings, heroes, options.cache) for entry in entries]
    print(json.dumps({
        "ok": True,
        "updated": int(time.time()),
        "days": options.days,
        "lobby": options.lobby,
        "settings": settings,
        "accounts": accounts,
    }, ensure_ascii=False))


if __name__ == "__main__":
    sys.exit(main())
