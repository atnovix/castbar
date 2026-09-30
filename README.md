# CastBar — voor een headless MacBook

**Geschikt voor een headless MacBook: een MacBook Pro met Touch Bar zonder (werkend) ingebouwd scherm, toch
prettig bruikbaar.** Casten naar je tv met één tik op de Touch Bar, een werkende toetsenbordverlichting, en een Mac
die in je tas niet wakker blijft.

Heb je een MacBook met een kapot of verwijderd scherm die je als headless Mac wilt blijven gebruiken, met een
externe monitor, een tv of helemaal zonder beeld? Dan is dit voor jou.

> *English summary:* tools for running a **headless MacBook**, a 2016–2020 Intel MacBook Pro whose built-in display is broken or has been removed:
> a Touch Bar button that lists AirPlay and Chromecast screens and mirrors to them with one tap, a fix for the
> keyboard backlight (the ambient light sensor lived in the display), and a guard that puts the Mac back to sleep
> when it's woken while locked. The UI automation targets **Dutch** macOS and Chrome; see *Beperkingen*.

Gemaakt door [Atnovix](https://atnovix.com) voor een MacBook Pro 16" (2019) waarvan het scherm kapot was en is
verwijderd. Hij draait nu op een externe USB-C-monitor of cast naar een tv.

## Wat zit erin

| Onderdeel | Wat het doet |
|---|---|
| **CastBar** | Logo in de Control Strip van de Touch Bar. Tik erop en alle schermen op je netwerk verschijnen als knoppen: tik op een tv en je scherm wordt erheen gecast. |
| **WakeGuard** | Vergrendelde Mac die wakker wordt en niet binnen enkele seconden met Touch ID wordt ontgrendeld, gaat weer slapen. Handig als hij in je tas zit. |
| **Toetsenbordverlichting** | Zet de automatische helderheid uit, zodat de verlichting weer werkt zonder de lichtsensor uit het scherm. |
| **Claude-knop** | Tweede knop naast het logo: opent [Claude Code](https://claude.com/claude-code) in Terminal, in de map van het voorste Finder-venster. |

## CastBar

- **AirPlay** (Apple TV, AirPlay-tv's): zet *Synchrone weergave* aan via Bedieningscentrum.
- **Chromecast / Google TV**: macOS kan zelf niet naar Chromecast casten, dus CastBar gebruikt Google Chrome
  (*Weergave › Casten… › Bronnen › Scherm casten*) en bevestigt het deelvenster (volledig scherm, systeemaudio mee).
- Alleen apparaten die beeld kunnen tonen komen in de lijst (AirPlay `features` bit 7, Chromecast `ca` bit 0).
  Speakers zoals HomePod en Google Home vallen weg. Apparaten die in Chrome alleen "specifieke videosites" kunnen
  afspelen worden na één poging verborgen.
- Het apparaat waarnaar je cast wordt **blauw** en er verschijnt een rode **Stop**-knop. Nogmaals op het apparaat
  tikken stopt ook. **Oranje** = bezig met verbinden of stoppen.
- Geen monitor aangesloten en nergens mee verbonden? Dan springt de lijst vanzelf open.

## WakeGuard

Het ontwaken zelf is niet te blokkeren: dat regelt de T2-chip voordat macOS draait. WakeGuard zorgt dat hij snel
weer gaat slapen als hij vergrendeld blijft:

| Situatie | Tijd om te ontgrendelen |
|---|---|
| Net vergrendeld | 10 s |
| Gewekt door de Touch ID-knop (`EC.PowerButton`) | 15 s |
| Gewekt door toets of trackpad (`EC.KeyboardTouchpad`) | 3 s |

Met een monitor aangesloten kun je als reserve je wachtwoord typen: zolang je typt blijft hij wakker, maximaal 45 s.

## Vereisten

- Intel MacBook Pro **met Touch Bar** (2016–2020), getest op macOS 14 Sonoma
- macOS in het **Nederlands** (zie *Beperkingen*)
- Command Line Tools (`xcode-select --install`)
- Google Chrome, alleen nodig voor Chromecast

## Installeren

```sh
git clone https://github.com/atnovix/castbar.git
cd castbar
./install.sh
```

`install.sh`:
1. maakt eenmalig een eigen ondertekeningscertificaat *CastBar Local Signing* in je login-sleutelhanger;
2. bouwt `~/Applications/CastBar.app` en `~/.local/bin/wakeguard`;
3. zet de LaunchAgents neer, zodat alles bij het inloggen start en na een crash herstart;
4. zet *Synchrone weergave* vast in de menubalk (CastBar bedient AirPlay via dat menu).

Daarna nog rechten geven in **Systeeminstellingen › Privacy en beveiliging**:

| Recht | Voor |
|---|---|
| Toegankelijkheid | CastBar |
| Scherm- en systeemaudio-opname | Google Chrome (casten naar Chromecast) |
| Automatisering › Finder | CastBar (Claude-knop; wordt de eerste keer gevraagd) |

Na een codewijziging: `./build.sh` bouwt alleen wat veranderd is en herstart het betreffende onderdeel. Dankzij het
eigen certificaat blijft het Toegankelijkheid-vinkje dan geldig.

## Hoe het werkt

- **Touch Bar**: private API's, dezelfde als [MTMR](https://github.com/Toxblh/MTMR) en
  [Pock](https://github.com/pock/pock) gebruiken (`NSTouchBarItem addSystemTrayItem:`,
  `NSTouchBar presentSystemModalTouchBar:placement:systemTrayItemIdentifier:`,
  `DFRElementSetControlStripPresenceForIdentifier`). macOS haalt het icoon weg na sluiten of uitklappen van de
  Control Strip; CastBar zet het terug.
- **Apparaten zoeken**: Bonjour (`_airplay._tcp`, `_googlecast._tcp`), gefilterd op de TXT-records.
- **Verbinden**: Toegankelijkheid (AX) bedient het menu *Synchrone weergave* en het cast-venster van Chrome.
- **Toetsenbordverlichting**: `KeyboardBrightnessClient` uit het private CoreBrightness-framework, via
  JavaScript for Automation (`osascript -l JavaScript`); er is geen compiler voor nodig.
- **WakeGuard**: wekreden uit `IOPMrootDomain`, vergrendelstatus uit `CGSessionCopyCurrentDictionary`,
  `pmset sleepnow` om te slapen.

## Beperkingen

- De automatisering zoekt op **Nederlandse** teksten van macOS en Chrome ("Weergave", "Casten…", "Bronnen",
  "Scherm casten", "Je volledige scherm delen", "Delen", …). In een andere taal moeten die in `Mirroring.swift` worden
  aangepast.
- Private API's kunnen bij een macOS-update veranderen.
- Een verbinding die buiten CastBar om is gestart, ziet CastBar niet.
- AirPlay zonder enig scherm (geen monitor, dus geen menubalk) is niet getest.

## Problemen

**`redefinition of module 'SwiftBridging'` bij bouwen.** Een oudere Command Line Tools-installatie laat
`/Library/Developer/CommandLineTools/usr/include/swift/module.modulemap` achter, dat botst met `bridging.modulemap`.
Oplossen:

```sh
sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap ~/module.modulemap.bak
```

Zonder sudo kan het ook met een kloon (APFS, neemt geen ruimte in); `build.sh` gebruikt die automatisch:

```sh
cp -cR /Library/Developer/CommandLineTools ~/.local/clt
rm ~/.local/clt/usr/include/swift/module.modulemap
```

**Logo verdwenen uit de Touch Bar.** Klap de Control Strip in; CastBar zet het binnen een paar seconden terug.

**Logs**: `~/Library/Logs/castbar.log` en `~/Library/Logs/wakeguard.log`.

## Hulpmiddelen

- `tools/axtool dump|press <bundle-id> …`: verken de Toegankelijkheid-boom van een app, of druk op een element.
- `tools/whiten in.png out.png`: maakt zwarte pixels wit, voor logo's op de zwarte Touch Bar.

## Klepsensor

Er is geen actie nodig. De sensor zit in de onderkant van de laptop en reageert op magneten in het scherm. Zonder
scherm ziet macOS de klep dus altijd als open (`AppleClamshellState = No`).

## Licentie

[MIT](LICENSE) © Atnovix
