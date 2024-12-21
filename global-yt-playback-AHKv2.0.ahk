; ========== [CONTROLS] ===========
;        Media_Prev = YT rewind 5 sec
; Ctrl + Media_Prev = YT rewind 10 sec
;  Media_Play_Pause = YT toggle play/pause
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

Media_Prev:: YoutubeControl("rewind 5 sec", "{left}")
^Media_Prev:: YoutubeControl("rewind 10 sec", "{j}")
Media_Next:: YoutubeControl("fast forward 5 sec", "{Right}")
^Media_Next:: YoutubeControl("fast forward 10 sec", "{l}")
; Most browsers allow Media_Play_Pause by default but this ensures that it targets a YouTube tab
Media_Play_Pause:: YoutubeControl("play/pause", "{k}")

; If you don't have Media_Play_Pause key, uncomment and set hotkey
; hotkey::Media_Play_Pause

; action param not used but added for clarity future use
YoutubeControl(action, keyPress) {
	global video, workspace
	if WinExist(video) {
		WinActivate
		sleep 11 ; Delay rounds to nearest multiple of 10 or 15.6 ms
		Send keyPress
		sleep 11
		if WinExist(workspace)
			WinActivate
	}
}

GetWinInfo() {
	global
	winTitle := WinGetTitle("A")
	winId := WinGetID("A")
	winClass := WinGetClass("A")
	winProcess := WinGetProcessName("A")
	currentID := "ahk_id " winId
}

<#`:: DisplayActiveWindowStats()

DisplayActiveWindowStats() {
	GetWinInfo()
	MsgBox "Active window title: " winTitle "`n"
		. "Active window ID: " winId "`n"
		. "Active window class: " winClass "`n"
		. "Active window process: " winProcess
}

/*
Contrary to what Claude and ChatGPT suggests for AHKv2,
you DON'T use a depreciated ByRef keyword (which is CLEARLY STATED IN THE DOCS FOR AHKv2)
and instead the global vars have to be wrapped in "" for it to be
properly dereferenced with %% and assigned values (which is NOT CLEARLY STATED IN THE DOCS FOR AHKv2)
*/
<#1:: PairWindow("IsWinPaired1", "workspace", "Main Workspace")
<#2:: PairWindow("IsWinPaired2", "win2", "Window 2")
<#3:: PairWindow("IsWinPaired3", "win3", "Window 3")
<#4:: PairWindow("IsWinPaired4", "win4", "Window 4")
<#5:: PairWindow("IsWinPaired5", "win5", "Window 5")

PairWindow(pairedStatus, window, windowName) {
	global
	GetWinInfo()
	if (%window% == "") {
		%window% := "ahk_id " winId ;
		%pairedStatus% := true
		MsgBox "[Pairing " windowName "]`n"
			. "title: " winTitle "`n"
			. "workspace: " workspace "`n"
			. "process: " winProcess, , "T3"
	} else if (currentID != %window%) {
		if WinExist(%window%) {
			inputBuffer := maxInputBuffer
			WinActivate
		}
	} else if (currentID == %window%) {
		inputBuffer--
		if (WinExist(%window%) && (inputBuffer == 0)) {
			inputBuffer := maxInputBuffer
			WinMinimize
		}
	}
}

^<#1:: UnpairWindow("IsWinPaired1", "workspace", "Main Workspace")
^<#2:: UnpairWindow("IsWinPaired2", "win2", "Window 2")
^<#3:: UnpairWindow("IsWinPaired3", "win3", "Window 3")
^<#4:: UnpairWindow("IsWinPaired4", "win4", "Window 4")
^<#5:: UnpairWindow("IsWinPaired5", "win5", "Window 5")
^<#0:: UnpairAllWindows()

UnpairWindow(pairedStatus, window, windowName) {
	global
	if (%pairedStatus%) {
		%window% := ""
		%pairedStatus% := false
		MsgBox "[Unpaired " windowName "]", , "T1"
	} else {
		MsgBox "" windowName " is already unpaired!", , "T1"
	}
}

UnpairAllWindows() {
	confirmUnpair := MsgBox("Are you sure you want to unpair all windows?", , "YesNo")
	if confirmUnpair = "Yes" {
		global workspace, win2, win3, win4, win5, IsWinPaired1, IsWinPaired2,
			IsWinPaired3, IsWinPaired4, IsWinPaired5
		workspace := win2 := win3 := win4 := win5 := ""
		IsWinPaired1 := IsWinPaired2 := IsWinPaired3 := IsWinPaired4 := IsWinPaired5 := false
		MsgBox "[Unpaired All Windows]", , "T1"
	}
}

;=========== GUI ===========
; currently under development, limited functionality

^`:: OpenGUI()

OpenGUI() {
	; Create the main GUI
	MainGui := Gui("+Resize", "Window Management")
	MainGui.Opt("-MaximizeBox")

	; Active Window Information Section
	GetWinInfo()
	MainGui.AddText("w240 Section", "Active Window Details:")
	MainGui.AddEdit("w240 vActiveTitle ReadOnly", winTitle)
	MainGui.AddEdit("w240 vActiveProcess ReadOnly", winProcess)
	MainGui.AddEdit("w240 vActiveClass ReadOnly", winClass)
	MainGui.AddEdit("w240 vActiveID ReadOnly", winId)


	; Window Pairing Section
	; MainGui.AddText("w200", "Window Pairing:")
	/*
	MainGui.AddText("w100 Section", "Workspace")
	MainGui.AddButton("w100", "Set as Window 2").OnEvent("Click", (*) => GuiPairWindow(2))
	MainGui.AddButton("w100", "Set as Window 3").OnEvent("Click", (*) => GuiPairWindow(3))
	MainGui.AddButton("w100", "Set as Window 4").OnEvent("Click", (*) => GuiPairWindow(4))
	MainGui.AddButton("w100", "Set as Window 5").OnEvent("Click", (*) => GuiPairWindow(5))
	
	*/

	WorkspaceSelect := MainGui.AddDDL("w240")
	UpdateWinList()


	WorkspaceSelect.OnEvent("Change", WindowSelected)

	WindowSelected(Ctrl, *) {
		SelectedTitle := Ctrl.Text
		SelectedID := "ahk_id " WinGetId(SelectedTitle)
		global workspace := SelectedID
		global IsWinPaired1 := true
	}

	UpdateWinList() {

		for Win in WinGetList()
		{
			windowTitle := WinGetTitle(Win)
			if (windowTitle != "")
				WorkspaceSelect.Add([windowTitle])
		}
	}

	/*
	; Unpair Options
	MainGui.AddButton("YS w50", "Unpair").OnEvent("Click", (*) => GuiUnpairWindow(1))
	MainGui.AddButton("w50", "Unpair").OnEvent("Click", (*) => GuiUnpairWindow(2))
	MainGui.AddButton("w50", "Unpair").OnEvent("Click", (*) => GuiUnpairWindow(3))
	MainGui.AddButton("w50", "Unpair").OnEvent("Click", (*) => GuiUnpairWindow(4))
	MainGui.AddButton("w50", "Unpair").OnEvent("Click", (*) => GuiUnpairWindow(5))
	
	MainGui.Add("Text", "XM w240", "Unpair Options and Quick Actions:")
	MainGui.AddDDL("w240 vWindowChoice", [winTitle, "test title 2", "test title 3"])
	MainGui.AddButton("w240", "Unpair All Windows").OnEvent("Click", (*) => GuiUnpairWindow(10))
	MainGui.AddButton("w240", "Show Window Stats").OnEvent("Click", ShowWindowStats)
	MainGui.AddButton("w240", "Close").OnEvent("Click", (*) => MainGui.Destroy())
	*/

	; Show the GUI
	MainGui.Show("w260 h450")


	; Defined event handlers
	GuiPairWindow(num) {
		switch num {
			case 1: PairWindow("IsWinPaired1", "workspace", "Main Workspace")
			case 2: PairWindow("IsWinPaired2", "win2", "Window 2")
			case 3: PairWindow("IsWinPaired3", "win3", "Window 3")
			case 4: PairWindow("IsWinPaired4", "win4", "Window 4")
			case 5: PairWindow("IsWinPaired5", "win5", "Window 5")
		}

		MainGui.Destroy()
	}

	GuiUnpairWindow(num) {
		switch num {
			case 1: UnpairWindow("IsWinPaired1", "workspace", "Main Workspace")
			case 2: UnpairWindow("IsWinPaired2", "win2", "Window 2")
			case 3: UnpairWindow("IsWinPaired3", "win3", "Window 3")
			case 4: UnpairWindow("IsWinPaired4", "win4", "Window 4")
			case 5: UnpairWindow("IsWinPaired5", "win5", "Window 5")
			case 10: UnpairAllWindows()
		}

		MainGui.Destroy()
	}

	ShowWindowStats(*) {
		DisplayActiveWindowStats()
	}

}