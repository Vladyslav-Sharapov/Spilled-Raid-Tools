-- Spilled Raid Tools - Timed fight reminders (like NSRT / MRT timers)
--
-- Written in the raid note (shared) or in "My reminders" (only you), one per line:
--   {time:2:20} Aura Mastery                 -> everyone sees it 2:20 into the fight
--   {time:1:05} @Bob @Anna Use {spell:31821} -> only Bob and Anna
--   {time:45} @healer Big damage soon        -> roles: @tank @healer @dps, classes: @priest ...
--   {boss:Plexus Sentinel}                   -> lines below only for that boss (name or encounter ID)
--   {boss:all}                               -> back to every boss
local ADDON, ns = ...
local SRT = ns.SRT
local Print = SRT.Print

local db
local display, lines = nil, {}  -- on-screen frame and its font strings
local active = {}               -- reminders on screen: { text, speak, at }
local timers = {}
local fightStart, testing

local MAX_LINES = 5
local HOLD = 2.5                -- seconds a reminder stays after it hits 0

---------------------------------------------------------------------------
-- Parsing
---------------------------------------------------------------------------
local ROLE_TAGS = { tank = "TANK", tanks = "TANK", healer = "HEALER", healers = "HEALER", heal = "HEALER",
                    dps = "DAMAGER", damage = "DAMAGER", damager = "DAMAGER" }

local function ForMe(targets)
    if #targets == 0 then return true end
    local me = (UnitName("player") or ""):lower()
    local role = UnitGroupRolesAssigned("player")
    local _, class = UnitClass("player")
    class = (class or ""):lower()
    for _, t in ipairs(targets) do
        t = t:lower()
        if t == "all" or t == "everyone" or t == me or t == class or ROLE_TAGS[t] == role then return true end
        -- "Name-Realm"
        if t:match("^([^%-]+)") == me then return true end
    end
    return false
end

local function BossMatches(filter, encounterID, encounterName)
    if not filter then return true end
    if encounterName == nil then return true end -- test mode: every boss
    if tonumber(filter) then return tonumber(filter) == encounterID end
    local ok, found = pcall(function()
        return encounterName:lower():find(filter:lower(), 1, true) ~= nil
    end)
    return ok and found
end

-- "2:20" -> 140, "45" -> 45
local function ToSeconds(str)
    local m, sec = str:match("^(%d+):(%d+)$")
    if m then return tonumber(m) * 60 + tonumber(sec) end
    return tonumber(str)
end

-- Plain text for text-to-speech: no icons, tags or color codes
local function Plain(text)
    text = text:gsub("|T.-|t", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    text = text:gsub("{spell:(%d+)}", function(id) return C_Spell.GetSpellName(tonumber(id)) or "" end)
    text = text:gsub("{.-}", "")
    return strtrim(text)
end

local function Parse(text, list, encounterID, encounterName)
    local filter
    for line in ((text or "") .. "\n"):gmatch("(.-)\r?\n") do
        local boss = line:match("^%s*{boss:([^}]*)}")
        if boss then
            boss = strtrim(boss)
            filter = (boss ~= "" and boss:lower() ~= "all") and boss or nil
        elseif BossMatches(filter, encounterID, encounterName) then
            local times = {}
            for t in line:gmatch("{time:([%d:]+)}") do
                local sec = ToSeconds(t)
                if sec then times[#times + 1] = sec end
            end
            if #times > 0 then
                local targets = {}
                local rest = line:gsub("{time:[%d:]+}", "")
                rest = rest:gsub("@([^%s,:;]+)[,:;]?", function(name)
                    targets[#targets + 1] = name
                    return ""
                end)
                rest = strtrim(rest)
                if rest ~= "" and ForMe(targets) then
                    -- {spell:ID} on screen = icon + spell name
                    local shown = rest:gsub("{spell:(%d+)}", function(id)
                        local name = C_Spell.GetSpellName(tonumber(id))
                        if name then return "{spell:" .. id .. "} " .. name end
                    end)
                    for _, sec in ipairs(times) do
                        list[#list + 1] = { time = sec, text = SRT.FormatNote(shown), speak = Plain(rest) }
                    end
                end
            end
        end
    end
    return list
end

local function Collect(encounterID, encounterName)
    local list = {}
    Parse(db.note, list, encounterID, encounterName)
    Parse(db.myReminders, list, encounterID, encounterName)
    table.sort(list, function(a, b) return a.time < b.time end)
    return list
end

---------------------------------------------------------------------------
-- Display
---------------------------------------------------------------------------
local function FormatLeft(sec)
    if sec >= 10 then return ("%d"):format(math.ceil(sec)) end
    return ("%.1f"):format(sec)
end

local function Speak(text)
    if not db.reminderTTS or text == "" then return end
    pcall(function()
        local voice = TextToSpeech_GetSelectedVoice(Enum.TtsVoiceType.Standard)
        TextToSpeech_Speak(text, voice)
    end)
end

local function OnUpdate()
    local now = GetTime()
    local n = 0
    for i = #active, 1, -1 do
        local r = active[i]
        if now > r.at + HOLD then table.remove(active, i) end
    end
    for _, r in ipairs(active) do
        n = n + 1
        if n > MAX_LINES then break end
        local left = r.at - now
        if left > 0 then
            lines[n]:SetText(("%s  |cffffd100%s|r"):format(r.text, FormatLeft(left)))
            lines[n]:SetAlpha(1)
        else
            if not r.fired then
                r.fired = true
                if db.reminderSound then PlaySound(SOUNDKIT.RAID_WARNING, "Master") end
                Speak(r.speak)
            end
            -- blink while it is "now"
            lines[n]:SetText("|cffff3333>>|r " .. r.text .. " |cffff3333<<|r")
            lines[n]:SetAlpha(0.6 + 0.4 * math.abs(math.sin(now * 6)))
        end
    end
    for i = n + 1, MAX_LINES do lines[i]:SetText("") end
    if #active == 0 and not display.moving then display:SetScript("OnUpdate", nil) end
end

local function BuildDisplay()
    local f = CreateFrame("Frame", "SpilledRaidToolsReminders", UIParent, "BackdropTemplate")
    f:SetSize(500, 40)
    f:SetFrameStrata("HIGH")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local p, _, rp, x, y = s:GetPoint()
        db.reminderPoint = { p, rp, x, y }
    end)
    f:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background" })
    f:SetBackdropColor(0, 0, 0, 0)
    f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.hint:SetPoint("BOTTOM", f, "TOP", 0, 4)
    f.hint:SetText("Reminders - drag to move, click Done in settings")
    f.hint:Hide()
    for i = 1, MAX_LINES do
        local fs = f:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
        fs:SetPoint("TOP", 0, -(i - 1) * (db.reminderFontSize + 8))
        lines[i] = fs
    end
    display = f
end

function SRT:RefreshReminders()
    if not display then return end
    display:ClearAllPoints()
    if db.reminderPoint then
        display:SetPoint(db.reminderPoint[1], UIParent, db.reminderPoint[2], db.reminderPoint[3], db.reminderPoint[4])
    else
        display:SetPoint("TOP", UIParent, "TOP", 0, -180)
    end
    local font = GameFontNormalHuge:GetFont()
    for i, fs in ipairs(lines) do
        fs:SetFont(font, db.reminderFontSize, "OUTLINE")
        fs:ClearAllPoints()
        fs:SetPoint("TOP", 0, -(i - 1) * (db.reminderFontSize + 8))
    end
    display:SetHeight(MAX_LINES * (db.reminderFontSize + 8))
end

local function Add(r)
    if not display then BuildDisplay() SRT:RefreshReminders() end
    active[#active + 1] = r
    table.sort(active, function(a, b) return a.at < b.at end)
    display:Show()
    display:SetScript("OnUpdate", OnUpdate)
end

---------------------------------------------------------------------------
-- Fight timeline
---------------------------------------------------------------------------
local function Stop()
    for _, t in ipairs(timers) do t:Cancel() end
    wipe(timers)
    wipe(active)
    fightStart, testing = nil, false
    for _, fs in ipairs(lines) do fs:SetText("") end
end

local function Start(encounterID, encounterName)
    Stop()
    if not db.remindersOn then return 0 end
    fightStart = GetTime()
    local list = Collect(encounterID, encounterName)
    for _, r in ipairs(list) do
        local showIn = r.time - db.reminderLead
        local item = { text = r.text, speak = r.speak, at = fightStart + r.time }
        if showIn <= 0 then
            Add(item)
        else
            timers[#timers + 1] = C_Timer.NewTimer(showIn, function() Add(item) end)
        end
    end
    return #list
end

-- Test: run every reminder (all bosses) starting now
function SRT:TestReminders()
    local n = Start(nil, nil)
    if n == 0 then
        Print("No reminders found. Add lines like  {time:0:10} Test reminder  to the note or My reminders.")
    else
        testing = true
        Print(("Testing %d reminder%s from 0:00 (an encounter end or /srt test stop ends it)."):format(n, n > 1 and "s" or ""))
    end
end

function SRT:StopReminders() Stop() end

-- Show the display so it can be dragged
function SRT:MoveReminders(on)
    if not display then BuildDisplay() self:RefreshReminders() end
    if on == nil then on = not display.moving end
    display.moving = on
    display:EnableMouse(on)
    display:SetBackdropColor(0, 0, 0, on and 0.5 or 0)
    display.hint:SetShown(on)
    if on then
        lines[1]:SetText("Aura Mastery  |cffffd1003.0|r")
        display:Show()
    else
        lines[1]:SetText("")
        if #active > 0 then display:SetScript("OnUpdate", OnUpdate) end
    end
end

function SRT:InitReminders()
    db = self.db
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ENCOUNTER_START")
ev:RegisterEvent("ENCOUNTER_END")
ev:SetScript("OnEvent", function(_, event, encounterID, encounterName)
    if not db then return end
    if event == "ENCOUNTER_START" then
        local ok, err = pcall(Start, encounterID, encounterName)
        if not ok then Print("Reminder error: " .. tostring(err)) end
    else
        Stop()
    end
end)
