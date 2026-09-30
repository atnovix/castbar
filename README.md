# CastBar — for a headless MacBook

**Made for a headless MacBook: a Touch Bar MacBook Pro without a (working) built-in display that is still pleasant
to use.** Cast to your TV with one tap on the Touch Bar, get a working keyboard backlight again, and keep the Mac from
staying awake in your bag.

Got a MacBook with a broken or removed screen that you want to keep using as a headless Mac, with an external
monitor, a TV, or no display at all? This is for you.

Built by [Atnovix](https://atnovix.com) for a 16" MacBook Pro (2019) whose display broke and was removed. It now runs
on an external USB-C monitor or casts to a TV.

🇳🇱 *Nederlandse samenvatting: zie [In het kort (Nederlands)](#in-het-kort-nederlands) onderaan.*

## What's inside

| Component | What it does |
|---|---|
| **CastBar** | A logo in the Touch Bar's Control Strip. Tap it and every screen on your network shows up as a button; tap a TV and your screen is mirrored to it. |
| **WakeGuard** | A locked Mac that wakes up and isn't unlocked with Touch ID within a few seconds goes straight back to sleep. Handy when it's in your bag. |
| **Keyboard backlight** | Turns off automatic brightness so the backlight works again without the ambient light sensor that lived in the display. |
| **Claude button** | A second button next to the logo: opens [Claude Code](https://claude.com/claude-code) in Terminal, in the folder of the frontmost Finder window. |

## CastBar

- **AirPlay** (Apple TV, AirPlay TVs): turns on *Screen Mirroring* through Control Center.
- **Chromecast / Google TV**: macOS can't cast to Chromecast by itself, so CastBar drives Google Chrome
  (*View › Cast… › Sources › Cast screen*) and confirms the share dialog (entire screen, system audio included).
- Only devices that can show video are listed (AirPlay `features` bit 7, Chromecast `ca` bit 0), so speakers such
  as HomePod and Google Home are left out. Devices that Chrome can only use for "specific video sites" are hidden
  after one attempt.
- The device you're casting to turns **blue** and a red **Stop** button appears. Tapping the device again stops too.
  **Orange** means it's connecting or stopping.
- No monitor attached and nothing connected? The list opens by itself.

## WakeGuard

Waking itself can't be blocked: the T2 chip handles it before macOS runs. WakeGuard makes sure the Mac goes back to
sleep quickly if it stays locked:

| Situation | Time to unlock |
|---|---|
| Just locked | 10 s |
| Woken by the Touch ID button (`EC.PowerButton`) | 15 s |
| Woken by a key or the trackpad (`EC.KeyboardTouchpad`) | 3 s |

With a monitor attached you can still type your password as a fallback: it stays awake while you type, up to 45 s.

## Requirements

- Intel MacBook Pro **with Touch Bar** (2016–2020), tested on macOS 14 Sonoma
- macOS in **Dutch** (see *Limitations*)
- Command Line Tools (`xcode-select --install`)
- Google Chrome, only needed for Chromecast

## Installation

```sh
git clone https://github.com/atnovix/castbar.git
cd castbar
./install.sh
```

`install.sh`:
1. creates a code-signing certificate *CastBar Local Signing* in your login keychain (once);
2. builds `~/Applications/CastBar.app` and `~/.local/bin/wakeguard`;
3. installs the LaunchAgents, so everything starts at login and restarts after a crash;
4. pins *Screen Mirroring* to the menu bar (CastBar drives AirPlay through that menu).

Then grant permissions in **System Settings › Privacy & Security**:

| Permission | For |
|---|---|
| Accessibility | CastBar |
| Screen & System Audio Recording | Google Chrome (casting to Chromecast) |
| Automation › Finder | CastBar (Claude button; asked the first time) |

After changing the code, `./build.sh` rebuilds only what changed and restarts that component. Thanks to the
certificate, the Accessibility permission stays valid.

## How it works

- **Touch Bar**: private APIs, the same ones [MTMR](https://github.com/Toxblh/MTMR) and
  [Pock](https://github.com/pock/pock) use (`NSTouchBarItem addSystemTrayItem:`,
  `NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:`,
  `DFRElementSetControlStripPresenceForIdentifier`). macOS removes the icon when the list is closed or the Control
  Strip is expanded; CastBar puts it back.
- **Finding devices**: Bonjour (`_airplay._tcp`, `_googlecast._tcp`), filtered on their TXT records.
- **Connecting**: Accessibility (AX) drives the *Screen Mirroring* menu and Chrome's cast dialog.
- **Keyboard backlight**: `KeyboardBrightnessClient` from the private CoreBrightness framework, through
  JavaScript for Automation (`osascript -l JavaScript`), so no compiler is needed.
- **WakeGuard**: wake reason from `IOPMrootDomain`, lock state from `CGSessionCopyCurrentDictionary`,
  `pmset sleepnow` to sleep.

## Limitations

- The automation looks for the **Dutch** labels of macOS and Chrome ("Weergave", "Casten…", "Bronnen",
  "Scherm casten", "Je volledige scherm delen", "Delen", …). For another language, change them in `Mirroring.swift`.
- Private APIs can change with a macOS update.
- CastBar doesn't see connections started outside CastBar.
- AirPlay with no display at all (no monitor, so no menu bar) hasn't been tested.

## Troubleshooting

**`redefinition of module 'SwiftBridging'` when building.** An older Command Line Tools install leaves
`/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap` behind, which clashes with
`bridging.modulemap`. Fix:

```sh
sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap ~/module.modulemap.bak
```

Without sudo you can use a clone instead (APFS, takes no extra space); `build.sh` picks it up automatically:

```sh
cp -cR /Library/Developer/CommandLineTools ~/.local/clt
rm ~/.local/clt/usr/include/swift/module.modulemap
```

**Logo gone from the Touch Bar.** Collapse the Control Strip; CastBar puts it back within a few seconds.

**Logs**: `~/Library/Logs/castbar.log` and `~/Library/Logs/wakeguard.log`.

## Tools

- `tools/axtool dump|press <bundle-id> …`: explore an app's Accessibility tree, or press an element.
- `tools/whiten in.png out.png`: turns black pixels white, for logos on the black Touch Bar.

## Lid sensor

Nothing to do. The sensor sits in the bottom case and reacts to magnets in the display, so without a display macOS
always sees the lid as open (`AppleClamshellState = No`).

## In het kort (Nederlands)

**Geschikt voor een headless MacBook**: een MacBook Pro met Touch Bar waarvan het ingebouwde scherm kapot of
verwijderd is.

- **CastBar**: tik op het logo in de Touch Bar en kies een tv. AirPlay (Apple TV) gaat via *Synchrone weergave*,
  Chromecast / Google TV via Google Chrome. Blauw = verbonden, nogmaals tikken of **Stop** = stoppen.
- **WakeGuard**: vergrendeld en niet met Touch ID ontgrendeld? Dan gaat hij binnen enkele seconden weer slapen, ook in
  je tas.
- **Toetsenbordverlichting**: werkt weer, ook zonder de lichtsensor uit het scherm.

**Installeren:**

```sh
git clone https://github.com/atnovix/castbar.git
cd castbar
./install.sh
```

Daarna in **Systeeminstellingen › Privacy en beveiliging**: *Toegankelijkheid* aan voor CastBar, en
*Scherm- en systeemaudio-opname* aan voor Google Chrome.

**Let op:** de automatisering werkt met een **Nederlandstalige** macOS en Chrome.

## License

[MIT](LICENSE) © Atnovix
