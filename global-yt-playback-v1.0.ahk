;=========== CONTROLS ===========
; Change keys in code if you don't have media keys
; Media_Prev = Rewind
; Media_Next = FastForward
; Media_Play_Pause = Play/Pause (no script needed to work)
; <#` (LWin + `) = display active window stats
; <#1 (LWin + 1) = pair currently active application/window
; <#2 (LWin + 2) = pair secondary window
; ^<#2 (Ctrl + LWin + 2) = unpair secondary window

#Requires AutoHotkey v1.1.37.01
#InstallKeybdHook ; Allow use of additional special keys
#SingleInstance ; Prompt to replace instance if already running
#Warn ; For debugging
SendMode Input ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir% ; Force script to use its own folder as working directory.
SetTitleMatchMode 2 ; Allow WinTitle to be matched anywhere from a window's title

video := "YouTube" ; Replace with "ahk_exe chrome.exe" if not working (use your browser.exe)
workspace := "A" ; Initialize default workspace to active window
secondaryIsPaired := false
secondaryID := ""

Media_Prev::YoutubeRewind(video, workspace)

YoutubeRewind(video, workspace)
{
	if WinExist(video) 
	{
		WinActivate
		sleep 11
		Send j
		sleep 11
		
		if WinExist(workspace)
		{
			WinActivate
		}
	}
}

Media_Next::YoutubeFastforward(video, workspace)

YoutubeFastforward(video, workspace)
{
	if WinExist(video)
	{
		WinActivate
		sleep 11
		Send l
		sleep 11
		
		if WinExist(workspace)
		{
			WinActivate
		}
	}
}

; If you don't have Media_Play_Pause key, uncomment line below and set hotkey
; hotkey::Media_Play_Pause

<#`::DisplayActiveWindowStats()

DisplayActiveWindowStats()
{
	WinGetTitle, title, A
	WinGet, id, ID, A
	WinGetClass, class, A
	WinGet, process, ProcessName, A
	MsgBox, % "Active window title: " title "`n"
        . "Active window ID: " id "`n"
				. "Active window class: " class "`n"
        . "Active window process: " process
}

<#1::PairActiveWindow()

PairActiveWindow()
{
	WinGetTitle, title, A
	WinGet, id, ID, A
	WinGet, process, ProcessName, A
	global workspace := % "ahk_id " id ; Change workspace to current active window
	MsgBox, % "[Pairing Current Active Window]`n"
				. "title: " title "`n"
				. "workspace: " workspace "`n"
				. "process: " process
}

<#2::ToggleSecondaryWindow()

ToggleSecondaryWindow()
{
	WinGetTitle, title, A
	WinGet, id, ID, A
	WinGet, process, ProcessName, A
	currentID := % "ahk_id " id
	global secondaryIsPaired, secondaryID, workspace
	if (!secondaryIsPaired)
	{	
		if (workspace == "A")
		{
			MsgBox, "Please pair a primary workspace first!"
		} else if (currentID != workspace)
		{
			secondaryID := currentID ; Change secondaryID to current active window
			secondaryIsPaired := true
			MsgBox, % "[Pairing Secondary Window]`n"
						. "title: " title "`n"
						. "secondary: " secondaryID "`n"
						. "process: " process
		} else {
			secondaryIsPaired := false
			MsgBox, "Current Window is already primary workspace!`n"
						. "Please choose a different window"
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
		MsgBox, % "[Unpaired Secondary Window]"
	} else {
		MsgBox, % "Secondary Window is already unpaired!"
	}

}