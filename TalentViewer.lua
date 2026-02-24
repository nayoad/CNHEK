-- TalentViewer.lua
-- Talent Simulator - freely allocate talents, save/load multiple builds
-- BY Hekili Titan Edition

local addonName, ns = ...
local Hekili = _G[ addonName ]

-- Constants
local ICON_SIZE = 34
local ICON_GAP = 8
local MAX_COLS = 4
local MAX_ROWS = 11
local HEADER_H = 50
local TREE_PAD = 10
local TREE_W = MAX_COLS * (ICON_SIZE + ICON_GAP) + ICON_GAP + 20
local LIST_W = 210  -- Right side build list width
local FRAME_W = TREE_W * 3 + TREE_PAD * 4 + 10 + LIST_W + TREE_PAD
local FRAME_H = MAX_ROWS * (ICON_SIZE + ICON_GAP) + HEADER_H + TREE_PAD * 2 + 110

-- Colors
local CLR_MAX = {0.95, 0.85, 0.1}
local CLR_PART = {0.1, 0.9, 0.1}
local CLR_ZERO = {0.5, 0.5, 0.5}

local viewerFrame = nil
local currentBuildName = nil
local currentIsPreset = false
local isSimMode = false  -- true=simulation mode (clickable), false=view current talents

-- Simulation data: simData[tab][index] = { name, icon, tier, column, rank, maxRank }
local simData = {}
local simPoints = {0, 0, 0}
local simTabNames = {}
local simTabIcons = {}
local simTotalAvail = 0  -- Total available talent points

-- Forward declarations
local ReadCurrentTalents
local GetPointsInTab
local RefreshUI
local RefreshBuildList

-- Cache UI detection result
local cachedUIFont = nil
local cachedUIType = nil  -- "elvui", "ndui", "default"

local function DetectUI()
    if cachedUIType and cachedUIType ~= "default" then return cachedUIType, cachedUIFont end

    -- NDui detection: NDui[1] = B (utility module), NDui[4] = DB (database)
    if _G.NDui then
        local B = _G.NDui[1]
        if B and type(B) == "table" and (B.Reskin or B.SetBD or B.CreateBDFrame) then
            cachedUIType = "ndui"
            local DB = _G.NDui[4]
            if DB and DB.Font and DB.Font[1] then
                cachedUIFont = DB.Font[1]
            end
            return cachedUIType, cachedUIFont
        end
        -- Fallback: if NDui exists, recognize it
        cachedUIType = "ndui"
        return cachedUIType, cachedUIFont
    end

    -- ElvUI detection
    if _G.ElvUI then
        local E = _G.ElvUI[1]
        if E then
            cachedUIType = "elvui"
            if E.media and E.media.normFont then cachedUIFont = E.media.normFont end
            return cachedUIType, cachedUIFont
        end
    end

    return "default", nil
end

-- Get NDui B module
local function GetNDuiB()
    if _G.NDui then return _G.NDui[1] end
    return nil
end

-- General skin helper function
local function SkinFrame(frame, template)
    if not frame then return end
    local uiType = DetectUI()
    if uiType == "ndui" then
        local B = GetNDuiB()
        if B then
            if B.StripTextures then pcall(B.StripTextures, frame) end
            if B.SetBD then pcall(B.SetBD, frame) end
        end
    elseif uiType == "elvui" then
        if frame.StripTextures then frame:StripTextures() end
        if frame.SetTemplate then frame:SetTemplate(template or "Transparent") end
    end
end

local function SkinButton(btn)
    if not btn then return end
    local uiType = DetectUI()
    if uiType == "ndui" then
        local B = GetNDuiB()
        if B and B.Reskin then pcall(B.Reskin, btn) end
    elseif uiType == "elvui" then
        local E = ElvUI[1]
        local S = E:GetModule("Skins")
        S:HandleButton(btn)
    end
end

local function SkinEditBox(box)
    if not box then return end
    local uiType = DetectUI()
    if uiType == "ndui" then
        local B = GetNDuiB()
        if B then
            if B.StripTextures then pcall(B.StripTextures, box) end
            if B.CreateBDFrame then pcall(B.CreateBDFrame, box, 0, true) end
        end
    elseif uiType == "elvui" then
        local E = ElvUI[1]
        local S = E:GetModule("Skins")
        S:HandleEditBox(box)
    end
end

local function SkinClose(btn)
    if not btn then return end
    local uiType = DetectUI()
    if uiType == "ndui" then
        local B = GetNDuiB()
        if B and B.Reskin then pcall(B.Reskin, btn) end
    elseif uiType == "elvui" then
        local E = ElvUI[1]
        local S = E:GetModule("Skins")
        S:HandleCloseButton(btn)
    end
end

local function SetUIFont(fontString, size, flags)
    if not fontString or not fontString.SetFont then return end
    local _, font = DetectUI()
    if font then
        pcall(fontString.SetFont, fontString, font, size or 12, flags or "")
    end
end

local function SkinTreePanel(panel)
    if not panel then return end
    local uiType = DetectUI()
    if uiType == "ndui" then
        local B = GetNDuiB()
        if B then
            if B.StripTextures then pcall(B.StripTextures, panel) end
            if B.CreateBD then pcall(B.CreateBD, panel, 0.7) end
        end
    elseif uiType == "elvui" then
        if panel.StripTextures then pcall(panel.StripTextures, panel) end
        panel:SetBackdrop({
            bgFile = "Interface\\Buttons\\WHITE8X8",
            edgeFile = "Interface\\Buttons\\WHITE8X8",
            edgeSize = 1,
        })
        panel:SetBackdropColor(0.05, 0.05, 0.05, 0.7)
        panel:SetBackdropBorderColor(0, 0, 0, 1)
    end
end

-- ============================================================
-- HKT encode/decode (dedicated export/import format)
-- Format: !HKT!<base64 encoded data>
-- ============================================================
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function B64Encode(data)
    local result = {}
    local pad = ""
    local len = #data
    local rem = len % 3
    if rem > 0 then
        pad = string.rep("=", 3 - rem)
        data = data .. string.rep("\0", 3 - rem)
        len = len + 3 - rem
    end
    for i = 1, len, 3 do
        local b1, b2, b3 = string.byte(data, i, i + 2)
        local n = b1 * 65536 + b2 * 256 + b3
        local c1 = math.floor(n / 262144) % 64
        local c2 = math.floor(n / 4096) % 64
        local c3 = math.floor(n / 64) % 64
        local c4 = n % 64
        result[#result + 1] = string.sub(B64, c1 + 1, c1 + 1)
            .. string.sub(B64, c2 + 1, c2 + 1)
            .. string.sub(B64, c3 + 1, c3 + 1)
            .. string.sub(B64, c4 + 1, c4 + 1)
    end
    local encoded = table.concat(result)
    if #pad > 0 then
        encoded = string.sub(encoded, 1, #encoded - #pad) .. pad
    end
    return encoded
end

local B64Rev = {}
for i = 1, 64 do B64Rev[string.byte(B64, i)] = i - 1 end
B64Rev[string.byte("=")] = 0

local function B64Decode(data)
    data = data:gsub("[^A-Za-z0-9+/=]", "")
    local result = {}
    for i = 1, #data, 4 do
        local c1 = B64Rev[string.byte(data, i)] or 0
        local c2 = B64Rev[string.byte(data, i + 1)] or 0
        local c3 = B64Rev[string.byte(data, i + 2)] or 0
        local c4 = B64Rev[string.byte(data, i + 3)] or 0
        local n = c1 * 262144 + c2 * 4096 + c3 * 64 + c4
        result[#result + 1] = string.char(math.floor(n / 65536) % 256)
            .. string.char(math.floor(n / 256) % 256)
            .. string.char(n % 256)
    end
    local decoded = table.concat(result)
    local padCount = select(2, data:gsub("=", "")) or 0
    if padCount > 0 then
        decoded = string.sub(decoded, 1, #decoded - padCount)
    end
    return decoded
end

local function SerializeBuild(buildName, tabNames, points, talents)
    local parts = {}
    parts[#parts + 1] = buildName
    parts[#parts + 1] = (tabNames[1] or "") .. "|" .. (tabNames[2] or "") .. "|" .. (tabNames[3] or "")
    parts[#parts + 1] = (points[1] or 0) .. "|" .. (points[2] or 0) .. "|" .. (points[3] or 0)
    for tab = 1, 3 do
        local tParts = {}
        if talents[tab] then
            local indices = {}
            for i in pairs(talents[tab]) do
                indices[#indices + 1] = tonumber(i) or i
            end
            table.sort(indices)
            for _, i in ipairs(indices) do
                local t = talents[tab][i]
                if t and t.rank and t.rank > 0 then
                    tParts[#tParts + 1] = i .. ":" .. (t.name or "?") .. ":" .. t.rank .. ":" .. (t.maxRank or 0)
                end
            end
        end
        parts[#parts + 1] = table.concat(tParts, ";")
    end
    return table.concat(parts, "\n")
end

local function DeserializeBuild(raw)
    local lines = {}
    for line in raw:gmatch("[^\n]+") do
        lines[#lines + 1] = line
    end
    if #lines < 6 then return nil end

    local buildName = lines[1]
    local tn1, tn2, tn3 = lines[2]:match("^(.-)|(.-)|(.-)$")
    local p1, p2, p3 = lines[3]:match("^(%d+)|(%d+)|(%d+)$")

    if not tn1 or not p1 then return nil end

    local talents = { {}, {}, {} }
    for tab = 1, 3 do
        local line = lines[3 + tab] or ""
        for entry in line:gmatch("[^;]+") do
            local idx, name, rank, maxRank = entry:match("^(%d+):(.+):(%d+):(%d+)$")
            if idx then
                talents[tab][tonumber(idx)] = {
                    name = name,
                    rank = tonumber(rank),
                    maxRank = tonumber(maxRank),
                }
            end
        end
    end

    return {
        name = buildName,
        tabNames = { tn1, tn2, tn3 },
        points = { tonumber(p1), tonumber(p2), tonumber(p3) },
        talents = talents,
    }
end

local HKT_PREFIX = "!HKT!"

local function ExportToString(buildName, tabNames, points, talents)
    local raw = SerializeBuild(buildName, tabNames, points, talents)
    return HKT_PREFIX .. B64Encode(raw)
end

local function ImportFromString(str)
    str = str:trim()
    if str:sub(1, #HKT_PREFIX) ~= HKT_PREFIX then return nil end
    local encoded = str:sub(#HKT_PREFIX + 1)
    local raw = B64Decode(encoded)
    return DeserializeBuild(raw)
end

-- ============================================================
-- Data storage
-- User builds: stored in global DB (SavedVariables), separate per user
-- Preset builds: in TalentBuilds.lua, maintained by author, distributed with addon
-- ============================================================
local function GetDB()
    if not Hekili.DB or not Hekili.DB.global then return nil end
    if not Hekili.DB.global.talentBuilds then
        Hekili.DB.global.talentBuilds = {}
    end
    return Hekili.DB.global.talentBuilds
end

local function GetUserBuilds()
    local db = GetDB()
    if not db then return {} end
    local _, className = UnitClass("player")
    if not db[className] then db[className] = {} end
    return db[className]
end

local function GetPresetBuilds()
    local _, className = UnitClass("player")
    if Hekili.PresetTalentBuilds and Hekili.PresetTalentBuilds[className] then
        return Hekili.PresetTalentBuilds[className]
    end
    return {}
end

-- Get all builds (preset+user), returns { name, data, isPreset }
local function GetAllBuilds()
    local result = {}
    -- Preset builds
    local presets = GetPresetBuilds()
    for name, data in pairs(presets) do
        result[name] = { data = data, isPreset = true }
    end
    -- User builds (same name overrides preset)
    local userBuilds = GetUserBuilds()
    for name, data in pairs(userBuilds) do
        result[name] = { data = data, isPreset = false }
    end
    return result
end

local function SaveBuild(buildName, data, points, tabNames)
    local builds = GetUserBuilds()
    builds[buildName] = {
        talents = {},
        points = {points[1], points[2], points[3]},
        tabNames = {tabNames[1], tabNames[2], tabNames[3]},
        timestamp = time(),
    }
    for tab = 1, 3 do
        builds[buildName].talents[tab] = {}
        if data[tab] then
            for i, t in pairs(data[tab]) do
                builds[buildName].talents[tab][i] = {
                    name = t.name,
                    icon = t.icon,
                    tier = t.tier,
                    column = t.column,
                    rank = t.rank,
                    maxRank = t.maxRank,
                }
            end
        end
    end
end

local function LoadBuild(buildName)
    -- Look in user builds first, then preset builds
    local userBuilds = GetUserBuilds()
    local b = userBuilds[buildName]
    local isPreset = false

    if not b then
        local presets = GetPresetBuilds()
        b = presets[buildName]
        isPreset = true
    end
    if not b then return false, false end

    -- First read current talent structure (get icon/tier/column info)
    ReadCurrentTalents()

    -- Override with saved rank
    for tab = 1, 3 do
        if b.talents and b.talents[tab] then
            for i, saved in pairs(b.talents[tab]) do
                local idx = tonumber(i) or i
                if simData[tab] and simData[tab][idx] then
                    simData[tab][idx].rank = saved.rank or 0
                    -- If preset build has name but no icon, keep the icon from the game
                    if saved.name then simData[tab][idx].name = saved.name end
                elseif saved.name then
                    -- Talent in preset but not in current game data (different class), skip
                end
            end
            simPoints[tab] = GetPointsInTab(tab)
        else
            -- No saved data for this tree, reset to zero
            if simData[tab] then
                for _, t in pairs(simData[tab]) do
                    t.rank = 0
                end
            end
            simPoints[tab] = 0
        end
        simTabNames[tab] = b.tabNames and b.tabNames[tab] or simTabNames[tab] or ("Tree " .. tab)
    end
    return true, isPreset
end

local function DeleteBuild(buildName)
    local builds = GetUserBuilds()
    builds[buildName] = nil
end

-- ============================================================
-- Read current talents from game into simData
-- ============================================================
ReadCurrentTalents = function()
    local numTabs = GetNumTalentTabs()
    if not numTabs or numTabs == 0 then return end

    wipe(simData)
    -- Simulation mode uses fixed level 80 71 points, view mode uses actual level
    if isSimMode then
        simTotalAvail = 71
    else
        simTotalAvail = UnitLevel("player") - 9
        if simTotalAvail < 0 then simTotalAvail = 0 end
    end

    for tab = 1, min(numTabs, 3) do
        simData[tab] = {}
        local _, tabName, _, tabIcon, pts = GetTalentTabInfo(tab)
        simTabNames[tab] = tabName or ("Tree " .. tab)
        simTabIcons[tab] = tabIcon
        simPoints[tab] = tonumber(pts) or 0

        local numTalents = GetNumTalents(tab)
        for i = 1, numTalents do
            local name, iconTex, tier, column, rank, maxRank = GetTalentInfo(tab, i)
            if name then
                simData[tab][i] = {
                    name = name,
                    icon = iconTex,
                    tier = tier,
                    column = column,
                    rank = rank or 0,
                    maxRank = maxRank or 0,
                }
            end
        end
    end
end

-- ============================================================
-- Talent point rule check
-- ============================================================
local function GetTierRequirement(tier)
    -- Tier N requires (tier-1)*5 total points in previous tiers
    return (tier - 1) * 5
end

GetPointsInTab = function(tab)
    local total = 0
    if simData[tab] then
        for _, t in pairs(simData[tab]) do
            total = total + (t.rank or 0)
        end
    end
    return total
end

local function GetTotalPoints()
    local total = 0
    for tab = 1, 3 do
        total = total + GetPointsInTab(tab)
    end
    return total
end

local function CanAddPoint(tab, index)
    local t = simData[tab] and simData[tab][index]
    if not t then return false end
    if t.rank >= t.maxRank then return false end
    if GetTotalPoints() >= simTotalAvail then return false end

    -- Check tier requirements
    local needed = GetTierRequirement(t.tier)
    local tabPts = GetPointsInTab(tab)
    if tabPts < needed then return false end

    return true
end

local function CanRemovePoint(tab, index)
    local t = simData[tab] and simData[tab][index]
    if not t then return false end
    if t.rank <= 0 then return false end

    -- After simulated removal, check if higher tier talents still meet prerequisites
    t.rank = t.rank - 1
    local valid = true

    -- Check all higher-tier spent talents in this tree
    for _, other in pairs(simData[tab]) do
        if other.rank > 0 and other.tier > t.tier then
            local needed = GetTierRequirement(other.tier)
            local pts = GetPointsInTab(tab)
            if pts < needed then
                valid = false
                break
            end
        end
    end

    t.rank = t.rank + 1  -- Restore
    return valid
end

-- ============================================================
-- Refresh right side build list
-- ============================================================
RefreshBuildList = function()
    local f = viewerFrame
    if not f or not f.scrollChild then return end

    -- Clear old buttons
    for _, btn in ipairs(f.buildButtons) do
        btn:Hide()
        btn:SetParent(nil)
    end
    wipe(f.buildButtons)

    local allBuilds = GetAllBuilds()
    local yOff = 0
    local btnH = 32
    local btnGap = 3

    -- Show preset builds first
    for name, info in pairs(allBuilds) do
        if info.isPreset then
            local b = info.data
            local pts = format("%d/%d/%d", b.points and b.points[1] or 0, b.points and b.points[2] or 0, b.points and b.points[3] or 0)

            local btn = CreateFrame("Button", nil, f.scrollChild, "BackdropTemplate")
            btn:SetSize(LIST_W - 14, btnH)
            btn:SetPoint("TOPLEFT", 2, -yOff)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })

            -- Highlight current selection
            if currentBuildName == name then
                btn:SetBackdropColor(0.1, 0.3, 0.5, 0.8)
                btn:SetBackdropBorderColor(0.3, 0.7, 1, 1)
            else
                btn:SetBackdropColor(0.1, 0.1, 0.15, 0.6)
                btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
            end

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", 4, 5)
            label:SetWidth(LIST_W - 22)
            label:SetJustifyH("LEFT")
            label:SetText("|cFF00CCFF" .. name .. "|r")

            local sub = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            sub:SetPoint("LEFT", 4, -10)
            sub:SetText("|cFF888888[Preset] " .. pts .. "|r")

            btn:SetScript("OnClick", function()
                isSimMode = true
                currentBuildName = name
                currentIsPreset = true
                LoadBuild(name)
                RefreshUI()
            end)

            btn:SetScript("OnEnter", function(self)
                if currentBuildName ~= name then
                    self:SetBackdropColor(0.15, 0.2, 0.3, 0.8)
                end
            end)
            btn:SetScript("OnLeave", function(self)
                if currentBuildName ~= name then
                    self:SetBackdropColor(0.1, 0.1, 0.15, 0.6)
                end
            end)

            table.insert(f.buildButtons, btn)
            yOff = yOff + btnH + btnGap
        end
    end

    -- Then show user builds
    for name, info in pairs(allBuilds) do
        if not info.isPreset then
            local b = info.data
            local pts = format("%d/%d/%d", b.points and b.points[1] or 0, b.points and b.points[2] or 0, b.points and b.points[3] or 0)

            local btn = CreateFrame("Button", nil, f.scrollChild, "BackdropTemplate")
            btn:SetSize(LIST_W - 14, btnH)
            btn:SetPoint("TOPLEFT", 2, -yOff)
            btn:SetBackdrop({
                bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
                edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                tile = true, tileSize = 16, edgeSize = 10,
                insets = { left = 2, right = 2, top = 2, bottom = 2 }
            })

            if currentBuildName == name then
                btn:SetBackdropColor(0.1, 0.4, 0.1, 0.8)
                btn:SetBackdropBorderColor(0.3, 1, 0.3, 1)
            else
                btn:SetBackdropColor(0.1, 0.1, 0.15, 0.6)
                btn:SetBackdropBorderColor(0.3, 0.3, 0.4, 0.8)
            end

            local label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("LEFT", 4, 5)
            label:SetWidth(LIST_W - 22)
            label:SetJustifyH("LEFT")
            label:SetText("|cFF00FF00" .. name .. "|r")

            local sub = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            sub:SetPoint("LEFT", 4, -10)
            sub:SetText("|cFF888888[Custom] " .. pts .. "|r")

            -- Left-click to load, right-click to delete (confirmation dialog)
            btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
            btn:SetScript("OnClick", function(self, button)
                if button == "RightButton" then
                    StaticPopupDialogs["HEKILI_TV_DELETE_BUILD"] = {
                        text = "Confirm delete build \"%s\"?",
                        button1 = "Confirm",
                        button2 = "Cancel",
                        OnAccept = function()
                            DeleteBuild(name)
                            Hekili:Print("|cFFFFFF00Build \"" .. name .. "\" deleted.|r")
                            if currentBuildName == name then
                                currentBuildName = nil
                                currentIsPreset = false
                            end
                            RefreshBuildList()
                        end,
                        timeout = 0,
                        whileDead = true,
                        hideOnEscape = true,
                    }
                    StaticPopup_Show("HEKILI_TV_DELETE_BUILD", name)
                else
                    isSimMode = true
                    currentBuildName = name
                    currentIsPreset = false
                    LoadBuild(name)
                    RefreshUI()
                end
            end)

            btn:SetScript("OnEnter", function(self)
                if currentBuildName ~= name then
                    self:SetBackdropColor(0.15, 0.2, 0.15, 0.8)
                end
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:AddLine(name, 1, 1, 1)
                GameTooltip:AddLine(pts, 0.7, 0.7, 0.7)
                GameTooltip:AddLine("Left-click: Load build", 0, 1, 0)
                GameTooltip:AddLine("Right-click: Delete build", 1, 0.3, 0.3)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave", function(self)
                if currentBuildName ~= name then
                    self:SetBackdropColor(0.1, 0.1, 0.15, 0.6)
                end
                GameTooltip:Hide()
            end)

            table.insert(f.buildButtons, btn)
            yOff = yOff + btnH + btnGap
        end
    end

    -- Update scroll area height
    f.scrollChild:SetHeight(max(1, yOff))
end

-- ============================================================
-- UI refresh
-- ============================================================
RefreshUI = function()
    local f = viewerFrame
    if not f or not f:IsShown() then return end

    -- Class info
    local _, className = UnitClass("player")
    local classColor = RAID_CLASS_COLORS[className] or {r=1, g=1, b=1}
    local localizedClass = UnitClass("player")
    f.classInfo:SetText(format("|cFF%02x%02x%02x%s|r  Level %d",
        classColor.r * 255, classColor.g * 255, classColor.b * 255,
        localizedClass, UnitLevel("player")))

    local totalUsed = GetTotalPoints()
    local remaining = simTotalAvail - totalUsed

    -- Mode label
    if isSimMode then
        if currentBuildName then
            local tag = currentIsPreset and "|cFF00CCFF[Preset]|r" or "|cFF00FF00[Custom]|r"
            f.modeText:SetText("|cFF00FFFF[Sim Mode]|r " .. tag .. " |cFFFFFF00" .. currentBuildName .. "|r")
        else
            f.modeText:SetText("|cFF00FFFF[Sim Mode]|r Unsaved")
        end
        f.pointsInfo:SetText("|cFFFFFFFFUsed: |cFFFFFF00" .. totalUsed .. "|r / " .. simTotalAvail ..
            "  |cFFFFFFFFRemaining: " .. (remaining > 0 and "|cFF00FF00" or "|cFFFF0000") .. remaining .. "|r")
    else
        f.modeText:SetText("|cFF00FF00[Current Talents]|r")
        f.pointsInfo:SetText("|cFFFFFFFFTotal Talent Points: |cFFFFFF00" .. totalUsed .. "|r / " .. simTotalAvail)
    end

    -- Auto-fill save name box
    if f.saveNameBox then
        if currentBuildName then
            f.saveNameBox:SetText(currentBuildName)
            if f.saveNameBox.placeholder then f.saveNameBox.placeholder:Hide() end
        else
            f.saveNameBox:SetText("")
            if f.saveNameBox.placeholder then f.saveNameBox.placeholder:Show() end
        end
    end

    -- Refresh 3 trees
    for tab = 1, 3 do
        local tabPts = GetPointsInTab(tab)
        local tabMax = 0
        if simData[tab] then
            for _, t in pairs(simData[tab]) do
                tabMax = tabMax + (t.maxRank or 0)
            end
        end

        local hdrColor = tabPts > 0 and "|cFF00FF00" or "|cFF888888"
        f.treeHeaders[tab]:SetText(hdrColor .. (simTabNames[tab] or "Unknown") .. "|r  " ..
            "|cFFFFFF00" .. tabPts .. "|r / " .. tabMax)

        -- Refresh icons
        for idx, btn in pairs(f.talentBtns[tab]) do
            btn:Hide()
        end

        if simData[tab] then
            local panel = f.treePanels[tab]
            for i, t in pairs(simData[tab]) do
                local btn = f.talentBtns[tab][i]
                if not btn then
                    btn = CreateTalentButton(panel, tab, i)
                    f.talentBtns[tab][i] = btn
                end

                local x = ICON_GAP + (t.column - 1) * (ICON_SIZE + ICON_GAP) + 8
                local y = -(30 + (t.tier - 1) * (ICON_SIZE + ICON_GAP) + 5)
                btn:ClearAllPoints()
                btn:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)

                btn.icon:SetTexture(t.icon)
                btn.rankText:SetText(t.rank .. "/" .. t.maxRank)
                btn.talentTab = tab
                btn.talentIndex = i

                if t.rank == t.maxRank and t.maxRank > 0 then
                    btn.rankText:SetTextColor(CLR_MAX[1], CLR_MAX[2], CLR_MAX[3])
                    btn.border:SetBackdropBorderColor(CLR_MAX[1], CLR_MAX[2], CLR_MAX[3], 1)
                    btn.icon:SetDesaturated(false)
                    btn.desatOverlay:Hide()
                    btn.border:Show()
                elseif t.rank > 0 then
                    btn.rankText:SetTextColor(CLR_PART[1], CLR_PART[2], CLR_PART[3])
                    btn.border:SetBackdropBorderColor(CLR_PART[1], CLR_PART[2], CLR_PART[3], 1)
                    btn.icon:SetDesaturated(false)
                    btn.desatOverlay:Hide()
                    btn.border:Show()
                else
                    btn.rankText:SetTextColor(CLR_ZERO[1], CLR_ZERO[2], CLR_ZERO[3])
                    btn.icon:SetDesaturated(true)
                    btn.desatOverlay:Show()
                    btn.border:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.6)
                    btn.border:Show()
                end

                btn:Show()
            end
        end
    end

    -- Refresh right side build list
    RefreshBuildList()
end

-- ============================================================
-- Create talent button
-- ============================================================
function CreateTalentButton(parent, tab, index)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ICON_SIZE, ICON_SIZE)

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    btn.icon = icon

    -- 1px border (ElvUI style)
    local border = CreateFrame("Frame", nil, btn, "BackdropTemplate")
    border:SetPoint("TOPLEFT", -1, 1)
    border:SetPoint("BOTTOMRIGHT", 1, -1)
    border:SetBackdrop({
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
    })
    border:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    btn.border = border

    local rankBg = btn:CreateTexture(nil, "OVERLAY")
    rankBg:SetPoint("BOTTOMRIGHT", 2, -2)
    rankBg:SetSize(24, 14)
    rankBg:SetColorTexture(0, 0, 0, 0.8)
    btn.rankBg = rankBg

    local rankText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rankText:SetPoint("CENTER", rankBg, "CENTER", 0, 0)
    btn.rankText = rankText
    SetUIFont(rankText, 11, "OUTLINE")

    local desatOverlay = btn:CreateTexture(nil, "OVERLAY", nil, 1)
    desatOverlay:SetAllPoints(icon)
    desatOverlay:SetColorTexture(0, 0, 0, 0.5)
    btn.desatOverlay = desatOverlay

    -- Mouse tooltip
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if not isSimMode and self.talentTab and self.talentIndex then
            GameTooltip:SetTalent(self.talentTab, self.talentIndex)
        else
            local t = simData[self.talentTab] and simData[self.talentTab][self.talentIndex]
            if t then
                GameTooltip:AddLine(t.name, 1, 1, 1)
                GameTooltip:AddLine(format("Rank: %d / %d", t.rank, t.maxRank), CLR_PART[1], CLR_PART[2], CLR_PART[3])
                GameTooltip:AddLine(format("Tier: %d", t.tier), 0.7, 0.7, 0.7)
                if isSimMode then
                    if CanAddPoint(self.talentTab, self.talentIndex) then
                        GameTooltip:AddLine("Left-click: Add point", 0, 1, 0)
                    end
                    if CanRemovePoint(self.talentTab, self.talentIndex) then
                        GameTooltip:AddLine("Right-click: Remove point", 1, 0.3, 0.3)
                    end
                end
            end
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- Left-click to add point
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn:SetScript("OnClick", function(self, button)
        if not isSimMode then return end
        if button == "LeftButton" then
            if CanAddPoint(self.talentTab, self.talentIndex) then
                local t = simData[self.talentTab][self.talentIndex]
                t.rank = t.rank + 1
                simPoints[self.talentTab] = GetPointsInTab(self.talentTab)
                RefreshUI()
            end
        elseif button == "RightButton" then
            if CanRemovePoint(self.talentTab, self.talentIndex) then
                local t = simData[self.talentTab][self.talentIndex]
                t.rank = t.rank - 1
                simPoints[self.talentTab] = GetPointsInTab(self.talentTab)
                RefreshUI()
            end
        end
    end)

    return btn
end

-- ============================================================
-- Create main frame
-- ============================================================
local function CreateViewer()
    if viewerFrame then return viewerFrame end

    local f = CreateFrame("Frame", "HekiliTalentViewer", UIParent, "BackdropTemplate")
    f:SetSize(FRAME_W, FRAME_H)
    f:SetPoint("CENTER")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    f:SetBackdropColor(0.08, 0.08, 0.08, 0.95)

    -- Title
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -8)
    title:SetText("|cFF00FF00Hekili|r Talent Simulator")

    -- Close button
    local closeBtn = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -3, -3)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    -- Second row: class info + mode
    local classInfo = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    classInfo:SetPoint("TOPLEFT", 12, -28)
    f.classInfo = classInfo

    local modeText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    modeText:SetPoint("TOP", 0, -28)
    f.modeText = modeText

    local pointsInfo = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    pointsInfo:SetPoint("TOPRIGHT", -40, -28)
    f.pointsInfo = pointsInfo

    -- 3 talent trees
    f.treePanels = {}
    f.treeHeaders = {}
    f.talentBtns = {}

    for tab = 1, 3 do
        local panel = CreateFrame("Frame", nil, f, "BackdropTemplate")
        local xOff = TREE_PAD + (tab - 1) * (TREE_W + TREE_PAD / 2)
        panel:SetPoint("TOPLEFT", xOff, -(HEADER_H))
        panel:SetSize(TREE_W, MAX_ROWS * (ICON_SIZE + ICON_GAP) + 68)
        panel:SetBackdrop({
            bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 12,
            insets = { left = 2, right = 2, top = 2, bottom = 2 }
        })
        panel:SetBackdropColor(0.05, 0.05, 0.05, 0.7)
        f.treePanels[tab] = panel

        local header = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        header:SetPoint("TOP", 0, -5)
        f.treeHeaders[tab] = header

        f.talentBtns[tab] = {}

        -- "Apply" button at the bottom of each tree
        local treeApplyBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
        treeApplyBtn:SetSize(TREE_W - 16, 20)
        treeApplyBtn:SetPoint("BOTTOM", panel, "BOTTOM", 0, 4)
        treeApplyBtn:SetText("|cFFFF8800Apply Talents|r")
        treeApplyBtn.tabIndex = tab
        treeApplyBtn:SetScript("OnClick", function(self)
            if not isSimMode then
                Hekili:Print("|cFFFF0000Please load a simulation build first!|r")
                return
            end

            local myTab = self.tabIndex
            local applied = 0

            -- Build target rank
            local targets = {}
            if simData[myTab] then
                for k, sim in pairs(simData[myTab]) do
                    targets[tonumber(k) or k] = sim.rank or 0
                end
            end

            -- Read talent structure from game API and sort
            local numTalents = GetNumTalents(myTab)
            local sorted = {}
            for i = 1, numTalents do
                local name, _, tier, column = GetTalentInfo(myTab, i)
                local target = targets[i] or 0
                if name and tier and target > 0 then
                    table.insert(sorted, { index = i, tier = tier, column = column, simRank = target })
                end
            end
            table.sort(sorted, function(a, b)
                if a.tier ~= b.tier then return a.tier < b.tier end
                return a.column < b.column
            end)

            -- Loop multiple rounds to spend all points in this tree
            for round = 1, 80 do
                local allDone = true
                for _, entry in ipairs(sorted) do
                    local _, _, _, _, curRank = GetTalentInfo(myTab, entry.index)
                    if entry.simRank > (curRank or 0) then
                        allDone = false
                        break
                    end
                end
                if allDone then break end

                for _, entry in ipairs(sorted) do
                    local _, _, _, _, curRank = GetTalentInfo(myTab, entry.index)
                    curRank = curRank or 0
                    if entry.simRank > curRank then
                        LearnTalent(myTab, entry.index)
                        local _, _, _, _, newRank = GetTalentInfo(myTab, entry.index)
                        if (newRank or 0) > curRank then
                            applied = applied + 1
                        end
                    end
                end
            end

            if applied > 0 then
                Hekili:Print(format("|cFF00FF00[%s] Successfully applied %d talent points!|r", simTabNames[myTab] or "?", applied))
            else
                Hekili:Print(format("|cFFFFFF00[%s] Already matches build, no action needed.|r", simTabNames[myTab] or "?")
            end
        end)
        f.treePanels[tab].applyBtn = treeApplyBtn
    end

    -- ============================================================
    -- Right side build list panel
    -- ============================================================
    local listPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    listPanel:SetPoint("TOPLEFT", f, "TOPLEFT", TREE_W * 3 + TREE_PAD * 3.5 + 10, -(HEADER_H))
    listPanel:SetSize(LIST_W, MAX_ROWS * (ICON_SIZE + ICON_GAP) + 68)
    listPanel:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 2, right = 2, top = 2, bottom = 2 }
    })
    listPanel:SetBackdropColor(0.05, 0.05, 0.05, 0.8)

    local listTitle = listPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    listTitle:SetPoint("TOP", 0, -5)
    listTitle:SetText("|cFFFFFF00Saved Builds|r")

    -- Scroll area
    local scrollFrame = CreateFrame("ScrollFrame", nil, listPanel)
    scrollFrame:SetPoint("TOPLEFT", 5, -22)
    scrollFrame:SetPoint("BOTTOMRIGHT", -5, 5)

    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetSize(LIST_W - 10, 1)
    scrollFrame:SetScrollChild(scrollChild)

    -- Mouse wheel scrolling
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = max(0, scrollChild:GetHeight() - self:GetHeight())
        local newScroll = current - delta * 25
        newScroll = max(0, min(newScroll, maxScroll))
        self:SetVerticalScroll(newScroll)
    end)

    f.listPanel = listPanel
    f.scrollFrame = scrollFrame
    f.scrollChild = scrollChild
    f.buildButtons = {}

    -- ============================================================
    -- Bottom button bar
    -- ============================================================
    local btnY = -FRAME_H + 30
    local btnW, btnH = 90, 22
    local btnGap = 6

    -- View current talents
    local btnCurrent = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnCurrent:SetSize(btnW, btnH)
    btnCurrent:SetPoint("BOTTOMLEFT", 10, 8)
    btnCurrent:SetText("Current Talents")
    btnCurrent:SetScript("OnClick", function()
        isSimMode = false
        currentBuildName = nil
        currentIsPreset = false
        ReadCurrentTalents()
        RefreshUI()
    end)

    -- New simulation
    local btnNew = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnNew:SetSize(btnW, btnH)
    btnNew:SetPoint("LEFT", btnCurrent, "RIGHT", btnGap, 0)
    btnNew:SetText("New Sim")
    btnNew:SetScript("OnClick", function()
        isSimMode = true
        currentBuildName = nil
        currentIsPreset = false
        -- Read current talent structure but reset all points to zero
        ReadCurrentTalents()
        for tab = 1, 3 do
            if simData[tab] then
                for _, t in pairs(simData[tab]) do
                    t.rank = 0
                end
            end
            simPoints[tab] = 0
        end
        RefreshUI()
    end)

    -- Simulate from current talents
    local btnFromCurrent = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnFromCurrent:SetSize(btnW + 20, btnH)
    btnFromCurrent:SetPoint("LEFT", btnNew, "RIGHT", btnGap, 0)
    btnFromCurrent:SetText("Sim from Current")
    btnFromCurrent:SetScript("OnClick", function()
        isSimMode = true
        currentBuildName = nil
        currentIsPreset = false
        ReadCurrentTalents()
        RefreshUI()
    end)

    -- Reset points
    local btnReset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnReset:SetSize(btnW - 10, btnH)
    btnReset:SetPoint("LEFT", btnFromCurrent, "RIGHT", btnGap, 0)
    btnReset:SetText("Reset")
    btnReset:SetScript("OnClick", function()
        if not isSimMode then return end
        for tab = 1, 3 do
            if simData[tab] then
                for _, t in pairs(simData[tab]) do
                    t.rank = 0
                end
            end
            simPoints[tab] = 0
        end
        RefreshUI()
    end)

    -- Save build name input box (manually created, WotLK compatible)
    local saveNameBox = CreateFrame("EditBox", "HekiliTVSaveNameBox", f, "BackdropTemplate")
    saveNameBox:SetSize(130, 22)
    saveNameBox:SetPoint("LEFT", btnReset, "RIGHT", btnGap + 10, 0)
    saveNameBox:SetAutoFocus(false)
    saveNameBox:SetMaxLetters(32)
    saveNameBox:SetFontObject(ChatFontNormal)
    saveNameBox:SetText("")
    saveNameBox:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 }
    })
    saveNameBox:SetBackdropColor(0, 0, 0, 0.8)
    saveNameBox:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    saveNameBox:SetTextInsets(5, 5, 2, 2)
    saveNameBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    saveNameBox:SetScript("OnEnterPressed", function(self)
        self:ClearFocus()
        -- Press Enter to save directly
        if isSimMode then
            local name = self:GetText():trim()
            if name ~= "" then
                SaveBuild(name, simData, simPoints, simTabNames)
                currentBuildName = name
                currentIsPreset = false
                Hekili:Print("|cFF00FF00Talent build \"" .. name .. "\" saved!|r")
                RefreshUI()
            end
        end
    end)
    f.saveNameBox = saveNameBox

    -- Input box placeholder text
    local placeholder = saveNameBox:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    placeholder:SetPoint("LEFT", 6, 0)
    placeholder:SetText("Enter build name...")
    saveNameBox.placeholder = placeholder
    saveNameBox:SetScript("OnTextChanged", function(self)
        if self:GetText() == "" then
            self.placeholder:Show()
        else
            self.placeholder:Hide()
        end
    end)
    saveNameBox:SetScript("OnEditFocusGained", function(self)
        self:SetBackdropBorderColor(0.6, 0.8, 1, 1)
    end)
    saveNameBox:SetScript("OnEditFocusLost", function(self)
        self:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    end)

    -- Save build button
    local btnSave = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnSave:SetSize(btnW - 10, btnH)
    btnSave:SetPoint("LEFT", saveNameBox, "RIGHT", btnGap, 0)
    btnSave:SetText("|cFF00FF00Save|r")
    btnSave:SetScript("OnClick", function()
        if not isSimMode then
            Hekili:Print("|cFFFF0000Please enter simulation mode before saving!|r")
            return
        end
        local name = saveNameBox:GetText():trim()
        if name == "" then
            Hekili:Print("|cFFFF0000Please enter a build name!|r")
            return
        end
        SaveBuild(name, simData, simPoints, simTabNames)
        currentBuildName = name
        currentIsPreset = false
        Hekili:Print("|cFF00FF00Talent build \"" .. name .. "\" saved!|r")
        RefreshUI()
    end)

    -- Export button
    local btnExport = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnExport:SetSize(btnW - 10, btnH)
    btnExport:SetPoint("LEFT", btnSave, "RIGHT", btnGap, 0)
    btnExport:SetText("|cFFFF8800Export|r")
    btnExport:SetScript("OnClick", function()
        if not isSimMode then
            Hekili:Print("|cFFFF0000Please enter simulation mode first!|r")
            return
        end
        local buildName = saveNameBox:GetText():trim()
        if buildName == "" then buildName = "Unnamed Build" end

        -- Collect talent data
        local talentsForExport = {}
        for tab = 1, 3 do
            talentsForExport[tab] = {}
            if simData[tab] then
                for i, t in pairs(simData[tab]) do
                    if t and t.rank and t.rank > 0 then
                        talentsForExport[tab][tonumber(i) or i] = {
                            name = t.name or "?",
                            rank = t.rank,
                            maxRank = t.maxRank or 0,
                        }
                    end
                end
            end
        end

        local pts = { GetPointsInTab(1), GetPointsInTab(2), GetPointsInTab(3) }
        local exportStr = ExportToString(buildName, simTabNames, pts, talentsForExport)

        -- Display in a copyable text box
        if not viewerFrame.exportFrame then
            local ef = CreateFrame("Frame", nil, viewerFrame, "BackdropTemplate")
            ef:SetSize(500, 200)
            ef:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            ef:SetFrameStrata("TOOLTIP")
            ef:SetMovable(true)
            ef:EnableMouse(true)
            ef:RegisterForDrag("LeftButton")
            ef:SetScript("OnDragStart", ef.StartMoving)
            ef:SetScript("OnDragStop", ef.StopMovingOrSizing)
            ef:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 }
            })
            ef:SetBackdropColor(0.08, 0.08, 0.08, 0.98)

            local efTitle = ef:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            efTitle:SetPoint("TOP", 0, -8)
            efTitle:SetText("|cFFFF8800Export Talent String|r")

            local efHint = ef:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            efHint:SetPoint("TOP", 0, -26)
            efHint:SetText("|cFFAAAAAACtrl+A Select All, Ctrl+C Copy, share with others to import|r")

            local scrollFrame = CreateFrame("ScrollFrame", nil, ef)
            scrollFrame:SetPoint("TOPLEFT", 10, -42)
            scrollFrame:SetPoint("BOTTOMRIGHT", -10, 35)

            local editBox = CreateFrame("EditBox", nil, scrollFrame)
            editBox:SetMultiLine(true)
            editBox:SetAutoFocus(false)
            editBox:SetFontObject(GameFontHighlightSmall)
            editBox:SetWidth(476)
            editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); ef:Hide() end)
            scrollFrame:SetScrollChild(editBox)

            scrollFrame:EnableMouseWheel(true)
            scrollFrame:SetScript("OnMouseWheel", function(self, delta)
                local cur = self:GetVerticalScroll()
                local maxS = max(0, editBox:GetHeight() - self:GetHeight())
                local newS = max(0, min(cur - delta * 30, maxS))
                self:SetVerticalScroll(newS)
            end)

            ef.editBox = editBox

            local efClose = CreateFrame("Button", nil, ef, "UIPanelButtonTemplate")
            efClose:SetSize(80, 22)
            efClose:SetPoint("BOTTOM", 0, 8)
            efClose:SetText("Close")
            efClose:SetScript("OnClick", function() ef:Hide() end)

            viewerFrame.exportFrame = ef
        end

        local ef = viewerFrame.exportFrame
        ef.editBox:SetText(exportStr)
        if not ef._skinApplied then
            ef._skinApplied = true
            SkinFrame(ef)
            for _, child in pairs({ef:GetChildren()}) do
                if child.GetObjectType and child:GetObjectType() == "Button" then
                    SkinButton(child)
                end
            end
        end
        ef:Show()
        ef.editBox:SetFocus()
        ef.editBox:HighlightText()
    end)

    -- Import button
    local btnImport = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    btnImport:SetSize(btnW - 10, btnH)
    btnImport:SetPoint("LEFT", btnExport, "RIGHT", btnGap, 0)
    btnImport:SetText("|cFF00CCFF Import|r")
    btnImport:SetScript("OnClick", function()
        if not viewerFrame.importFrame then
            local imf = CreateFrame("Frame", nil, viewerFrame, "BackdropTemplate")
            imf:SetSize(500, 200)
            imf:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
            imf:SetFrameStrata("TOOLTIP")
            imf:SetMovable(true)
            imf:EnableMouse(true)
            imf:RegisterForDrag("LeftButton")
            imf:SetScript("OnDragStart", imf.StartMoving)
            imf:SetScript("OnDragStop", imf.StopMovingOrSizing)
            imf:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 16,
                insets = { left = 4, right = 4, top = 4, bottom = 4 }
            })
            imf:SetBackdropColor(0.08, 0.08, 0.08, 0.98)

            local imfTitle = imf:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
            imfTitle:SetPoint("TOP", 0, -8)
            imfTitle:SetText("|cFF00CCFF Import Talent String|r")

            local imfHint = imf:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            imfHint:SetPoint("TOP", 0, -26)
            imfHint:SetText("|cFFAAAAAAAAPaste a talent string starting with !HKT!, then click Import|r")

            local scrollFrame = CreateFrame("ScrollFrame", nil, imf)
            scrollFrame:SetPoint("TOPLEFT", 10, -42)
            scrollFrame:SetPoint("BOTTOMRIGHT", -10, 35)

            local editBox = CreateFrame("EditBox", nil, scrollFrame)
            editBox:SetMultiLine(true)
            editBox:SetAutoFocus(false)
            editBox:SetFontObject(GameFontHighlightSmall)
            editBox:SetWidth(476)
            editBox:SetScript("OnEscapePressed", function(self) self:ClearFocus(); imf:Hide() end)
            scrollFrame:SetScrollChild(editBox)

            scrollFrame:EnableMouseWheel(true)
            scrollFrame:SetScript("OnMouseWheel", function(self, delta)
                local cur = self:GetVerticalScroll()
                local maxS = max(0, editBox:GetHeight() - self:GetHeight())
                local newS = max(0, min(cur - delta * 30, maxS))
                self:SetVerticalScroll(newS)
            end)

            imf.editBox = editBox

            local imfImport = CreateFrame("Button", nil, imf, "UIPanelButtonTemplate")
            imfImport:SetSize(80, 22)
            imfImport:SetPoint("BOTTOMLEFT", 100, 8)
            imfImport:SetText("|cFF00FF00Import|r")
            imfImport:SetScript("OnClick", function()
                local text = imf.editBox:GetText()
                if not text or text:trim() == "" then
                    Hekili:Print("|cFFFF0000Please paste a talent string!|r")
                    return
                end

                local parsed = ImportFromString(text)
                if not parsed then
                    Hekili:Print("|cFFFF0000Failed to parse! Please confirm it is a valid !HKT! string.|r")
                    return
                end

                local totalParsed = 0
                for tab = 1, 3 do
                    for _ in pairs(parsed.talents[tab]) do
                        totalParsed = totalParsed + 1
                    end
                end

                if totalParsed == 0 then
                    Hekili:Print("|cFFFF0000No talent data found in string!|r")
                    return
                end

                isSimMode = true
                ReadCurrentTalents()

                for tab = 1, 3 do
                    simTabNames[tab] = parsed.tabNames[tab] or simTabNames[tab]
                    if simData[tab] then
                        for _, t in pairs(simData[tab]) do
                            t.rank = 0
                        end
                    end
                    for idx, p in pairs(parsed.talents[tab]) do
                        if simData[tab] and simData[tab][idx] then
                            simData[tab][idx].rank = p.rank or 0
                        end
                    end
                    simPoints[tab] = GetPointsInTab(tab)
                end

                SaveBuild(parsed.name, simData, simPoints, simTabNames)
                currentBuildName = parsed.name
                currentIsPreset = false

                Hekili:Print(format("|cFF00FF00Successfully imported build \"%s\" (%d/%d/%d), %d talents total!|r",
                    parsed.name, parsed.points[1], parsed.points[2], parsed.points[3], totalParsed))

                imf:Hide()
                RefreshUI()
            end)

            local imfClose = CreateFrame("Button", nil, imf, "UIPanelButtonTemplate")
            imfClose:SetSize(80, 22)
            imfClose:SetPoint("BOTTOMRIGHT", -100, 8)
            imfClose:SetText("Cancel")
            imfClose:SetScript("OnClick", function() imf:Hide() end)

            viewerFrame.importFrame = imf
        end

        local imf = viewerFrame.importFrame
        imf.editBox:SetText("")
        if not imf._skinApplied then
            imf._skinApplied = true
            SkinFrame(imf)
            for _, child in pairs({imf:GetChildren()}) do
                if child.GetObjectType and child:GetObjectType() == "Button" then
                    SkinButton(child)
                end
            end
        end
        imf:Show()
        imf.editBox:SetFocus()
    end)

    f.btnCurrent = btnCurrent
    f.btnNew = btnNew
    f.btnFromCurrent = btnFromCurrent
    f.btnReset = btnReset
    f.btnSave = btnSave
    f.btnExport = btnExport
    f.btnImport = btnImport

    f:Hide()
    viewerFrame = f
    return f
end

-- ============================================================
-- Public API
-- ============================================================
function Hekili:ToggleTalentViewer()
    local f = CreateViewer()

    -- NDui / ElvUI skin takeover (executed once on first open)
    if not f._skinApplied then
        f._skinApplied = true

        -- Main frame
        SkinFrame(f)

        -- Talent tree panel (manual backdrop, avoid SetTemplate inset squeezing icons)
        for tab = 1, 3 do
            if f.treePanels and f.treePanels[tab] then
                SkinTreePanel(f.treePanels[tab])
                SkinButton(f.treePanels[tab].applyBtn)
            end
        end

        -- List panel
        SkinFrame(f.listPanel)
        SkinEditBox(f.saveNameBox)

        -- Bottom button skin
        local bottomBtns = { f.btnCurrent, f.btnNew, f.btnFromCurrent, f.btnReset, f.btnSave, f.btnExport, f.btnImport }
        for _, btn in ipairs(bottomBtns) do
            SkinButton(btn)
        end

        -- Adapt font
        if f.classInfo then SetUIFont(f.classInfo, 12) end
        if f.modeText then SetUIFont(f.modeText, 12) end
        if f.pointsInfo then SetUIFont(f.pointsInfo, 12) end

        for tab = 1, 3 do
            if f.treeHeaders and f.treeHeaders[tab] then
                SetUIFont(f.treeHeaders[tab], 12)
            end
        end

        for _, btn in ipairs(bottomBtns) do
            if btn then
                local text = btn:GetFontString()
                if text then SetUIFont(text, 12) end
            end
        end

        for tab = 1, 3 do
            if f.treePanels and f.treePanels[tab] and f.treePanels[tab].applyBtn then
                local text = f.treePanels[tab].applyBtn:GetFontString()
                if text then SetUIFont(text, 12) end
            end
        end

        if f.saveNameBox then
            local _, font = DetectUI()
            if font then
                pcall(f.saveNameBox.SetFont, f.saveNameBox, font, 12, "")
                if f.saveNameBox.placeholder then SetUIFont(f.saveNameBox.placeholder, 11) end
            end
        end

        -- Close button skin
        for _, child in pairs({f:GetChildren()}) do
            if child.GetObjectType and child:GetObjectType() == "Button" then
                if child.GetNormalTexture and child:GetNormalTexture() then
                    local tex = child:GetNormalTexture():GetTexture()
                    if tex and tostring(tex):find("CloseButton") then
                        SkinClose(child)
                    end
                end
            end
        end
    end

    if f:IsShown() then
        f:Hide()
    else
        isSimMode = false
        currentBuildName = nil
        currentIsPreset = false
        ReadCurrentTalents()
        f:Show()
        RefreshUI()
    end
end

function Hekili:OpenTalentSimulator()
    local f = CreateViewer()
    isSimMode = true
    currentBuildName = nil
    currentIsPreset = false
    ReadCurrentTalents()
    f:Show()
    RefreshUI()
end

function Hekili:RefreshTalentViewer()
    if viewerFrame and viewerFrame:IsShown() and not isSimMode then
        ReadCurrentTalents()
        RefreshUI()
    end
end

-- Slash commands
SLASH_HEKILITV1 = "/hekilitv"
SLASH_HEKILITV2 = "/htv"
SlashCmdList["HEKILITV"] = function(msg)
    msg = (msg or ""):trim():lower()
    if msg == "sim" or msg == "new" then
        Hekili:OpenTalentSimulator()
    else
        Hekili:ToggleTalentViewer()
    end
end
