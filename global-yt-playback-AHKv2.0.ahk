; ========== [CONTROLS] ===========
;        Media_Prev = YT rewind 5 sec
; Ctrl + Media_Prev = YT rewind 10 sec
;  Media_Play_Pause = YT toggle play/pause (should work w/o script, see line 98)
;        Media_Next = YT fast forward 5 sec
; Ctrl + Media_Next = YT fast forward 10 sec
;           Win + ` = display active window stats
;           Win + 1 = pair active as workspace
;           Win + 2 = pair active as window 2
;           Win + 3 = pair active as window 3
;           Win + 4 = pair active as window 4
;           Win + 5 = pair active as window 5
;    Ctrl + Win + 1 = unpair workspace
;    Ctrl + Win + 2 = unpair window 2
;    Ctrl + Win + 3 = unpair window 3
;    Ctrl + Win + 4 = unpair window 4
;    Ctrl + Win + 5 = unpair window 5
;    Ctrl + Win + 0 = unpair all windows
;          Ctrl + ` = open GUI (currently under development)

#Requires AutoHotkey v2.0
#SingleInstance ; Prompt to replace instance if already running
#Warn ; For debugging
InstallKeybdHook ; Allow use of additional special keys
; SendMode Input ; (AHKv2 default) Recommended for new scripts due to its superior speed and reliability.
; SetWorkingDir A_ScriptDir ; (AHKv2 default) Force script to use its own folder as working directory.
; SetTitleMatchMode 2 ; (AHKv2 default) Allow WinTitle to be matched anywhere from a window's title

video := "YouTube" ; Replace with "ahk_exe chrome.exe" if not working (use your browser.exe)
workspace := win2 := win3 := win4 := win5 := ""
IsWinPaired1 := IsWinPaired2 := IsWinPaired3 := IsWinPaired4 := IsWinPaired5 := false
inputBuffer := maxInputBuffer := 2 ; Used to reduce unwanted window minimize

Media_Prev::YoutubeControl("rewind 5 sec", "{left}")
^Media_Prev::YoutubeControl("rewind 10 sec", "{j}")
Media_Next::YoutubeControl("fast forward 5 sec", "{Right}")
^Media_Next::YoutubeControl("fast forward 10 sec", "{l}")

; Most browsers allow this by default. If not, or you want to specifically target yt, then uncomment
; Media_Play_Pause::YoutubeControl("play/pause", "{k}")

; If you don't have Media_Play_Pause key, uncomment and set hotkey
; hotkey::Media_Play_Pause

YoutubeControl(action, keyPress) ; action param not used but added for clarity future use
{
	global video, workspace
	if WinExist(video) 
	{
		WinActivate
		sleep 11 ; Delay rounds to nearest multiple of 10 or 15.6 ms
		Send keyPress
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
	global inputBuffer, maxInputBuffer
	GetWinInfo()
	if (workspace == "")
	{
		global workspace := "ahk_id " winId ; Sets workspace to current active window
		global IsWinPaired1 := true
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
	global IsWinPaired1, workspace
	if (IsWinPaired1)
	{
		workspace := ""
		IsWinPaired1 := false
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
		global IsWinPaired2 := true
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
	global IsWinPaired2, win2
	if (IsWinPaired2)
	{
		win2 := ""
		IsWinPaired2 := false
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
		global IsWinPaired3 := true
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
	global IsWinPaired3, win3
	if (IsWinPaired3)
	{
		win3 := ""
		IsWinPaired3 := false
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
		global IsWinPaired4 := true
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
	global IsWinPaired4, win4
	if (IsWinPaired4)
	{
		win4 := ""
		IsWinPaired4 := false
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
		global IsWinPaired5 := true
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
	global IsWinPaired5, win5
	if (IsWinPaired5)
	{
		win5 := ""
		IsWinPaired5 := false
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
		global workspace, win2, win3, win4, win5, IsWinPaired1, IsWinPaired2,
		IsWinPaired3, IsWinPaired4, IsWinPaired5
		workspace := win2 := win3 := win4 := win5 := ""
		IsWinPaired1 := IsWinPaired2 := IsWinPaired3 := IsWinPaired4 := IsWinPaired5 := false
		MsgBox "[Unpaired All Windows]",, "T1"		
	}
}

;=========== GUI ===========
; currently under development

^`::OpenGUI()

OpenGUI()
{
	; Create the main GUI
	MainGui := Gui("+Resize", "Window Management")
	MainGui.Opt("+AlwaysOnTop")
	
	; Active Window Information Section
	GetWinInfo()
	MainGui.Add("Text", "w240 section", "Active Window Details:")
	MainGui.Add("Edit", "w240 vActiveTitle ReadOnly", winTitle)
	MainGui.Add("Edit", "w240 vActiveProcess ReadOnly", winProcess)
	MainGui.Add("Edit", "w240 vActiveClass ReadOnly", winClass)
	MainGui.Add("Edit", "w240 vActiveID ReadOnly", winId)
	
	; Window Pairing Section
	MainGui.Add("Text", "w240", "Window Pairing:")
	MainGui.Add("Button", "w240", "Set as Main Workspace").OnEvent("Click", PairWorkspace)
	MainGui.Add("Button", "w240", "Set as Window 2").OnEvent("Click", PairWindow2)
	MainGui.Add("Button", "w240", "Set as Window 3").OnEvent("Click", PairWindow3)
	MainGui.Add("Button", "w240", "Set as Window 4").OnEvent("Click", PairWindow4)
	MainGui.Add("Button", "w240", "Set as Window 5").OnEvent("Click", PairWindow5)
	
	; Unpair Options and Quick Actions
	MainGui.Add("Text", "w240", "Unpair Options and Quick Actions:")
	MainGui.Add("Button", "w240", "Unpair Workspace").OnEvent("Click", UnpairWorkspace)
	MainGui.Add("Button", "w240", "Unpair All Windows").OnEvent("Click", UnpairAll)
	MainGui.Add("Button", "w240", "Show Window Stats").OnEvent("Click", ShowWindowStats)
	MainGui.Add("Button", "w240", "Close").OnEvent("Click", (*) => MainGui.Destroy())
	
	; Show the GUI
	MainGui.Show("w260 h450")

	; Defined event handlers
	PairWorkspace(*)
	{
		MainWorkspace()
		MainGui.Destroy()
	}

	PairWindow2(*)
	{
		Window2()
		MainGui.Destroy()
	}

	PairWindow3(*)
	{
		Window3()
		MainGui.Destroy()
	}

	PairWindow4(*)
	{
		Window4()
		MainGui.Destroy()
	}

	PairWindow5(*)
	{
		Window5()
		MainGui.Destroy()
	}

	UnpairWorkspace(*)
	{
		UnpairMainWorkspace()
		MainGui.Destroy()
	}

	UnpairAll(*)
	{
		UnpairAllWindows()
		MainGui.Destroy()
	}

	ShowWindowStats(*)
	{
		DisplayActiveWindowStats()
	}
}