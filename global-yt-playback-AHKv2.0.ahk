; =========== CONTROLS ===========
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
workspace := win2 := win3 := win4 := win5 := ""
win1IsPaired := win2IsPaired := win3IsPaired := win4IsPaired := win5IsPaired := false
inputBuffer := 0 ; Used to reduce unwanted window minimize

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
		sleep 11
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
		Send "{Right}" ; YT fast forward 5 seconds
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
		Send "{l}" ; YT fast forward 10 seconds
		sleep 11
		if WinExist(workspace) 
			WinActivate
	}
}

; Redundant code for Media_Play_Pause (most browsers allow this, if not, then uncomment)
; Media_Play_Pause::YoutubePlayPause(video, workspace)

; YoutubeFastforward(video, workspace)
; {
; 	if WinExist(video)
; 	{
; 		WinActivate
; 		sleep 11
; 		Send {k} ; YT toggle play/pause
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
	global currentID := "ahk_id " winId
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

<#1::MainWorkspace()

MainWorkspace()
{
	global inputBuffer
	GetWinInfo()
	if (workspace == "")
	{
		global workspace := "ahk_id " winId ; Sets workspace to current active window
		global win1IsPaired := true
		MsgBox "[Pairing Main Workspace]`n"
					. "title: " winTitle "`n"
					. "workspace: " workspace "`n"
					. "process: " winProcess,, "T3"
	} else if (currentID != workspace) 
		{
			if WinExist(workspace)
			{
				inputBuffer := 0
				WinActivate
			}
		} else if (currentID == workspace)
			{
				inputBuffer++
				if (WinExist(workspace) && (inputBuffer == 2)) 
				{	
					inputBuffer := 0
					WinMinimize
				}
			}	
}

^<#1::UnpairMainWorkspace()

UnpairMainWorkspace()
{
	global win1IsPaired, workspace
	if (win1IsPaired)
	{
		workspace := ""
		win1IsPaired := false
		MsgBox "[Unpaired Main Workspace]",, "T1"
	} else {
		MsgBox "Main Workspace is already unpaired!",, "T1"
	}
}

<#2::Window2()

Window2()
{
	GetWinInfo()
	if (win2 == "")
	{
		global win2 := "ahk_id " winId ; Sets window 2 to current active window
		global win2IsPaired := true
		MsgBox "[Pairing Window 2]`n"
					. "title: " winTitle "`n"
					. "workspace: " workspace "`n"
					. "process: " winProcess,, "T3"
	} else if (currentID != win2) 
		{
			if WinExist(win2)
				WinActivate
		} else if (currentID == win2)
			{
				if WinExist(win2) 
					WinMinimize
			}	
}

^<#2::UnpairWindow2()

UnpairWindow2()
{
	global win2IsPaired, win2
	if (win2IsPaired)
	{
		win2 := ""
		win2IsPaired := false
		MsgBox "[Unpaired Window 2]",, "T1"
	} else {
		MsgBox "Window 2 is already unpaired!",, "T1"
	}
}

<#3::Window3()

Window3()
{
	GetWinInfo()
	if (win3 == "")
	{
		global win3 := "ahk_id " winId ; Sets window 3 to current active window
		global win3IsPaired := true
		MsgBox "[Pairing Window 3]`n"
					. "title: " winTitle "`n"
					. "workspace: " workspace "`n"
					. "process: " winProcess,, "T3"
	} else if (currentID != win3) 
		{
			if WinExist(win3)
				WinActivate
		} else if (currentID == win3)
			{
				if WinExist(win3) 
					WinMinimize
			}	
}

^<#3::UnpairWindow3()

UnpairWindow3()
{
	global win3IsPaired, win3
	if (win3IsPaired)
	{
		win3 := ""
		win3IsPaired := false
		MsgBox "[Unpaired Window 3]",, "T1"
	} else {
		MsgBox "Window 3 is already unpaired!",, "T1"
	}
}


<#0::UnpairAllWindows()

UnpairAllWindows()
{
	

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
