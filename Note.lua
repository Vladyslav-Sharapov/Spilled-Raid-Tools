-- Spilled Raid Tools - Raid note: leader / assist writes it, everyone with the addon sees it
local ADDON, ns = ...
local SRT = ns.SRT
local Print = SRT.Print

local PREFIX = "SpilledRT"
local MAX_LEN = 2000   -- note length limit
local CHUNK = 200      -- addon messages are limited to 255 bytes
local SendAddon = C_ChatInfo.SendAddonMessage

local db
local noteFrame, noteText

---------------------------------------------------------------------------
-- Text: {skull} / {rt8} -> raid icons, {spell:ID} -> spell icon, my name highlighted
---------------------------------------------------------------------------
local ICONS = { star = 1, circle = 2, diamond = 3, triangle = 4, moon = 5, square = 6, cross = 7, x = 7, skull = 8 }

local function IconTag(n)
    return ("|T%s%d:0|t"):format(SRT.ICON_PATH, n)
end

local function Format(text)
    text = text:gsub("{rt(%d)}", function(n)
        n = tonumber(n)
        if n >= 1 and n <= 8 then return IconTag(n) end
    end)
    text = text:gsub("{(%a+)}", function(w)
        local n = ICONS[w:lower()]
        if n then return IconTag(n) end
    end)
    text = text:gsub("{spell:(%d+)}", function(id)
        local tex = C_Spell.GetSpellTexture(tonumber(id))
        if tex then return ("|T%s:0|t"):format(tex) end
    end)
    -- reminder tags (see Reminders.lua)
    text = text:gsub("{time:([%d:]+)}", "|cffffd100[%1]|r")
    text = text:gsub("{boss:([^}]*)}", "|cffff8800== %1 ==|r")
    text = text:gsub("@([^%s,:;]+)", "|cff66ccff@%1|r")
    local me = UnitName("player")
    if me then
        text = text:gsub(me:gsub("%p", "%%%0"), "|cff33ff33" .. me .. "|r")
    end
    return text
end
SRT.FormatNote = Format

-- addon messages can't carry line breaks: "~" -> "~t", newline -> "~n"
local function Encode(text) return (text:gsub("~", "~t"):gsub("\n", "~n")) end
local function Decode(text) return (text:gsub("~(.)", { t = "~", n = "\n" })) end

---------------------------------------------------------------------------
-- Note window
---------------------------------------------------------------------------
local PAD = 8

local function SavePoint(frame, key)
    local p, _, rp, x, y = frame:GetPoint()
    db[key] = { p, rp, x, y }
end

local function BuildNoteFrame()
    local f = CreateFrame("Frame", "SpilledRaidToolsNote", UIParent, "BackdropTemplate")
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.6)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s) if not db.locked then s:StartMoving() end end)
    f:SetScript("OnDragStop", function(s) s:StopMovingOrSizing() SavePoint(s, "notePoint") end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetPoint("TOPLEFT", PAD, -7)
    title:SetText("Raid note")
    f.title = title

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButtonNoScripts")
    close:SetSize(20, 20)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() SRT:ToggleNote(false) end)

    local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    text:SetPoint("TOPLEFT", PAD, -24)
    text:SetJustifyH("LEFT")
    text:SetJustifyV("TOP")
    text:SetWordWrap(true)
    noteText = text

    noteFrame = f
end

function SRT:RefreshNote()
    if not noteFrame then return end
    local f = noteFrame
    f:ClearAllPoints()
    if db.notePoint then
        f:SetPoint(db.notePoint[1], UIParent, db.notePoint[2], db.notePoint[3], db.notePoint[4])
    else
        f:SetPoint("LEFT", UIParent, "LEFT", 40, 0)
    end
    f:SetScale(db.scale)
    f:SetWidth(db.noteWidth)
    local font = GameFontHighlight:GetFont()
    noteText:SetFont(font, db.noteFontSize, "")
    noteText:SetWidth(db.noteWidth - PAD * 2)
    local note = db.note or ""
    if note == "" then
        noteText:SetText("|cff888888(no note)|r")
    else
        noteText:SetText(Format(note))
    end
    f.title:SetText(db.noteFrom and ("Raid note |cff888888- " .. db.noteFrom .. "|r") or "Raid note")
    f:SetHeight(noteText:GetStringHeight() + 24 + PAD)
    f:SetShown(db.noteShown)
end

function SRT:ToggleNote(show)
    if show == nil then show = not db.noteShown end
    db.noteShown = show
    if show and not noteFrame then BuildNoteFrame() end
    self:RefreshNote()
end

local function SetNote(text, from)
    db.note = text
    db.noteFrom = from
    if text == "" then
        SRT:ToggleNote(false)
    elseif db.noteAutoShow then
        SRT:ToggleNote(true)
    else
        SRT:RefreshNote()
    end
end

---------------------------------------------------------------------------
-- Sending: split into chunks, send a few per second (the server throttles addon messages)
---------------------------------------------------------------------------
local sendQueue, sendTicker = {}, nil

local function SendNext()
    local msg = sendQueue[1]
    if not msg then
        if sendTicker then sendTicker:Cancel() sendTicker = nil end
        return
    end
    local ch = SRT.GroupChannel()
    if not ch then wipe(sendQueue) return end
    local res = SendAddon(PREFIX, msg.text, ch)
    -- newer clients return a result code (0 = sent); retry a few times when throttled
    if type(res) == "number" and res ~= 0 and msg.tries < 20 then
        msg.tries = msg.tries + 1
        return
    end
    table.remove(sendQueue, 1)
end

local function SendNote(text)
    local data = Encode(text)
    local id = math.random(1000, 9999)
    local parts = {}
    for i = 1, math.max(#data, 1), CHUNK do parts[#parts + 1] = data:sub(i, i + CHUNK - 1) end
    for i, part in ipairs(parts) do
        sendQueue[#sendQueue + 1] = { text = ("NOTE^%d^%d^%d^%s"):format(id, i, #parts, part), tries = 0 }
    end
    if not sendTicker then sendTicker = C_Timer.NewTicker(0.3, SendNext) end
end

local function CanSend()
    if not IsInGroup() then return false, "You are not in a group." end
    if IsInRaid() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return false, "You need leader or assist to send the raid note."
    end
    if InCombatLockdown() then return false, "Can't send the note in combat." end
    return true
end

---------------------------------------------------------------------------
-- Receiving
---------------------------------------------------------------------------
local incoming = {}   -- [sender .. id] = { n = total, parts = {} }

local function FromLeader(sender)
    if not IsInRaid() then return true end -- party: anyone
    local ok, allowed = pcall(function()
        return UnitIsGroupLeader(sender) or UnitIsGroupAssistant(sender)
    end)
    return ok and allowed
end

function SRT:OnNoteMessage(msg, sender)
    local id, i, n, part = msg:match("^NOTE%^(%d+)%^(%d+)%^(%d+)%^(.*)$")
    i, n = tonumber(i), tonumber(n)
    if not (id and i and n) then return end
    local ok, short = pcall(Ambiguate, sender or "", "none")
    if not ok then return end

    local key = short .. id
    local entry = incoming[key]
    if not entry then
        entry = { n = n, parts = {}, got = 0 }
        incoming[key] = entry
    end
    if not entry.parts[i] then
        entry.parts[i] = part
        entry.got = entry.got + 1
    end
    if entry.got < entry.n then return end
    incoming[key] = nil

    if not FromLeader(short) then return end
    local text = Decode(table.concat(entry.parts))
    SetNote(text, short)
    if text ~= "" then Print("New raid note from " .. short .. ".") end
end

---------------------------------------------------------------------------
-- Used by the Note tab of the settings window
---------------------------------------------------------------------------
SRT.NOTE_MAX_LEN = MAX_LEN

function SRT:SendRaidNote(text)
    local ok, why = CanSend()
    if not ok then Print(why) return end
    text = strtrim(text or "")
    SendNote(text)
    SetNote(text, UnitName("player"))
    Print(text == "" and "Raid note cleared for everyone." or "Raid note sent.")
end

function SRT:ShowNoteLocally(text)
    SetNote(strtrim(text or ""), nil)
    self:ToggleNote(true)
end

function SRT:OpenNoteEditor()
    self:OpenOptions("note")
end

---------------------------------------------------------------------------
function SRT:InitNote()
    db = self.db
    if db.noteShown then
        BuildNoteFrame()
        self:RefreshNote()
    end
end
