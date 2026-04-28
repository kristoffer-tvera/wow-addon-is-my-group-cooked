# IsMyGroupCooked

A lightweight World of Warcraft addon that helps you quickly judge whether your freshly-formed group is ready for content — or whether it's time to bail with a polite excuse.

When you join a party or raid, IsMyGroupCooked pops up a small window listing each member, class-colored, with their equipped item level. If the verdict is "yes, we are cooked," one click sends a friendly farewell to group chat and drops you from the group.

## Features

- Auto-shows a group summary window when you join a party or raid
- Lists each member with **Name - Realm** and **equipped item level**
- Names are colored by class
- Inspects group members in the background to retrieve item levels, with caching
- Two action buttons:
  - **I guess this'll do** — closes the window
  - **Get me out of here** — sends a random polite goodbye to group chat and leaves the group
- Movable window (drag to reposition)
- Slash commands to re-open the panel any time

## Installation

1. Download or clone this repository.
2. Copy the folder into your WoW `Interface/AddOns/` directory and make sure it is named `IsMyGroupCooked` (the folder name must match the `.toc` file).
3. Restart WoW or reload the UI (`/reload`).
4. Make sure the addon is enabled on the character select screen.

## Usage

- Join a group — the window appears automatically after a short delay.
- Or run one of the slash commands at any time:
  - `/cooked`
  - `/ismygroupcooked`

## Leave Messages

When you click **Get me out of here**, one of the following messages is sent to party/raid chat before you leave:

- "Goodbye"
- "Have a nice evening"
- "I have to go, sorry!"

## Compatibility

Supports retail WoW interface versions `120000`, `120001`, and `120005` (see [IsMyGroupCooked.toc](IsMyGroupCooked.toc)).

## License

See [LICENSE](LICENSE).
