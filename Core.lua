-- Spilled Raid Tools - Core
local ADDON, ns = ...
local SRT = {}
ns.SRT = SRT
_G.SpilledRaidTools = SRT

SRT.defaults = {
    pullSeconds      = 10,    -- default pull timer
    breakMinutes     = 10,    -- default break timer
    announcePull     = true,  -- duplicate pull countdown in raid warning
    pullCountFrom    = 5,     -- raid-warn every second from N down (0 = only start + PULL)
    announceBreak    = true,  -- announce break start / end in raid warning
    announceReady    = true,  -- announce ready check result
    announceOthers   = true,  -- also announce pulls / breaks / ready checks started by other players
    buffReportToChat = true,  -- post buff check in group chat (false = only you see it)
    checkVantus      = true,  -- buff check also lists players without a vantus rune
    expireWarnMinutes = 5,    -- buff check warns when food / flask has less than this left (0 = off)
    checkSoulwell    = true,  -- on ready check, ask warlocks for a Soulwell
    inviteMaxRank    = 5,     -- Invite button: guild ranks 1..N (1 = Guild Master)
    promoteMaxRank   = 2,     -- Promote button: guild ranks 1..N get raid assist
    autoPromote      = false, -- promote those ranks automatically when they join
    sortMaxGroup     = 4,     -- Sort button: only groups 1..N are sorted (higher = bench)
    tankMark1        = 6,     -- Tanks button: first tank gets Square
    tankMark2        = 2,     -- second tank gets Circle (orange)
    noteFontSize     = 13,    -- raid note text size
    noteWidth        = 320,   -- raid note window width
    noteAutoShow     = true,  -- show the raid note window when a new note arrives
    minimapButton    = true,  -- show the minimap button
    remindersOn      = true,  -- show timed fight reminders ({time:2:20} lines in the notes)
    reminderLead     = 5,     -- show a reminder this many seconds before its time (countdown)
    reminderFontSize = 28,
    reminderSound    = true,  -- raid warning sound when a reminder hits 0
    reminderTTS      = false, -- also read it out loud (text to speech)
    myReminders      = "",    -- personal reminders, only you see them
    checkDurability  = true,  -- on ready check, warn about players with low durability
    durabilityMin    = 40,    -- warn below this durability %
    locked           = false,
    shown            = true,
    scale            = 1,
}

local db
local ICON_PATH = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_"
-- raid icon index -> world marker index (icons: 1 star,2 circle,3 diamond,4 triangle,5 moon,6 square,7 cross,8 skull)
local ICON_TO_WM = { 5, 6, 3, 2, 7, 1, 4, 8 }
local ICON_NAMES = { "Star", "Circle", "Diamond", "Triangle", "Moon", "Square", "Cross", "Skull" }
SRT.ICON_NAMES = ICON_NAMES
SRT.ICON_PATH = ICON_PATH
local COLUMN_ORDER = { 8, 7, 6, 5, 4, 3, 2, 1 } -- skull first

local SendChat = C_ChatInfo.SendChatMessage
local SendAddon = C_ChatInfo.SendAddonMessage

-- Our own addon-message prefix. Other players with this addon use it to tell
-- each other "I already announced this", so nothing is posted twice.
local PREFIX = "SpilledRT"
C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
C_ChatInfo.RegisterAddonMessagePrefix("BigWigs") -- to see break timers from BigWigs users
C_ChatInfo.RegisterAddonMessagePrefix("LibDRBLT") -- LibDurability (MRT etc.) durability replies

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function Print(msg)
    print("|cff33ccffSpilled Raid Tools:|r " .. msg)
end
SRT.Print = Print

SRT.debug = false
local function Debug(...)
    if SRT.debug then print("|cffff9900SRT debug:|r", ...) end
end

-- Which chat channel the group uses (nil = not in a group)
local function GroupChannel()
    if IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end
SRT.GroupChannel = GroupChannel

local function CanLead()
    return UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- Raid warning when allowed (raid: leader/assist, party: leader),
-- otherwise normal group chat, otherwise only print to yourself.
local function Announce(msg)
    local ch = GroupChannel()
    if not ch then Print(msg) return end
    if CanLead() then ch = "RAID_WARNING" end
    Debug("announce", ch, msg)
    SendChat(msg, ch)
end

-- Is this player name me? (pcall: Midnight can hide names in some situations)
local function IsMe(name)
    if not name then return false end
    local ok, result = pcall(function()
        return Ambiguate(name, "short") == UnitName("player")
    end)
    return ok and result
end

-- Tell other Spilled Raid Tools users that I am announcing something
local function SendSRT(what)
    local ch = GroupChannel()
    if ch then SendAddon(PREFIX, what, ch) end
end

-- When did another Spilled Raid Tools user last announce PULL / BREAK / RC?
local lastSeen = {}
local function Recent(what, seconds)
    return lastSeen[what] and (GetTime() - lastSeen[what]) < seconds
end

-- List of unit tokens for everyone in the group (works in party and raid)
local function GroupUnits()
    local units = {}
    if IsInRaid() then
        for i = 1, GetNumGroupMembers() do units[#units + 1] = "raid" .. i end
    else
        units[1] = "player"
        for i = 1, GetNumSubgroupMembers() do units[#units + 1] = "party" .. i end
    end
    return units
end
SRT.GroupUnits = GroupUnits

---------------------------------------------------------------------------
-- Pull timer (Blizzard countdown -> shown by BigWigs, DBM and default UI)
---------------------------------------------------------------------------
local pullTicker
local myPullAt = 0         -- when I last started a pull myself
local otherPullAt = 0      -- when someone else last started a pull

local function StopPullAnnounce()
    if pullTicker then pullTicker:Cancel() pullTicker = nil end
end

-- Posts "Pull in X sec", then every second from pullCountFrom, then PULL
local function StartPullAnnounce(sec)
    StopPullAnnounce()
    local endTime = GetTime() + sec
    local lastSaid = math.ceil(sec)
    Announce(("Pull in %d sec"):format(lastSaid))
    pullTicker = C_Timer.NewTicker(0.2, function()
        local left = math.ceil(endTime - GetTime())
        if left >= lastSaid then return end -- same second as last time
        lastSaid = left
        if left <= 0 then
            Announce(">> PULL PULL PULL <<")
            StopPullAnnounce()
        elseif left <= db.pullCountFrom then
            Announce(tostring(left))
        end
    end)
end

function SRT:StartPull(sec)
    sec = math.floor(tonumber(sec or db.pullSeconds) or 10)
    if IsInRaid() and not CanLead() then
        Print("You need leader or assist to start a pull timer.")
        return
    end
    myPullAt = GetTime()
    if db.announcePull then SendSRT("PULL") end
    C_PartyInfo.DoCountdown(sec)
    if db.announcePull then StartPullAnnounce(sec) end
end

function SRT:CancelPull()
    local wasRunning = pullTicker ~= nil
    StopPullAnnounce()
    C_PartyInfo.DoCountdown(0)
    if wasRunning and db.announcePull then Announce("Pull cancelled ;(") end
end

-- Someone started a Blizzard countdown (me, or another player / boss mod)
local function OnCountdownStarted(timeRemaining)
    if GetTime() - myPullAt < 1 then return end -- that was my own pull
    otherPullAt = GetTime()
    if not (db.announcePull and db.announceOthers) then return end
    -- wait a moment: if the starter also has this addon, they announce it themselves
    C_Timer.After(0.5, function()
        if Recent("PULL", 3) then Debug("pull announced by another SRT user") return end
        StartPullAnnounce((tonumber(timeRemaining) or db.pullSeconds) - 0.5)
    end)
end

-- Someone cancelled the countdown
local function OnCountdownCancelled()
    if not pullTicker then return end            -- I wasn't announcing anything
    if GetTime() - myPullAt < 1 then return end  -- echo of me restarting my own pull
    StopPullAnnounce()
    local cancelledAt = GetTime()
    C_Timer.After(0.3, function()
        -- if a new countdown started right away it was a restart, not a cancel
        if otherPullAt < cancelledAt and myPullAt < cancelledAt then
            Announce("Pull cancelled ;(")
        end
    end)
end

---------------------------------------------------------------------------
-- Break timer (BigWigs addon message; DBM also listens to it)
---------------------------------------------------------------------------
local breakTicker, breakEnds

local function FormatTime(s)
    return ("%d:%02d"):format(math.floor(s / 60), s % 60)
end

local function StopBreakDisplay()
    if breakTicker then breakTicker:Cancel() breakTicker = nil end
    breakEnds = nil
    if SRT.status then SRT.status:SetText("") end
end

local function AnnounceBreakStart(minutes)
    -- GetGameTime() (realm clock) can be a few minutes off, so only use it for the
    -- realm's time zone and take the exact time from GetServerTime() (real UTC time).
    local now = GetServerTime()
    local utc = date("!*t", now)
    local h, m = GetGameTime()
    local diff = (h * 60 + m - (utc.hour * 60 + utc.min)) % 1440
    if diff > 840 then diff = diff - 1440 end            -- time zones go from -12h to +14h
    local offset = math.floor(diff / 30 + 0.5) * 30      -- zones are whole / half hours
    local backAt = date("!%H:%M", now + offset * 60 + math.ceil(minutes) * 60)
    Announce(("BREAK %d min - back at %s (realm time)"):format(minutes, backAt))
end

-- Shows the countdown on the frame. announceEnd = post "Break is over",
-- mine = I started it (then also start a ready check when it ends)
local function StartBreakTimer(sec, announceEnd, mine)
    StopBreakDisplay()
    breakEnds = GetTime() + sec
    if SRT.status then SRT.status:SetText("Break: " .. FormatTime(sec)) end
    breakTicker = C_Timer.NewTicker(1, function()
        local left = math.floor(breakEnds - GetTime() + 0.5)
        if left <= 0 then
            StopBreakDisplay()
            if announceEnd then Announce("Break is over - get ready!") end
            if mine and IsInGroup() and CanLead() then SRT:ReadyCheck() end
            return
        end
        if SRT.status then SRT.status:SetText("Break: " .. FormatTime(left)) end
    end)
end

function SRT:StartBreak(minutes)
    minutes = tonumber(minutes or db.breakMinutes) or 10
    local sec = math.floor(minutes * 60)
    local ch = GroupChannel()
    if not ch then
        Print("You must be in a group to send a break timer to boss mods.")
    else
        if IsInRaid() and not CanLead() then
            Print("You need leader or assist - boss mods will ignore your break timer.")
        end
        if db.announceBreak then SendSRT("BREAK") end
        SendAddon("BigWigs", "P^Break^" .. sec, ch)
    end
    if db.announceBreak then AnnounceBreakStart(minutes) end
    StartBreakTimer(sec, db.announceBreak, true)
end

function SRT:CancelBreak()
    local ch = GroupChannel()
    if ch then
        if db.announceBreak then SendSRT("BREAK") end
        SendAddon("BigWigs", "P^Break^0", ch)
    end
    if breakEnds and db.announceBreak then Announce("Break cancelled :/") end
    StopBreakDisplay()
end

-- Break timer started / cancelled by another player (BigWigs message)
local function OnBreakFromOther(sec)
    C_Timer.After(0.5, function()
        local announce = db.announceBreak and db.announceOthers and not Recent("BREAK", 3)
        if sec <= 0 then
            if breakEnds and announce then Announce("Break cancelled :/") end
            StopBreakDisplay()
            return
        end
        if announce then AnnounceBreakStart(math.floor(sec / 60 + 0.5)) end
        StartBreakTimer(math.floor(sec), announce, false)
    end)
end

---------------------------------------------------------------------------
-- Ready check (+ announce the result, also when someone else starts it)
---------------------------------------------------------------------------
local rcByMe, rcByButton, rcAnnounced = false, false, false
local rcStarter            -- short name of whoever started the ready check
local rcReady = {}         -- [GUID] = true/false from READY_CHECK_CONFIRM

function SRT:ReadyCheck()
    if not IsInGroup() then Print("You are not in a group.") return end
    if not CanLead() then Print("You need to be leader (or assist in a raid) to start a ready check.") return end
    rcByButton = true
    if db.announceReady then SendSRT("RC") end
    DoReadyCheck()
end

local function CheckReady(final)
    if rcAnnounced or not db.announceReady then return end
    -- announce if I started it, or if someone without this addon started it
    local shouldAnnounce = rcByMe or (db.announceOthers and not Recent("RC", 40))
    Debug("check final=", final, "byMe=", rcByMe, "announce=", shouldAnnounce)
    if not shouldAnnounce then return end

    local notReady = {}
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) and UnitIsConnected(unit) then
            local name = UnitName(unit)
            local guid = UnitGUID(unit)
            local ready = (guid and rcReady[guid])
                or GetReadyCheckStatus(unit) == "ready"
                or name == rcStarter                       -- the starter is auto-ready
                or (rcByMe and UnitIsUnit(unit, "player"))
            if not ready then notReady[#notReady + 1] = name end
        end
    end
    Debug("not ready:", #notReady)

    if #notReady == 0 then
        Announce("Everyone is ready!")
        rcAnnounced = true
    elseif final then
        local list = table.concat(notReady, ", ", 1, math.min(#notReady, 8))
        if #notReady > 8 then list = list .. " +" .. (#notReady - 8) end
        Announce("Not ready: " .. list)
        rcAnnounced = true
    end
end

-- Runs CheckReady but shows any error instead of failing silently
local function SafeCheckReady(final)
    local ok, err = pcall(CheckReady, final)
    if not ok then Print("Ready check error: " .. tostring(err)) end
end

---------------------------------------------------------------------------
-- Durability check on ready check
-- The game can't read other players' durability, so on every ready check each
-- player with this addon sends their own durability ("DUR:<pct>") to the group.
-- Players with MRT (or anything else using LibDurability) send theirs on ready
-- check too (prefix "LibDRBLT", message "<pct>,<broken items>"), so we read those as well.
---------------------------------------------------------------------------
local durability = {}      -- ["Name" or "Name-Realm"] = average durability %

local function MyDurability()
    local cur, max = 0, 0
    for slot = 1, 18 do
        local c, m = GetInventoryItemDurability(slot)
        if c and m and m > 0 then cur, max = cur + c, max + m end
    end
    if max == 0 then return 100 end
    return math.floor(cur / max * 100)
end

local function UnitKey(unit)
    local ok, name = pcall(GetUnitName, unit, true)
    return ok and name or nil
end

local function SendDurability()
    SendSRT("DUR:" .. MyDurability())
end

local function CheckDurability(byMe)
    if not db.checkDurability then return end
    -- same rule as the ready check result: only one player announces it
    if not (byMe or (db.announceOthers and not Recent("RC", 40))) then return end

    local low, unknown = {}, {}
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) and UnitIsConnected(unit) then
            local pct
            if UnitIsUnit(unit, "player") then
                pct = MyDurability()
            else
                local key = UnitKey(unit)
                pct = key and durability[key]
            end
            if not pct then
                unknown[#unknown + 1] = UnitName(unit)
            elseif pct < db.durabilityMin then
                low[#low + 1] = { name = UnitName(unit), pct = pct }
            end
        end
    end
    table.sort(low, function(a, b) return a.pct < b.pct end)

    if #low > 0 then
        local parts = {}
        for i = 1, math.min(#low, 8) do parts[i] = ("%s %d%%"):format(low[i].name, low[i].pct) end
        local list = table.concat(parts, ", ")
        if #low > 8 then list = list .. " +" .. (#low - 8) end
        Announce(("Low durability (<%d%%): %s - go repair!"):format(db.durabilityMin, list))
    else
        Print(("Durability: everyone checked is above %d%%."):format(db.durabilityMin))
    end
    if #unknown > 0 then
        Print("Durability unknown (no Spilled Raid Tools or MRT): " .. table.concat(unknown, ", "))
    end
end

local function SafeCheckDurability(byMe)
    local ok, err = pcall(CheckDurability, byMe)
    if not ok then Print("Durability check error: " .. tostring(err)) end
end

---------------------------------------------------------------------------
-- Soulwell reminder on ready check
---------------------------------------------------------------------------
local SOULWELL_SPELL = 29893   -- Create Soulwell
local SOULWELL_RECENT = 600    -- don't nag if one was put down in the last 10 min
local lastSoulwell = 0

local function OnSpellcast(unit, spellID)
    local ok, isWell = pcall(function() return spellID == SOULWELL_SPELL end)
    if ok and isWell and (unit == "player" or unit:find("^party") or unit:find("^raid")) then
        lastSoulwell = GetTime()
        Debug("Soulwell by", unit)
    end
end

local function CheckSoulwell()
    if not db.checkSoulwell then return end
    if not (rcByMe or (db.announceOthers and not Recent("RC", 40))) then return end
    if GetTime() - lastSoulwell < SOULWELL_RECENT then return end

    local locks = {}
    for _, unit in ipairs(GroupUnits()) do
        if UnitExists(unit) and UnitIsConnected(unit) and not UnitIsDeadOrGhost(unit) then
            local _, class = UnitClass(unit)
            if class == "WARLOCK" then locks[#locks + 1] = UnitName(unit) end
        end
    end
    if #locks > 0 then
        Announce(("Healthstones! %s - please put down a Soulwell."):format(table.concat(locks, ", ", 1, math.min(#locks, 3))))
    end
end

---------------------------------------------------------------------------
-- UI
---------------------------------------------------------------------------
local SIZE, GAP, LABEL_W, PAD = 24, 3, 44, 8

local function Tooltip(btn, title, ...)
    local lines = { ... }
    btn:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(title)
        for _, l in ipairs(lines) do GameTooltip:AddLine(l, 1, 1, 1) end
        GameTooltip:Show()
    end)
    btn:HookScript("OnLeave", GameTooltip_Hide)
end

local function IconButton(name, parent, template, texture)
    local b = CreateFrame("Button", name, parent, template)
    b:SetSize(SIZE, SIZE)
    b:SetNormalTexture(texture)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    b:SetPushedTexture(texture)
    b:GetPushedTexture():SetVertexColor(0.6, 0.6, 0.6)
    return b
end

-- Secure button that runs a macro: left-click / right-click text
local function MacroButton(name, parent, texture, leftMacro, rightMacro)
    local b = IconButton(name, parent, "SecureActionButtonTemplate", texture)
    b:RegisterForClicks("AnyUp", "AnyDown")
    b:SetAttribute("type1", "macro")
    b:SetAttribute("macrotext1", leftMacro)
    b:SetAttribute("type2", "macro")
    b:SetAttribute("macrotext2", rightMacro or leftMacro)
    return b
end

local function RowLabel(parent, text, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetPoint("TOPLEFT", PAD, y - 6)
    fs:SetText(text)
end

function SRT:BuildUI()
    local width = PAD * 2 + LABEL_W + 9 * (SIZE + GAP)
    local f = CreateFrame("Frame", "SpilledRaidToolsFrame", UIParent, "BackdropTemplate")
    self.frame = f
    f:SetSize(width, 136)
    f:SetFrameStrata("MEDIUM")
    f:SetClampedToScreen(true)
    f:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    f:SetBackdropColor(0, 0, 0, 0.75)
    f:SetBackdropBorderColor(0.4, 0.4, 0.4)

    -- movement
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", function(s)
        if not db.locked and not InCombatLockdown() then s:StartMoving() end
    end)
    f:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local p, _, rp, x, y = s:GetPoint()
        db.point = { p, rp, x, y }
    end)

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", PAD, -7)
    title:SetText("Spilled Raid Tools")

    local gear = CreateFrame("Button", nil, f)
    gear:SetSize(16, 16)
    gear:SetPoint("TOPRIGHT", -6, -5)
    gear:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
    gear:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    gear:SetScript("OnClick", function() SRT:OpenOptions() end)
    Tooltip(gear, "Settings", "Open the settings window (also groups board)")

    local clearIcon = "Interface\\Buttons\\UI-GroupLoot-Pass-Up"

    -- Row 1: world (ground) markers
    local y1 = -24
    RowLabel(f, "Ground", y1)
    for col, icon in ipairs(COLUMN_ORDER) do
        local wm = ICON_TO_WM[icon]
        local b = MacroButton("SRT_WorldMarker" .. wm, f, ICON_PATH .. icon, "/wm " .. wm, "/cwm " .. wm)
        b:SetPoint("TOPLEFT", PAD + LABEL_W + (col - 1) * (SIZE + GAP), y1)
        Tooltip(b, ICON_NAMES[icon] .. " (ground)", "Left-click: place, then click the ground", "Right-click: remove")
    end
    local clearWM = MacroButton("SRT_WorldMarkerClear", f, clearIcon, "/cwm 0")
    clearWM:SetPoint("TOPLEFT", PAD + LABEL_W + 8 * (SIZE + GAP), y1)
    Tooltip(clearWM, "Clear all ground markers")

    -- Row 2: target markers
    local y2 = y1 - SIZE - GAP
    RowLabel(f, "Target", y2)
    for col, icon in ipairs(COLUMN_ORDER) do
        local b = MacroButton("SRT_TargetMarker" .. icon, f, ICON_PATH .. icon, "/tm " .. icon, "/tm 0")
        b:SetPoint("TOPLEFT", PAD + LABEL_W + (col - 1) * (SIZE + GAP), y2)
        Tooltip(b, ICON_NAMES[icon] .. " (target)", "Left-click: mark your target", "Right-click: clear target's mark")
    end
    local clearRT = MacroButton("SRT_TargetMarkerClear", f, clearIcon, "/tm 0")
    clearRT:SetPoint("TOPLEFT", PAD + LABEL_W + 8 * (SIZE + GAP), y2)
    Tooltip(clearRT, "Clear target's mark")

    -- Row 3: actions (4 buttons)
    local y3 = y2 - SIZE - 8
    local bw = math.floor((width - PAD * 2 - GAP * 3) / 4)
    local function ActionButton(label, x, onLeft, onRight, y)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(bw, 24)
        b:SetPoint("TOPLEFT", PAD + x * (bw + GAP), y or y3)
        b:SetText(label)
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, btn)
            if btn == "RightButton" then
                if onRight then onRight() end
            else
                onLeft()
            end
        end)
        return b
    end
    local ready = ActionButton("Ready", 0, function() SRT:ReadyCheck() end)
    Tooltip(ready, "Ready check", "Announces 'Everyone is ready!' or who is not ready")
    self.pullBtn = ActionButton("Pull", 1, function() SRT:StartPull() end, function() SRT:CancelPull() end)
    Tooltip(self.pullBtn, "Pull timer", "Left-click: start (also raid warning)", "Right-click: cancel",
        "Change the default in options or /srt pull <sec>")
    self.breakBtn = ActionButton("Break", 2, function() SRT:StartBreak() end, function() SRT:CancelBreak() end)
    Tooltip(self.breakBtn, "Break timer", "Left-click: start (BigWigs / DBM bar)", "Right-click: cancel",
        "Change the default in options or /srt break <min>")
    local buffs = ActionButton("Buffs", 3, function() SRT:BuffCheck() end)
    Tooltip(buffs, "Buff check", "Checks food, flask, vantus rune and raid buffs",
        "Also warns when food / flask is about to run out", "Posts who is missing what in group chat")

    -- Row 4: gear + roster tools
    local y4 = y3 - 24 - GAP
    local gearBtn = ActionButton("Gear", 0, function() SRT:GearCheck() end, nil, y4)
    Tooltip(gearBtn, "Gear check", "Inspects everyone for missing enchants and empty gem sockets",
        "Takes about 1 sec per player")
    local inviteBtn = ActionButton("Invite", 1, function() SRT:GuildInvite() end, nil, y4)
    Tooltip(inviteBtn, "Guild invite", "Invites online max-level guild members",
        "Ranks to invite: set in options")
    local promoteBtn = ActionButton("Promote", 2, function() SRT:PromoteAssists() end, nil, y4)
    Tooltip(promoteBtn, "Promote", "Gives raid assist to guild members up to the rank set in options",
        "You must be raid leader")
    local sortBtn = ActionButton("Sort", 3, function() SRT:SortGroups() end, function() SRT:OpenOptions("groups") end, y4)
    Tooltip(sortBtn, "Sort groups", "Left-click: sort by your order (default tanks, healers, melee, ranged)",
        "Right-click: groups board - drag players, change the order, pin players",
        "Only groups 1 to N are sorted - higher groups are left alone as bench")

    -- Row 5: tanks + raid note (double width)
    local y5 = y4 - 24 - GAP
    -- secure macro button: marking is protected, so it has to be a real click
    local tanks = CreateFrame("Button", "SRT_MarkTanks", f, "SecureActionButtonTemplate, UIPanelButtonTemplate")
    tanks:SetSize(bw * 2 + GAP, 24)
    tanks:SetPoint("TOPLEFT", PAD, y5)
    tanks:SetText("Mark tanks")
    tanks:RegisterForClicks("AnyUp", "AnyDown")
    tanks:SetAttribute("type1", "macro")
    tanks:SetAttribute("type2", "macro")
    local tankMsg
    tanks:SetScript("PreClick", function(b, btn, down)
        if InCombatLockdown() then tankMsg = nil return end -- keeps the last macro
        local mark, clear, msg = SRT:TankMarkMacros()
        b:SetAttribute("macrotext1", mark or "")
        b:SetAttribute("macrotext2", clear or "")
        tankMsg = (btn == "LeftButton" and not down) and msg or nil
    end)
    tanks:SetScript("PostClick", function()
        if tankMsg then Print(tankMsg) tankMsg = nil end
    end)
    Tooltip(tanks, "Mark tanks", "Left-click: first tank Square, second tank Circle (change in options)",
        "Right-click: clear tank marks")
    local note = ActionButton("Raid note", 2, function() SRT:ToggleNote() end, function() SRT:OpenNoteEditor() end, y5)
    note:SetWidth(bw * 2 + GAP)
    Tooltip(note, "Raid note", "Left-click: show / hide the note", "Right-click: edit and send the note (leader / assist)")

    -- status line (break countdown)
    self.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    self.status:SetPoint("TOP", f, "TOP", 0, y5 - 30)
    f:SetHeight(-(y5 - 30) + 16)

    self:Refresh()
end

function SRT:Refresh()
    local f = self.frame
    if not f or InCombatLockdown() then return end
    f:SetScale(db.scale)
    f:ClearAllPoints()
    if db.point then
        f:SetPoint(db.point[1], UIParent, db.point[2], db.point[3], db.point[4])
    else
        f:SetPoint("CENTER", 0, 200)
    end
    f:SetShown(db.shown)
    self.pullBtn:SetText(("Pull %ds"):format(db.pullSeconds))
    self.breakBtn:SetText(("Break %dm"):format(db.breakMinutes))
    if self.RefreshNote then self:RefreshNote() end
    if self.RefreshReminders then self:RefreshReminders() end
    if self.RefreshMinimap then self:RefreshMinimap() end
end

function SRT:Toggle()
    if InCombatLockdown() then Print("Can't show/hide in combat.") return end
    db.shown = not db.shown
    self:Refresh()
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("READY_CHECK")
ev:RegisterEvent("READY_CHECK_CONFIRM")
ev:RegisterEvent("READY_CHECK_FINISHED")
ev:RegisterEvent("CHAT_MSG_ADDON")
ev:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
pcall(ev.RegisterEvent, ev, "START_PLAYER_COUNTDOWN")
pcall(ev.RegisterEvent, ev, "CANCEL_PLAYER_COUNTDOWN")

ev:SetScript("OnEvent", function(_, event, ...)
    local a1, a2, a3, a4 = ...

    if event == "ADDON_LOADED" and a1 == ADDON then
        SpilledRaidToolsDB = SpilledRaidToolsDB or {}
        db = SpilledRaidToolsDB
        for k, v in pairs(SRT.defaults) do
            if db[k] == nil then db[k] = v end
        end
        SRT.db = db
        SRT:BuildUI()
        if SRT.InitOptions then SRT:InitOptions() end
        if SRT.InitNote then SRT:InitNote() end
        if SRT.InitReminders then SRT:InitReminders() end
        if SRT.InitMinimap then SRT:InitMinimap() end

    elseif event == "READY_CHECK" then
        -- a1 = name of the player who started it
        local ok, short = pcall(Ambiguate, a1 or "", "short")
        rcStarter = ok and short or nil
        rcByMe = rcByButton or IsMe(a1)
        rcByButton = false
        rcAnnounced = false
        wipe(rcReady)
        wipe(durability)
        SendDurability() -- always reply, so whoever announces has our data
        local okWell, errWell = pcall(CheckSoulwell)
        if not okWell then Print("Soulwell check error: " .. tostring(errWell)) end
        Debug("READY_CHECK by", a1, "byMe=", rcByMe)

    elseif event == "READY_CHECK_CONFIRM" then
        -- a1 = unit, a2 = isReady
        local guid = a1 and UnitExists(a1) and UnitGUID(a1)
        if guid then rcReady[guid] = a2 and true or false end
        Debug("CONFIRM", a1, a2)
        SafeCheckReady(false)

    elseif event == "READY_CHECK_FINISHED" then
        Debug("FINISHED")
        SafeCheckReady(true)
        local byMe = rcByMe
        C_Timer.After(1, function() SafeCheckDurability(byMe) end) -- let late replies arrive
        rcByMe = false

    elseif event == "START_PLAYER_COUNTDOWN" then
        -- a1 = who started it, a2 = seconds remaining
        Debug("COUNTDOWN start", a2)
        OnCountdownStarted(a2)

    elseif event == "CANCEL_PLAYER_COUNTDOWN" then
        Debug("COUNTDOWN cancel")
        OnCountdownCancelled()

    elseif event == "CHAT_MSG_ADDON" then
        -- a1 = prefix, a2 = message, a3 = channel, a4 = sender
        if IsMe(a4) then return end -- my own message coming back
        if a1 == PREFIX and a2:sub(1, 4) == "DUR:" then
            local pct = tonumber(a2:sub(5))
            local ok, key = pcall(Ambiguate, a4 or "", "none")
            if pct and ok and key then durability[key] = pct end
            Debug("durability", a4, pct)
        elseif a1 == PREFIX and a2:sub(1, 5) == "NOTE^" then
            if SRT.OnNoteMessage then SRT:OnNoteMessage(a2, a4) end
        elseif a1 == PREFIX then
            lastSeen[a2] = GetTime()
            Debug("SRT user", a4, "announces", a2)
        elseif a1 == "LibDRBLT" then
            local pct = tonumber(a2:match("^(%d+),%d+$"))
            local ok, key = pcall(Ambiguate, a4 or "", "none")
            if pct and ok and key then durability[key] = pct end
            Debug("LibDurability", a4, pct)
        elseif a1 == "BigWigs" then
            local kind, what, value = strsplit("^", a2)
            if kind == "P" and what == "Break" then
                Debug("break from", a4, value)
                OnBreakFromOther(tonumber(value) or 0)
            end
        end

    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        -- a1 = unit, a2 = cast GUID, a3 = spell ID
        OnSpellcast(a1, a3)

    elseif event == "PLAYER_REGEN_ENABLED" then
        SRT:Refresh() -- apply anything changed during combat
    end
end)
