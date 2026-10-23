-- Spilled Raid Tools - Marker buttons: free markers bright, markers in use faded.
-- Midnight hides raid marks on units from addons (secret values), so the target
-- row usually stays bright; placed ground markers can still be read.
local ADDON, ns = ...
local SRT = ns.SRT

local ticker

-- free (and unknown) = bright, used = faded grey
local function Show(b, state)
    local tex = b:GetNormalTexture()
    if not tex then return end
    local used = state == "used"
    tex:SetDesaturated(used)
    tex:SetAlpha(used and 0.3 or 1)
end

-- Midnight can hide values from addons ("secret"): then we don't know
local function Secret(v)
    return issecretvalue and issecretvalue(v)
end

local function UpdateGround()
    for wm, b in pairs(SRT.wmButtons or {}) do
        local ok, active = pcall(IsRaidMarkerActive, wm)
        if not ok or Secret(active) then
            Show(b, "unknown")
        else
            Show(b, active and "used" or "free")
        end
    end
end

local function TargetUnits()
    local units = { "player", "target", "focus", "mouseover", "pet", "targettarget" }
    for _, u in ipairs(SRT.GroupUnits()) do
        units[#units + 1] = u
        units[#units + 1] = u .. "target"
    end
    for i = 1, 40 do units[#units + 1] = "nameplate" .. i end
    return units
end

local function UpdateTargets()
    local used, hidden = {}, false
    for _, u in ipairs(TargetUnits()) do
        if UnitExists(u) then
            local ok, idx = pcall(GetRaidTargetIndex, u)
            if not ok or Secret(idx) then
                hidden = true
            elseif idx then
                used[idx] = true
            end
        end
    end
    for icon, b in pairs(SRT.tmButtons or {}) do
        if used[icon] then
            Show(b, "used")
        else
            -- if some marks were hidden from us, a "free" icon might really be in use
            Show(b, hidden and "unknown" or "free")
        end
    end
end

local function Update()
    if not SRT.frame or not SRT.frame:IsShown() then return end
    pcall(UpdateGround)
    pcall(UpdateTargets)
end

function SRT:InitMarkerStatus()
    -- world markers have no event, so a light ticker covers both rows
    if not ticker then ticker = C_Timer.NewTicker(0.5, Update) end
    Update()
end
