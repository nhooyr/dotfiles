<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

# dotfiles

- [1. Fresh macOS install](#1-fresh-macos-install)
- [2. Adjust system preferences](#2-adjust-system-preferences)
- [3. Notification Center](#3-notification-center)
- [4. Install apps](#4-install-apps)
- [5. Prune dock](#5-prune-dock)
- [6. Setup Apps](#6-setup-apps)
- [8. Setup Alfred](#8-setup-alfred)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# 1. Fresh macOS install

- Enable everything but Siri.

# 2. Adjust system preferences

1.  General -> Set menu bar to autohide.
1.  Desktop & Screen Saver -> Switch to Desert Moonlight.
1.  Dock
    1. Minimize using scale effect.
    1. Enable auto-hide.
    1. Disable show recent applications in Dock.
1.  Mission Control -> Group windows by application.
1.  Notifications
    1. Enable Do Not Disturb when display is sleeping and locked.
    1. Sort order Recents by App.
1.  Make sure addresses are correct in Walet.
1.  Add middle and ring finger to Touch ID.
1.  Security & Privacy
    1. Enable Apple Watch unlock.
    1. Enable Firewall.
1.  Bluetooth -> Show Bluetooth in menu bar.
1.  Sound
    1. 75% the alert volume.
    1. Show volume in menu bar.
1.  Keyboard
    1. Map Caps Lock to Escape.
    1. Touch Bar shows Expanded Control Strip.
    1. Press Fn key to Show App Controls.
    1. Add 6 spaces and then enable keybindings to quickly
       switch to them in Shortcuts -> Mission Control.
       Will require reopening preferences.
    1. Disable Show Input menu in menu bar.
    1. Customize control strip to include:
       1. Media
       1. Space
       1. Volume slider
       1. Brightness slider
       1. Screen lock
       1. Do Not Disturb
1.  Trackpad
    1. Make click light.
    1. Set tracking speed to 6.
    1. Swipe between pages to use 3 fingers.
    1. Mission control and App Expose to use 4 fingers.
1.  Displays
    1. Scaled to More Space.
    1. Disable show mirroring options in menu bar.
1.  Adjust battery indicator to show percentage.
1.  Date & Time -> Show date.
1.  Sharing -> Rename to ien.
1.  Set profile photo.

# 3. Notification Center

1. Today
1. Calendar
1. Tomorrow

# 4. Install apps

1. Install all apps purchased on the Mac App Store.
1. Setup 1Password.
   - Adjust all vaults to remove archived and occasional.
   - Change Show keybinding to `Opt + \` as `Opt + Cmd + \` causes random beeping.
1. Clone into `~/src/nhooyr/dotfiles`.
1. Clone secrets into `~/src/nhooyr/dotfiles/secrets`
1. Run [`./bootstrap.sh`](./bootstrap.sh)

# 5. Prune dock

1. Finder
1. Safari
1. Mail
1. Things
1. Calendar
1. Messages
1. Spotify
1. Terminal

# 6. Setup Apps

1. Safari
   1. Safari opens with `All windows from last session`.
   1. Homepage and search should be https://duckduckgo.com.
   1. Show website icons in tabs.
   1. Remove all toolbar icons except for Show/Hide Tab Overview.
   1. Disable autofill of usernames and passwords.
   1. Show full website address.
   1. Show Develop menu.
   1. Configure DDG as appropriate.
1. wipr
1. Alfred
   1. Only clipboard manager to `Cmd + Shift + v` otherwise prefer Spotlight.
1. Terminal.app
1. BetterTouchTool

# 8. Setup Alfred
