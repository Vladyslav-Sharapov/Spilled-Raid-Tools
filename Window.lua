-- Spilled Raid Tools - Settings window (own window with tabs) + raid groups board
local ADDON, ns = ...
local SRT = ns.SRT
local Print = SRT.Print

local W               -- the window
local tabs = {}       -- { button, panel, id }
local controls = {}   -- everything with an :Update() (re-read from db)

local WIDTH, HEIGHT = 560, 480
local VALUE_X = 300   -- x where stepper / checkbox controls start

local function UpdateAll()
    for _, c in ipairs(controls) do c:Update() end
end

local function AddTooltip(frame, title, tip)
    if not tip then return end
    frame:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title)
        GameTooltip:AddLine(tip, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    frame:HookScript("OnLeave", GameTooltip_Hide)
end

local function Button(parent, text, w, onClick)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(w, 22)
    b:SetText(text)
    b:SetScript("OnClick", onClick)
    return b
end

---------------------------------------------------------------------------
-- Simple list layout: one control per row
---------------------------------------------------------------------------
local function NewList(panel)
    local list = { panel = panel, y = -4 }

    function list:Label(text)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", 4, self.y - 4)
        fs:SetText(text)
        return fs
    end

    function list:Header(text)
        self.y = self.y - 4
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("TOPLEFT", 0, self.y)
        fs:SetText(text)
        self.y = self.y - 20
    end

    function list:Check(key, text, tip)
        local label = self:Label(text)
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", VALUE_X, self.y)
        cb:SetScript("OnClick", function(b)
            SRT:SetOption(key, b:GetChecked() and true or false)
            UpdateAll()
        end)
        AddTooltip(cb, text, tip)
        function cb:Update() self:SetChecked(SRT.db[key] and true or false) end
        controls[#controls + 1] = cb
        self.y = self.y - 26
        return cb, label
    end

    -- "<  value  >" stepper (fmt = format string or function(value) -> text)
    function list:Stepper(key, text, tip, min, max, step, fmt)
        self:Label(text)
        local f = CreateFrame("Frame", nil, panel)
        f:SetSize(200, 22)
        f:SetPoint("TOPLEFT", VALUE_X, self.y)
        local value = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        value:SetPoint("LEFT", 26, 0)
        value:SetPoint("RIGHT", -26, 0)
        local function Change(dir)
            local v = (SRT.db[key] or min) + dir * step
            v = math.floor(v / step + 0.5) * step
            v = math.max(min, math.min(max, v))
            SRT:SetOption(key, v)
            UpdateAll()
        end
        local down = Button(f, "<", 24, function() Change(-1) end)
        down:SetPoint("LEFT")
        local up = Button(f, ">", 24, function() Change(1) end)
        up:SetPoint("RIGHT")
        AddTooltip(f, text, tip)
        f:EnableMouse(true)
        function f:Update()
            local v = SRT.db[key] or min
            value:SetText(type(fmt) == "function" and fmt(v) or fmt:format(v))
        end
        controls[#controls + 1] = f
        self.y = self.y - 26
        return f
    end

    function list:Button(text, w, onClick)
        local b = Button(panel, text, w, onClick)
        b:SetPoint("TOPLEFT", 4, self.y - 2)
        self.y = self.y - 28
        return b
    end

    return list
end

local function RankText(v) return ("%d - %s"):format(v, SRT.RankName(v)) end
local function IconText(v)
    if v == 0 then return "None" end
    return ("|T%s%d:0|t %s"):format(SRT.ICON_PATH, v, SRT.ICON_NAMES[v])
end

---------------------------------------------------------------------------
-- Tabs
---------------------------------------------------------------------------
local function BuildGeneral(panel)
    local l = NewList(panel)
    l:Header("Pull & break")
    l:Stepper("pullSeconds", "Pull timer", "Default pull countdown length.", 3, 60, 1, "%d sec")
    l:Check("announcePull", "Pull in raid warning", "Duplicate the pull countdown in raid warning.")
    l:Stepper("pullCountFrom", "Count every second from", "Raid-warn each second from this number down (0 = only start and PULL).", 0, 10, 1, "%d")
    l:Stepper("breakMinutes", "Break timer", "Default break length (sent to BigWigs / DBM).", 1, 30, 1, "%d min")
    l:Check("announceBreak", "Break in raid warning", "Announce break start and end in raid warning.")
    l:Check("postWithoutLead", "Post without lead / assist",
        "Off (default): without raid lead or assist (party: leader) you never post automatic messages - " ..
        "pulls / breaks / ready checks of others, check results, buff and gear reports only show for you. " ..
        "Turn on when you need it without assist.")
    l:Check("announceOthers", "Also announce for other players",
        "Announce pulls, breaks and ready checks started by other players too. " ..
        "Players who also use this addon announce their own, so nothing is posted twice.")
    l:Header("Frame")
    l:Check("shown", "Show frame", "Show the Spilled Raid Tools frame.")
    l:Check("locked", "Lock frames", "Prevent dragging the frame and the raid note.")
    l:Stepper("scale", "Scale", "Frame scale.", 0.6, 2, 0.05, "%.2f")
    l:Check("minimapButton", "Minimap button", "Show the minimap button (left: show/hide frame, right: settings).")
    l:Button("Blizzard options panel", 180, function() W:Hide() SRT:OpenBlizzardOptions() end)
end

local function BuildChecks(panel)
    local l = NewList(panel)
    l:Header("Ready check")
    l:Check("announceReady", "Announce ready check result", "Announce 'Everyone is ready!' or who is not ready.")
    l:Check("checkDurability", "Durability check", "Raid-warn players below the durability limit (players with this addon or MRT).")
    l:Stepper("durabilityMin", "Durability warning below", "Warn about players below this average durability.", 5, 100, 5, "%d%%")
    l:Check("checkSoulwell", "Soulwell reminder", "Ask warlocks for a Soulwell (skipped if one was put down in the last 10 min).")
    l:Check("autoBuffCheck", "Auto buff check", "Run the buff check when a ready check starts. " ..
        "Only one player posts it: the starter if they have this addon, otherwise the highest ranked addon user.")
    l:Check("blockMRTReport", "Keep MRT's ready check report off", "Turns off MRT's own food / flask chat report " ..
        "on ready check on your client, so the buffs are posted once. Other players' MRT can't be changed.")
    l:Header("Buff & gear check")
    l:Check("checkVantus", "Check vantus runes", "Buff check also lists players without a vantus rune.")
    l:Stepper("expireWarnMinutes", "Warn when food / flask expires within", "0 = off.", 0, 15, 1, "%d min")
    l:Check("buffReportToChat", "Post results to group chat", "Off = only you see the buff / gear check result.")
end

local function BuildReminders(panel)
    local l = NewList(panel)
    l:Header("Fight reminders  ({time:2:20} lines in the notes)")
    l:Check("remindersOn", "Show fight reminders", "Show {time:...} lines from the raid note and My reminders on screen during boss fights.")
    l:Stepper("reminderLead", "Show before (countdown)", "Show the reminder this many seconds early with a countdown.", 1, 15, 1, "%d sec")
    l:Stepper("reminderFontSize", "Text size", "Size of the on-screen reminder text.", 14, 48, 2, "%d")
    l:Check("reminderSound", "Sound at 0", "Play the raid warning sound when a reminder hits 0.")
    l:Check("reminderTTS", "Read out loud (text to speech)", "Speak the reminder when it hits 0.")
end

local function BuildRoster(panel)
    local l = NewList(panel)
    l:Header("Guild")
    l:Stepper("inviteMaxRank", "Invite guild ranks up to", "Invite button: online max-level guild members of these ranks.", 1, 10, 1, RankText)
    l:Stepper("promoteMaxRank", "Promote guild ranks up to", "Promote button: these guild ranks get raid assist.", 1, 10, 1, RankText)
    l:Check("autoPromote", "Auto promote", "Promote those ranks automatically when they join (you must be raid leader).")
    l:Header("Tank marks")
    l:Stepper("tankMark1", "First tank", "Mark tanks button: icon for the first tank.", 0, 8, 1, IconText)
    l:Stepper("tankMark2", "Second tank", "Mark tanks button: icon for the second tank.", 0, 8, 1, IconText)
    l:Header("Raid note")
    l:Check("noteAutoShow", "Show note when it arrives", "Open the raid note window when the leader sends a new note.")
    l:Stepper("noteFontSize", "Text size", "Font size of the raid note.", 8, 24, 1, "%d")
    l:Stepper("noteWidth", "Window width", "Width of the raid note window.", 150, 600, 10, "%d")
    l:Button("Edit raid note", 140, function() SRT:OpenNoteEditor() end)
end

---------------------------------------------------------------------------
-- Presets: [name box] [Save] [Presets v]  (menu: each preset -> Load / Delete)
-- kind = "notePresets" or "groupPresets" (saved in db); getData() -> table to save,
-- applyData(data, name) loads it.
---------------------------------------------------------------------------
local function PresetRow(panel, kind, nameWidth, getData, applyData)
    local function Store()
        if type(SRT.db[kind]) ~= "table" then SRT.db[kind] = {} end
        return SRT.db[kind]
    end

    local row = CreateFrame("Frame", nil, panel)
    row:SetSize(nameWidth + 168, 22)

    local name = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    name:SetSize(nameWidth, 20)
    name:SetPoint("LEFT", 6, 0)
    name:SetAutoFocus(false)
    name:SetMaxLetters(30)
    name:SetScript("OnEnterPressed", name.ClearFocus)
    name:SetScript("OnEscapePressed", name.ClearFocus)
    AddTooltip(name, "Preset name", "Type a name, then click Save. Saving with an existing name replaces it.")

    local dropdown
    local save = Button(row, "Save", 50, function()
        local n = strtrim(name:GetText() or "")
        if n == "" then n = date("%d.%m %H:%M") end
        local store = Store()
        local existed = store[n] ~= nil
        store[n] = getData()
        name:SetText(n)
        name:ClearFocus()
        Print(("Preset '%s' %s."):format(n, existed and "updated" or "saved"))
        if dropdown and dropdown.GenerateMenu then dropdown:GenerateMenu() end
    end)
    save:SetPoint("LEFT", name, "RIGHT", 4, 0)

    local ok = pcall(function()
        dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
        dropdown:SetWidth(104)
        dropdown:SetPoint("LEFT", save, "RIGHT", 4, 0)
        dropdown:SetDefaultText("Presets")
        dropdown:SetupMenu(function(_, root)
            local names = {}
            for n in pairs(Store()) do names[#names + 1] = n end
            table.sort(names)
            if #names == 0 then
                root:CreateTitle("No presets saved yet")
                return
            end
            for _, n in ipairs(names) do
                local entry = root:CreateButton(n)
                entry:CreateButton("Load", function()
                    local data = Store()[n]
                    if data then
                        name:SetText(n)
                        applyData(data, n)
                    end
                end)
                entry:CreateButton("|cffff5555Delete|r", function()
                    Store()[n] = nil
                    Print(("Preset '%s' deleted."):format(n))
                    dropdown:GenerateMenu()
                end)
            end
        end)
    end)
    if not ok then
        -- very old menu API: a plain button that lists presets in chat
        dropdown = Button(row, "Presets", 104, function()
            local names = {}
            for n in pairs(Store()) do names[#names + 1] = n end
            table.sort(names)
            Print("Presets: " .. (#names > 0 and table.concat(names, ", ") or "none") ..
                " - type a name and press Enter to load it.")
        end)
        dropdown:SetPoint("LEFT", save, "RIGHT", 4, 0)
        name:SetScript("OnEnterPressed", function(self)
            local data = Store()[strtrim(self:GetText())]
            if data then applyData(data, strtrim(self:GetText())) end
            self:ClearFocus()
        end)
    end
    return row
end

local function CopyTable(t)
    local c = {}
    for k, v in pairs(t or {}) do c[k] = v end
    return c
end

---------------------------------------------------------------------------
-- Note tab: shared raid note + personal reminders
---------------------------------------------------------------------------
local function EditArea(panel, width, height, maxLetters, getText, onChange)
    local bg = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    bg:SetSize(width, height)
    bg:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    bg:SetBackdropColor(0, 0, 0, 0.6)
    bg:SetBackdropBorderColor(0.4, 0.4, 0.4)

    local scroll = CreateFrame("ScrollFrame", nil, bg, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -26, 6)

    local eb = CreateFrame("EditBox", nil, scroll)
    eb:SetMultiLine(true)
    eb:SetAutoFocus(false)
    eb:SetFontObject(ChatFontNormal)
    eb:SetWidth(width - 36)
    eb:SetMaxLetters(maxLetters)
    eb:SetScript("OnEscapePressed", eb.ClearFocus)
    eb:SetScript("OnTextChanged", function(self, user) if user then onChange(self:GetText()) end end)
    if ScrollingEdit_OnCursorChanged then
        eb:SetScript("OnCursorChanged", ScrollingEdit_OnCursorChanged)
        eb:SetScript("OnUpdate", function(self, elapsed) ScrollingEdit_OnUpdate(self, elapsed, scroll) end)
    end
    scroll:SetScrollChild(eb)
    bg:EnableMouse(true)
    bg:SetScript("OnMouseDown", function() eb:SetFocus() end)

    function eb:Update()
        if not self:HasFocus() then self:SetText(getText() or "") end
    end
    controls[#controls + 1] = eb
    return bg, eb
end

local function BuildNote(panel)
    local w = 524
    local t1 = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t1:SetPoint("TOPLEFT", 0, 0)
    t1:SetText("Raid note  |cff888888(shared)|r")
    local area1, noteBox = EditArea(panel, w, 142, SRT.NOTE_MAX_LEN or 2000,
        function() return SRT.db.noteDraft or SRT.db.note end,
        function(text) SRT.db.noteDraft = text end)
    area1:SetPoint("TOPLEFT", 0, -26)
    local mineBox -- set below

    local send = Button(panel, "Send to group", 130, function() SRT:SendRaidNote(noteBox:GetText()) end)
    send:SetPoint("TOPLEFT", 0, -172)
    local mine = Button(panel, "Show only to me", 130, function() SRT:ShowNoteLocally(noteBox:GetText()) end)
    mine:SetPoint("LEFT", send, "RIGHT", 6, 0)
    local clear = Button(panel, "Clear text", 100, function()
        noteBox:SetText("")
        SRT.db.noteDraft = ""
        noteBox:SetFocus()
    end)
    clear:SetPoint("LEFT", mine, "RIGHT", 6, 0)
    local show = Button(panel, "Show / hide note", 130, function() SRT:ToggleNote() end)
    show:SetPoint("LEFT", clear, "RIGHT", 6, 0)

    local t2 = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    t2:SetPoint("TOPLEFT", 0, -204)
    t2:SetText("My reminders  |cff888888(only you see these - saved automatically)|r")
    local area2
    area2, mineBox = EditArea(panel, w, 90, 2000,
        function() return SRT.db.myReminders end,
        function(text) SRT.db.myReminders = text end)
    area2:SetPoint("TOPLEFT", 0, -222)

    -- note presets: raid note + my reminders
    local presets = PresetRow(panel, "notePresets", 130,
        function() return { note = noteBox:GetText(), mine = mineBox:GetText() } end,
        function(data, n)
            SRT.db.noteDraft = data.note or ""
            SRT.db.myReminders = data.mine or ""
            noteBox:SetText(SRT.db.noteDraft)
            mineBox:SetText(SRT.db.myReminders)
            Print(("Note preset '%s' loaded - click Send to group to share it."):format(n))
        end)
    presets:SetPoint("TOPRIGHT", panel, "TOPRIGHT", 0, 2)

    local test = Button(panel, "Test reminders", 130, function() SRT:TestReminders() end)
    test:SetPoint("TOPLEFT", 0, -316)
    local stop = Button(panel, "Stop test", 100, function() SRT:StopReminders() end)
    stop:SetPoint("LEFT", test, "RIGHT", 6, 0)
    local move
    move = Button(panel, "Move display", 130, function()
        SRT:MoveReminders()
        move:SetText(move:GetText() == "Move display" and "Done" or "Move display")
    end)
    move:SetPoint("LEFT", stop, "RIGHT", 6, 0)

    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 0, -346)
    help:SetPoint("RIGHT", panel, "RIGHT")
    help:SetJustifyH("LEFT")
    help:SetText("|cffffd100{time:2:20} Aura Mastery|r  on screen 2:20 into the boss fight (with countdown).\n" ..
        "|cff66ccff@Bob @healer @tank @dps @priest|r  only for them.   " ..
        "|cffff8800{boss:Name}|r  lines below only for that boss ({boss:all} = every boss).\n" ..
        "{spell:31821} {skull} {cross} ... show icons.  Several times in one line: {time:1:10}{time:3:40} Text")
end

---------------------------------------------------------------------------
-- Groups tab: drag & drop board + sort order + pins
---------------------------------------------------------------------------
local BOX_W, SLOT_H, BOX_GAP = 124, 17, 6
local boxes = {}          -- [group] = box frame with .slots[1..5]
local boardPanel, boardInfo
local dragFrom, dragLabel
local CAT_TAG = { TANK = "|cff6699ffT|r", HEALER = "|cff33ff33H|r", MELEE = "|cffff6633M|r", RANGED = "|cffcc99ffR|r" }

local function CanMove()
    if InCombatLockdown() then Print("Can't move players in combat.") return false end
    if not IsInRaid() then Print("You must be in a raid.") return false end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        Print("You need leader or assist to move players.")
        return false
    end
    return true
end

local function RefreshBoard()
    if not boardPanel or not boardPanel:IsVisible() then return end
    for g = 1, 8 do
        for s = 1, 5 do
            local slot = boxes[g].slots[s]
            slot.index, slot.name, slot.group = nil, nil, g
            slot.text:SetText("")
        end
        boxes[g].count = 0
    end
    if not IsInRaid() then
        boardInfo:SetText("Join a raid to see and move groups.")
        return
    end
    boardInfo:SetText("Drag a player onto a group to move, onto a player to swap. " ..
        "Right-click: pin to group (Sort keeps them there).")
    local pins = SRT:SortPins()
    for i = 1, GetNumGroupMembers() do
        local name, _, subgroup, _, _, class, _, online = GetRaidRosterInfo(i)
        local box = name and boxes[subgroup]
        if box and box.count < 5 then
            box.count = box.count + 1
            local slot = box.slots[box.count]
            slot.index, slot.name = i, name
            local color = (class and C_ClassColor.GetClassColor(class)) or NORMAL_FONT_COLOR
            local short = Ambiguate(name, "short")
            local text = online and color:WrapTextInColorCode(short) or ("|cff777777" .. short .. "|r")
            local ok, cat = pcall(SRT.UnitCategory, SRT, "raid" .. i)
            local tag = ok and CAT_TAG[cat] or ""
            local pin = pins[name] and " |cffffaa00*|r" or ""
            slot.text:SetText(tag .. " " .. text .. pin)
        end
    end
end
SRT.RefreshBoard = RefreshBoard

local function Move(from, toGroup, toSlot)
    if not CanMove() or not from.index then return end
    local pins = SRT:SortPins()
    if toSlot and toSlot.index and toSlot.index ~= from.index then
        if toSlot.group == from.group then return end
        SwapRaidSubgroup(from.index, toSlot.index)
        -- pinned players keep being pinned to where they were dragged
        if pins[from.name] then pins[from.name] = toSlot.group end
        if pins[toSlot.name] then pins[toSlot.name] = from.group end
    elseif toGroup and toGroup ~= from.group then
        if boxes[toGroup].count >= 5 then
            Print("Group " .. toGroup .. " is full - drop onto a player to swap.")
            return
        end
        SetRaidSubgroup(from.index, toGroup)
        if pins[from.name] then pins[from.name] = toGroup end
    end
end

local function DragTarget()
    for g = 1, 8 do
        local box = boxes[g]
        if box:IsMouseOver() then
            for s = 1, 5 do
                if box.slots[s]:IsMouseOver() then return g, box.slots[s] end
            end
            return g, nil
        end
    end
end

local function BuildDragLabel()
    dragLabel = CreateFrame("Frame", nil, UIParent)
    dragLabel:SetSize(120, 16)
    dragLabel:SetFrameStrata("TOOLTIP")
    dragLabel.text = dragLabel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    dragLabel.text:SetPoint("CENTER")
    dragLabel:SetScript("OnUpdate", function(self)
        local x, y = GetCursorPosition()
        local s = UIParent:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("CENTER", UIParent, "BOTTOMLEFT", x / s, y / s + 10)
    end)
    dragLabel:Hide()
end

local function BuildGroups(panel)
    boardPanel = panel
    for g = 1, 8 do
        local col, row = (g - 1) % 4, math.floor((g - 1) / 4)
        local box = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        box:SetSize(BOX_W, 5 * SLOT_H + 22)
        box:SetPoint("TOPLEFT", col * (BOX_W + BOX_GAP), -row * (5 * SLOT_H + 22 + BOX_GAP))
        box:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        box:SetBackdropColor(0, 0, 0, 0.5)
        box:SetBackdropBorderColor(0.4, 0.4, 0.4)
        local title = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        title:SetPoint("TOPLEFT", 6, -5)
        title:SetText("Group " .. g)
        box.slots, box.count = {}, 0
        for s = 1, 5 do
            local slot = CreateFrame("Button", nil, box)
            slot:SetSize(BOX_W - 10, SLOT_H)
            slot:SetPoint("TOPLEFT", 5, -18 - (s - 1) * SLOT_H)
            slot:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            slot.text = slot:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            slot.text:SetPoint("LEFT", 2, 0)
            slot.text:SetPoint("RIGHT", -2, 0)
            slot.text:SetJustifyH("LEFT")
            slot.group = g
            slot:RegisterForDrag("LeftButton")
            slot:RegisterForClicks("RightButtonUp")
            slot:SetScript("OnDragStart", function(self)
                if not self.index then return end
                dragFrom = self
                if not dragLabel then BuildDragLabel() end
                dragLabel.text:SetText(self.text:GetText())
                dragLabel:Show()
            end)
            slot:SetScript("OnDragStop", function()
                if dragLabel then dragLabel:Hide() end
                local from = dragFrom
                dragFrom = nil
                if not from then return end
                local g2, target = DragTarget()
                if g2 then Move(from, g2, target) end
            end)
            slot:SetScript("OnClick", function(self)
                if not self.name then return end
                local pins = SRT:SortPins()
                if pins[self.name] then
                    pins[self.name] = nil
                else
                    pins[self.name] = self.group
                end
                RefreshBoard()
            end)
            box.slots[s] = slot
        end
        boxes[g] = box
    end

    local boardBottom = -2 * (5 * SLOT_H + 22 + BOX_GAP)
    boardInfo = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    boardInfo:SetPoint("TOPLEFT", 0, boardBottom)
    boardInfo:SetPoint("RIGHT", panel, "RIGHT")
    boardInfo:SetJustifyH("LEFT")

    -- sort order: 4 rows with up / down
    local y = boardBottom - 34
    local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("TOPLEFT", 0, y)
    header:SetText("Sort button order")
    for i = 1, 4 do
        local ry = y - 20 - (i - 1) * 24
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", 4, ry - 4)
        local function Swap(a, b)
            local order = SRT:SortOrder()
            if order[a] and order[b] then order[a], order[b] = order[b], order[a] end
            UpdateAll()
        end
        local upBtn = Button(panel, "Up", 44, function() Swap(i, i - 1) end)
        upBtn:SetPoint("TOPLEFT", 110, ry)
        local downBtn = Button(panel, "Down", 50, function() Swap(i, i + 1) end)
        downBtn:SetPoint("LEFT", upBtn, "RIGHT", 2, 0)
        upBtn:SetEnabled(i > 1)
        downBtn:SetEnabled(i < 4)
        function fs:Update()
            local cat = SRT:SortOrder()[i]
            self:SetText(("%d. %s %s"):format(i, CAT_TAG[cat] or "", SRT.SORT_CATEGORIES[cat] or "?"))
        end
        controls[#controls + 1] = fs
    end

    -- right side: groups to sort, actions
    local rx = 260
    local maxLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    maxLabel:SetPoint("TOPLEFT", rx, y - 4)
    maxLabel:SetText("Sort groups 1 to")
    local maxStep = CreateFrame("Frame", nil, panel)
    maxStep:SetSize(100, 22)
    maxStep:SetPoint("TOPLEFT", rx + 130, y)
    local maxValue = maxStep:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    maxValue:SetPoint("CENTER")
    local function ChangeMax(d)
        SRT:SetOption("sortMaxGroup", math.max(1, math.min(8, SRT.db.sortMaxGroup + d)))
        UpdateAll()
    end
    Button(maxStep, "<", 24, function() ChangeMax(-1) end):SetPoint("LEFT")
    Button(maxStep, ">", 24, function() ChangeMax(1) end):SetPoint("RIGHT")
    function maxStep:Update() maxValue:SetText(SRT.db.sortMaxGroup) end
    controls[#controls + 1] = maxStep
    AddTooltip(maxStep, "Sort groups 1 to", "Higher groups are left alone (bench).")

    local sortBtn = Button(panel, "Sort now", 110, function() SRT:SortGroups() end)
    sortBtn:SetPoint("TOPLEFT", rx, y - 34)
    local clearBtn = Button(panel, "Clear pins", 110, function()
        wipe(SRT:SortPins())
        RefreshBoard()
        Print("All pins cleared.")
    end)
    clearBtn:SetPoint("LEFT", sortBtn, "RIGHT", 6, 0)

    local note = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    -- group presets: who is in which group + sort order
    local presets = PresetRow(panel, "groupPresets", 96,
        function()
            local layout = {}
            if IsInRaid() then
                for i = 1, GetNumGroupMembers() do
                    local n, _, subgroup = GetRaidRosterInfo(i)
                    if n then layout[n] = subgroup end
                end
            else
                layout = CopyTable(SRT:SortPins())
            end
            return { layout = layout, order = CopyTable(SRT:SortOrder()), maxGroup = SRT.db.sortMaxGroup }
        end,
        function(data, n)
            local pins = SRT:SortPins()
            wipe(pins)
            for k, v in pairs(data.layout or {}) do pins[k] = v end
            if data.order and #data.order == 4 then SRT.db.sortOrder = CopyTable(data.order) end
            if data.maxGroup then SRT:SetOption("sortMaxGroup", data.maxGroup) end
            UpdateAll()
            RefreshBoard()
            Print(("Group preset '%s' loaded (players pinned to their saved groups)."):format(n))
            if IsInRaid() then SRT:SortGroups(true) end
        end)
    presets:SetPoint("TOPLEFT", rx - 6, y - 64)

    note:SetPoint("TOPLEFT", rx, y - 92)
    note:SetPoint("RIGHT", panel, "RIGHT")
    note:SetJustifyH("LEFT")
    note:SetText("T tank, H healer, M melee, R ranged. Melee / ranged comes from the " ..
        "spec (after a gear check) or is guessed from the class.")

    panel:SetScript("OnShow", RefreshBoard)
    panel:RegisterEvent("GROUP_ROSTER_UPDATE")
    panel:SetScript("OnEvent", RefreshBoard)
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local TAB_LIST = {
    { id = "general", label = "General",  build = BuildGeneral },
    { id = "checks",  label = "Checks",   build = BuildChecks  },
    { id = "roster",  label = "Roster",   build = BuildRoster  },
    { id = "groups",  label = "Groups",   build = BuildGroups  },
    { id = "note",    label = "Note",     build = BuildNote    },
    { id = "reminders", label = "Reminders", build = BuildReminders },
}

local function SelectTab(id)
    W.lastTab = id
    for _, t in ipairs(tabs) do
        local on = t.id == id
        t.panel:SetShown(on)
        if on then t.button:LockHighlight() else t.button:UnlockHighlight() end
    end
    UpdateAll()
end

local function Build()
    W = CreateFrame("Frame", "SpilledRaidToolsSettings", UIParent, "BasicFrameTemplateWithInset")
    W:SetSize(WIDTH, HEIGHT)
    W:SetPoint("CENTER")
    W:SetFrameStrata("HIGH")
    W:SetToplevel(true)
    W:SetClampedToScreen(true)
    W:SetMovable(true)
    W:EnableMouse(true)
    W:RegisterForDrag("LeftButton")
    W:SetScript("OnDragStart", W.StartMoving)
    W:SetScript("OnDragStop", W.StopMovingOrSizing)
    W:SetScript("OnShow", UpdateAll)
    tinsert(UISpecialFrames, W:GetName()) -- Esc closes it

    local title = W.TitleText or W:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    if not W.TitleText then title:SetPoint("TOP", 0, -5) end
    title:SetText("Spilled Raid Tools")

    for i, t in ipairs(TAB_LIST) do
        local b = Button(W, t.label, 84, function() SelectTab(t.id) end)
        b:SetPoint("TOPLEFT", 14 + (i - 1) * 88, -30)
        local panel = CreateFrame("Frame", nil, W)
        panel:SetPoint("TOPLEFT", 18, -62)
        panel:SetPoint("BOTTOMRIGHT", -18, 14)
        panel:Hide()
        t.build(panel)
        tabs[#tabs + 1] = { id = t.id, button = b, panel = panel }
    end
end

function SRT:ShowWindow(tab)
    if not W then Build() end
    W:Show()
    SelectTab(tab or W.lastTab or "general")
end

function SRT:ToggleWindow()
    if W and W:IsShown() then W:Hide() else self:ShowWindow() end
end
