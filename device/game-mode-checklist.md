# Tab S7 — In-device settings checklist for Brawl Stars

Do these in order. No PC needed. ~15 minutes.

## 1. Force 120 Hz refresh rate

Settings → Display → Motion smoothness → **Adaptive** (it caps at 120).
Then immediately:

- Settings → Display → Screen resolution → **WQXGA+** (native).
- Settings → Display → Brightness → manual, ≥ 40%. Below 40% the panel
  drops to 60 Hz to save power. Do not use auto brightness while gaming.
- Settings → Display → Eye comfort shield → **OFF**. Blue light filter
  adds a compositor pass.

## 2. Game Booster Plus — install if missing

Galaxy Store → search "Game Booster Plus" by Samsung → install.

Then: Settings → Advanced features → Game Launcher → **ON**.
Open Game Launcher → settings (gear icon, top right) →

- Game performance: **Prioritize performance**
- Game Booster → **Block during game** → enable ALL:
  - Auto brightness
  - Edge panels
  - Navigation gestures (use 3-button nav while gaming — faster)
  - Screenshots via palm swipe (false triggers in Brawl Stars)
  - Alerts during game: notifications, calls — block both
- Game Booster → Resource priority → **Prioritize game** (not "balanced")
- Game Booster → Block touch on edge → **ON** (palm rejection)
- Game Booster → Memory boost → run it before each session

## 3. Add Brawl Stars to Game Launcher

Game Launcher → Library → tap "+" → add Brawl Stars.
Then long-press the tile → **Game settings** →

- Resolution: **Original** (Brawl Stars is 60 FPS capped; don't downscale)
- Frame rate: **Original**
- Performance: **Performance** profile
- Touch protection: **ON**

## 4. Battery + power

- Settings → Battery and device care → Battery → **More battery settings**:
  - Power saving: **OFF**
  - Adaptive battery: **OFF** (it deprioritizes Brawl Stars when not in
    foreground, causing reconnect spikes)
  - Background usage limits → Brawl Stars: **NOT** in any restricted list.
    Specifically remove it from "Deep sleeping apps" and
    "Never sleeping apps" should INCLUDE Brawl Stars.
- Plug in while playing. The 865+ throttles hard at ~42°C under battery
  drain; on charger with cool ambient, the SoC stays at boost clocks.

## 5. Background hygiene

- Settings → Apps → sort by "Recently opened" → for everything other than
  Brawl Stars and core system: **Force stop** before a session.
- Bixby Routines → create routine "When Brawl Stars opens":
  - Enable Do Not Disturb
  - Disable WiFi auto-switch to mobile data
  - Disable Bluetooth (if you're not using a controller)
  - Disable location

## 6. WiFi

- Settings → Connections → WiFi → your network → gear icon → **View more**:
  - Auto reconnect: ON
  - IP settings: **DHCP** (static doesn't help on consumer networks)
  - Privacy: **Use device MAC** (randomized MAC adds DHCP renegotiation
    spikes when roaming between APs)
- On your **router**, not the tablet:
  - Use 5 GHz band, channel width 80 MHz, manually pick channel 36, 40,
    44, 48, 149, 153, 157, or 161 (least crowded — check with WiFi
    Analyzer app).
  - Disable band steering and 802.11k/v/r if Tab S7 keeps roaming mid-game.
  - QoS: prioritize the Tab S7's MAC if your router supports it. Mark
    Brawl Stars traffic (UDP, Supercell ASN AS200449) as EF/voice class
    if you have DSCP-aware QoS.

## 7. DNS

Settings → Connections → More connection settings → Private DNS →
**Private DNS provider hostname** → `dns.cloudflare.com`

(Not "Automatic". Automatic uses your ISP's DNS which is usually slower
and sometimes routes through a different POP. Cloudflare's 1.1.1.1 over
TLS is typically 5–15 ms faster from a residential connection in NA/EU.)

## 8. Things NOT to do

- Don't use "RAM Plus" / "Extended RAM". It's swap to UFS storage; under
  memory pressure it causes the exact stutters you're trying to avoid.
- Don't install "ping reducer" or "game booster" apps from Play Store.
  They proxy your traffic through their server, adding hops. Samsung's
  built-in Game Booster Plus is the only one that's actually privileged.
- Don't enable "Developer options → Force GPU rendering" while Game
  Booster is on. They conflict and cause frame drops.
- Don't disable animations from Developer options if you're going to run
  `adb/optimize.sh` — that script does it.
