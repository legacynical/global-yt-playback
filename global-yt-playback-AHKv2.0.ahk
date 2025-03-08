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
global winSelectList := []
global winList := []

^`:: {
	MainGui.Show("w280 h450")
	UpdateGUI()
	UpdateWinList()
}

; Create the main GUI
MainGui := Gui("+Resize", "Window Pairing")
MainGui.Opt("-MaximizeBox")

; Add Controls for active window stats
MainGui.AddText("w240 Section", "Focused Window Details:")
activeWinTitle := MainGui.AddEdit("w240 vActiveTitle ReadOnly", "[Active Window Title]")
activeWinProcess := MainGui.AddEdit("w240 vActiveProcess ReadOnly", "[Active Window Process]")
activeWinClass := MainGui.AddEdit("w240 vActiveClass ReadOnly", "[Active Window Class]")
activeWinId := MainGui.AddEdit("w240 vActiveID ReadOnly", "[Active Window Id]")

; Add controls for window DropDownList select
MainGui.AddText("w100 Section", "Workspace")
WorkspaceSelect := MainGui.AddDDL("w240")
winSelectList.Push(WorkspaceSelect)

/*
MainGui.AddButton("w100", "Set as Window 2").OnEvent("Click", (*) => GuiPairWindow(2))
MainGui.AddButton("w100", "Set as Window 3").OnEvent("Click", (*) => GuiPairWindow(3))
MainGui.AddButton("w100", "Set as Window 4").OnEvent("Click", (*) => GuiPairWindow(4))
MainGui.AddButton("w100", "Set as Window 5").OnEvent("Click", (*) => GuiPairWindow(5))

MainGui.AddButton("YS w50", "Unpair").OnEvent("Click", (*) => GuiUnpairWindow(1))
MainGui.AddButton("w50", "Unpair").OnEvent("Click", (*) => GuiUnpairWindow(2))
MainGui.AddButton("w50", "Unpair").OnEvent("Click", (*) => GuiUnpairWindow(3))
MainGui.AddButton("w50", "Unpair").OnEvent("Click", (*) => GuiUnpairWindow(4))
MainGui.AddButton("w50", "Unpair").OnEvent("Click", (*) => GuiUnpairWindow(5))

MainGui.Add("Text", "XM w240", "Unpair Options and Quick Actions:")
MainGui.AddDDL("w240 vWindowChoice", ["test title 1", "test title 2", "test title 3"])
MainGui.AddButton("w240", "Unpair All Windows").OnEvent("Click", (*) => GuiUnpairWindow(10))
MainGui.AddButton("w240", "Show Window Stats").OnEvent("Click", ShowWindowStats)
MainGui.AddButton("w240", "Close").OnEvent("Click", (*) => MainGui.Destroy())
*/

; Assign event handlers
WorkspaceSelect.OnEvent("Change", WindowSelected)

SetTimer UpdateGUI, 250 ; calls UpdateGUI() every 500ms


UpdateGUI() {
	; if the GUI window doesn't exist or is minimized...
	if (!(WinExist("ahk_id " MainGui.Hwnd)) || (WinGetMinMax("ahk_id " MainGui.Hwnd) == -1)) {
		return ; ...then don't update the GUI
	}
	GetWinInfo() ; called to get latest win info
	activeWinTitle.Value := winTitle
	activeWinProcess.Value := winProcess
	activeWinClass.Value := winClass
	activeWinId.Value := winId
}


WindowSelected(Ctrl, *) {
	global winList, workspace, IsWinPaired1
	for index, window in winList {
		if (window.string == Ctrl.Text) {
			workspace := "ahk_id " window.hwnd
			IsWinPaired1 := true
			UpdateWinList() ;
			return
		}
	}
	MsgBox "Selected window not found. Try Again!", , "T1"
	UpdateWinList()
	Ctrl.Value := 1 ; Reset selection to "[Select Window...]"
}

UpdateWinList() { ; To be called after GUI actions instead of constant polling for performance
	global winList
	for winSelect in winSelectList
	{
		for hwnd in WinGetList() ; hwnd is the unique window handle
		{
			windowTitle := WinGetTitle(hwnd)
			windowProcess := WinGetProcessName(hwnd)
			if (windowTitle != "") {
				displayString := "[" windowProcess "] " windowTitle
				winList.Push({ string: displayString, hwnd: hwnd })
			}
		}
		; Update dropdown options
		choices := ["[Select Window...]"]
		for window in winList {
			choices.Push(window.string)
		}
		winSelect.Delete()
		winSelect.Add(choices)
	}
}

GuiPairWindow(num) {
	switch num {
		case 1: PairWindow("IsWinPaired1", "workspace", "Main Workspace")
		case 2: PairWindow("IsWinPaired2", "win2", "Window 2")
		case 3: PairWindow("IsWinPaired3", "win3", "Window 3")
		case 4: PairWindow("IsWinPaired4", "win4", "Window 4")
		case 5: PairWindow("IsWinPaired5", "win5", "Window 5")
	}
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
}

ShowWindowStats(*) {
	DisplayActiveWindowStats()
}