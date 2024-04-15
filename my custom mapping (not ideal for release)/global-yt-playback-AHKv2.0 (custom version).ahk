; ========== [CONTROLS] ===========
;            F19 = YT rewind 5 sec
;     Ctrl + F19 = YT rewind 10 sec
;            F20 = YT toggle play/pause
;            F21 = YT fast forward 5 sec
;     Ctrl + F21 = YT fast forward 10 sec
;        Win + ` = display active window stats
;        Win + 1 = pair active as workspace
;        Win + 2 = pair active as window 2
;        Win + 3 = pair active as window 3
;        Win + 4 = pair active as window 4
;        Win + 5 = pair active as window 5
; Ctrl + Win + 1 = unpair workspace
; Ctrl + Win + 2 = unpair window 2
; Ctrl + Win + 3 = unpair window 3
; Ctrl + Win + 4 = unpair window 4
; Ctrl + Win + 5 = unpair window 5
; Ctrl + Win + 0 = unpair all windows
;       Ctrl + ` = open GUI (not currently functional)

#Requires AutoHotkey v2.0
#SingleInstance ; Prompt to replace instance if already running
#Warn ; For debugging
InstallKeybdHook ; Allow use of additional special keys
; SendMode Input ; (AHKv2 default) Recommended for new scripts due to its superior speed and reliability.
; SetWorkingDir A_ScriptDir ; (AHKv2 default) Force script to use its own folder as working directory.
; SetTitleMatchMode 2 ; (AHKv2 default) Allow WinTitle to be matched anywhere from a window's title

video := "YouTube" ; Replace with "ahk_exe chrome.exe" if not working (use your browser.exe)
spotify := "ahk_exe Spotify.exe"
workspace := win2 := win3 := win4 := win5 := ""
win1IsPaired := win2IsPaired := win3IsPaired := win4IsPaired := win5IsPaired := false
inputBuffer := maxInputBuffer := 2 ; Used to reduce unwanted window minimize

F19::YoutubeRewind5(video, workspace)

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

^F19::YoutubeRewind10(video, workspace)

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

F20::YoutubePlayPause(video, workspace)

YoutubePlayPause(video, workspace)
{
	if WinExist(video)
	{
		WinActivate
		sleep 11
		Send "{k}" ; YT play/pause
		sleep 11
		if WinExist(workspace) 
			WinActivate
	}
}

F21::YoutubeFastforward5(video, workspace)

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

^F21::YoutubeFastforward10(video, workspace)

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

; Media_Prev::SpotifyPrevious(spotify)

; SpotifyPrevious(spotify)
; {
; 	if WinExist(spotify)
; 	{
; 		WinActivate
; 		sleep 11
; 		ControlSend "^{Left}"
; 		sleep 11
; 		if WinExist(workspace)
; 		{
; 			WinActivate
; 		}	else {
; 			WinMinimize
; 		}
; 	}
; }

Media_Play_Pause::SpotifyPlayPause(spotify)

SpotifyPlayPause(spotify)
{
	if WinExist(spotify)
		{
			WinActivate
			sleep 11
			Send "{Space}"
			sleep 11
			if WinExist(workspace)
			{
				WinActivate
			} else {
		 		WinMinimize
			}
		}
}

; Media_Next::SpotifyNext(spotify)

; SpotifyNext(spotify)
; {
; 	if WinExist(spotify)
; 		{
; 			WinActivate
; 			sleep 11
; 			Send "^{Right}"
; 			sleep 11
; 			if WinExist(workspace)
; 			{
; 				WinActivate
; 			}	else {
; 				WinMinimize
; 			}
; 		}
; }

; F22::

F23::SpotifyLowerVolume(spotify)

SpotifyLowerVolume(spotify)
{
	if WinExist(spotify)
	{
		

	}
}

F24::SpotifyRaiseVolume(spotify)

SpotifyRaiseVolume(spotify)
{
	if WinExist(spotify)
	{
		

	}
}

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
	global inputBuffer, maxInputBuffer
	GetWinInfo()
	if (workspace == "")
	{
		global workspace := "ahk_id " winId ; Sets workspace to current active window
		global win1IsPaired := true
		MsgBox "[Pairing Main Workspace]`n"
					. "title: " winTitle "`n"
					. "workspace: " workspace "`n"
					. "process: " winProcess,, "T3"
	} else if (currentID != workspace) {
		if WinExist(workspace)
		{
			inputBuffer := maxInputBuffer
			WinActivate
		}
	} else if (currentID == workspace) {
		inputBuffer--
		if (WinExist(workspace) && (inputBuffer == 0)) 
		{	
			inputBuffer := maxInputBuffer
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
	global inputBuffer, maxInputBuffer
	GetWinInfo()
	if (win2 == "")
	{
		global win2 := "ahk_id " winId ; Sets window 2 to current active window
		global win2IsPaired := true
		MsgBox "[Pairing Window 2]`n"
					. "title: " winTitle "`n"
					. "workspace: " workspace "`n"
					. "process: " winProcess,, "T3"
	} else if (currentID != win2) {
		if WinExist(win2)
		{
			inputBuffer := maxInputBuffer
			WinActivate
		}
	} else if (currentID == win2)	{
		inputBuffer--
		if (WinExist(win2) && (inputBuffer == 0))
		{	
			inputBuffer := maxInputBuffer
			WinMinimize
		}
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
	global inputBuffer, maxInputBuffer
	GetWinInfo()
	if (win3 == "")
	{
		global win3 := "ahk_id " winId ; Sets window 3 to current active window
		global win3IsPaired := true
		MsgBox "[Pairing Window 3]`n"
					. "title: " winTitle "`n"
					. "workspace: " workspace "`n"
					. "process: " winProcess,, "T3"
	} else if (currentID != win3) {
		if WinExist(win3)
		{
			inputBuffer := maxInputBuffer
			WinActivate
		}
	} else if (currentID == win3) {
		inputBuffer--
		if (WinExist(win3) && (inputBuffer == 0))
		{	
			inputBuffer := maxInputBuffer
			WinMinimize
		}
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

<#4::Window4()

Window4()
{
	global inputBuffer, maxInputBuffer
	GetWinInfo()
	if (win4 == "")
	{
		global win4 := "ahk_id " winId ; Sets window 4 to current active window
		global win4IsPaired := true
		MsgBox "[Pairing Window 4]`n"
					. "title: " winTitle "`n"
					. "workspace: " workspace "`n"
					. "process: " winProcess,, "T3"
	} else if (currentID != win4) {
		if WinExist(win4)
		{
			inputBuffer := maxInputBuffer
			WinActivate
		}
	} else if (currentID == win4) {
		inputBuffer--
		if (WinExist(win4) && (inputBuffer == 0))
		{	
			inputBuffer := maxInputBuffer
			WinMinimize
		}
	}	
}

^<#4::UnpairWindow4()

UnpairWindow4()
{
	global win4IsPaired, win4
	if (win4IsPaired)
	{
		win4 := ""
		win4IsPaired := false
		MsgBox "[Unpaired Window 4]",, "T1"
	} else {
		MsgBox "Window 4 is already unpaired!",, "T1"
	}
}

<#5::Window5()

Window5()
{
	global inputBuffer, maxInputBuffer
	GetWinInfo()
	if (win5 == "")
	{
		global win5 := "ahk_id " winId ; Sets window 5 to current active window
		global win5IsPaired := true
		MsgBox "[Pairing Window 5]`n"
					. "title: " winTitle "`n"
					. "workspace: " workspace "`n"
					. "process: " winProcess,, "T3"
	} else if (currentID != win5) {
		if WinExist(win5)
		{
			inputBuffer := maxInputBuffer
			WinActivate
		}
	} else if (currentID == win5) {
		inputBuffer--
		if (WinExist(win5) && (inputBuffer == 0))
		{	
			inputBuffer := maxInputBuffer
			WinMinimize
		}
	}	
}

^<#5::UnpairWindow5()

UnpairWindow5()
{
	global win5IsPaired, win5
	if (win5IsPaired)
	{
		win5 := ""
		win5IsPaired := false
		MsgBox "[Unpaired Window 5]",, "T1"
	} else {
		MsgBox "Window 5 is already unpaired!",, "T1"
	}
}

^<#0::UnpairAllWindows()

UnpairAllWindows()
{
	confirmUnpair := MsgBox("Are you sure you want to unpair all windows?",, "YesNo")
	if confirmUnpair = "Yes"
	{
		global workspace, win2, win3, win4, win5, win1IsPaired, win2IsPaired,
		win3IsPaired, win4IsPaired, win5IsPaired
		workspace := win2 := win3 := win4 := win5 := ""
		win1IsPaired := win2IsPaired := win3IsPaired := win4IsPaired := win5IsPaired := false
		MsgBox "[Unpaired All Windows]",, "T1"		
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
