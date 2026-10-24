# Dota 2 Stats for Omarchy

A bar widget for the [Omarchy](https://omarchy.org) shell that shows Dota 2 stats for one or more accounts, pulled from [OpenDota](https://www.opendota.com). No API key needed.

- **Bar:** win rate and W/L, rank, or the last game for the selected account.
- **Popup:** profile header with avatar and rank, overview KPIs, rank graph, top heroes with portraits, recent matches, and a settings tab.
- **Multiple accounts:** add or remove accounts from the popup; switch between them with a click, or see combined totals.
- **Notifications:** an Omarchy desktop notification after each new game.

Русская версия: [README.ru.md](README.ru.md).

## Requirements

- Omarchy with shell plugin support (Omarchy 4 "Quattro" or newer).
- `python3` (standard library only, nothing to install).
- Network access to `api.opendota.com`.
- Each Dota 2 profile must be public: in Dota 2, open **Settings → Game Details** and make sure matches are visible.

## Install

```sh
omarchy plugin add https://github.com/maybepritz/omarchy-dota-stats.git --enable
```

The widget is placed in the left section of the bar. Open it with a left click.

## Adding accounts

Open the popup, go to **Settings**, enter a Steam ID and an optional label, and press **Add**. The account is checked on OpenDota before it is saved.

- The ID can be the 32-bit account ID or the 64-bit SteamID; it is stored as the 32-bit ID.
- Remove an account with **Delete** in the same tab.

The list is stored in `~/.config/omarchy/dota-stats/accounts.json`:

```json
{
  "accounts": [
    {"id": 123456789, "label": "main"},
    {"id": 76561198000000000, "label": "second"}
  ]
}
```

You can also add or remove accounts from a terminal:

```sh
python3 dota_fetch.py --add 123456789 --label main
python3 dota_fetch.py --remove 123456789
```

## Settings

All settings are in the **Settings** tab and are saved to `~/.config/omarchy/dota-stats/settings.json`:

| Setting | Options | Default |
| --- | --- | --- |
| Refresh interval | 5, 10, 30, 60 min | 10 min |
| Matches in summary | 10, 20, 50 | 20 |
| Bar shows | win rate, rank, last game | win rate |
| Game notifications | on / off | on |

The popup also has a period filter (7 days, 30 days, all time) and a lobby filter (ranked, all public games).

## Controls

- **Left click** on the bar: open the popup.
- **Right click** on the bar: refresh now.
- **Middle click** on the bar: switch to the next account.
- IPC: `omarchy-shell dota-stats refresh`, `omarchy-shell dota-stats next`, `omarchy-shell dota-stats status`.

## How it works

- `dota_fetch.py` requests data from `api.opendota.com` and prints one JSON object. The shell service runs it on start, on the timer, and when you change a filter.
- Images (hero portraits, hero icons, avatars) and the hero list are cached in `~/.cache/omarchy/dota-stats/`. Profile and rank history are cached for an hour, the hero list for a week. Results that depend on the period or the latest games are always fetched fresh.
- If a refresh fails, the widget keeps showing the last good data together with the error.
- New-game notifications use `omarchy-notification-send`. The first run only records the latest game, so old matches are not announced.

Run the helper on its own to check it:

```sh
python3 dota_fetch.py --days 7 --lobby ranked
python3 dota_fetch.py --set refreshMinutes 30
```

## Data and privacy

The plugin only sends requests to `api.opendota.com` for the accounts you add. It stores the account list, settings, and cached API responses and images locally. Nothing is sent anywhere else. Data comes from OpenDota; Dota 2 and hero images belong to Valve.

## Limitations

- OpenDota does not always include GPM for the match list; missing values are shown as `—`.
- The rank graph shows the rank tier (`rank_tier`) from ranked games, not an exact MMR. OpenDota does not provide exact MMR for every account.
- The free OpenDota limit is about 60 requests per minute and 2000 per day. Each account makes about three uncached requests per refresh. A 5-minute interval with several accounts can reach the daily limit.

## Remove

```sh
omarchy plugin remove maybepritz.dota-stats
```

To also delete your data, remove `~/.config/omarchy/dota-stats/` and `~/.cache/omarchy/dota-stats/`.

## License

MIT. See [LICENSE](LICENSE).
