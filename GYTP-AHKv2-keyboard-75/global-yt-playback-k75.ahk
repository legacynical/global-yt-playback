#Requires AutoHotkey v2.0
#SingleInstance ; Prompt to replace instance if already running
#Warn ; For debugging
InstallKeybdHook ; Allow use of additional special keys
DetectHiddenWindows(false) ; ideal setting for ux, esp. for gui ddl
; SendMode Input ; (AHKv2 default) Recommended for new scripts due to its superior speed and reliability.
; SetWorkingDir A_ScriptDir ; (AHKv2 default) Force script to use its own folder as working directory.
; SetTitleMatchMode 2 ; (AHKv2 default) Allow WinTitle to be matched anywhere from a window's title

app := GYTP([
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
	50,    ; set inputDelay (50-100 ideal for apps to accept input)
	2,     ; set maxMinWinBuffer (presses needed to minimize if paired window already in focus)
	false, ; set guiDebugMode
	false, ; set hotkeyDebugMode
)
class GYTP {
	__New(workspaceList, inputDelay, maxMinWinBuffer, guiDebugMode, hotkeyDebugMode) {
		this.workspaceList := workspaceList
		this.inputDelay := inputDelay
		this.maxMinWinBuffer := maxMinWinBuffer
		this.guiDebugMode := guiDebugMode
		this.hotkeyDebugMode := hotkeyDebugMode

		this.guiHwnd := ""
		this.browserMap := Map(
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
		this.ytWin := DetectWindowEvent(this.browserMap)
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

class DetectWindowEvent {
	__New(browserMap) {
		this.browserMap := browserMap
		this.targetYT := 0

		this.cbForegroundChange := CallbackCreate(this.OnForegroundChange.Bind(this), "Fast", 7)
		this.hookForegroundChange := DllCall(
			"SetWinEventHook",
			"UInt", 0x0003,                 ; eventMin          EVENT_SYSTEM_FOREGROUND 
			"UInt", 0x0003,                 ; eventMax
			"Ptr", 0,                       ; hmodWinEventProc  (0 = none)
			"Ptr", this.cbForegroundChange,	; callback pointer
			"UInt", 0,                      ; idProcess         (0 = all)
			"UInt", 0,                      ; idThread          (0 = all)
			"UInt", 0,                      ; dwFlags           (0 = out-of-context)
			"Ptr"                           ; return type       HWINEVENTHOOK
		)
		
		this.cbTitleChange := CallbackCreate(this.OnTitleChange.Bind(this), "Fast", 7)
		this.hookTitleChange := DllCall(
			"SetWinEventHook",
			"UInt", 0x800C,                 ; eventMin          EVENT_OBJECT_NAMECHANGE 
			"UInt", 0x800C,                 ; eventMax
			"Ptr", 0,                       ; hmodWinEventProc  (0 = none)
			"Ptr", this.cbTitleChange,	    ; callback pointer
			"UInt", 0,                      ; idProcess         (0 = all)
			"UInt", 0,                      ; idThread          (0 = all)
			"UInt", 0,                      ; dwFlags           (0 = out-of-context)
			"Ptr"                           ; return type       HWINEVENTHOOK
		)

		OnExit(ObjBindMethod(this, "Cleanup"))
	}

	OnForegroundChange(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
		try {
			if !hwnd
				return
			if this.IsYouTubeWindow(hwnd) && this.targetYT != hwnd {
				this.targetYT := hwnd
				CursorMsg "YT Target Updated: " WinGetTitle(hwnd)
			}
			UpdateGUI()
		}
	}

	OnTitleChange(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
		try {
			if !hwnd
				return

			; Only process top-level window for NAMECHANGE events
			if idObject != 0
				return

			isYT := this.IsYouTubeWindow(hwnd)
			newTitle := WinGetTitle(hwnd)

			if hwnd == this.targetYT {
				if app.hotkeyDebugMode
					CursorMsg "Title changed: " newTitle
				if !isYT
					this.targetYT := 0
			}
			if isYT && this.targetYT != hwnd {
				this.targetYT := hwnd
				CursorMsg "YT Target Updated: " newTitle
			}
			UpdateGUI()
		}
	}

	IsYouTubeWindow(hwnd) {
		if !hwnd || !WinExist(hwnd)
			return false
		
		proc := WinGetProcessName(hwnd)
		if !this.browserMap.Has(proc)
			return false
		
		title := WinGetTitle(hwnd)
		if InStr(title, "Subscriptions - YouTube")
			return false

		return InStr(title, "- YouTube -") && this.browserMap.Has(proc)
	}

	GetTargetYT() {
		return (this.targetYT && WinExist(this.targetYT))
			? this.targetYT
			: 0
  }

	FindAnyYouTubeWindow() {
		for hwnd in WinGetList() {
			if this.IsYouTubeWindow(hwnd)
				return hwnd
		}
		return 0
	}

  Cleanup(*) {
		if this.hookForegroundChange
			DllCall("UnhookWinEvent", "Ptr", this.hookForegroundChange)
		if this.cbForegroundChange
			CallbackFree(this.cbForegroundChange)

		if this.hookTitleChange
			DllCall("UnhookWinEvent", "Ptr", this.hookTitleChange)
		if this.cbTitleChange
			CallbackFree(this.cbTitleChange)
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

; alternate volume controls for keyboards without volume knobs
^F22:: Send "{Volume_Mute}"
^F23:: Send "{Volume_Down}"
^F24:: Send "{Volume_Up}"

YoutubeControl(keyPress) {
	hwnd := app.ytWin.GetTargetYT()

	if !hwnd || !app.ytWin.IsYouTubeWindow(hwnd) {
		hwnd := app.ytWin.FindAnyYouTubeWindow()
		app.ytWin.targetYT := hwnd
	}

	if hwnd {
		lastActiveHwnd := WinGetID("A")
		WinActivate(hwnd)
		if WinWaitActive(hwnd, , 1) {
			Sleep app.inputDelay
			Send keyPress
		} else {
			CursorMsg "WinWaitActive did not find target"
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
			Sleep app.inputDelay
			Send keyPress
		} else {
			CursorMsg "WinWaitActive did not find target"
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

CursorMsg(msg, ms := 2000) {
	static text := ""
	static timer := ""

	if(text != "")
		text .= "`n" msg
	else
		text := msg

	ToolTip text

	if (timer)
		SetTimer timer, 0

	timer := () => (
		ToolTip(),
		text := "",
		timer := ""
	)
	SetTimer timer, -ms
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
	local maxInputBuffer := app.maxMinWinBuffer
	static inputBuffer := maxInputBuffer
	
	local currentWin := GetWinInfo()
	if (!currentWin) {
		CursorMsg "No active window found!"
		return
	}

	local currentID := currentWin.id

	if (workspaceObject.id == "") {
		workspaceObject.id := currentID
		workspaceObject.isPaired := true
		CursorMsg "[Pairing " workspaceObject.label "]`n"
			. "title: " currentWin.title "`n"
			. "workspace: " currentWin.id "`n"
			. "process: " currentWin.process
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
		CursorMsg "[Unpaired " windowLabel "]"
	} else {
		CursorMsg "" windowLabel " is already unpaired!"
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
		CursorMsg "[Unpaired All Windows]"
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
			CursorMsg "index: " index "`nid: " workspaceObject.id
	} else {
		CursorMsg "[Error] That window no longer exists!`n"
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
			CursorMsg "UpdateWinList: workspaceObject.isPaired = true`n" 
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
	local windowProcess := WinGetProcessName(hwnd)
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
