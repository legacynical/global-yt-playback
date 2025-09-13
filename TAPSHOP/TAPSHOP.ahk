#Requires AutoHotkey v2.0
#SingleInstance ; Prompt to replace instance if already running
#Warn ; For debugging
InstallKeybdHook ; Allow use of additional special keys
DetectHiddenWindows(false) ; ideal setting for ux, esp. for gui ddl
; SendMode Input ; (AHKv2 default) Recommended for new scripts due to its superior speed and reliability.
; SetWorkingDir A_ScriptDir ; (AHKv2 default) Force script to use its own folder as working directory.
; SetTitleMatchMode 2 ; (AHKv2 default) Allow WinTitle to be matched anywhere from a window's title
; ListHotkeys

TAPSHOP := App(Config())
TAPSHOP.InitializeGUI()

class Config {
  __New() {
    this.inputDelay := 50               ; 50–100 recommended
    this.minimizeThreshold := 2         ; presses before minimize
    this.isGuiDebugMode := false
    this.isHotkeyDebugMode := false
    this.browserProcesses := Map(
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
      "falkon.exe", 1
    )
  }
}

class App {
	__New(cfg) {
		this.cfg := cfg
		this.workspaceList := []
		loop 9
			this.workspaceList.Push(Workspace("Window " A_Index))

		this.guiWin := 0
		this.guiHwnd := 0
		this.ytWin := DetectWindowEvent(this.cfg)
		CursorMsg "TAPSHOP ready"
	}

	InitializeGUI() {
		if !this.guiWin {
			this.guiWin := MainWindow(this.workspaceList, this.cfg)
			this.guiHwnd := this.guiWin.MainGui.Hwnd
		}
		return this.guiWin
	}

	ShowGUI() {
		this.InitializeGui()
		this.guiWin.MainGui.Show(this.cfg.isGuiDebugMode ? "w500 h650" : "w500 h500")
		this.guiWin.UpdateGUI()
	}

	SafeUpdateGUI() {
    if this.guiWin && WinExist(this.guiWin.MainGui.Hwnd)
      this.guiWin.UpdateGUI()
  }

	SafeUpdateWinList(workspaceObject) {
    if this.guiWin && WinExist(this.guiWin.MainGui.Hwnd)
      this.guiWin.UpdateWinList(workspaceObject)
  }

	GetSpotifyWindow() {
		static cachedID := 0
		if (cachedID && WinExist(cachedID))
			return cachedID

		hwnd := 0
		try hwnd := WinGetID("ahk_exe Spotify.exe")
		if hwnd
			cachedID := hwnd
		
		return hwnd
	}
}
class Workspace {
	__New(label) {
		this.label := label
		this.id := ""
		this.isPaired := false
		this.isUpdating := false

		this.ddl := ""
		this.focusEvent := ""
		this.changeEvent := ""
		this.options := []
	}
}

class DetectWindowEvent {
	__New(cfg) {
		this.cfg := cfg
		this.targetYT := 0

		this.cbForegroundChange := CallbackCreate(this._OnForegroundChange.Bind(this), "Fast", 7)
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
		
		this.cbTitleChange := CallbackCreate(this._OnTitleChange.Bind(this), "Fast", 7)
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

	_OnForegroundChange(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
		try {
			if !hwnd
				return
			if this.IsYouTubeWindow(hwnd) && this.targetYT != hwnd {
				this.targetYT := hwnd
				CursorMsg "YT Target Updated: " WinGetTitle(hwnd)
			}
			TAPSHOP.SafeUpdateGUI()
		}
	}

	_OnTitleChange(hWinEventHook, event, hwnd, idObject, idChild, dwEventThread, dwmsEventTime) {
		try {
			; Only process top-level window for NAMECHANGE events
			if idObject != 0
				return

			if !hwnd
				return

			isYT := this.IsYouTubeWindow(hwnd)
			newTitle := WinGetTitle(hwnd)

			if hwnd == this.targetYT {
				if this.cfg.isHotkeyDebugMode
					CursorMsg "Title changed: " newTitle
				if !isYT
					this.targetYT := 0
			}
			if isYT && this.targetYT != hwnd {
				this.targetYT := hwnd
				CursorMsg "YT Target Updated: " newTitle
			}
			TAPSHOP.SafeUpdateGUI()
		}
	}

	IsYouTubeWindow(hwnd) {
		if !hwnd || !WinExist(hwnd)
			return false
		
		proc := WinGetProcessName(hwnd)
		if !this.cfg.browserProcesses.Has(proc)
			return false
		
		title := WinGetTitle(hwnd)
		if InStr(title, "Subscriptions - YouTube")
			return false

		return InStr(title, "- YouTube -") && this.cfg.browserProcesses.Has(proc)
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

; https://learn.microsoft.com/en-us/windows/win32/inputdev/wm-appcommand
class MediaAppCommand {
	static WM_APPCOMMAND := 0x0319
	static codes := Map(
		"APPCOMMAND_MEDIA_REWIND", 50,
		"APPCOMMAND_MEDIA_FAST_FORWARD", 49,
		"APPCOMMAND_MEDIA_PLAY_PAUSE", 14,
		"APPCOMMAND_MEDIA_STOP", 13,
		"APPCOMMAND_MEDIA_PREVIOUSTRACK", 12,
		"APPCOMMAND_MEDIA_NEXTTRACK", 11,
		"APPCOMMAND_VOLUME_UP", 10,
		"APPCOMMAND_VOLUME_DOWN", 9,
		"APPCOMMAND_VOLUME_MUTE", 8,
	)

	static Send(hwnd, name) {
		cmd := this.codes.Get(name, "")
		if (cmd = "")
			throw Error("Unknown AppCommand: " name)
		lParam := cmd << 16 ; pack cmd into high word (low 32 bits)
		return DllCall(
			"SendMessage", 
			"Ptr", hwnd,                    ; hWnd         (recipient window)
			"UInt", this.WM_APPCOMMAND,     ; Msg          (WM_APPCOMMAND = 0x0319)
			"Ptr", hwnd,                    ; wParam       (source hwnd, hwnd or 0 is fine)
			"Ptr", lParam,                  ; lParam       (packed cmd << 16)
			"Ptr"                           ; return type  LRESULT
		)
	}
}

F19:: YoutubeControl("{Left}") ; rewind 5 sec
^F19:: YoutubeControl("j") ; rewind 10 sec
F21:: YoutubeControl("{Right}") ; fast forward 5 sec
^F21:: YoutubeControl("l") ; fast forward 10 sec
F20:: YoutubeControl("k") ; play/pause
; F20:: YoutubeControlV2("APPCOMMAND_MEDIA_PLAY_PAUSE") ; play/pause, but collides with spotify

Media_Prev:: SpotifyControlV2("APPCOMMAND_MEDIA_PREVIOUSTRACK") ; skip to previous
Media_Play_Pause:: SpotifyControlV2("APPCOMMAND_MEDIA_PLAY_PAUSE") ; play/pause
Media_Next:: SpotifyControlV2("APPCOMMAND_MEDIA_NEXTTRACK") ; skip to next

; NOTE: modifier keys are inconsistent w/ special keys like Media_*
; For few language keyboard layouts, playback seeking doesn't work with right ctrl (ex. korean microsoft IME)
^Media_Prev:: SpotifyControlV2("APPCOMMAND_MEDIA_REWIND") ; seek backward
; ^Media_Prev:: SpotifyControl("+{Left}") ; seek backward
^Media_Next:: SpotifyControlV2("APPCOMMAND_MEDIA_FAST_FORWARD") ; seek forward
; ^Media_Next:: SpotifyControl("+{Right}") ; seek forward

; NOTE: AppCommand volume control only affects system level volume
F22:: SpotifyControl("!+b") ; like/unlike song (there is no mute shortcut in spotify)
F23:: SpotifyControl("^{Down}") ; lower volume
F24:: SpotifyControl("^{Up}") ; raise volume

; alternate volume controls for keyboards without volume knobs
^F22:: Send "{Volume_Mute}"
^F23:: Send "{Volume_Down}"
^F24:: Send "{Volume_Up}"

YoutubeControl(keyPress) {
	hwnd := TAPSHOP.ytWin.GetTargetYT()

	if !hwnd || !TAPSHOP.ytWin.IsYouTubeWindow(hwnd) {
		hwnd := TAPSHOP.ytWin.FindAnyYouTubeWindow()
		TAPSHOP.ytWin.targetYT := hwnd
	}

	if hwnd {
		lastActiveHwnd := WinGetID("A")
		WinActivate(hwnd)
		if WinWaitActive(hwnd, , 1) {
			Sleep TAPSHOP.cfg.inputDelay
			SendInput keyPress
		} else {
			CursorMsg "WinWaitActive did not find target"
		}
		WinActivate(lastActiveHwnd)
	}
}

; YoutubeControlV2(appCommand) {
; 	hwnd := TAPSHOP.ytWin.GetTargetYT()
; 	if !hwnd || !TAPSHOP.ytWin.IsYouTubeWindow(hwnd) {
; 		hwnd := TAPSHOP.ytWin.FindAnyYouTubeWindow()
; 		TAPSHOP.ytWin.targetYT := hwnd
; 	}
; 	if !hwnd {
; 		CursorMsg("Youtube window not found.")
; 		return
; 	}
; 	MediaAppCommand.Send(hwnd, appCommand)
; }

SpotifyControl(keyPress) {
	spotifyWin := TAPSHOP.GetSpotifyWindow()

	if (spotifyWin) {
		local lastActiveHwnd := WinGetID("A")
		WinActivate(spotifyWin)
		if WinWaitActive(spotifyWin, , 1) {
			Sleep TAPSHOP.cfg.inputDelay
			SendInput keyPress
		} else {
			CursorMsg "WinWaitActive did not find target"
		}
		WinActivate(lastActiveHwnd)
	}
}

SpotifyControlV2(appCommand) {
	spotifyWin := TAPSHOP.GetSpotifyWindow()
	if (!spotifyWin) {
		CursorMsg("Spotify window not found.")
		return
	}
	MediaAppCommand.Send(spotifyWin, appCommand)
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

<#1:: PairWindow(TAPSHOP.workspaceList[1])
<#2:: PairWindow(TAPSHOP.workspaceList[2])
<#3:: PairWindow(TAPSHOP.workspaceList[3])
<#4:: PairWindow(TAPSHOP.workspaceList[4])
<#5:: PairWindow(TAPSHOP.workspaceList[5])
<#6:: PairWindow(TAPSHOP.workspaceList[6])
<#7:: PairWindow(TAPSHOP.workspaceList[7])
<#8:: PairWindow(TAPSHOP.workspaceList[8])
<#9:: PairWindow(TAPSHOP.workspaceList[9])

PairWindow(workspaceObject) {
	local maxInputBuffer := TAPSHOP.cfg.minimizeThreshold
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
	if WinExist(TAPSHOP.guiHwnd)
		TAPSHOP.SafeUpdateWinList(workspaceObject)
}

^<#1:: UnpairWindow(TAPSHOP.workspaceList[1])
^<#2:: UnpairWindow(TAPSHOP.workspaceList[2])
^<#3:: UnpairWindow(TAPSHOP.workspaceList[3])
^<#4:: UnpairWindow(TAPSHOP.workspaceList[4])
^<#5:: UnpairWindow(TAPSHOP.workspaceList[5])
^<#6:: UnpairWindow(TAPSHOP.workspaceList[6])
^<#7:: UnpairWindow(TAPSHOP.workspaceList[7])
^<#8:: UnpairWindow(TAPSHOP.workspaceList[8])
^<#9:: UnpairWindow(TAPSHOP.workspaceList[9])
^<#0:: UnpairAllWindows(TAPSHOP.workspaceList)

UnpairWindow(workspaceObject) {
	local windowLabel := workspaceObject.label
	if (workspaceObject.isPaired) {
		workspaceObject.id := ""
		workspaceObject.isPaired := false
		CursorMsg "[Unpaired " windowLabel "]"
	} else {
		CursorMsg "" windowLabel " is already unpaired!"
	}
	TAPSHOP.SafeUpdateWinList(workspaceObject)
}

UnpairAllWindows(workspaceList) {
	confirmUnpair := MsgBox("Are you sure you want to unpair all windows?", , "YesNo")
	if confirmUnpair = "Yes" {
		for workspaceObject in TAPSHOP.workspaceList {
			workspaceObject.id := ""
			workspaceObject.isPaired := false
		}		
		CursorMsg "[Unpaired All Windows]"
	}
}

;=========== GUI ===========
^<#`:: ToggleMainWindow()

ToggleMainWindow() {
	TAPSHOP.ShowGUI()
}

class MainWindow {
	__New(workspaceList, cfg) {
		this.workspaceList := workspaceList
		this.cfg := cfg
		this.MainGui := 0
		this.activeWinTitleLabel := ""
		this.debugLabel := ""
		this._build()
	}

	_build() {
		; TODO: Prevent scroll select for DDLs (this needs more lower level implementations)
		MainGui := Gui("+Resize", "Window Pairing")
		MainGui.Opt("-MaximizeBox")
		this.MainGui := MainGui
		
		MainGui.AddText("w240 Section", "Focused Window Details:")
		this.activeWinTitleLabel := MainGui.AddEdit("w400 vActiveTitle ReadOnly", "[Active Window Title]")
		; activeWinClassLabel := MainGui.AddEdit("w240 vActiveClass ReadOnly", "[Active Window Class]")
		; activeWinIdLabel := MainGui.AddEdit("w240 vActiveID ReadOnly", "[Active Window Id]")
		this.debugLabel := this.cfg.isGuiDebugMode
			? MainGui.AddEdit("w400 h150 ReadOnly", "[Debug]")
			: ""
		
		for space in this.workspaceList {
			MainGui.AddText("w100 Section", space.label)
			space.ddl := MainGui.AddDDL("w400")			
			this.UpdateWinList(space)
			this.AssignWorkspaceOnEvent(space)
		}
	}
	
	/* TODO: integrate these functions into gui control generation
MainGui.AddButton("YS w50", "Unpair").OnEvent("Click", (*) => GuiUnpairWindow(1))
MainGui.AddButton("w240", "Unpair All Windows").OnEvent("Click", (*) => GuiUnpairWindow(10))
*/

	UpdateGUI() {
		if !(WinExist(this.MainGui.Hwnd))
			return		

    if (WinGetMinMax(this.MainGui.Hwnd) == -1)
      return
		
		local winInfo := GetWinInfo()
		if (winInfo)
			this.activeWinTitleLabel.Value := "[" StrReplace(winInfo.process, ".exe") "] " winInfo.title
		; activeWinClass.Value := winInfo.class
		; activeWinId.Value := winInfo.id
	}

	; Assign event handlers
	AssignWorkspaceOnEvent(workspaceObject) {
		workspaceObject.focusEvent := workspaceObject.ddl.OnEvent("Focus", (*) => this.UpdateWinList(workspaceObject))
		workspaceObject.changeEvent := workspaceObject.ddl.OnEvent("Change", (*) => this.WorkspaceSelected(workspaceObject))
		; MsgBox "updated: " workspaceObject.label
	}

	WorkspaceSelected(workspaceObject) {
		local isDebugMode := this.cfg.isGuiDebugMode
		selectedIndex := workspaceObject.ddl.Value
		; if (selectedIndex < 1 || selectedIndex > workspaceObject.options.Length)
		; 	return
		selectedOption := workspaceObject.options[selectedIndex]
		; if (!selectedOption.id)
		; 	return
		if WinExist(selectedOption.id) {
			workspaceObject.id := selectedOption.id
			workspaceObject.isPaired := true
			if isDebugMode
				CursorMsg "index: " selectedIndex "`nid: " workspaceObject.id
		} else {
			CursorMsg "[Error] That window no longer exists!`n"
			. "Attempting to refresh options, please select again..."
		}
		this.UpdateWinList(workspaceObject)
	}

	UpdateAllWinList() {
		for space in this.workspaceList {
			this.UpdateWinList(space)
		}
	}
	
	UpdateWinList(workspaceObject) {
		if workspaceObject.isUpdating
			return
		workspaceObject.isUpdating := true

		if !WinExist(workspaceObject.id) {
			workspaceObject.isPaired := false
			workspaceObject.id := ""
		}

		if workspaceObject.isPaired {
			workspaceObject.ddl.Delete()
			workspaceObject.ddl.Add([this.IdToDisplayString(workspaceObject.id)])
			if this.cfg.isGuiDebugMode { ; DEBUG print
				CursorMsg "UpdateWinList: workspaceObject.isPaired = true`n" 
				. "adding id: " workspaceObject.id "`n"
				. "adding displayText: " this.IdToDisplayString(workspaceObject.id)
			}
			workspaceObject.options := []
			workspaceObject.options.Push(
				{
					displayTitle: this.IdToDisplayString(workspaceObject.id), id: workspaceObject.id
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
						workspaceObject.ddl.Add([this.IdToDisplayString(hwnd)]) ; populates rest of options
						workspaceObject.options.Push(
					{
						displayTitle: this.IdToDisplayString(hwnd), id: hwnd
					}
				)
			}
		}
		
		if this.cfg.isGuiDebugMode {
			msg := ""
			for obj in workspaceObject.options {
				msg .= "displayTitle: " . obj.displayTitle . ", id: " . obj.id . "`n"
			}
			this.debugLabel.Value := msg
		}
		workspaceObject.ddl.Choose(1)
		workspaceObject.isUpdating := false
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

}