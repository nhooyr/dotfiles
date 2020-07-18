# Install

<!-- START doctoc generated TOC please keep comment here to allow auto update -->
<!-- DON'T EDIT THIS SECTION, INSTEAD RE-RUN doctoc TO UPDATE -->

- [1. Fresh macOS install](#1-fresh-macos-install)
- [2. Adjust system preferences](#2-adjust-system-preferences)
- [3. Notification Center](#3-notification-center)
- [4. Install apps](#4-install-apps)
- [5. Prune dock](#5-prune-dock)
- [6. Setup Apps](#6-setup-apps)

<!-- END doctoc generated TOC please keep comment here to allow auto update -->

# 1. Fresh macOS install

- Enable everything but Siri.

# 2. Adjust system preferences

1.  General -> Set menu bar to autohide.
1.  Desktop & Screen Saver -> Switch to Mojave Night.
1.  Dock
    1. Minimize using scale effect.
    1. Enable auto-hide.
1.  Mission Control -> Group windows by application.
1.  Notifications
    1. Enable Do Not Disturb when display is sleeping and locked.
    1. Sort order Recents by App.
1.  Internet Accounts
    1. Disable iCloud mail.
1.  Make sure addresses are correct in Walet.
1.  Add middle and ring finger to Touch ID.
1.  Security & Privacy
    1. Enable Apple Watch unlock.
    1. Enable Firewall.
    1. Add Terminal.app to Developer Tools in Privacy.
    1. Add Terminal.app to Full Disk Access.
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
    1. Disable spotlight shortcut.
1.  Trackpad
    1. Make click light.
    1. Set tracking speed to 6.
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
   - Disable all 1Password notifications.
1. Clone into `~/src/nhooyr/dotfiles`.
1. Clone secrets into `~/src/nhooyr/dotfiles/secrets`
1. Run [`./bootstrap.sh`](./bootstrap.sh)

# 5. Prune dock

1. Finder
1. Safari
1. Mail
1. Calendar
1. Reminders
1. Notes
1. Spotify
1. Terminal

# 6. Setup Apps

1. Finder
   1. Enable keep folders on top and remove items from trash in advanced.
   1. Set view to list and make it the default.
   1. Enable path bar.
   1. Sidebar should be:
      1. Recents
      1. AirDrop
      1. ~
      1. ~/src/nhooyr
1. Safari
   1. Safari opens with `All windows from last session`.
   1. Homepage and search should be https://duckduckgo.com.
      - Remember to load duckduckgo settings.
   1. Show website icons in tabs.
   1. Remove Back/Forward, 1Password and Tab Preview from toolbar
   1. Disable autofill of usernames and passwords.
   1. Show full website address.
   1. Show Develop menu.
   1. Configure DDG as appropriate.
   1. Save reading list offline automatically.
1. wipr
1. Alfred
   1. Set theme to macOS.
      - Hide hat, result shortcuts and menu bar.
   1. Setup only clipboard history on `Cmd+Shift+v` with 3 months duration.
   1. Disable snippets in clipboard history integration.
1. Terminal.app
   1. Import settings.
1. BetterTouchTool
   1. Import the preset.
   1. Disable the menu bar icon.
   1. Enable launch on startup.
   1. Window snapping
      1. Disable border width, animation and rounded corners.
      1. Set padding space to 40px.
      1. Disable window size resoration if dragged.
   1. Set rotation degree requirement to 10.
   1. Disable scroll between pages with three fingers.
1. Setup Fastmail and Google in Internet Accounts.
   1. Change Fastmail description to `nhooyr`.
   1. Enable only Mail for Fastmail.
   1. Enable only Mail and Calendars for Google.
1. Slack
   1. codercom.slack.com
   1. gophers.slack.com
1. Setup Parallels.
   1. Disable menu bar icon.
