-- Spilled Raid Tools - Roster tools: guild invite by rank, promote, sort groups
local ADDON, ns = ...
local SRT = ns.SRT
local Print = SRT.Print

local InviteUnit = C_PartyInfo.InviteUnit

-- Guild ranks are shown 1-based like in the guild window (1 = Guild Master).
local function RankName(rank)
    local ok, name = pcall(GuildControlGetRankName, rank)
    return (ok and name and name ~= "") and name or ("Rank " .. rank)
end
SRT.RankName = RankName

local function ShortName(name)
    local ok, short = pcall(Ambiguate, name or "", "none")
    return ok and short or name
end

-- [name] = 1-based guild rank, for everyone in the guild roster
local function GuildRanks()
    local ranks = {}
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex = GetGuildRosterInfo(i)
        if name then ranks[ShortName(name)] = rankIndex + 1 end
    end
    return ranks
end

local function InGroup(name)
    return UnitInParty(name) or UnitInRaid(name)
end

---------------------------------------------------------------------------
-- Invite online max-level guild members up to a rank
---------------------------------------------------------------------------
local pending = {}       -- names still to invite once the group is a raid
local pendingUntil = 0

local function DoInvite()
    local maxRank = SRT.db.inviteMaxRank
    local maxLevel = GetMaxLevelForPlayerExpansion()
    local me = UnitName("player")
    local list = {}
    for i = 1, GetNumGuildMembers() do
        local name, _, rankIndex, level, _, _, _, _, online, _, _, _, _, isMobile = GetGuildRosterInfo(i)
        local short = name and ShortName(name)
        if short and online and not isMobile and rankIndex + 1 <= maxRank and level >= maxLevel
            and short ~= me and not InGroup(short) then
            list[#list + 1] = short
        end
    end
    if #list == 0 then
        Print(("Invite: nobody to invite (online, max level, rank up to %s)."):format(RankName(maxRank)))
        return
    end

    wipe(pending)
    if IsInRaid() then
        for _, n in ipairs(list) do InviteUnit(n) end
    else
        -- a party holds 5: invite what fits, the rest once it becomes a raid
        local room = 5 - math.max(GetNumGroupMembers(), 1)
        for i, n in ipairs(list) do
            if i <= room then InviteUnit(n) else pending[#pending + 1] = n end
        end
        pendingUntil = GetTime() + 120
    end
    Print(("Invite: inviting %d guild members (rank up to %s)%s."):format(#list, RankName(maxRank),
        #pending > 0 and ", converting to raid when the first one joins" or ""))
end

function SRT:GuildInvite()
    if not IsInGuild() then Print("You are not in a guild.") return end
    if IsInGroup() and not (UnitIsGroupLeader("player") or (IsInRaid() and UnitIsGroupAssistant("player"))) then
        Print("You need to be leader (or assist in a raid) to invite.")
        return
    end
    C_GuildInfo.GuildRoster()        -- refresh the online list, then invite
    C_Timer.After(1, DoInvite)
end

---------------------------------------------------------------------------
-- Promote guild members up to a rank to raid assist
---------------------------------------------------------------------------
local function Promote(silent)
    if not IsInRaid() or not UnitIsGroupLeader("player") then
        if not silent then Print("You need to be raid leader to promote.") end
        return
    end
    local ranks = GuildRanks()
    local maxRank = SRT.db.promoteMaxRank
    local promoted = {}
    for i = 1, GetNumGroupMembers() do
        local name, raidRank = GetRaidRosterInfo(i)
        local gr = name and ranks[name]
        if gr and gr <= maxRank and raidRank == 0 then
            PromoteToAssistant("raid" .. i)
            promoted[#promoted + 1] = name
        end
    end
    if #promoted > 0 then
        Print("Promoted to assist: " .. table.concat(promoted, ", "))
    elseif not silent then
        Print(("Promote: no one to promote (guild rank up to %s)."):format(RankName(maxRank)))
    end
end

function SRT:PromoteAssists()
    if not IsInGuild() then Print("You are not in a guild.") return end
    Promote(false)
end

---------------------------------------------------------------------------
-- Sort groups by category in a custom order (default: tanks, healers, melee, ranged).
-- Pinned players stay in their pinned group. Only groups 1..sortMaxGroup are
-- touched (higher groups = bench). The game applies one move at a time, so we
-- do one step per roster update.
---------------------------------------------------------------------------
SRT.SORT_CATEGORIES = { TANK = "Tanks", HEALER = "Healers", MELEE = "Melee", RANGED = "Ranged" }
local DEFAULT_ORDER = { "TANK", "HEALER", "MELEE", "RANGED" }

-- Melee damage specs (everything else that deals damage counts as ranged)
local MELEE_SPECS = {
    [70] = true,                                  -- Retribution
    [71] = true, [72] = true,                     -- Arms, Fury
    [103] = true,                                 -- Feral
    [251] = true, [252] = true,                   -- Frost, Unholy DK
    [255] = true,                                 -- Survival
    [259] = true, [260] = true, [261] = true,     -- Rogue
    [263] = true,                                 -- Enhancement
    [269] = true,                                 -- Windwalker
    [577] = true,                                 -- Havoc
}
-- When the spec is unknown (not inspected yet), guess from the class
local MELEE_CLASSES = { WARRIOR = true, ROGUE = true, DEATHKNIGHT = true, PALADIN = true, MONK = true, DEMONHUNTER = true }

SRT.specCache = SRT.specCache or {}   -- [GUID] = spec ID, filled by the gear check

function SRT:SortOrder()
    local db = self.db
    if type(db.sortOrder) ~= "table" or #db.sortOrder ~= #DEFAULT_ORDER then
        db.sortOrder = { unpack(DEFAULT_ORDER) }
    end
    return db.sortOrder
end

function SRT:SortPins()
    if type(self.db.sortPins) ~= "table" then self.db.sortPins = {} end
    return self.db.sortPins
end

function SRT:UnitCategory(unit)
    local role = UnitGroupRolesAssigned(unit)
    if role == "TANK" or role == "HEALER" then return role end
    local spec
    if UnitIsUnit(unit, "player") then
        local idx = GetSpecialization()
        spec = idx and GetSpecializationInfo(idx)
    else
        spec = self.specCache[UnitGUID(unit) or ""]
    end
    if spec and spec > 0 then return MELEE_SPECS[spec] and "MELEE" or "RANGED" end
    local _, class = UnitClass(unit)
    return MELEE_CLASSES[class] and "MELEE" or "RANGED"
end

local sorting, sortSteps, sortTimer = false, 0, nil
local sortMaxOverride    -- group presets sort all 8 groups

local function SortStep()
    if sortTimer then sortTimer:Cancel() sortTimer = nil end
    if not sorting then return end
    if InCombatLockdown() or not IsInRaid() then sorting = false return end

    sortSteps = sortSteps + 1
    if sortSteps > 80 then
        sorting = false
        Print("Sort: stopped (too many moves). Try again.")
        return
    end

    local maxGroup = sortMaxOverride or SRT.db.sortMaxGroup
    local rank = {}
    for i, cat in ipairs(SRT:SortOrder()) do rank[cat] = i end
    local pins = SRT:SortPins()

    local members, count, free = {}, {}, {}
    for g = 1, 8 do count[g], free[g] = 0, 5 end
    local unpinned = {}
    for i = 1, GetNumGroupMembers() do
        local name, _, subgroup = GetRaidRosterInfo(i)
        if name then
            count[subgroup] = count[subgroup] + 1
            if subgroup <= maxGroup then
                local m = { index = i, name = name, group = subgroup,
                            rank = rank[SRT:UnitCategory("raid" .. i)] or 9 }
                local pin = pins[name]
                if pin and pin <= maxGroup and free[pin] > 0 then
                    m.want = pin
                    free[pin] = free[pin] - 1
                else
                    unpinned[#unpinned + 1] = m
                end
                members[#members + 1] = m
            end
        end
    end
    table.sort(unpinned, function(a, b)
        if a.rank ~= b.rank then return a.rank < b.rank end
        return a.name < b.name
    end)
    local g = 1
    for _, m in ipairs(unpinned) do
        while g < 8 and free[g] == 0 do g = g + 1 end
        m.want = g
        free[g] = free[g] - 1
    end

    for _, m in ipairs(members) do
        if m.group ~= m.want then
            if count[m.want] < 5 then
                SetRaidSubgroup(m.index, m.want)
            else
                for _, o in ipairs(members) do
                    if o.group == m.want and o.want ~= m.want then
                        SwapRaidSubgroup(m.index, o.index)
                        break
                    end
                end
            end
            -- wait for GROUP_ROSTER_UPDATE (or retry if it never comes)
            sortTimer = C_Timer.NewTimer(1, SortStep)
            return
        end
    end
    sorting = false
    local names = {}
    for i, cat in ipairs(SRT:SortOrder()) do names[i] = SRT.SORT_CATEGORIES[cat] end
    Print("Sort: groups sorted (" .. table.concat(names, ", ") .. ").")
end

-- allGroups = true: sort every group (pinned players go to their group even from the bench)
function SRT:SortGroups(allGroups)
    if InCombatLockdown() then Print("Can't sort groups in combat.") return end
    if not IsInRaid() then Print("You must be in a raid to sort groups.") return end
    if not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        Print("You need leader or assist to move players.")
        return
    end
    sortMaxOverride = allGroups and 8 or nil
    sorting, sortSteps = true, 0
    SortStep()
end

---------------------------------------------------------------------------
-- Mark tanks: first tank gets tankMark1, second tankMark2 (0 = no mark)
---------------------------------------------------------------------------
local function IsTank(unit)
    return UnitGroupRolesAssigned(unit) == "TANK" or GetPartyAssignment("MAINTANK", unit)
end

-- Setting raid marks is protected in Midnight, so the Mark tanks button is a
-- secure macro button: right before each click we write "/tm [@raid3] 6" lines.
-- Returns markMacro, clearMacro, summary (or nil + reason when nothing to do)
function SRT:TankMarkMacros()
    if not IsInGroup() then return nil, nil, "You are not in a group." end
    if IsInRaid() and not (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        return nil, nil, "You need leader or assist to mark in a raid."
    end
    local icons = { self.db.tankMark1, self.db.tankMark2 }
    local mark, clear, done, n = {}, {}, {}, 0
    for _, unit in ipairs(self.GroupUnits()) do
        if UnitExists(unit) and IsTank(unit) then
            n = n + 1
            local icon = icons[n]
            -- Midnight hides current marks (secret values), so we can't check what a
            -- tank already has: clear first, then set, so it never toggles off.
            if icon and icon > 0 then
                mark[#mark + 1] = ("/tm [@%s] 0\n/tm [@%s] %d"):format(unit, unit, icon)
                done[#done + 1] = self.ICON_NAMES[icon]
            end
            clear[#clear + 1] = ("/tm [@%s] 0"):format(unit)
        end
    end
    if #done == 0 then return nil, nil, "No tanks found - players need the tank role (or main tank)." end
    return table.concat(mark, "\n"), table.concat(clear, "\n"),
        ("Marked %d tank%s: %s"):format(#done, #done > 1 and "s" or "", table.concat(done, ", "))
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local promoteTimer
local ev = CreateFrame("Frame")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:SetScript("OnEvent", function()
    -- finish a guild invite: convert to raid, then invite the rest
    if #pending > 0 then
        if GetTime() > pendingUntil then
            wipe(pending)
        elseif IsInRaid() then
            for _, n in ipairs(pending) do
                if not InGroup(n) then InviteUnit(n) end
            end
            wipe(pending)
        elseif IsInGroup() and UnitIsGroupLeader("player") then
            C_PartyInfo.ConvertToRaid()
        end
    end

    if sorting then
        if sortTimer then sortTimer:Cancel() end
        sortTimer = C_Timer.NewTimer(0.2, SortStep)
    end

    -- auto promote (debounced: the roster fires many updates at once)
    if SRT.db and SRT.db.autoPromote and IsInGuild() and IsInRaid() and UnitIsGroupLeader("player") then
        if promoteTimer then promoteTimer:Cancel() end
        promoteTimer = C_Timer.NewTimer(1, function()
            promoteTimer = nil
            if not InCombatLockdown() then Promote(true) end
        end)
    end
end)
