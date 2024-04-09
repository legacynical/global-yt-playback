;=========== CONTROLS ===========
; Change keys in code if you don't have media keys
; Media_Prev = Rewind
; Media_Next = FastForward
; Media_Play_Pause = Play/Pause (no script needed to work)
; <#` (LWin + `) = display active window stats
; <#1 (LWin + 1) = pair currently active application/window
; <#2 (LWin + 2) = pair secondary window
; ^<#2 (Ctrl + LWin + 2) = unpair secondary window
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
secondaryIsPaired := false
secondaryID := ""

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
; 	Send {k} ; YT play/pause
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

<#1::PairActiveWindow()

PairActiveWindow()
{
	GetWinInfo()
	global workspace := "ahk_id " winId ; Change workspace to current active window
	MsgBox "[Pairing Current Active Window]`n"
				. "title: " winTitle "`n"
				. "workspace: " workspace "`n"
				. "process: " winProcess
}

<#2::ToggleSecondaryWindow()

ToggleSecondaryWindow()
{
	GetWinInfo()
	currentID := "ahk_id " winId
	global secondaryIsPaired, secondaryID, workspace
	if (!secondaryIsPaired)
	{	
		if (workspace == "A")
		{
			MsgBox "Please pair a primary workspace first!"
		} else if (currentID != workspace)
		{
			secondaryID := currentID ; Change secondaryID to current active window
			secondaryIsPaired := true
			MsgBox "[Pairing Secondary Window]`n"
						. "title: " winTitle "`n"
						. "secondary: " secondaryID "`n"
						. "process: " winProcess
		} else {
			secondaryIsPaired := false
			MsgBox "Current Window is already primary workspace!`n"
						. "Please choose a different window."
		}
	} else if (currentID != secondaryID)
		{
			if WinExist(secondaryID)
				WinActivate
		} else if (currentID == secondaryID)
			{
				if WinExist(workspace)	
					WinActivate
			}
}

^<#2::UnpairSecondaryWindow()

UnpairSecondaryWindow()
{
	global secondaryIsPaired, secondaryID
	if (secondaryIsPaired)
	{
		secondaryID := ""
		secondaryIsPaired := false
		MsgBox "[Unpaired Secondary Window]"
	} else {
		MsgBox "Secondary Window is already unpaired!"
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
