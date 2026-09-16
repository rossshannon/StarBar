# Song Rating
macOS menu bar app for rating music in iTunes/Music.app

<img src="./Press/Snapshot.png" width=300 style="border-radius:4px">

This is Ross Shannon's fork of [MainasuK/Song-Rating](https://github.com/MainasuK/Song-Rating). It adds a favourite heart and fixes clicking on macOS 27.

## Requirements
- macOS 12 +

## Build and install
Needs Xcode. The build script finds Xcode even when `xcode-select` points at the Command Line Tools.

```bash
./build.sh              # Release build into build/
./build.sh --install    # Also replace /Applications/Song Rating.app and relaunch it
./build.sh --watch -i   # Rebuild and reinstall on source changes (needs fswatch)
```

The app is signed ad hoc ("Sign to Run Locally") with bundle ID `com.rossshannon.musicrating`. After a rebuild, macOS can ask again for permission to control Music.

## Using the menu bar
- **Click a star** to set that rating.
- **Half stars**: turn on "Half star" in Preferences. Then click the left half of a star, or the gap just before it, to set a half star. For example, click just left of the third star for 3½ stars. You can also drag across the stars.
- **Heart**: click the heart after the stars to mark the song as a favourite in Music. A filled heart means the song is a favourite.
- **Right-click** to open the player popover.

## FAQ
### Are half-star ratings saved?
Yes. Music stores a rating as a number from 0 to 100, where each star is 20. So 3½ stars is saved as 70. The Music app on the Mac can't display half stars, so it shows the whole stars only (70 shows as 3 stars). The value is still stored, Song Rating shows it, and smart playlist rules and AppleScript can use it.

To check a rating yourself:

```bash
osascript -e 'tell application "Music" to get {name, rating, favorited} of current track'
```

### Why is the favourite a heart when Music uses a star?
Music now uses a star for favourites and stars for ratings. In the menu bar, a heart keeps the favourite separate from the five rating stars. It is the same setting: Music's "Favorite" (called `favorited` in AppleScript, and `loved` in older versions).

### How can I check the track rating in iTunes/Music.app?  
Check the checkbox for "Star Ratings" in General preferences. [More info](https://support.apple.com/guide/music/general-preferences-mus4130f48/mac)

### Why the popover player sometimes follows to new screen scenes but sometimes not?
The popover will jump to new scren scene when it get focused. It will stand in the old screen if the current focused window not the popover.

### Why Song Rating not show star rating when iTunes/Music playing?
Please check the Security & Privacy settings and check the checkbox of Song Rating.
![Automation](./Press/Automation.png)

## License
Song Rating is released under the [MIT License](./LICENSE).
