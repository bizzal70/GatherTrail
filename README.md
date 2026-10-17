# GatherTrail

Remembers where your characters find things, works out the best place to go for more, and guides you there. An addon for World of Warcraft: Forever (client 1.60.x).

**This is a beta.** See "What is and is not proven" below.

## What it tracks

| | Recorded when you |
|---|---|
| **Ore** | mine a vein, fail to, or point at one |
| **Herbs** | pick one, fail to, or point at one |
| **Fishing pools** | point at a pool, or fish it after pointing at it |
| **Skinning spots** | skin a creature (filed under the leather it gave) |
| **Treasure chests** | open one, or point at one |
| **Rare creatures** | see one, kill and loot one, or the game marks one on the minimap |

Every character on your account adds to the same history, including characters that cannot gather: pointing at a vein with a character who has no Mining still records it.

## Using it

Click the pickaxe button on the minimap, or type `/gt`.

1. Pick a tab (Ore, Herbs, Fish, Skins, Chests, Rares) and, if you like, one or more types in the list.
2. The right side ranks the zones you have records in. Hover a zone to see how its score was reached.
3. Press **Start route**. An arrow shows the way to the next stop, the game's own map marker is placed on it, and the route is drawn on the world map with numbered stops.

The ranking weighs how many nodes a zone has and how often they have been there, how short a loop they make, how far away the zone is, whether it is above your level or hostile to your faction, and whether you have the skill for the nodes.

GatherTrail starts empty. It has no built-in database; everything it knows, it learned from your own play.

## Getting between zones

As you play it also records flight masters (when you open a flight map), the places you walk from one zone into another, and transports such as boats. A route to another zone then comes with steps: go to this flight master, fly there, cross here.

## Options

The **Options** button in the window, or these commands:

| Command | What it does |
|---|---|
| `/gt` | Open the window |
| `/gt route` | Route through every node in the zone you are in |
| `/gt skip`, `/gt stop` | Skip to the next stop, or stop the route |
| `/gt show ore` (or `herb`, `fish`, `skin`, `chest`, `rare`) | Show or hide one kind of pin |
| `/gt pins`, `/gt minimap` | Show or hide pins on the world map or minimap |
| `/gt beacon`, `/gt sound` | The in-world marker, and the sound on reaching a stop |
| `/gt detect` | Record nodes you point at on the minimap |
| `/gt zone`, `/gt stats`, `/gt travel` | What is known about this zone, your records, and travel |
| `/gt forget` | Delete the record nearest to you |
| `/gt help` | List every command |

Export and import are on the Options page. An export is plain text you can keep as a backup or give to a friend; importing never loses anything you already have.

## What is and is not proven

Confirmed working in the game during the Forever beta:

- Mining, herbs, skinning and treasure chests, including failed attempts
- Pointing at nodes in the world and at tracking blips on the minimap
- Profession skill, zone crossings on foot, and zone levels learned from the creatures you meet
- The window, the Options page and the minimap pins

Written and tested outside the game, but not yet seen working in it:

- Fishing pools and rare creatures
- Flight masters and transports
- The marker in the world on the next stop

If one of these does not work for you, `/gt debug` prints what the game reports, which is what is needed to fix it.

## Known limits

- **English only.** Fishing pools, chests and ore blips on the minimap are recognised by English words in their names.
- **Routes are straight lines.** The addon knows where things are, not what is in the way.
- **Minimap blips are not read automatically.** The game does not tell addons where its tracking blips are, so you have to point at one for it to be recorded.
- **Combat.** The game restricts what addons may read during combat; a record that cannot be made is skipped.
- **Square minimaps** are not supported; pins assume a round one.

## Your data

Everything is saved on your own computer, in the game's saved-settings folder, as `GatherTrail.lua`. Nothing is sent anywhere.

## More from this author

Other small addons for World of Warcraft: Forever, all free:

- **[MouseTip](https://www.curseforge.com/wow/addons/mousetip)** shows tooltips at your mouse cursor.
- **[RangeShade](https://www.curseforge.com/wow/addons/rangeshade)** shades action buttons red when your target is out of range.
- **[VendorMate](https://github.com/bizzal70/VendorMate)** sells junk and repairs at vendors, and warns when your gear is wearing out.
- **[AltBoard](https://github.com/bizzal70/AltBoard)** shows all your characters at a glance: level, gold, rested and where you left them.
- **[SwiftQuest](https://github.com/bizzal70/SwiftQuest)** accepts quests and hands them in as soon as you talk to the quest giver, and can read them aloud so you still get the story.
- **[SessionRecap](https://github.com/bizzal70/SessionRecap)** keeps a running tally of your play session: gold, experience per hour, quests, gathering and loot.

## Installing

Copy this folder into `World of Warcraft\_classic_beta_\Interface\AddOns\` as `GatherTrail`, restart the game, and enable GatherTrail on the character select screen.

## Developing

- `tools\Link-Addon.ps1` links this folder into the game's AddOns folder, so edits are live after `/reload`.
- `python tests/run.py` runs the tests (`pip install lupa` once). They run the addon in real Lua 5.1 against a fake of the game's API.
- `tools\Publish.ps1 -Message "..."` runs the tests and pushes to GitHub. GitHub runs the tests again on every push.

## Releasing

`tools\Publish.ps1 -Message "Release x.y.z" -Tag vx.y.z` publishes and tags. The tag makes GitHub package the addon and attach the zip to a GitHub release. A tag with `beta` in it, such as `v0.17.0-beta1`, is released as a beta.

To also upload to CurseForge and Wago, two things are needed once:

1. Create the project on each site, then add its ID to `GatherTrail.toc`:
   `## X-Curse-Project-ID: 123456` and `## X-Wago-ID: abc123`.
2. Create an upload token on each site and add it to this repository's secrets (Settings, Secrets and variables, Actions) as `CF_API_KEY` and `WAGO_API_TOKEN`.

Before each release: raise `## Version:` in `GatherTrail.toc` and add the version to `CHANGELOG.md`.

## Licence

MIT. See `LICENSE`.
