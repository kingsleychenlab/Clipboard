<div align="center">

<img src="docs/icon.png" width="128" alt="Clipboard">

# Clipboard

**A Spotlight-style clipboard history for macOS.**

Press `Cmd+Shift+V` anywhere · type to filter · hit Enter · it pastes itself.

</div>

## Install

Requires macOS 13+. No Xcode needed — Command Line Tools are enough.

```sh
git clone https://github.com/USERNAME/clipboard.git
cd clipboard
./install.sh
```

That builds it, installs it to `/Applications`, and starts it. Nothing will
appear on screen — that's correct, it has no dock or menu bar icon. Press
`Cmd+Shift+V`.

**Grant Accessibility.** The first time you press Enter on a clip, macOS will ask
for Accessibility permission — it's required to send the `Cmd+V` keystroke for
you. Approve it under **System Settings → Privacy & Security → Accessibility**.
Without it everything still works; you just press `Cmd+V` yourself.

**Start it at login.** **System Settings → General → Login Items → `+` →
Clipboard**

## Use

Press `Cmd+Shift+V` from any app. The overlay appears with your recent clips,
newest first. Type to narrow them down, pick one, and it pastes into whatever you
were doing.

| Key | Action |
| --- | --- |
| `Cmd+Shift+V` | Show / hide the overlay |
| *type* | Filter clips (fuzzy — `hw` matches `hello world`) |
| `↑` `↓` | Move selection |
| `Enter` | Paste the selected clip into the app you came from |
| `Cmd+Delete` | Delete the selected clip for good |
| `Esc` | Dismiss |

Clicking outside dismisses it too. The mouse is never required — though hovering
a row reveals a trash button if you'd rather click.

Deleting only forgets the app's copy; whatever is on your system clipboard right
now stays there.

It keeps your last 100 clips — text and images — and remembers them across
restarts. Clips your password manager marks as concealed are never recorded.
