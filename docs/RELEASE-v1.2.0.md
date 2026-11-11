## Zero idle cost, faster restore, safer launcher swap

### Highlights
- **Idle CPU now measures 0** — the daemon no longer polls. It blocks on the `p2p0` link state via netlink and wakes only on real events; a 60 s heartbeat reads a few sysfs bytes as a safety net. Previously 0.21 % of one core, 43,200 wakeups per day.
- **Disconnect restore in ~1.5 s** — fixed `sleep` calls replaced with state polling.
- **Launcher swap can no longer strand you** — if the current default home can't be resolved, the swap is skipped entirely. Third-party launchers are captured and restored verbatim.
- **Dense probe after a link event** — a `p2p0` link event only means the P2P group is up; the virtual display registers several seconds later, so the daemon now probes at 1 Hz for up to 30 s.

### Fixed
- `DENSITY_FALLBACK` was referenced but never defined — a sink reporting density `0` left the phone at 640 dpi (a 480×270 dp canvas)
- Removed the `inotifyd` drm watcher: it self-excited against the module's own sysfs reads and pushed idle CPU to 0.55 %
- A dead link watcher is restarted instead of silently degrading to the heartbeat
- `uninstall.sh` now waits for the daemon to finish restoring before wiping state, and reaps orphan watchers
- `extd stop` no longer races a second restore against the daemon's own
- Launcher restore is verified instead of assumed
- Numeric size parsing is guarded against empty fields
- ShellCheck clean at `-S info`

### Notes
- Wired DP hotplug is detected by the 60 s heartbeat — sysfs emits no hotplug notification. `extd on` applies immediately.
- **ColorOS 16 / realme UI 7 only.** Adapted and verified on a single **realme GT 8 (RMX6699)**.
- Requires **[Lawnchair Launcher](https://github.com/LawnchairLauncher/lawnchair)**.
