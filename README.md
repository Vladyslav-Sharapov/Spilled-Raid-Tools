# Spilled Raid Tools

A small raid leading addon for World of Warcraft (Retail / Midnight): one-click ground and target markers,
ready check with durability and Soulwell reminders, pull and break timers (BigWigs / DBM compatible),
buff and gear checks, guild invite and group sorting, a shared raid note and timed fight reminders.

## Install

Put the folder here (it must contain `SpilledRaidTools.toc` directly):

```
World of Warcraft\_retail_\Interface\AddOns\SpilledRaidTools\
```

If you download the repository as a zip, rename the folder from `Spilled-Raid-Tools` to `SpilledRaidTools`.
Then restart WoW or type `/reload`.

## The frame

| Button | What it does |
| --- | --- |
| Ground row | Left-click: place a world marker (then click the ground). Right-click: remove. X: clear all. |
| Target row | Left-click: mark your target. Right-click: clear. X: clear your target's mark. |
| Ready | Ready check. Announces "Everyone is ready!" or "Not ready: ...". Also raid-warns players below 40% durability and asks warlocks for a Soulwell. |
| Pull | Left: countdown (BigWigs / DBM show it) plus a raid warning countdown. Right: cancel. |
| Break | Left: break bar in BigWigs / DBM plus raid warning. Right: cancel. |
| Buffs | Checks food, flask, vantus rune and raid buffs, warns when food or flask runs out within 5 min. |
| Gear | Inspects everyone for missing enchants and empty gem sockets (about 1 sec per player). |
| Invite | Invites online max-level guild members up to a guild rank. |
| Promote | Gives raid assist to the guild ranks you choose (optionally automatic). |
| Sort | Left: sort groups in your order (default tanks, healers, melee, ranged). Right: groups board. |
| Mark tanks | Left: first tank Square, second tank Circle (changeable). Right: clear. |
| Raid note | Left: show / hide the note. Right: edit and send it. |
| Gear icon | Settings window (General, Checks, Roster, Groups, Note, Reminders). |
| Ready check icon | Next to the gear: show / hide the ready check window. |

Durability is only known for players who have this addon or MRT (it uses LibDurability's messages).

## Ready check window

On every ready check a window opens (like MRT's) with one line per player: ready status,
food and flask (with minutes left), vantus rune, missing raid buffs (hover for names) and durability.
It updates live and closes 5 seconds after the ready check ends. Right-click **Ready**
(or `/srt rcw`) opens it any time. Settings > Checks: turn it off, or show it only as lead / assist.

## Who posts

By default only the **raid leader and assists** (in a party: the leader) post automatic messages:
pulls / breaks / ready checks started by others, ready check results, durability, Soulwell and buffs.
Everyone else sees buff and gear check results only in their own chat. Turn on
**Post without lead / assist** (Settings > General) when you need it without assist.

## Ready check: one announcer

When a ready check starts, the buff check runs automatically (option) and the results
(not ready, low durability, Soulwell, buffs) are posted by **one** player only: the starter if they
have this addon, otherwise the addon user with the highest group rank (leader, then assist, then
alphabetical). Every copy of the addon works out the same answer, so nothing is posted twice.

MRT has its own "food / flask report on ready check". The option **Keep MRT's ready check report off**
(on by default) switches it off on your client so buffs are only posted once. Other players' MRT
can't be changed by an addon - ask them to turn that MRT option off if it is on.

Marker buttons show what is in use: markers that are placed (ground) or on a unit (target) are lit
with a glow, free ones are dimmed. Target marks are found on your target, focus, group members,
their targets and nameplates. If the game hides a mark (Midnight secret values), the free ones
are not dimmed, so you never see wrong info.

## Groups board

Open it with right-click on **Sort**, Settings > Groups, or `/srt groups`.

- Drag a player onto a group to move them, onto a player to swap them.
- Right-click a player to pin them to their group. Sort always keeps pinned players there.
- Change the sort order with Up / Down. Melee / ranged comes from the spec when known
  (the gear check reads it), otherwise it is guessed from the class.
- Only groups 1 to N are sorted (default 4), higher groups are left alone as bench.

## Raid note and fight reminders

Write the note in Settings > Note and click **Send to group**. Everyone with the addon sees it
(in a raid only leader / assist can send). **My reminders** is a second note only you see.

```
{time:2:20} Aura Mastery                  on screen 2:20 into the boss fight
{time:1:05} @Bob @Anna Use {spell:31821}  only Bob and Anna see it
{time:45} @healer Big damage soon         roles: @tank @healer @dps, classes: @priest @mage ...
{time:1:10}{time:3:40} Stack on {skull}   several times in one line
{boss:Plexus Sentinel}                    lines below only for this boss (name or encounter ID)
{boss:all}                                back to every boss
```

A reminder appears 5 seconds early with a countdown, then flashes with a sound at 0
(text to speech is optional). `{skull}`, `{cross}`, `{rt1}`..`{rt8}` and `{spell:ID}` show icons.
Test it with **Test reminders** (or `/srt test`) and move it with **Move display** (or `/srt move`).

## Presets

The Note and Groups tabs can save presets: type a name and click **Save**, then use the **Presets** menu to load or delete.

- Note presets keep the raid note and My reminders (load, then **Send to group**).
- Group presets keep who is in which group and the sort order. Loading one moves everyone
  back to their saved group (leader / assist, in a raid).

## Other players

Pulls, breaks and ready checks started by other players are announced too (option). If the starter
also has this addon, only they announce it, so nothing is posted twice.

In a raid, raid warnings need leader or assist, otherwise messages go to raid chat.

## Commands

```
/srt                show / hide the frame
/srt pull 15        set the default pull to 15 sec   (/srt pull = start a pull)
/srt break 5        set the default break to 5 min  (/srt break = start a break)
/srt rc             ready check
/srt buffs          buff check
/srt gear           gear check
/srt invite | promote | sort
/srt note           show / hide the raid note   (/srt note edit = editor)
/srt test [stop]    test fight reminders
/srt move           move the reminder display
/srt config         settings window
/srt groups         groups board
/srt lock | unlock | reset | debug
```

## Minimap button

Left-click: show / hide the frame. Right-click: settings. Drag to move it around the minimap.
It is also in the addon list button next to the minimap, and can be turned off in settings.

## License

[MIT](LICENSE)
