-- Spilled Raid Tools - Minimap button (+ addon compartment entry)
local ADDON, ns = ...
local SRT = ns.SRT

local button

local function Click(_, btn)
    if btn == "RightButton" then SRT:OpenOptions() else SRT:Toggle() end
end

local function ShowTooltip(owner)
    GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
    GameTooltip:SetText("Spilled Raid Tools")
    GameTooltip:AddLine("Left-click: show / hide frame", 1, 1, 1)
    GameTooltip:AddLine("Right-click: settings", 1, 1, 1)
    GameTooltip:AddLine("Drag: move button", 1, 1, 1)
    GameTooltip:Show()
end

-- place the button on the minimap edge at the saved angle
local function UpdatePosition()
    local angle = math.rad(SRT.db.minimapAngle or 225)
    local r = Minimap:GetWidth() / 2 + 10
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * r, math.sin(angle) * r)
end

local function OnDragUpdate()
    local mx, my = Minimap:GetCenter()
    local px, py = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale()
    SRT.db.minimapAngle = math.deg(math.atan2(py / scale - my, px / scale - mx))
    UpdatePosition()
end

local function Build()
    local b = CreateFrame("Button", "SpilledRaidToolsMinimapButton", Minimap)
    b:SetSize(31, 31)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:RegisterForDrag("LeftButton")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local bg = b:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)

    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetTexture(SRT.ICON_PATH .. "8")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)

    local border = b:CreateTexture(nil, "OVERLAY")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")

    b:SetScript("OnClick", Click)
    b:SetScript("OnEnter", ShowTooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:SetScript("OnDragStart", function(s) s:SetScript("OnUpdate", OnDragUpdate) end)
    b:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)

    button = b
    UpdatePosition()
end

function SRT:RefreshMinimap()
    if self.db.minimapButton and not button then Build() end
    if button then button:SetShown(self.db.minimapButton) end
end

function SRT:InitMinimap()
    self:RefreshMinimap()
end

-- Addon compartment (the addon list button next to the minimap), set in the .toc
function SpilledRaidTools_OnAddonCompartmentClick(_, btn)
    Click(nil, btn)
end
