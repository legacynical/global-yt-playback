;=========== CONTROLS ===========
; Change keys in code if you don't have media keys
; Media_Prev = Rewind
; Media_Next = FastForward
; Media_Play_Pause = Play/Pause (no script needed to work)
; <#` (LWin + `) = display active window stats
; <#1 (LWin + 1) = pair currently active application/window
; <#2 (LWin + 2) = pair/toggle 2nd window
; <#3 (LWin + 3) = pair/toggle 3rd window
; ^<#1 (Ctrl + LWin + 1) = unpair main workspace
; ^<#2 (Ctrl + LWin + 2) = unpair 2nd window
; ^<#3 (Ctrl + LWin + 3) = unpair 3rd window
; ^` (CTRL + `) = open GUI

#Requires AutoHotkey v2.0
#SingleInstance ; Prompt to replace instance if already running
#Warn ; For debugging
InstallKeybdHook ; Allow use of additional special keys
; SendMode Input ; (AHKv2 default) Recommended for new scripts due to its superior speed and reliability.
; SetWorkingDir A_ScriptDir ; (AHKv2 default) Force script to use its own folder as working directory.
; SetTitleMatchMode 2 ; (AHKv2 default) Allow WinTitle to be matched anywhere from a window's title

video := "YouTube" ; Replace with "ahk_exe chrome.exe" if not working (use your browser.exe)
workspace := "A" ; Initialize default workspace to active window
win1IsPaired := win2IsPaired := win3IsPaired := win4IsPaired := win5IsPaired := false
win2ID := win3ID := win4ID := win5ID := ""

Media_Prev::YoutubeRewind5(video, workspace)

YoutubeRewind5(video, workspace)
{
	if WinExist(video) 
	{
		WinActivate
		sleep 11 ; Delay rounds to nearest multiple of 10 or 15.6 ms
		Send "{Left}" ; YT rewind 5 seconds
		sleep 11
		if WinExist(workspace) 
			WinActivate
	}
}

^Media_Prev::YoutubeRewind10(video, workspace)

YoutubeRewind10(video, workspace)
{
	if WinExist(video) 
	{
		WinActivate
		sleep 11 ; Delay rounds to nearest multiple of 10 or 15.6 ms
		Send "{j}" ; YT rewind 10 seconds
		sleep 11		
		if WinExist(workspace) 
			WinActivate
	}
}

Media_Next::YoutubeFastforward5(video, workspace)

YoutubeFastforward5(video, workspace)
{
	if WinExist(video)
	{
		WinActivate
		sleep 11
		Send "{Right}" ; YT fast forward 10 seconds
		sleep 11
		if WinExist(workspace) 
			WinActivate
	}
}

^Media_Next::YoutubeFastforward10(video, workspace)

YoutubeFastforward10(video, workspace)
{
	if WinExist(video)
	{
		WinActivate
		sleep 11
		Send "{l}" ; YT fast forward 5 seconds
		sleep 11
		if WinExist(workspace) 
			WinActivate
	}
}

; Redundant code for Media_Play_Pause (most browsers allow this)
; Media_Play_Pause::YoutubePlayPause(video, workspace)

; YoutubeFastforward(video, workspace)
; {
; 	if WinExist(video)
; 	{
; 		WinActivate
; 		sleep 11
; 		Send {k} ; YT play/pause
; 		sleep 11
; 		if WinExist(workspace) 
; 			WinActivate
; 	}
; }

; If you don't have Media_Play_Pause key, uncomment line below and set hotkey
; hotkey::Media_Play_Pause

GetWinInfo()
{
	global winTitle := WinGetTitle("A")
	global winId := WinGetID("A")
	global winClass := WinGetClass("A")
	global winProcess := WinGetProcessName("A")
}

<#`::DisplayActiveWindowStats()

DisplayActiveWindowStats()
{
	GetWinInfo()
	MsgBox "Active window title: " winTitle "`n"
        . "Active window ID: " winId "`n"
				. "Active window class: " winClass "`n"
        . "Active window process: " winProcess
}

<#1::PairMainWorkspace()

PairMainWorkspace()
{
	GetWinInfo()
	if (workspace == "A")
	{
		global workspace := "ahk_id " winId ; Change workspace to current active window
		global win1IsPaired := true
		MsgBox "[Pairing Main Workspace]`n"
					. "title: " winTitle "`n"
					. "workspace: " workspace "`n"
					. "process: " winProcess
	} else {
		MsgBox "Main Workspace already paired!"
	}

}

^<#1::UnpairMainWorkspace()

UnpairMainWorkspace()
{
	global win1IsPaired, workspace
	if (!win1IsPaired)
	{
		workspace := "A"
		win1IsPaired := false
		MsgBox "[Unpaired Window 2]"
	} else {
		MsgBox "Main Workspace is already unpaired!"
	}
}

<#2::Window2()

Window2()
{
	GetWinInfo()
	currentID := "ahk_id " winId
	global win2IsPaired, win2ID, workspace
	if (!win2IsPaired)
	{	
		if (workspace == "A")
		{
			MsgBox "Please pair a main workspace first!"
		} else if (currentID != workspace)
		{
			win2ID := currentID ; Change secondaryID to current active window
			win2IsPaired := true
			MsgBox "[Pairing Window 2]`n"
						. "title: " winTitle "`n"
						. "window 2: " win2ID "`n"
						. "process: " winProcess
		} else {
			win2IsPaired := false
			MsgBox "Current Window is already a main workspace!`n"
						. "Please choose a different window."
		}
	} else if (currentID != win2ID)
		{
			if WinExist(win2ID)
				WinActivate
		} else if (currentID == win2ID)
			{
				if WinExist(workspace)	
					WinActivate
			}
}

^<#2::UnpairWindow2()

UnpairWindow2()
{
	global win2IsPaired, win2ID
	if (win2IsPaired)
	{
		win2ID := ""
		win2IsPaired := false
		MsgBox "[Unpaired Window 2]"
	} else {
		MsgBox "Window 2 is already unpaired!"
	}
}

<#3::Window3()

Window3()
{
	GetWinInfo()
	currentID := "ahk_id " winId
	global win3IsPaired, win3ID, workspace
	if (!win3IsPaired)
	{	
		if (workspace == "A")
		{
			MsgBox "Please pair a main workspace first!"
		} else if (currentID != workspace)
		{
			win3ID := currentID ; Change secondaryID to current active window
			win3IsPaired := true
			MsgBox "[Pairing Window 3]`n"
						. "title: " winTitle "`n"
						. "window 2: " win3ID "`n"
						. "process: " winProcess
		} else {
			win3IsPaired := false
			MsgBox "Current Window is already a main workspace!`n"
						. "Please choose a different window."
		}
	} else if (currentID != win3ID)
		{
			if WinExist(win3ID)
				WinActivate
		} else if (currentID == win3ID)
			{
				if WinExist(workspace)	
					WinActivate
			}
}

^<#3::UnpairWindow3()

UnpairWindow3()
{
	global win3IsPaired, win3ID
	if (win3IsPaired)
	{
		win3ID := ""
		win3IsPaired := false
		MsgBox "[Unpaired Window 3]"
	} else {
		MsgBox "Window 3 is already unpaired!"
	}
}


;=========== GUI ===========
; not currently functional, need to read more docs and play around

^`::OpenGUI()

OpenGUI()
{
	GetWinInfo()
  activeProcess := winProcess
    
  ; Create GUI
	MyGui := Gui()
  MyGui.Add("Text",, "Active window process: " activeProcess)
  MyGui.AddEdit(activeProcess)
  Btn := MyGui.Add("Button", "default xm", "OK")  ; xm puts it at the bottom left corner.
	Btn.OnEvent("Click", ProcessUserInput)
	MyGui.OnEvent("Close", ProcessUserInput)
	MyGui.OnEvent("Escape", ProcessUserInput)  
	MyGui.Show()

	ProcessUserInput(*)
	{
		Saved := MyGui.Submit()  ; Save the contents of named controls into an object.
		MsgBox("You entered: " Saved.activeProcess)
	}
}
