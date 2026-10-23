-- Spilled Raid Tools - Gear check (missing enchants / empty gem sockets)
local ADDON, ns = ...
local SRT = ns.SRT
local Print = SRT.Print

-- Slots that can be enchanted (Midnight). Edit this list if Blizzard changes it.
-- The off hand only counts when it is a weapon (not a shield / off-hand item).
local ENCHANT_SLOTS = {
    { slot = 1,  name = "Head"      },
    { slot = 3,  name = "Shoulders" },
    { slot = 5,  name = "Chest"     },
    { slot = 7,  name = "Legs"      },
    { slot = 8,  name = "Feet"      },
    { slot = 11, name = "Ring 1"    },
    { slot = 12, name = "Ring 2"    },
    { slot = 16, name = "Weapon"    },
    { slot = 17, name = "Off hand", weaponOnly = true },
}
local GEAR_SLOTS = { 1, 2, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17 }

local INSPECT_TIMEOUT = 3   -- seconds to wait for one player's gear
local INSPECT_GAP     = 0.5 -- pause between players (the server throttles inspects)
local MAX_NAMES       = 8

local SendChat = C_ChatInfo.SendChatMessage
local GroupUnits = SRT.GroupUnits
local GroupChannel = SRT.GroupChannel

---------------------------------------------------------------------------
-- Reading one player's gear
---------------------------------------------------------------------------
-- item:itemID:enchantID:gem1:gem2:gem3:gem4:...
local function ParseLink(link)
    local fields = { strsplit(":", link:match("item:([%-%d:]*)") or "") }
    local enchant = tonumber(fields[2]) or 0
    local gems = 0
    for i = 3, 6 do
        if (tonumber(fields[i]) or 0) > 0 then gems = gems + 1 end
    end
    return enchant, gems
end

local function SocketCount(link)
    local stats = C_Item.GetItemStats(link)
    local n = 0
    if stats then
        for k, v in pairs(stats) do
            if k:find("^EMPTY_SOCKET_") then n = n + v end
        end
    end
    return n
end

-- Returns { enchants = { "Legs", ... }, sockets = <number of empty sockets> }
local function ScanGear(unit)
    local r = { enchants = {}, sockets = 0 }
    for _, e in ipairs(ENCHANT_SLOTS) do
        local link = GetInventoryItemLink(unit, e.slot)
        if link then
            local isWeapon = select(6, C_Item.GetItemInfoInstant(link)) == Enum.ItemClass.Weapon
            if not e.weaponOnly or isWeapon then
                local enchant = ParseLink(link)
                if enchant == 0 then r.enchants[#r.enchants + 1] = e.name end
            end
        end
    end
    for _, slot in ipairs(GEAR_SLOTS) do
        local link = GetInventoryItemLink(unit, slot)
        if link then
            local _, gems = ParseLink(link)
            local empty = SocketCount(link) - gems
            if empty > 0 then r.sockets = r.sockets + empty end
        end
    end
    return r
end

---------------------------------------------------------------------------
-- Inspect queue: one player at a time
---------------------------------------------------------------------------
local running = false
local queue, results, skipped = {}, {}, {}
local current, currentGUID, timeoutTimer

local f = CreateFrame("Frame")

local function Report()
    running = false
    f:UnregisterEvent("INSPECT_READY")
    ClearInspectPlayer()

    local noEnchant, noGems = {}, {}
    for _, r in ipairs(results) do
        if #r.enchants > 0 then
            noEnchant[#noEnchant + 1] = ("%s (%s)"):format(r.name, table.concat(r.enchants, ", "))
        end
        if r.sockets > 0 then
            noGems[#noGems + 1] = ("%s (%d)"):format(r.name, r.sockets)
        end
    end

    local lines = {}
    local function Add(label, list)
        if #list == 0 then return end
        -- several short lines so nothing gets cut at the 255 character limit
        for i = 1, #list, MAX_NAMES do
            local part = table.concat(list, ", ", i, math.min(#list, i + MAX_NAMES - 1))
            lines[#lines + 1] = (i == 1 and ("%s: %s"):format(label, part)) or part
        end
    end
    Add("Missing enchants", noEnchant)
    Add("Empty sockets", noGems)
    if #lines == 0 then
        lines[1] = ("Gear check: all %d checked players are fully enchanted and gemmed!"):format(#results)
    else
        table.insert(lines, 1, "Gear check:")
    end

    local ch = GroupChannel()
    for _, line in ipairs(lines) do
        if ch and SRT.db.buffReportToChat then SendChat(line, ch) else Print(line) end
    end
    if #skipped > 0 then
        Print("Gear not checked (offline, too far or no answer): " .. table.concat(skipped, ", "))
    end
end

local InspectNext

local function Finish(unit, name, ok)
    if timeoutTimer then timeoutTimer:Cancel() timeoutTimer = nil end
    current, currentGUID = nil, nil
    if ok then
        local good, r = pcall(ScanGear, unit)
        if good then
            r.name = name
            results[#results + 1] = r
        else
            skipped[#skipped + 1] = name
        end
    else
        skipped[#skipped + 1] = name
    end
    C_Timer.After(INSPECT_GAP, InspectNext)
end

function InspectNext()
    if not running then return end
    if InCombatLockdown() then
        Print("Gear check stopped: entered combat.")
        running = false
        f:UnregisterEvent("INSPECT_READY")
        return
    end
    local unit = table.remove(queue, 1)
    if not unit then Report() return end

    local name = UnitName(unit)
    if not UnitExists(unit) then return InspectNext() end
    if not UnitIsConnected(unit) or not CanInspect(unit) or not UnitIsVisible(unit) then
        skipped[#skipped + 1] = name
        return InspectNext()
    end

    current, currentGUID = unit, UnitGUID(unit)
    NotifyInspect(unit)
    timeoutTimer = C_Timer.NewTimer(INSPECT_TIMEOUT, function()
        timeoutTimer = nil
        if current == unit then Finish(unit, name, false) end
    end)
end

f:SetScript("OnEvent", function(_, event, guid)
    if event == "INSPECT_READY" and current and guid == currentGUID then
        local unit = current
        -- remember the spec for melee / ranged sorting (pcall: may be a secret value)
        pcall(function()
            local spec = GetInspectSpecialization(unit)
            if spec and spec > 0 then SRT.specCache[guid] = spec end
        end)
        -- give the item links a moment to fill in
        C_Timer.After(0.3, function()
            if current == unit then Finish(unit, UnitName(unit), true) end
        end)
    end
end)

function SRT:GearCheck()
    if InCombatLockdown() then Print("Can't check gear in combat.") return end
    if running then Print("Gear check already running...") return end

    wipe(queue) wipe(results) wipe(skipped)
    for _, u in ipairs(GroupUnits()) do
        if UnitExists(u) then
            if UnitIsUnit(u, "player") then
                local r = ScanGear("player")
                r.name = UnitName("player")
                results[#results + 1] = r
            else
                queue[#queue + 1] = u
            end
        end
    end

    running = true
    f:RegisterEvent("INSPECT_READY")
    if #queue > 0 then
        Print(("Gear check: inspecting %d players, this takes about %d sec..."):format(#queue, math.ceil(#queue * 1)))
    end
    InspectNext()
end
