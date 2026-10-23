-- Spilled Raid Tools - Options panel (Esc > Options > AddOns) and slash commands
local ADDON, ns = ...
local SRT = ns.SRT
local Print = SRT.Print
SRT.settings = {}

function SRT:InitOptions()
    local ok, err = pcall(function()
        local db = self.db
        local category = Settings.RegisterVerticalLayoutCategory("Spilled Raid Tools")
        self.category = category

        local function Register(key, name, varType)
            local s = Settings.RegisterAddOnSetting(category, "SRT_" .. key, key, db, varType, name, SRT.defaults[key])
            s:SetValueChangedCallback(function() SRT:Refresh() end)
            SRT.settings[key] = s
            return s
        end

        local function Slider(key, name, tip, min, max, step, fmt)
            local s = Register(key, name, Settings.VarType.Number)
            local o = Settings.CreateSliderOptions(min, max, step)
            o:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v)
                if type(fmt) == "function" then return fmt(v) end
                return fmt:format(v)
            end)
            Settings.CreateSlider(category, s, o, tip)
        end

        local function Check(key, name, tip)
            Settings.CreateCheckbox(category, Register(key, name, Settings.VarType.Boolean), tip)
        end

        Slider("pullSeconds", "Pull timer", "Default pull countdown length.", 3, 60, 1, "%d sec")
        Check("announcePull", "Pull in raid warning", "Duplicate the pull countdown in raid warning.")
        Slider("pullCountFrom", "Count every second from", "Raid-warn each second from this number down (0 = only start and PULL).", 0, 10, 1, "%d")
        Slider("breakMinutes", "Break timer", "Default break length (sent to BigWigs / DBM).", 1, 30, 1, "%d min")
        Check("announceBreak", "Break in raid warning", "Announce break start and end in raid warning.")
        Check("announceReady", "Ready check result", "Announce 'Everyone is ready!' or who is not ready.")
        Check("postWithoutLead", "Post without lead / assist",
            "Off: without lead or assist you never post automatic messages or check results to chat.")
        Check("announceOthers", "Also announce for other players",
            "Announce pulls, breaks and ready checks started by other players too.\n" ..
            "Players who also use this addon announce their own, so nothing is posted twice.")
        Check("checkDurability", "Durability check on ready check",
            "On ready check, raid-warn players below the durability limit.\n" ..
            "Only works for players who have this addon or MRT.")
        Slider("durabilityMin", "Durability warning below", "Warn about players below this average durability.", 5, 100, 5, "%d%%")
        Check("checkVantus", "Check vantus runes", "Buff check also lists players without a vantus rune.")
        Slider("expireWarnMinutes", "Warn when food / flask expires within",
            "Buff check lists players whose food or flask runs out soon (0 = off).", 0, 15, 1, "%d min")
        Check("checkSoulwell", "Soulwell reminder on ready check",
            "On ready check, ask warlocks for a Soulwell (skipped if one was put down in the last 10 min).")
        Check("autoBuffCheck", "Auto buff check on ready check",
            "Run the buff check when a ready check starts. Only one player posts it.")
        Check("blockMRTReport", "Keep MRT's ready check report off",
            "Turn off MRT's own food / flask chat report on ready check (your client only).")
        local function Rank(v) return ("%d - %s"):format(v, SRT.RankName(v)) end
        Slider("inviteMaxRank", "Invite guild ranks up to", "Invite button: online max-level guild members of these ranks.", 1, 10, 1, Rank)
        Slider("promoteMaxRank", "Promote guild ranks up to", "Promote button: these guild ranks get raid assist.", 1, 10, 1, Rank)
        Check("autoPromote", "Auto promote", "Promote those ranks automatically when they join (you must be raid leader).")
        Slider("sortMaxGroup", "Sort groups 1 to", "Sort button: only these groups are sorted, higher groups are left alone (bench).", 1, 8, 1, "%d")
        local function Icon(v)
            if v == 0 then return "None" end
            return ("|T%s%d:0|t %s"):format(SRT.ICON_PATH, v, SRT.ICON_NAMES[v])
        end
        Slider("tankMark1", "First tank mark", "Mark tanks button: icon for the first tank.", 0, 8, 1, Icon)
        Slider("tankMark2", "Second tank mark", "Mark tanks button: icon for the second tank.", 0, 8, 1, Icon)
        Check("noteAutoShow", "Show raid note when it arrives", "Open the raid note window when the leader sends a new note.")
        Slider("noteFontSize", "Raid note text size", "Font size of the raid note.", 8, 24, 1, "%d")
        Slider("noteWidth", "Raid note width", "Width of the raid note window.", 150, 600, 10, "%d")
        Check("minimapButton", "Minimap button", "Show the minimap button (left: show/hide frame, right: options).")
        Check("buffReportToChat", "Post buff / gear check to group chat", "Off = only you see the result.")
        Check("locked", "Lock frames", "Prevent dragging the frame and the raid note.")
        Check("shown", "Show frame", "Show the Spilled Raid Tools frame.")
        Slider("scale", "Scale", "Frame scale.", 0.6, 2, 0.05, "%.2f")

        Settings.RegisterAddOnCategory(category)
    end)
    if not ok then Print("Options panel unavailable (" .. tostring(err) .. "). Use /srt commands.") end
end

-- Opens our own settings window (Window.lua); the Blizzard panel stays as a fallback
function SRT:OpenOptions(tab)
    if self.ShowWindow then
        self:ShowWindow(tab)
    elseif self.category then
        Settings.OpenToCategory(self.category:GetID())
    else
        Print("Use /srt help")
    end
end

function SRT:OpenBlizzardOptions()
    if self.category then Settings.OpenToCategory(self.category:GetID()) end
end

-- Change a setting from anywhere (keeps the Blizzard panel in sync)
function SRT:SetOption(key, value)
    if SRT.settings[key] then
        SRT.settings[key]:SetValue(value)   -- updates panel + db + refresh
    else
        SRT.db[key] = value
        SRT:Refresh()
    end
end
local function Set(key, value) SRT:SetOption(key, value) end

SLASH_SPILLEDRAIDTOOLS1 = "/srt"
SlashCmdList.SPILLEDRAIDTOOLS = function(msg)
    local cmd, arg = strsplit(" ", strtrim(msg or ""):lower(), 2)
    local n = tonumber(arg)
    if cmd == "" then
        SRT:Toggle()
    elseif cmd == "pull" then
        if n then Set("pullSeconds", math.floor(n)) Print("Default pull timer: " .. math.floor(n) .. " sec")
        else SRT:StartPull() end
    elseif cmd == "break" then
        if n then Set("breakMinutes", math.floor(n)) Print("Default break: " .. math.floor(n) .. " min")
        else SRT:StartBreak() end
    elseif cmd == "rc" or cmd == "ready" then SRT:ReadyCheck()
    elseif cmd == "buffs" then SRT:BuffCheck()
    elseif cmd == "gear" then SRT:GearCheck()
    elseif cmd == "invite" or cmd == "inv" then SRT:GuildInvite()
    elseif cmd == "promote" then SRT:PromoteAssists()
    elseif cmd == "sort" then SRT:SortGroups()
    elseif cmd == "note" then
        if arg == "edit" then SRT:OpenNoteEditor() else SRT:ToggleNote() end
    elseif cmd == "lock" then Set("locked", true) Print("Frame locked.")
    elseif cmd == "unlock" then Set("locked", false) Print("Frame unlocked - drag to move.")
    elseif cmd == "config" or cmd == "options" then SRT:OpenOptions()
    elseif cmd == "groups" then SRT:OpenOptions("groups")
    elseif cmd == "test" then
        if arg == "stop" then SRT:StopReminders() else SRT:TestReminders() end
    elseif cmd == "move" then SRT:MoveReminders()
    elseif cmd == "debug" then
        SRT.debug = not SRT.debug
        Print("Debug " .. (SRT.debug and "ON" or "OFF"))
    elseif cmd == "reset" then
        if InCombatLockdown() then Print("Not in combat.") return end
        SRT.db.point = nil
        SRT:Refresh()
        Print("Position reset.")
    else
        Print("/srt - show/hide frame")
        Print("/srt pull [sec] - start pull, or set default (e.g. /srt pull 15)")
        Print("/srt break [min] - start break, or set default (e.g. /srt break 5)")
        Print("/srt rc - ready check,  /srt buffs - buff check,  /srt gear - gear check")
        Print("/srt invite | promote | sort - roster tools")
        Print("/srt note - show/hide raid note,  /srt note edit - edit and send it")
        Print("/srt test [stop] - test fight reminders,  /srt move - move the reminder display")
        Print("/srt config - settings window,  /srt groups - raid groups board")
        Print("/srt lock | unlock | reset | debug")
    end
end
