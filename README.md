# TWoW Bulk Mail

Bulk mail sending addon for **Turtle WoW (Vanilla / Interface 11200)**.

## Install

- Put the `TWoWBulkMail` folder in `Interface/AddOns/`.
- Reload UI or restart the game.

## Usage

1. Open a mailbox.
2. Go to the **Send Mail** tab.
3. Use the **TWoW Bulk Mail Send Queue** window:
   - **Alt-Click** items in your bags to add/remove them from the queue.
   - Or drag & drop items into the drop area.
4. Click **AutoSend Rules** to define destinations and rules.
5. Click **Send** to start bulk sending.

While sending:
- **Pause/Resume** pauses or continues the pipeline.
- **Stop** stops sending and shows a per-item log in **Last run**.

## Commands

- `/bm` or `/bulkmail` (opens the command root)
- `/bm autosend edit` (toggle AutoSend Rules window)

## Notes

- Sending **money** may trigger the `SEND_MONEY` confirmation popup; the addon auto-confirms this during bulk sending.
- Subject/body and per-destination options only fill fields when the UI fields are empty.

## Credits

This addon is based on the original **BulkMail2** (2.3.3-era) addon:
- BulkMail2 by **hyperactiveChipmunk**, with later maintenance and updates by **NeoTron** and other contributors.

It embeds and uses several Ace2-era libraries, including (non-exhaustive):
- Ace2 (AceAddon/AceDB/AceEvent/AceHook/AceConsole/AceLocale/AceLibrary)
- Tablet-2.0, Dewdrop-2.0, Abacus-2.0, Gratuity-2.0
- PeriodicTable-2.0
