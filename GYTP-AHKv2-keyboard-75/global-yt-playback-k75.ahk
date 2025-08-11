#Requires AutoHotkey v2.0
#SingleInstance ; Prompt to replace instance if already running
#Warn ; For debugging
InstallKeybdHook ; Allow use of additional special keys
DetectHiddenWindows(false) ; ideal setting for ux, esp. for gui ddl
; SendMode Input ; (AHKv2 default) Recommended for new scripts due to its superior speed and reliability.
; SetWorkingDir A_ScriptDir ; (AHKv2 default) Force script to use its own folder as working directory.
; SetTitleMatchMode 2 ; (AHKv2 default) Allow WinTitle to be matched anywhere from a window's title

app := GTYP([
	Workspace("", false, "Window 1"),
	Workspace("", false, "Window 2"),
	Workspace("", false, "Window 3"),
	Workspace("", false, "Window 4"),
	Workspace("", false, "Window 5"),
	Workspace("", false, "Window 6"),
	Workspace("", false, "Window 7"),
	Workspace("", false, "Window 8"),
	Workspace("", false, "Window 9")
	],
	false ; set guiDebugMode
)
class GTYP {
	__New(workspaceList, guiDebugMode) {
		this.workspaceList := workspaceList
		this.guiDebugMode := guiDebugMode
		this.isGuiRefresh := true
		this.maxInputBuffer := 2
		this.guiHwnd := ""
	}
}
class Workspace {
	__New(id, isPaired, label) {
		this.id := id
		this.isPaired := isPaired
		this.label := label
		this.ddl := ""
		this.focusEvent := ""
		this.changeEvent := ""
		this.options := []
	}
}

F19:: YoutubeControl("{Left}") ; rewind 5 sec
^F19:: YoutubeControl("j") ; rewind 10 sec
F21:: YoutubeControl("{Right}") ; fast forward 5 sec
^F21:: YoutubeControl("l") ; fast forward 10 sec
F20:: YoutubeControl("k") ; play/pause

Media_Prev:: SpotifyControl("^{Left}") ; skip to previous
^Media_Prev:: SpotifyControl("+{Left}") ; seek backward
Media_Play_Pause:: SpotifyControl("{Space}") ; play/pause
Media_Next:: SpotifyControl("^{Right}") ; skip to next
^Media_Next:: SpotifyControl("+{Right}") ; seek forward
F22:: SpotifyControl("!+b") ; like/unlike song (there is no mute shortcut in spotify, use play/pause instead)
F23:: SpotifyControl("^{Down}") ; lower volume
F24:: SpotifyControl("^{Up}") ; raise volume

YoutubeControl(keyPress) {
	local targetProcesses := Map(
		"chrome.exe", 1,
		"msedge.exe", 1,
		"firefox.exe", 1,
		"brave.exe", 1,
		"opera.exe", 1,
		"opera_gx.exe", 1,
		"vivaldi.exe", 1,
		"chromium.exe", 1,
		"waterfox.exe", 1,
		"tor.exe", 1,
		"yandex.exe", 1,
		"maxthon.exe", 1,
		"seamonkey.exe", 1,
		"epic.exe", 1,
		"slimjet.exe", 1,
		"comodo_dragon.exe", 1,
		"avast_secure_browser.exe", 1,
		"srware_iron.exe", 1,
		"falkon.exe", 1,
	)
	static targetID := "" 
	
	if (!targetID || !WinExist(targetID)) {
		for hwnd in WinGetList("YouTube") {
			proc := WinGetProcessName(hwnd)
			if targetProcesses.Has(proc) {
				targetID := hwnd
				; MsgBox "targetID set to window:" WinGetTitle(hwnd)
				break
			}	
		}
	}

	if (targetID && WinExist(targetID)) { 
		local lastActiveHwnd := WinGetID("A")
		WinActivate(targetID)
		if WinWaitActive(targetID, , 1) {
			Send keyPress
		} else {
			MsgBox "WinWaitActive did not find target in under 1 seconds", , "T1"
		}
		WinActivate(lastActiveHwnd)
	}
}

SpotifyControl(keyPress) {
	local targetProcess := "Spotify.exe"
	static targetID := ""

	if (!targetID || !WinExist(targetID)) {
		spotifyID := WinGetID("ahk_exe " targetProcess)
		if spotifyID {
			targetID := spotifyID
		}
	}

	if (targetID && WinExist(targetID)) {
		local lastActiveHwnd := WinGetID("A")
		WinActivate(targetID)
		if WinWaitActive(targetID, , 1) {
			Send keyPress
			sleep 15 ; Delay rounds to nearest multiple of 10 or 15.6 ms, values too low can lead to misfires
		} else {
			MsgBox "WinWaitActive did not find target in under 1 second", , "T1"
		}
		WinActivate(lastActiveHwnd)
	}
}

GetWinInfo(hwnd := "A") {
	try {
		if !WinExist(hwnd)
			return false
		activeHwnd := WinGetID(hwnd)
		return {
			title: WinGetTitle(activeHwnd),
      id: activeHwnd,
      class: WinGetClass(activeHwnd),
      process: WinGetProcessName(activeHwnd)
		}
	}	catch Error {
		return {
			title: "[Error]",
			id: 0,
			class: "[Error]",
			process: "[Access Denied]"
		}
	}
}

<#`:: DisplayActiveWindowStats()

DisplayActiveWindowStats() {
	local winInfo := GetWinInfo()
	If (winInfo) {
		MsgBox "Active window title: " winInfo.title "`n"
		. "Active window ID: " winInfo.id "`n"
		. "Active window class: " winInfo.class "`n"
		. "Active window process: " winInfo.process
	}
}

<#1:: PairWindow(app.workspaceList[1])
<#2:: PairWindow(app.workspaceList[2])
<#3:: PairWindow(app.workspaceList[3])
<#4:: PairWindow(app.workspaceList[4])
<#5:: PairWindow(app.workspaceList[5])
<#6:: PairWindow(app.workspaceList[6])
<#7:: PairWindow(app.workspaceList[7])
<#8:: PairWindow(app.workspaceList[8])
<#9:: PairWindow(app.workspaceList[9])

PairWindow(workspaceObject) {
	local maxInputBuffer := app.maxInputBuffer
	static inputBuffer := maxInputBuffer
	
	local currentWin := GetWinInfo()
	if (!currentWin) {
		MsgBox "No active window found!"
		return
	}

	local currentID := currentWin.id

	if (workspaceObject.id == "") {
		workspaceObject.id := currentID
		workspaceObject.isPaired := true
		MsgBox "[Pairing " workspaceObject.label "]`n"
			. "title: " currentWin.title "`n"
			. "workspace: " currentWin.id "`n"
			. "process: " currentWin.process, , "T3"
	} else if (currentID != workspaceObject.id) {
		if WinExist(workspaceObject.id) {
			inputBuffer := maxInputBuffer
			WinActivate(workspaceObject.id)
		}
	} else if (currentID == workspaceObject.id) {
		inputBuffer--
		if (WinExist(workspaceObject.id) && (inputBuffer <= 0)) {
			inputBuffer := maxInputBuffer
			WinMinimize(workspaceObject.id)
		}
	}
	if WinExist(app.guiHwnd)
		UpdateWinList(workspaceObject)
}

^<#1:: UnpairWindow(app.workspaceList[1])
^<#2:: UnpairWindow(app.workspaceList[2])
^<#3:: UnpairWindow(app.workspaceList[3])
^<#4:: UnpairWindow(app.workspaceList[4])
^<#5:: UnpairWindow(app.workspaceList[5])
^<#6:: UnpairWindow(app.workspaceList[6])
^<#7:: UnpairWindow(app.workspaceList[7])
^<#8:: UnpairWindow(app.workspaceList[8])
^<#9:: UnpairWindow(app.workspaceList[9])
^<#0:: UnpairAllWindows(app.workspaceList)

UnpairWindow(workspaceObject) {
	local windowLabel := workspaceObject.label
	if (workspaceObject.isPaired) {
		workspaceObject.id := ""
		workspaceObject.isPaired := false
		MsgBox "[Unpaired " windowLabel "]", , "T1"
	} else {
		MsgBox "" windowLabel " is already unpaired!", , "T1"
	}
	UpdateWinList(workspaceObject)
}

UnpairAllWindows(workspaceList) {
	confirmUnpair := MsgBox("Are you sure you want to unpair all windows?", , "YesNo")
	if confirmUnpair = "Yes" {
		for workspaceObject in app.workspaceList {
			workspaceObject.id := ""
			workspaceObject.isPaired := false
		}		
		MsgBox "[Unpaired All Windows]", , "T1"
	}
}

;=========== GUI ===========
^<#`:: {
	local isDebugMode := app.guiDebugMode
	isDebugMode ? MainGui.Show("w500 h450") : MainGui.Show("w500 h500")
	app.guiHwnd := MainGui.Hwnd
	UpdateGUI()
}

; TODO: Prevent scroll select for DDLs (this needs more lower level implementations)
; Create the main GUI
MainGui := Gui("+Resize", "Window Pairing")

MainGui.Opt("-MaximizeBox")

; Add Controls for active window stats
MainGui.AddText("w240 Section", "Focused Window Details:")
activeWinTitle := MainGui.AddEdit("w400 vActiveTitle ReadOnly", "[Active Window Title]")
; activeWinClass := MainGui.AddEdit("w240 vActiveClass ReadOnly", "[Active Window Class]")
; activeWinId := MainGui.AddEdit("w240 vActiveID ReadOnly", "[Active Window Id]")


debugLabel := app.guiDebugMode ? MainGui.AddEdit("w400 h150 ReadOnly", "[Debug]") : ""

; Add controls for window DropDownList select
AddDropDownListControls()

AddDropDownListControls() {
	for space in app.workspaceList {
		MainGui.AddText("w100 Section", space.label)
		space.ddl := MainGui.AddDDL("w400")
		UpdateWinList(space)
		AssignWorkspaceOnEvent(space)
	}
}

/* TODO: integrate these functions into gui control generation
MainGui.AddButton("YS w50", "Unpair").OnEvent("Click", (*) => GuiUnpairWindow(1))
MainGui.AddButton("w240", "Unpair All Windows").OnEvent("Click", (*) => GuiUnpairWindow(10))
*/


; TODO: make this a gui toggle
SetGuiRefreshTimer(app.isGuiRefresh) ; default true

SetGuiRefreshTimer(bool) {
	SetTimer UpdateGUI, (bool ? 250 : 0) ; calls UpdateGUI() every 250ms or disables timer
}


UpdateGUI() {
	; if the GUI window doesn't exist or is minimized...
	if (!(WinExist("ahk_id " app.guiHwnd)) || (WinGetMinMax("ahk_id " app.guiHwnd) == -1)) {
		return
	}
	
	local winInfo := GetWinInfo()
	if (winInfo)
		activeWinTitle.Value := "[" StrReplace(winInfo.process, ".exe") "] " winInfo.title
	; activeWinClass.Value := winInfo.class
	; activeWinId.Value := winInfo.id
}

; Assign event handlers
AssignWorkspaceOnEvent(workspaceObject) {
	workspaceObject.focusEvent := workspaceObject.ddl.OnEvent("Focus", (*) => UpdateWinList(workspaceObject))
	workspaceObject.changeEvent := workspaceObject.ddl.OnEvent("Change", (*) => WorkspaceSelected(workspaceObject))
	; MsgBox "updated: " workspaceObject.label
}

WorkspaceSelected(workspaceObject) {
	local isDebugMode := app.guiDebugMode
	index := workspaceObject.ddl.Value ; get selected index value
	; if selected window exists, pair it to workspace
	if WinExist(workspaceObject.options[index].id) {
		workspaceObject.id := workspaceObject.options[index].id
		workspaceObject.isPaired := true
		if isDebugMode
			MsgBox "index: " index "`nid: " workspaceObject.id
	} else {
		MsgBox "[Error] That window no longer exists!`n"
		. "Attempting to refresh options, please select again..."
	}
	UpdateWinList(workspaceObject)
}

UpdateAllWinList(workspaceList) {
	for space in app.workspaceList {
		UpdateWinList(space)
	}
}

UpdateWinList(workspaceObject) {
	if !WinExist(workspaceObject.id) {
		workspaceObject.isPaired := false
		workspaceObject.id := ""
	}

	if workspaceObject.isPaired {
		workspaceObject.ddl.Delete()
		workspaceObject.ddl.Add([IdToDisplayString(workspaceObject.id)])
		if app.guiDebugMode { ; DEBUG print
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

	if app.guiDebugMode {
		msg := ""
		for obj in workspaceObject.options {
			msg .= "displayTitle: " . obj.displayTitle . ", id: " . obj.id . "`n"
		}
		debugLabel.Value := msg
	}
	workspaceObject.ddl.Choose(1)
}

IdToDisplayString(hwnd) {
	local winInfo := GetWinInfo(hwnd)
	local windowProcess := StrReplace(WinGetProcessName(hwnd), ".exe")
	if (winInfo.title != "") { ; if not an blank title window
		return "[" windowProcess "] " winInfo.title
	}
	return "[" windowProcess "] non-empty title[" winInfo.title "]"  
}

; NOTE: This function will likely be deprecated as DDL controls/event listeners already handle this
; GuiPairWindow(num) {
; 	switch num {
; 		case 1: PairWindow(app.workspaceList[1])
; 		case 2: PairWindow(app.workspaceList[2])
; 		case 3: PairWindow(app.workspaceList[3])
; 		case 4: PairWindow(app.workspaceList[4])
; 		case 5: PairWindow(app.workspaceList[5])
; 	}
; }

; TODO: Add unpair buttons to gui, this will probably be a redundant method if I opt to create
; the controls dynamically along side the DDL controls being generated.
	; It could also be more simple/maintainable to utilize this, will have to consider.
; GuiUnpairWindow(num) {
; 	switch num {
; 		case 1: UnpairWindow(app.workspaceList[1])
; 		case 2: UnpairWindow(app.workspaceList[2])
; 		case 3: UnpairWindow(app.workspaceList[3])
; 		case 4: UnpairWindow(app.workspaceList[4])
; 		case 5: UnpairWindow(app.workspaceList[5])
; 		case 10: UnpairAllWindows(app.workspaceList)
; 	}
; }
