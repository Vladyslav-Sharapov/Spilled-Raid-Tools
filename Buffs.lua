-- Spilled Raid Tools - Food / flask / raid buff check
local ADDON, ns = ...
local SRT = ns.SRT
local Print = SRT.Print

-- Raid buffs are only checked if someone of that class is in the group.
-- The buff name is read from the spell ID, so it works in any client language
-- and catches every variant of a buff (e.g. all Blessing of the Bronze versions).
local RAID_BUFFS = {
    { spell = 1459,   class = "MAGE"    }, -- Arcane Intellect
    { spell = 21562,  class = "PRIEST"  }, -- Power Word: Fortitude
    { spell = 6673,   class = "WARRIOR" }, -- Battle Shout
    { spell = 1126,   class = "DRUID"   }, -- Mark of the Wild
    { spell = 462854, class = "SHAMAN"  }, -- Skyfury
    { spell = 381748, class = "EVOKER"  }, -- Blessing of the Bronze
}

-- Food: every "Well Fed" buff uses this icon.
local FOOD_ICON = 136000
local FOOD_NAME = "Well Fed"

-- Flask: any buff whose name contains one of these words (English client).
-- On a non-English client, add your language's word for flask here.
local FLASK_WORDS = { "Flask", "Phial" }

-- Vantus rune: every rune's buff is named "Vantus Rune: <boss/raid>". The
-- "Vantus Rune" part is read from an old rune (Kil'jaeden) so it works in any
-- client language (same trick MRT uses).
local VANTUS_PREFIX
local function VantusPrefix()
    if not VANTUS_PREFIX then
        local n = C_Spell.GetSpellName(237825)
        VANTUS_PREFIX = n and n:match("^(.-)%s*[:%-：]") or "Vantus Rune"
    end
    return VANTUS_PREFIX
end

local MAX_NAMES = 10 -- names per chat line before "+N more"

local SendChat = C_ChatInfo.SendChatMessage
local GroupUnits = SRT.GroupUnits     -- shared helpers from Core.lua
local GroupChannel = SRT.GroupChannel

---------------------------------------------------------------------------
-- Seconds left on an aura (math.huge if it never runs out)
local function TimeLeft(a)
    local exp = a.expirationTime
    if not exp or exp == 0 then return math.huge end
    return exp - GetTime()
end

-- Returns { food = bool, flask = bool, vantus = bool, buffs = { [buffName] = true },
--           foodLeft = sec, flaskLeft = sec }
local function ScanUnit(unit, wanted)
    local r = { food = false, flask = false, vantus = false, buffs = {}, foodLeft = 0, flaskLeft = 0 }
    local vantus = VantusPrefix()
    for i = 1, 255 do
        local a = C_UnitAuras.GetAuraDataByIndex(unit, i, "HELPFUL")
        if not a then break end
        local name = a.name
        if name then
            if a.icon == FOOD_ICON or name == FOOD_NAME then
                r.food = true
                r.foodLeft = math.max(r.foodLeft, TimeLeft(a))
            end
            for _, w in ipairs(FLASK_WORDS) do
                if name:find(w, 1, true) then
                    r.flask = true
                    r.flaskLeft = math.max(r.flaskLeft, TimeLeft(a))
                end
            end
            if name:sub(1, #vantus) == vantus then r.vantus = true end
            if wanted[name] then r.buffs[name] = true end
        end
    end
    return r
end

local function NameList(list, max)
    max = max or MAX_NAMES
    local s = table.concat(list, ", ", 1, math.min(#list, max))
    if #list > max then s = s .. " +" .. (#list - max) .. " more" end
    return s
end

---------------------------------------------------------------------------
function SRT:BuffCheck()
    if InCombatLockdown() then Print("Can't check buffs in combat.") return end

    local units = GroupUnits()

    -- which raid buffs can this group provide?
    local classes = {}
    for _, u in ipairs(units) do
        if UnitExists(u) then
            local _, class = UnitClass(u)
            if class then classes[class] = true end
        end
    end
    local wanted, order, missing = {}, {}, {}
    for _, b in ipairs(RAID_BUFFS) do
        local name = classes[b.class] and C_Spell.GetSpellName(b.spell)
        if name and not wanted[name] then
            wanted[name] = true
            order[#order + 1] = name
            missing[name] = {}
        end
    end

    -- scan everyone
    local noFood, noFlask, noVantus, expiring, skipped = {}, {}, {}, {}, {}
    local warnAt = (self.db.expireWarnMinutes or 0) * 60
    for _, u in ipairs(units) do
        if UnitExists(u) then
            local name = UnitName(u)
            if not UnitIsConnected(u) or UnitIsDeadOrGhost(u) or not UnitIsVisible(u) then
                skipped[#skipped + 1] = name
            else
                local ok, r = pcall(ScanUnit, u, wanted)
                if not ok then
                    skipped[#skipped + 1] = name
                else
                    if not r.food then noFood[#noFood + 1] = name end
                    if not r.flask then noFlask[#noFlask + 1] = name end
                    if not r.vantus then noVantus[#noVantus + 1] = name end
                    local soon = {}
                    if r.food and r.foodLeft < warnAt then
                        soon[#soon + 1] = ("food %dm"):format(math.ceil(r.foodLeft / 60))
                    end
                    if r.flask and r.flaskLeft < warnAt then
                        soon[#soon + 1] = ("flask %dm"):format(math.ceil(r.flaskLeft / 60))
                    end
                    if #soon > 0 then expiring[#expiring + 1] = ("%s (%s)"):format(name, table.concat(soon, ", ")) end
                    for _, buff in ipairs(order) do
                        if not r.buffs[buff] then table.insert(missing[buff], name) end
                    end
                end
            end
        end
    end

    -- build report
    local lines = {}
    local function Add(label, list, max)
        if #list > 0 then lines[#lines + 1] = ("%s (%d): %s"):format(label, #list, NameList(list, max)) end
    end
    Add("No food", noFood)
    Add("No flask", noFlask)
    if self.db.checkVantus then Add("No vantus rune", noVantus) end
    for _, buff in ipairs(order) do Add("No " .. buff, missing[buff]) end
    Add("Expiring soon", expiring, 5) -- longer entries, keep under the chat limit
    if #lines == 0 then
        lines[1] = self.db.checkVantus and "Buff check: everyone has food, flask, vantus rune and raid buffs!"
            or "Buff check: everyone has food, flask and raid buffs!"
    else
        table.insert(lines, 1, "Buff check:")
    end

    -- output
    local ch = GroupChannel()
    for _, line in ipairs(lines) do
        if ch and self.db.buffReportToChat and SRT.MayPost() then
            SendChat(line, ch)
        else
            Print(line)
        end
    end
    if #skipped > 0 then
        Print("Not checked (offline, dead or too far): " .. NameList(skipped))
    end
end
