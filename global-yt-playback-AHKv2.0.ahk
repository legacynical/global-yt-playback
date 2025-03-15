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

DetectHiddenWindows(false)
guiDebugMode := false ; Toggle for GUI debug prints
video := "YouTube" ; Replace with "ahk_exe chrome.exe" if not working (use your browser.exe)
guiHwnd := ""
;workspace := win2 := win3 := win4 := win5 := ""
;IsWinPaired1 := IsWinPaired2 := IsWinPaired3 := IsWinPaired4 := IsWinPaired5 := false

class Workspace {
	__New(id, isPaired, label) {
		this.id := id
		this.isPaired := isPaired
		this.label := label
		this.ddl := ""
		this.changeEvent := ""
		this.options := []
	}
}

workspaceList := [
	Workspace("", false, "Main Workspace"),
	Workspace("", false, "Window 2"),
	Workspace("", false, "Window 3"),
	Workspace("", false, "Window 4"),
	Workspace("", false, "Window 5")
]
inputBuffer := maxInputBuffer := 2 ; Used to reduce unwanted window minimize

Media_Prev:: YoutubeControl("{left}") ; rewind 5 sec
^Media_Prev:: YoutubeControl("{j}") ; rewind 10 sec
Media_Next:: YoutubeControl("{Right}") ; fast forward 5 sec
^Media_Next:: YoutubeControl("{l}") ; fast forward 10 sec
Media_Play_Pause:: YoutubeControl("{k}") ; play/pause
	; Most browsers allow Media_Play_Pause by default but this ensures that it targets a YouTube tab

; If you don't have Media_Play_Pause key, uncomment and set hotkey
; hotkey::Media_Play_Pause

; action param not used but added for clarity future use
YoutubeControl(keyPress) {
	global video, workspaceList
	if WinExist(video) {
		WinActivate
		sleep 11 ; Delay rounds to nearest multiple of 10 or 15.6 ms
		Send keyPress
		sleep 11
		if WinExist(workspaceList[1].id) ; YT playback will return window focus back to main workspace
			WinActivate
	}
}

GetWinInfo() {
	global
	; TODO: investigate bug [084] `winProcess := WinGetProcessName(active)`' access is denied
		; I think this bug triggers when my pc goes to sleep and the gui refresh for focused window details calls this function.
		; Interestingly only the WinGetProcessName() throws the error and not the get functions above it so I need to research that.
		; possible fix would be to exit return if active window `WinExist("A")` to ensure expected behavior
	local active := WinExist("A") ? "A" : "" ; get info of active window if it exists, else get info of last found window
	winTitle := WinGetTitle(active)
	winId := WinGetID(active)
	winClass := WinGetClass(active)
	winProcess := WinGetProcessName(active)
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
<#1:: PairWindow(workspaceList[1])
<#2:: PairWindow(workspaceList[2])
<#3:: PairWindow(workspaceList[3])
<#4:: PairWindow(workspaceList[4])
<#5:: PairWindow(workspaceList[5])

PairWindow(workspaceObject) {
	global
	GetWinInfo()
	; TODO: revert this refactor after debugging to test functionality
	;local window := workspaceObject.id ; only used for read-only operations
	if (workspaceObject.id == "") {
		workspaceObject.id := "ahk_id " winId
		workspaceObject.isPaired := true
		MsgBox "[Pairing " workspaceObject.label "]`n"
			. "title: " winTitle "`n"
			. "workspace: " winId "`n"
			. "process: " winProcess, , "T3"
	} else if (currentID != workspaceObject.id) {
		if WinExist(workspaceObject.id) {
			inputBuffer := maxInputBuffer
			WinActivate
		}
	} else if (currentID == workspaceObject.id) {
		inputBuffer--
		if (WinExist(workspaceObject.id) && (inputBuffer == 0)) {
			inputBuffer := maxInputBuffer
			WinMinimize
		}
	}
}

^<#1:: UnpairWindow(workspaceList[1])
^<#2:: UnpairWindow(workspaceList[2])
^<#3:: UnpairWindow(workspaceList[3])
^<#4:: UnpairWindow(workspaceList[4])
^<#5:: UnpairWindow(workspaceList[5])
^<#0:: UnpairAllWindows()

UnpairWindow(workspaceObject) {
	local windowLabel := workspaceObject.label
	if (workspaceObject.isPaired) {
		workspaceObject.id := ""
		workspaceObject.isPaired := false
		MsgBox "[Unpaired " windowLabel "]", , "T1"
	} else {
		MsgBox "" windowLabel " is already unpaired!", , "T1"
	}
}

UnpairAllWindows() {
	global
	confirmUnpair := MsgBox("Are you sure you want to unpair all windows?", , "YesNo")
	if confirmUnpair = "Yes" {
		for workspaceObject in workspaceList {
			workspaceObject.id := ""
			workspaceObject.isPaired := false
		}		
		MsgBox "[Unpaired All Windows]", , "T1"
	}
}

;=========== GUI ===========
; currently under development, limited functionality

^`:: {
	guiDebugMode ? MainGui.Show("w500 h450") : MainGui.Show("w500 h300")
	global guiHwnd := MainGui.Hwnd
	UpdateGUI()
}

; TODO: Prevent scroll select for DDLs
; Create the main GUI
MainGui := Gui("+Resize", "Window Pairing")
MainGui.Opt("-MaximizeBox")

; Add Controls for active window stats
MainGui.AddText("w240 Section", "Focused Window Details:")
activeWinTitle := MainGui.AddEdit("w400 vActiveTitle ReadOnly", "[Active Window Title]")
; activeWinClass := MainGui.AddEdit("w240 vActiveClass ReadOnly", "[Active Window Class]")
; activeWinId := MainGui.AddEdit("w240 vActiveID ReadOnly", "[Active Window Id]")

debugLabel := guiDebugMode ? MainGui.AddEdit("w400 h150 ReadOnly", "[Debug]") : ""

; Add controls for window DropDownList select
AddDropDownListControls()

AddDropDownListControls() {
	for space in workspaceList {
		MainGui.AddText("w100 Section", space.label)
		space.ddl := MainGui.AddDDL("w400")
		UpdateWinList(space)
		AssignWorkspaceOnEvent(space)
	}
}

/* TODO: Remove deprecated code below
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
isGuiRefresh := true ;TODO make this a gui toggle

SetGuiRefreshTimer(isGuiRefresh)

SetGuiRefreshTimer(bool) {
	SetTimer UpdateGUI, (bool ? 250 : 0) ; calls UpdateGUI() every 250ms or disables timer
}


UpdateGUI() {
	; if the GUI window doesn't exist or is minimized...
	if (!(WinExist("ahk_id " guiHwnd)) || (WinGetMinMax("ahk_id " guiHwnd) == -1)) {
		return
	}
	
	GetWinInfo() ; called to get latest win info
	activeWinTitle.Value := "[" StrReplace(winProcess, ".exe") "] " winTitle
	; activeWinClass.Value := winClass
	; activeWinId.Value := winId
}

; Assign event handlers
AssignWorkspaceOnEvent(workspaceObject) {
	workspaceObject.changeEvent := workspaceObject.ddl.OnEvent("Focus", (*) => UpdateWinList(workspaceObject))
	workspaceObject.changeEvent := workspaceObject.ddl.OnEvent("Change", (*) => WorkspaceSelected(workspaceObject))
	; MsgBox "updated: " workspaceObject.label
}

WorkspaceSelected(workspaceObject) {
	global
	; UnpairWindow(workspaceObject)
	
	index := workspaceObject.ddl.Value ; get selected index value
	; if selected window exists, pair it to workspace
	if WinExist(workspaceObject.options[index].id) {
		workspaceObject.id := "ahk_id " workspaceObject.options[index].id
		workspaceObject.isPaired := true
		if guiDebugMode { ; DEBUG print
			MsgBox "index: " index "`n"
			. "id: " workspaceObject.id
		}
	} else {
		MsgBox "[Error] That window no longer exists!`n"
		. "Attempting to refresh options, please select again..."
	}

	; TODO: remove this deprecated code
		; extractTitle := StrSplit(workspaceObject.ddl.Text, "] ", 2)
		; targetTitle := (extractTitle.Length >= 2) ? extractTitle[2] : ""
		; if WinExist(targetTitle) {
		; 	workspaceObject.id := "ahk_id" WinGetID(targetTitle)
		; 	workspaceObject.isPaired := true
		; }
		; PairWindow(workspaceObject)
		; MsgBox workspaceObject.ddl.Text
		
	UpdateWinList(workspaceObject)
}

UpdateAllWinList(workspaceList) {
	for space in workspaceList {
		UpdateWinList(space)
	}
}

UpdateWinList(workspaceObject) {
	; MsgBox "UpdateWinList fired"
	if workspaceObject.isPaired {
		workspaceObject.ddl.Delete()
		workspaceObject.ddl.Add([IdToDisplayString(workspaceObject.id)])
		if guiDebugMode { ; DEBUG print
			MsgBox "UpdateWinList: workspaceObject.isPaired = true`n" 
				. "adding id: " workspaceObject.id "`n"
				. "adding displayText: " IdToDisplayString(workspaceObject.id)
		}
		workspaceObject.options := []
		workspaceObject.options.Push(
			{
				displayTitle: IdToDisplayString(workspaceObject.id), id: workspaceObject.id
			}
		)
		
	} else {
		workspaceObject.ddl.Delete()
		workspaceObject.ddl.Add(["[Select Window...]"])
		workspaceObject.options := []
		workspaceObject.options.Push(
			{
				displayTitle: "[Select Window...]", id: ""
			}
		)
	}
	
	for hwnd in WinGetList() { ; hwnd is the unique window handle
		; TODO: this conditional lets some explorer processes slip past likely due to non-printable characters in the title
		; TODO research what non-printable control characters are for in empty titles of explorer.exe processes
		if (hwnd != workspaceObject.id ; filters out paired window
				&& RegExMatch(WinGetTitle(hwnd), "\S") ; ensures at least one non-whitespace anywhere in the title (doesn't account for non-printable control characters) 
				&& DllCall("IsWindowVisible", "Ptr", hwnd) ; ensures processing of only visible windows
					; NOTE: above 3 conditional checks is enough to prevent explorer processes leaking into workspaceObject.options
				; Optional conditional checks for future ref
					;&& !RegExMatch(WinGetTitle(hwnd), "^[\s\x00-\x1F\x7F]*$") ; filters out empty, whitespace only, and control-only titles
					;&& Trim(WinGetTitle(hwnd)) != "") ; filters out blank windows (doesn't account for non-printable control characters)
			)
		{
			workspaceObject.ddl.Add([IdToDisplayString(hwnd)]) ; populates rest of options
			workspaceObject.options.Push(
				{
					displayTitle: IdToDisplayString(hwnd), id: hwnd
				}
			)
		}
	}

	if guiDebugMode {
		msg := ""
		for obj in workspaceObject.options {
			msg .= "displayTitle: " . obj.displayTitle . ", id: " . obj.id . "`n"
		}
		debugLabel.Value := msg
	}
	workspaceObject.ddl.Choose(1)
}

IdToDisplayString(hwnd) {
	windowTitle := WinGetTitle(hwnd)
	windowProcess := StrReplace(WinGetProcessName(hwnd), ".exe")
	if (windowTitle != "") { ; if not an blank title window
		return displayString := "[" windowProcess "] " windowTitle
	}
	return displayString := "[" windowProcess "] non-empty title[" windowTitle "]"  
}

; This function will likely be deprecated as DDL controls/event listeners already handle this
GuiPairWindow(num) {
	switch num {
		case 1: PairWindow(workspaceList[1])
		case 2: PairWindow(workspaceList[2])
		case 3: PairWindow(workspaceList[3])
		case 4: PairWindow(workspaceList[4])
		case 5: PairWindow(workspaceList[5])
	}
}

; TODO: add unpair buttons to gui, this will probably be a redundant method if I opt to create
; the controls dynamically along side the DDL controls being generated.
GuiUnpairWindow(num) {
	switch num {
		case 1: UnpairWindow(workspaceList[1])
		case 2: UnpairWindow(workspaceList[2])
		case 3: UnpairWindow(workspaceList[3])
		case 4: UnpairWindow(workspaceList[4])
		case 5: UnpairWindow(workspaceList[5])
		case 10: UnpairAllWindows()
	}
}

; TODO: remove this deprecated function shadowed by activeWinTitle control
ShowWindowStats(*) {
	DisplayActiveWindowStats()
}