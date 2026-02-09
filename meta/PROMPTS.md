# Din

I want a simple macOS music player with basic 'playlist' support: I want it to have a single playlist. It should use macOS vibrancy effects. No need to support artwork (yet). For form factor I'm thinking of the 'VOX' music player: simple controls on top, with below it a list of songs. 
The controls should show (not in this order) play/pause, next/prev, volume control. There should be an (interactive) progress indicator, which states the current time in song and the total length of the song. I want to be able to right click a bunch of files in Finder and select 'Open with ...' and then have the application add the songs to the playlist and then start playing the first.
There should be a way to clear the playlist. And to remove selected items from the list.
When metadata is available, it should show Artist, Album and Song title. Otherwise name of the file. There should be a way to open the selected song in Finder.
When I drag a folder or file(s) on the top of the app (the control part), it should indicate that it'll clear the playlist and replace it with whatever is in the folder. When I drag it in the playlist area, then there should be an indicator of where the dragged content will be inserted into the playlist.

...

Cool, I managed to launch the app.
Some findings:
- When right clicking and opening a bunch of songs, it opened a new window for each song. None of the windows actually had an item in their playlist (also when trying to open a single song)
- When I dragged songs into a single window, and pressed play, it didn't start playing. I expected the first item in the list to play.
- There is no selected state for items in the playlist. Should be possible to select multiple items.
- The controls are enabled (and the play/pause button changes appearance) when there are no items in the playlist
- There should be a menu item that allows for opening folder(s) and file(s), shortcut: CMD-O. Clears playlist.
- There should be another menu item that allows for adding folder(s) and files(s), shortcut: CMD-SHIFT-O. Appends to playlist.
- When there is no album or artist information, then the ui element can just be hidden.
- At the bottom of the controls, just above the playlist there should be a UI element that shows the number of playlist items and the total playing time. The 'Clear playlist' button should go there (on the right side). There should also be a button there to toggle repeat (for the full playlist only).
- Songs in the playlist should be able to be swiped on in order to delete them, like in the macOS Mail app for instance.

...

Great, improvements are working great.
Here are some more findings:
- Opening multiple files with right click still opened multiple windows. The app should limit the amount of windows to 1.
- Color of indicator icon for current playing song should use the system color
- Rows in the playlist should all have the same color, separated by a subtle thin line
- Rows should always have the same height, even if there is less content (no artist/album info). The song title should then be vertically centered.
- When closing and opening Din, it should remember its state (playlist / playback position / volume / repeat).
- The volume control should just be a volume icon, which when hovered / clicked shows a slider as a popup.
- The playback controls should be horizontally centered. Keep the volume control on the right.

...

- Make the playlist summary horizontally centered
- Pressing space should trigger pause / play. `[` should trigger previous song, `]` should trigger next song
- The control section should keep the same height, independent from whether artist/album info is shown (so when no info is available, it should just show empty space).
- In the 'View' menu, there are 'Show Tab Bar' and 'Show All Tabs' items. Clicking them actually adds a useles tab bar. Disable tabs for the application.
- Sometimes clicking and double clicking an item doesn't seem to register (I'm using the trackpad)

...

- Selection of item works properly now (also when lightly tapping the trackpad (I've configured macOS with 'tap to click' on)). Double clicking/tapping items doesn't work reliably.
- Items in the playlist should be able to drag to reorder
- When dragging items from Finder, the items should be inserted at the dropped position.

...

- Reordering gives some weird kind of flickering and it doesn't work most of the tiem. This also happens when I try to drag in an item from Finder.
- I can move the selection with the keyboard (up/down) but then I want to have 'Enter' (or return) to start playing the selected song (or the first selected in case of multi-selection).

...

- Reordergin when the application is not playing anything works great. However, as soon as the app is playing, there is flickering again.

...

- The flickering is little less, but it is still there.

...

- The flickering is still there. Could it have anything to do with the current playing item indicator?

...

- The flickering is still there alas.

...

Great, the flickering problem seems solve now!

- Holding shift while pressing `[` or `]` should skip a few seconds backward/forward in time respectively
- The changes to the playlist should be undoable and redoable.
- The app should respond to the Mac's 'play', 'prev' and 'next' buttons

...

- Holding shift and pressing `[` or `]` doesn't seem to work yet. I just hear the default bleeb that indicates that a key event was rejected.
- The app doesn't respond to the Mac's 'play', 'prev' and 'next' buttons yet: does it need a permission or some configuration of some sort?

...

Thanks! FYI: you forgot to remove the if-else for checking whether a modifier was pressed. I updated it and now it works nicely!

- Pressing the next/prev media keys seems to skip 2 tracks instead of 1

...

- Make it possible to save and load playlists to/from m3u8 files

...
