## Global YouTube Playback   [![Ask DeepWiki](https://deepwiki.com/badge.svg)](https://deepwiki.com/legacynical/global-yt-playback)
**An AutoHotkey script to rewind/fast-forward youtube videos while focused on a different window.** <br>
**Creates hotkey macros for global youtube playback and paired window focus toggling.**

> *It's not that the few extra seconds I save from not having to move my mouse and click back and forth will increase my productivity, it's the satifaction of not having to deal with 
that and preventing occassional misfocused window mishaps that will get me to want to use 
it more and work longer.*
## Windows
### Running with AHK Installation
1. Install [AutoHotkey v2.0](https://www.autohotkey.com/)<br>
2. run the ` global-yt-playback-AHKv2.0.ahk ` script<br>
> [!TIP]
> Place script file (or script shortcut) in ` %APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup ` to autorun on startup.
### Running without AHK Installation
1. Download [latest GYTP release](https://github.com/legacynical/global-yt-playback/releases)<br>
2. run the GYTP.exe (right-click in system tray for ahk related settings/options, ``` Ctrl + ` ``` for GUI)
## Controls
> [!TIP]
> Change hotkeys in code if you don't have media keys or want to use different ones. <br>
> Refer to AHK's [Hotkeys](https://www.autohotkey.com/docs/v1/Hotkeys.htm) & [List of Keys](https://www.autohotkey.com/docs/v1/KeyList.htm) documentation for modifiers & keycodes.<br>

<pre>
        Media_Prev = YT rewind 5 sec<br>
 Ctrl + Media_Prev = YT rewind 10 sec<br>
  Media_Play_Pause = YT toggle play/pause (should work w/o script, see line 98)<br>
        Media_Next = YT fast forward 5 sec<br>
 Ctrl + Media_Next = YT fast forward 10 sec<br>
           Win + ` = display active window stats<br>
           Win + 1 = pair active as workspace<br>
       Win + [2-5] = pair active as window [2-5]<br>
    Ctrl + Win + 1 = unpair workspace<br>
Ctrl + Win + [2-5] = unpair window [2-5]<br>
    Ctrl + Win + 0 = unpair all windows<br>
          Ctrl + ` = open GUI (hint: ` is same key as ~)<br>
</pre>
## License
While I'm providing this AHK script under the MIT license, please note that the AHK interpreter is under the [GPL-2.0 license](https://github.com/AutoHotkey/AutoHotkey?tab=GPL-2.0-1-ov-file). This applies to compiled builds (.exe) as it packages both the AHK script and the AHK interpreter. For most users or developers, this shouldn't be of concern as the GPL-2.0 license itself is also quite permissive.
