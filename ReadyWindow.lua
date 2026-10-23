-- Spilled Raid Tools - Ready check window: ready status, food, flask, vantus, raid buffs, durability
local ADDON, ns = ...
local SRT = ns.SRT

local W, rows = nil, {}
local ticker, hideTimer
local endsAt, finished

local READY_TEX = {
    ready    = "Interface\\RaidFrame\\ReadyCheck-Ready",
    notready = "Interface\\RaidFrame\\ReadyCheck-NotReady",
    waiting  = "Interface\\RaidFrame\\ReadyCheck-Waiting",
}
local MISSING = "|cffff3333X|r"

-- columns: x offset, width, header
local COLS = {
    { key = "state",  x = 8,   w = 16,  title = ""       },
    { key = "name",   x = 28,  w = 110, title = "Player" },
    { key = "food",   x = 142, w = 46,  title = "Food"   },
    { key = "flask",  x = 192, w = 46,  title = "Flask"  },
    { key = "vantus", x = 242, w = 40,  title = "Vantus" },
    { key = "buffs",  x = 286, w = 54,  title = "Buffs"  },
    { key = "dur",    x = 344, w = 40,  title = "Dur."   },
}
local WIDTH = 392
local TOP = 44     -- space for title + header row

---------------------------------------------------------------------------
local function Minutes(sec)
    if not sec or sec == math.huge then return "" end
    return ("%dm"):format(math.ceil(sec / 60))
end

local function Cell(row, col, withIcon)
    local c = {}
    if withIcon then
        c.icon = row:CreateTexture(nil, "ARTWORK")
        c.icon:SetPoint("LEFT", col.x, 0)
        c.icon:SetSize(14, 14)
        c.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    end
    c.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.text:SetPoint("LEFT", col.x + (withIcon and 16 or 0), 0)
    c.text:SetWidth(col.w - (withIcon and 16 or 0))
    c.text:SetJustifyH("LEFT")
    c.text:SetWordWrap(false)
    return c
end

local function ShowRowTooltip(row)
    if not row.info then return end
    GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
    GameTooltip:SetText(row.info.name)
    for _, line in ipairs(row.info.lines) do GameTooltip:AddLine(line, 1, 1, 1) end
    GameTooltip:Show()
end

local function GetRow(i)
    if rows[i] then return rows[i] end
    local row = CreateFrame("Button", nil, W)
    row:SetHeight(16)
    row:SetPoint("LEFT", 0, 0)
    row:SetPoint("RIGHT", 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.state = row:CreateTexture(nil, "ARTWORK")
    row.state:SetPoint("LEFT", COLS[1].x, 0)
    row.state:SetSize(14, 14)
    row.name = Cell(row, COLS[2])
    row.food = Cell(row, COLS[3], true)
    row.flask = Cell(row, COLS[4], true)
    row.vantus = Cell(row, COLS[5], true)
    row.buffs = Cell(row, COLS[6])
    row.dur = Cell(row, COLS[7])
    row:SetScript("OnEnter", ShowRowTooltip)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = row
    return row
end

local function SetIconCell(cell, has, icon, text)
    if has then
        cell.icon:SetTexture(icon or 134400)
        cell.icon:Show()
        cell.text:SetText(text or "")
    else
        cell.icon:Hide()
        cell.text:SetText(MISSING)
    end
end

local function DurText(pct)
    if not pct then return "|cff777777?|r" end
    local color = (pct < SRT.db.durabilityMin and "ff3333") or (pct < 60 and "ffd100") or "33ff33"
    return ("|cff%s%d%%|r"):format(color, pct)
end

---------------------------------------------------------------------------
local function Update()
    if not W or not W:IsShown() then return end
    local db = SRT.db
    local units = SRT.GroupUnits()
    local wanted, order = SRT:WantedRaidBuffs(units)
    local warnAt = (db.expireWarnMinutes or 0) * 60
    local n = 0
    local rowH = (#units > 20) and 13 or 16

    for _, unit in ipairs(units) do
        if UnitExists(unit) then
            n = n + 1
            local row = GetRow(n)
            row:SetHeight(rowH)
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -TOP - (n - 1) * rowH)
            row:SetPoint("RIGHT", 0, 0)

            local name = UnitName(unit) or "?"
            local _, class = UnitClass(unit)
            local online = UnitIsConnected(unit)
            local color = class and C_ClassColor.GetClassColor(class)
            row.name.text:SetText(online and color and color:WrapTextInColorCode(name) or ("|cff777777" .. name .. "|r"))
            -- ready icons only during a ready check (not when opened by hand)
            row.state:SetTexture(READY_TEX[SRT:ReadyState(unit)])
            row.state:SetShown(endsAt ~= nil)
            row.dur.text:SetText(DurText(SRT:UnitDurability(unit)))

            local info = { name = name, lines = {} }
            local ok, r = false, nil
            if online and UnitIsVisible(unit) and not UnitIsDeadOrGhost(unit) then
                ok, r = pcall(SRT.ScanUnitBuffs, unit, wanted)
            end
            if ok and r then
                local foodSoon = r.food and r.foodLeft < warnAt
                local flaskSoon = r.flask and r.flaskLeft < warnAt
                SetIconCell(row.food, r.food, r.foodIcon,
                    (foodSoon and "|cffffd100" or "") .. Minutes(r.foodLeft) .. (foodSoon and "|r" or ""))
                SetIconCell(row.flask, r.flask, r.flaskIcon,
                    (flaskSoon and "|cffffd100" or "") .. Minutes(r.flaskLeft) .. (flaskSoon and "|r" or ""))
                if db.checkVantus then
                    SetIconCell(row.vantus, r.vantus, r.vantusIcon, "")
                else
                    row.vantus.icon:Hide()
                    row.vantus.text:SetText("")
                end
                local missing = {}
                for _, buff in ipairs(order) do
                    if not r.buffs[buff] then missing[#missing + 1] = buff end
                end
                row.buffs.text:SetText(#missing == 0 and "|cff33ff33OK|r" or ("|cffff3333-%d|r"):format(#missing))
                for _, buff in ipairs(missing) do info.lines[#info.lines + 1] = "|cffff3333Missing:|r " .. buff end
                if not r.food then info.lines[#info.lines + 1] = "|cffff3333No food|r" end
                if not r.flask then info.lines[#info.lines + 1] = "|cffff3333No flask|r" end
            else
                for _, key in ipairs({ "food", "flask", "vantus" }) do
                    row[key].icon:Hide()
                    row[key].text:SetText("")
                end
                local why = (not online and "offline") or (UnitIsDeadOrGhost(unit) and "dead") or "too far"
                row.buffs.text:SetText("|cff777777" .. why .. "|r")
                info.lines[1] = "Buffs not checked: " .. why
            end
            row.info = info
            row:Show()
        end
    end
    for i = n + 1, #rows do rows[i]:Hide() end
    W:SetHeight(TOP + n * rowH + 10)

    if endsAt and not finished then
        W.timeLeft:SetText(("%d"):format(math.max(0, math.ceil(endsAt - GetTime()))))
    else
        W.timeLeft:SetText(finished and "|cff888888done|r" or "")
    end
end

-- an error (e.g. a Midnight secret value) shows once, not every half second
local errorShown
local function SafeUpdate()
    local ok, err = pcall(Update)
    if not ok and not errorShown then
        errorShown = true
        SRT.Print("Ready check window error: " .. tostring(err))
    end
end

---------------------------------------------------------------------------
local function Build()
    W = CreateFrame("Frame", "SpilledRaidToolsReadyWindow", UIParent, "BackdropTemplate")
    W:SetSize(WIDTH, 100)
    W:SetFrameStrata("HIGH")
    W:SetClampedToScreen(true)
    W:SetMovable(true)
    W:EnableMouse(true)
    W:RegisterForDrag("LeftButton")
    W:SetScript("OnDragStart", function(s) if not SRT.db.locked then s:StartMoving() end end)
    W:SetScript("OnDragStop", function(s)
        s:StopMovingOrSizing()
        local p, _, rp, x, y = s:GetPoint()
        SRT.db.readyWindowPoint = { p, rp, x, y }
    end)
    W:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 14,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    W:SetBackdropColor(0, 0, 0, 0.8)
    W:SetBackdropBorderColor(0.4, 0.4, 0.4)
    W:Hide()

    local title = W:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 8, -8)
    title:SetText("Ready check")
    W.timeLeft = W:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    W.timeLeft:SetPoint("LEFT", title, "RIGHT", 8, 0)

    local close = CreateFrame("Button", nil, W, "UIPanelCloseButtonNoScripts")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() SRT:HideReadyWindow() end)

    for _, col in ipairs(COLS) do
        local h = W:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        h:SetPoint("TOPLEFT", col.x, -26)
        h:SetText(col.title)
    end
end

local function Place()
    W:ClearAllPoints()
    local pt = SRT.db.readyWindowPoint
    if pt then
        W:SetPoint(pt[1], UIParent, pt[2], pt[3], pt[4])
    else
        W:SetPoint("LEFT", UIParent, "LEFT", 300, 100)
    end
    W:SetScale(SRT.db.scale)
end

local function Open()
    if not W then Build() end
    if hideTimer then hideTimer:Cancel() hideTimer = nil end
    Place()
    W:Show()
    if not ticker then ticker = C_Timer.NewTicker(0.5, SafeUpdate) end
    SafeUpdate()
end

function SRT:HideReadyWindow()
    if hideTimer then hideTimer:Cancel() hideTimer = nil end
    if ticker then ticker:Cancel() ticker = nil end
    if W then W:Hide() end
end

-- Called from Core on READY_CHECK (timeout = seconds the ready check lasts)
function SRT:ReadyWindowStart(timeout)
    local db = self.db
    if not db.readyWindow then return end
    if db.readyWindowLeadOnly and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then return end
    -- the timeout can be a secret value in Midnight: then just use the usual 35 sec
    local sec = 35
    if not (issecretvalue and issecretvalue(timeout)) and tonumber(timeout) then sec = tonumber(timeout) end
    endsAt = GetTime() + sec
    finished = false
    Open()
end

-- Called from Core on READY_CHECK_FINISHED: keep it open a few more seconds
function SRT:ReadyWindowFinish()
    if not W or not W:IsShown() then return end
    finished = true
    SafeUpdate()
    if hideTimer then hideTimer:Cancel() end
    hideTimer = C_Timer.NewTimer(self.db.readyWindowHold or 5, function()
        hideTimer = nil
        self:HideReadyWindow()
    end)
end

-- Ready button right-click / "/srt rcw": open it any time (live), or close it
function SRT:ToggleReadyWindow()
    if W and W:IsShown() then self:HideReadyWindow() return end
    endsAt, finished = nil, false
    Open()
end
