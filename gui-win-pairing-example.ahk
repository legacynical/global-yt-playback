#Requires AutoHotkey v2.0

; Enable detection of hidden/minimized windows
DetectHiddenWindows(false)

; Declare global variables for window hwnds (0 means unassigned) and the window list
global win1 := 0
global win2 := 0
global win3 := 0
global windowList := []

; Create the GUI
mainGui := Gui()
mainGui.Title := "Window Selector"

; Add controls for win1
mainGui.Add("Text", "x10 y10", "Window 1:")
win1DropDown := mainGui.Add("DropDownList", "vWin1DropDown x+10 yp w300", ["[Select Window...]"])
resetWin1Btn := mainGui.Add("Button", "x+10 yp", "Reset")

; Add controls for win2
mainGui.Add("Text", "x10 y+10", "Window 2:")
win2DropDown := mainGui.Add("DropDownList", "vWin2DropDown x+10 yp w300", ["[Select Window...]"])
resetWin2Btn := mainGui.Add("Button", "x+10 yp", "Reset")

; Add controls for win3
mainGui.Add("Text", "x10 y+10", "Window 3:")
win3DropDown := mainGui.Add("DropDownList", "vWin3DropDown x+10 yp w300", ["[Select Window...]"])
resetWin3Btn := mainGui.Add("Button", "x+10 yp", "Reset")

; Add Reset All and Close buttons
resetAllBtn := mainGui.Add("Button", "x10 y+10", "Reset All")
closeBtn := mainGui.Add("Button", "x+10 yp", "Close")

; Assign event handlers
win1DropDown.OnEvent("Change", Win1DropDownChange)
resetWin1Btn.OnEvent("Click", ResetWin1Click)
win2DropDown.OnEvent("Change", Win2DropDownChange)
resetWin2Btn.OnEvent("Click", ResetWin2Click)
win3DropDown.OnEvent("Change", Win3DropDownChange)
resetWin3Btn.OnEvent("Click", ResetWin3Click)
resetAllBtn.OnEvent("Click", ResetAllClick)
closeBtn.OnEvent("Click", GuiClose)
mainGui.OnEvent("Close", GuiClose)

; Define hotkey Ctrl+` to update and show the GUI
^`:: {
  UpdateGUI()
  mainGui.Show()
}

; Function to update the GUI with the current list of windows
UpdateGUI() {
  global windowList, win1DropDown, win2DropDown, win3DropDown, win1, win2, win3
  windowList := []

  ; Populate windowList with all windows (including hidden/minimized)
  for hwnd in WinGetList() {
    title := WinGetTitle(hwnd)
    exe := WinGetProcessName(hwnd)
    displayString := "[" . exe . "] " . title
    windowList.Push({ string: displayString, hwnd: hwnd })
  }

  ; Prepare choices for dropdowns
  choices := ["[Select Window...]"]
  for window in windowList {
    choices.Push(window.string)
  }

  ; Update each dropdown with new choices
  win1DropDown.Delete()
  win1DropDown.Add(choices)
  win2DropDown.Delete()
  win2DropDown.Add(choices)
  win3DropDown.Delete()
  win3DropDown.Add(choices)

  ; Set dropdown selections based on current variable values
  SetDropDownSelection(win1DropDown, win1)
  SetDropDownSelection(win2DropDown, win2)
  SetDropDownSelection(win3DropDown, win3)
}

; Helper function to set dropdown selection based on the variable's hwnd
SetDropDownSelection(dropDown, winHwnd) {
  global windowList
  if (winHwnd = 0) {
    dropDown.Value := 1  ; Select "[Select Window...]"
  } else {
    found := false
    for index, window in windowList {
      if (window.hwnd = winHwnd) {
        dropDown.Value := index + 1  ; +1 because "[Select Window...]" is at index 1
        found := true
        break
      }
    }
    if (!found) {
      dropDown.Value := 1  ; Window no longer exists, revert to "[Select Window...]"
    }
  }
}

; Event handlers for dropdown changes
Win1DropDownChange(control, info) {
  global win1, windowList
  selectedIndex := control.Value
  if (selectedIndex = 1) {
    win1 := 0
  } else {
    win1 := windowList[selectedIndex - 1].hwnd
  }
}

Win2DropDownChange(control, info) {
  global win2, windowList
  selectedIndex := control.Value
  if (selectedIndex = 1) {
    win2 := 0
  } else {
    win2 := windowList[selectedIndex - 1].hwnd
  }
}

Win3DropDownChange(control, info) {
  global win3, windowList
  selectedIndex := control.Value
  if (selectedIndex = 1) {
    win3 := 0
  } else {
    win3 := windowList[selectedIndex - 1].hwnd
  }
}

; Event handlers for reset buttons
ResetWin1Click(control, info) {
  global win1, win1DropDown
  win1 := 0
  win1DropDown.Value := 1
}

ResetWin2Click(control, info) {
  global win2, win2DropDown
  win2 := 0
  win2DropDown.Value := 1
}

ResetWin3Click(control, info) {
  global win3, win3DropDown
  win3 := 0
  win3DropDown.Value := 1
}

ResetAllClick(control, info) {
  global win1, win2, win3, win1DropDown, win2DropDown, win3DropDown
  win1 := 0
  win2 := 0
  win3 := 0
  win1DropDown.Value := 1
  win2DropDown.Value := 1
  win3DropDown.Value := 1
}

; Event handler for both Close button and GUI close
GuiClose(p*) {
  if (p.Length = 1) {
    guiObj := p[1]          ; GUI "Close" event: p[1] is the GUI object
  } else if (p.Length = 2) {
    guiObj := p[1].Gui      ; Button "Click" event: p[1] is the control, .Gui gives the GUI object
  } else {
    return                  ; Unexpected number of parameters, do nothing
  }
  guiObj.Hide()               ; Hide the GUI
}