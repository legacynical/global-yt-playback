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
; Ctrl + Win + 1 = unpair workspace
; Ctrl + Win + 2 = unpair window 2
; Ctrl + Win + 3 = unpair window 3
;       Ctrl + ` = open GUI

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

YoutubeFastforward(video, workspace)
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
				WinActivate
		} else if (currentID == workspace)
			{
				if WinExist(workspace) 
					WinMinimize
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
