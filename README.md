You know how sometimes a blog or web form eats your comment or you lose some text and break your undo history and you wish you could rewind and see what was on your screen some minutes or hours ago?
I made a script to do that that has saved my butt more than once. 
It's also handy for checking things like what time you left the office.

All it does is take screenshots of all your displays every minute on the minute.
It stores them as images in a directory with filenames indicating the time of day of the screenshot.
That's effectively a circular buffer as screenshots that are 24 hours old get overwritten by new ones.
That way you always have a record of what was on your screen(s) over the last 24 hours.

## Optimizations

If the screenshot image for any display hasn't changed from the previous minute, it skips saving that image.
Also if your machine has been idle since the last screenshot, it skips the screenshots for all displays, whether or not the screen has changed.

We use lossy compression (jpeg or webp) and set the quality as low as possible without making any text unreadable.
The whole collection of images should be at most around a gigabyte, even with huge external displays.

## Normal Usage

After following the setup instructions below, here's everything you need to know to make use of this thing.
Filenames are, e.g., "scr2cap-13-59.jpg" for a screencap of display 2 at 1:59pm.
Say it's now 2:30pm and you want to see what was on your primary display in the last hour.
By running `open scr1cap-1[34]*` you can flip through everything starting at 1pm in Preview.app or whatever your default image viewer is.
You can skip forward to scr1cap-13-30.jpg to start at 1:30pm.
Or just highlight whatever range of files in Finder and double click to open them all at once.

## Setup Instructions

This assumes some command-line savviness.
Roughly you're setting up the Bash script crumbshot.sh to run every minute in the background.
That should be a pretty negligible use of your machine's resources.

Doing all this once will make scrumbs run indefinitely, including after rebooting your machine.

1. Create a directory for the screenshots to live, like `~/scrumbs`.
1. Put the crumbshot script somewhere on your machine, say `~/bin/crumbshot.sh`.
1. Run the following to install ImageMagick (used to compare and compress the image files):  
`brew install imagemagick`
1. Edit the paths in the script as needed (you'll definitely need to edit where it says "EDIT ME").
1. Run the the following to make it executable:  
`chmod a+x ~/bin/crumbshot.sh`
1. Add a line like the following to your cronfile.
Typically you edit your cronfile with `crontab -e`.  
`* * * * * ~/bin/crumbshot.sh`
1. Go to macOS Privacy & Security settings and give Full Disk Access to:  
`/bin/bash`  
`/usr/sbin/cron`  
1. Also in Privacy & Security settings, give Screen & System Audio Recording permission to:  
`/usr/sbin/cron`  

## Alternatives, courtesy of GPT-5

| Tool                       | Type                                          | Multi-display support                              | Rolling buffer behavior                                | Cost                               | Notable bits                          | Source                                           |
| -------------------------- | --------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------ | ---------------------------------- | ------------------------------------- | ------------------------------------------------ |
| TimeSnapper                | Periodic **screenshots**                      | “Active monitor, **all monitors**, or app window.” | Configurable interval + **auto-cleanup of old images** | **\$29.99**                        | Timeline “play back your week”        | ([Apple][1])                                     |
| Near North Screenshots     | Periodic **screenshots**                      | Multi-display handling discussed by devs/users     | **Keep N days** (auto-cleanup by days)                 | **\$19.99**                        | Day timeline; timesheet/report extras | ([nearnorthsoftware.com][2])                     |
| Auto Shot – Screenshot App | Periodic **screenshots**                      | “Support for **multiple monitors**”                | Cap count & interval (bounded history)                 | **Free**                           | Simple set-and-forget automation      | ([Apple][3])                                     |
| timeLAPSE                  | Periodic **screenshots** → optional timelapse | (Not stated)                                       | Save to folder; interval **1s–24h**                    | **\$9.99**                         | Very lightweight                      | ([Apple][4])                                     |
| RetroClip                  | **Instant-replay video** (RAM buffer)         | (Not stated)                                       | Keeps **last \~5 min** in memory; save on hotkey       | **Free**                           | Zero disk use until you save          | ([Apple][5])                                     |
| QAReplay                   | **Instant-replay video**                      | (Not explicit)                                     | Save **last 15/30/60/120 s**                           | **Free**                           | Cross-platform; bug-repro focused     | ([qareplay.com][6], [qareplay.macupdate.com][7]) |
| Screen Timelapse Lite      | **Timelapse video**                           | Claims **multi-screen**                            | Timelapse rather than ring buffer                      | **Free** (IAP full version listed) | Menu-bar controller                   | ([Apple][8])                                     |
| Screenpipe (open-source)   | Continuous **capture + OCR/search**           | Docs/community note multi-monitor                  | 24/7 local index (heavier than a buffer)               | **Free (open-source)**             | Rewind-like searchability             | ([github.com][9], [screenpi.pe][10])             |

[1]: https://apps.apple.com/us/app/timesnapper/id1456327684?mt=12 "
      ‎TimeSnapper on the Mac App Store
    "
[2]: https://www.nearnorthsoftware.com/software/screenshots.php?utm_source=chatgpt.com "Near North Screenshots"
[3]: https://apps.apple.com/us/app/auto-shot-screenshot-app/id6746736808?mt=12 "
      ‎Auto Shot - Screenshot App on the Mac App Store
    "
[4]: https://apps.apple.com/us/app/timelapse/id449502656?mt=12&utm_source=chatgpt.com "timeLAPSE on the Mac App Store"
[5]: https://apps.apple.com/us/app/retroclip/id1332064978?mt=12&utm_source=chatgpt.com "RetroClip on the Mac App Store"
[6]: https://qareplay.com/?utm_source=chatgpt.com "QAReplay"
[7]: https://qareplay.macupdate.com/?utm_source=chatgpt.com "Download QAReplay for Mac | MacUpdate"
[8]: https://apps.apple.com/us/app/screen-timelapse-lite/id1452228487?mt=12&utm_source=chatgpt.com "Screen Timelapse lite on the Mac App Store"
[9]: https://github.com/mediar-ai/screenpipe?utm_source=chatgpt.com "mediar-ai/screenpipe: AI app store powered by 24/7 ..."
[10]: https://screenpi.pe/?utm_source=chatgpt.com "screenpipe | computer use AI SDK"


## Optional Quantified-Self Thing

Separately, here's a bit of Wolfram code to touch all possible `24*60*numscreens` files, if you don't want missing files when the display is off.
It's safe to run any time -- it only touches files that don't exist. 
And the only reason to bother is that it can be handy for treating the screenshot timestamps as quantified-self data, like, "I've never been awake at 4am since I started running this on such-and-such date".
(Also this only makes sense if crumbshot.sh never deletes, only overwrites, existing screencap images.)

```
path = "~/scrumbs/";
numscreens = Length[SystemInformation["Devices", "ScreenInformation"]];
numcreated = 0;
prn["Screens: ", numscreens];
each[s_, Range[1, numscreens], 
  each[h_, Range[0, 23], 
    each[m_, Range[0, 59], 
      f = cat[path, "scr", s, "cap-", If[h < 10, "0", ""], h, "-", 
                                      If[m < 10, "0", ""], m, ".webp"];
      If[! FileExistsQ[f],
        numcreated++;
        CreateFile[f];
        SetFileDate[f, DateObject[{1970, 1, 1}]]]]]];
prn["Files created: ", numcreated];
```

<details style="cursor: pointer">
<summary><i>Changelog</i></summary>
<pre>
2025-08-27: Cleanup and add some utility scripts
2025-08-21: Automatically remove screencaps older than 24 hours
2025-08-20: Use webp image format, auto-determine number of displays
2025-08-19: Lots of refactoring and aborted wild ideas
2025-08-17: Created github.com/dreeves/scrumbs
2025-08-13: Added this changelog and improved the README a lot
2024:       Added instructions to make it work on modern macOS
2023ish:    Switched to Rewind.ai for a while
2023ish:    This broke when I upgraded to macOS Catalina
2017ish:    I originally wrote this
</pre>
</details>

## Scratch Area with Scattered Notes To Self

There's something conceptually wrong here.
Having older screenshots scattered among the ones within the 24-hour window is confusing. 
What would make sense is to pick how far back you want to save images and just cull everything older.

How about this:
1. Configurable horizon (limited to natural ones like 1h, 12h, 24h, 1w, 1m, 1y?)  
2. Configurable freq (period) like 60s  
3. When crumbshot starts it deletes all scrumbs at or outside the horizon  
4. Like if it's 1:59pm now then delete scrNcap-13-59.webp  
5. If machine idle for more than freq, exit  
6. Otherwise, save the screenshots  

Now you can have a tight freq and long horizon and you'll only use disk space in proportion to how often you actively use your computer. 
If you're using too much disk space, just crank down the horizon and you'll free space immediately.
If you relax the freq you'll start using less space going forward.

Overengineering idea: freq is a function of age.
So when crumbshot (or a separate reaper script) starts, it never culls the very oldest screenshot but as it walks forward in time it culls a smaller and smaller fraction of them.
Then you could have, say, screenshots every second in the most recent hour.
For 24 hours ago up to 1 hour ago, maybe you have screenshots every minute. etc.

Traditionally I've stored 1 screenshot per display for every minute in the previous 24 hours. 
If a screencapture ever failed it would leave the previous images alone.
That made for 1440 image files per display (and 3 displays, so 4320 total).

Instead I could:
1. Keep crumbshot.sh dirt simple, always blowing away the files for the current HH-MM and then storing new ones if the screencapture succeeds.  
2. Periodically run a sweeper that culls unneeded screencaps.  

Function to determine if a screencap is a keeper:

```
keeper(sc)
  let t be the last-modified time of sc
  let a be the age of sc in seconds, now - t
  let pred be the predecessor screencap, per the HH-MM in the filename
  if no predecessor then return true
  let succ be the successor screencap
  if no successor then return true
  let tp be the last-modified time of pred
  let ts be the last-modified time of succ
  # retain daily up to a year, hourly up to a month, 5-minutely up to a week,
  # minutely up to a day, 30-secondly up to 12 hours, and secondly up to an hour
  if a >= 1 year and ts-tp <= 1 day then return false
  if a >= 1 month and ts-tp <= 1 hour then return false
  if a >= 1 week and ts-tp <= 5 minutes then return false
  if a >= 1 day and ts-tp <= 1 minute then return false
  if a >= 12 hours and ts-tp <= 30 seconds then return false
  if a >= 1 hour and ts-tp <= 1 second then return false
  if imagediff(pred, sc) == 0 then return false
```

Or walk forward in time starting from the oldest file.
Initialize the previous timestamp, pt, to -infinity.
For each file, i, use i's age to determined the desired freq.
Then delete i if the delta from pt is less than that freq.
If we don't delete it, let pt = i.timestamp.
Continue to the next oldest file.

Theoretically that could delete too much, sort of. 
Like if you have these files:
1. 1.01 years old  
2. 1 year old      (3 days newer)  
3. 1 hour old  
Then you'll delete file 2 for being only a few days after file 1. but since 
there's more than a year between file 1 and file 3, you're creating too big a 
gap by doing so.

`[0, 3, 368] w/ gap=365`

The following algorithm (HT Gemini) I believe is correct:

```python
from typing import List
def cull_list(xs: List[float], G: float) -> List[float]:
  n = len(xs)
  if n <= 2: return xs[:]  # no interior points => nothing to cull
  out = [xs[0]]  # always keep the first element
  anchor = xs[0]
  for cur, nxt in zip(xs[1:-1], xs[2:]):  # interior windows
    if nxt - anchor >= G:
      out.append(cur)
      anchor = cur
  out.append(xs[-1])  # always keep the last element
  return out
```
