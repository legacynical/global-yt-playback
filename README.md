### Description
**An AutoHotkey script to rewind/fast-forward youtube videos while focused on a different window.** <br>
**Creates hotkey macros for global youtube playback and paired window focus toggling.**

> *It's not that the few extra seconds I save from not having to move my mouse and click back and forth will increase my productivity, it's the satifaction of not having to deal with 
that and preventing occassional misfocused window mishaps that will get me to want to use 
it more and work longer.*
### Installation (Windows)
1. Install [AutoHotkey](https://www.autohotkey.com/) <br>
2. run 'global-yt-playback-v1.0.ahk'
### Controls
> [!TIP]
> Change hotkeys in code if you don't have media keys or want to use different ones. <br>
Refer to AHK's [Hotkeys](https://www.autohotkey.com/docs/v1/Hotkeys.htm) & [List of Keys](https://www.autohotkey.com/docs/v1/KeyList.htm) documentation for modifiers & keycodes.

Media_Prev = Rewind <br>
Media_Next = FastForward <br>
Media_Play_Pause = Play/Pause (no script needed to work) <br>
LWin + ` = display active window stats <br>
LWin + 1 = pair currently active application/window as main workspace <br>
LWin + 2 = pair secondary window / toggle focus between main workspace & secondary window <br>
Ctrl + Lwin + 2 = unpair secondary window <br>
