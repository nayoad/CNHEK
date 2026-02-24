-- Targets.lua
-- June 2014

local addon, ns = ...
local Hekili = _G[addon]

local class = Hekili.Class
local state = Hekili.State

local FindUnitBuffByID = ns.FindUnitBuffByID
local FindUnitDebuffByID = ns.FindUnitDebuffByID

local UnitGetTotalAbsorbs = _G.UnitGetTotalAbsorbs or function() return 0 end

local targetCount = 0
local targets = {}

local myTargetCount = 0
local myTargets = {}

local addMissingTargets = true
local counted = {}

local formatKey = ns.formatKey
local orderedPairs = ns.orderedPairs
local FeignEvent, RegisterEvent = ns.FeignEvent, ns.RegisterEvent

local format = string.format
local insert, remove, wipe = table.insert, table.remove, table.wipe

local unitIDs = { "target", "targettarget", "focus", "focustarget", "boss1", "boss2", "boss3", "boss4", "boss5", "arena1", "arena2", "arena3", "arena4", "arena5" }

local npGUIDs = {}
local npUnits = {}

Hekili.unitIDs = unitIDs
Hekili.npGUIDs = npGUIDs
Hekili.npUnits = npUnits


function Hekili:GetNameplateUnitForGUID( id )
    return npUnits[ id ]
end

function Hekili:GetGUIDForNameplateUnit( unit )
    return npGUIDs[ unit ]
end

function Hekili:GetUnitByGUID( id )
    for _, unit in ipairs( unitIDs ) do
        if UnitGUID( unit ) == id then return unit end
    end
end

function Hekili:GetUnitByName( name )
    for _, unit in ipairs( unitIDs ) do
        if UnitName( unit ) == name then return unit end
    end

    for unit in pairs( npUnits ) do
        if UnitName( unit ) == name then return unit end
    end
end


do
    -- Pet-Based Target Detection
    -- Requires a class-appropriate pet ability on the player's action bars.
    -- ** Not the pet's action bar. **
    local petAction = 0
    local petSlot = 0

    local myClass = UnitClassBase( "player" )

    local petSpells = {
        HUNTER = {
            [288962] = true,
            [16827]  = true,
            [17253]  = true,
            [49966]  = true,

            count    = 4
        },

        WARLOCK = {
            [6360]  = true, -- Whiplash (Succubus)
            [54049] = true, -- Shadow Bite (Felhunter)
            [7814]  = true, -- Lash of Pain (Succubus)
            [30213] = true, -- Legion Strike (Felguard)

            count   = 4
        }
    }

    function Hekili:GetPetBasedTargetSpells()
        return petSpells[ myClass ]
    end

    function Hekili:CanUsePetBasedTargetDetection()
        return petSpells[ myClass ] ~= nil
    end

    function Hekili:HasPetBasedTargetSpell()
        return petSlot > 0
    end

    function Hekili:GetPetBasedTargetSpell()
        return petAction > 0 and petAction or nil
    end

    function Hekili:PetBasedTargetDetectionIsReady( skipRange )
        if petSlot == 0 then return false, "Pet action not found in player action bars." end
        if not UnitExists( "pet" ) then return false, "No active pet." end
        if UnitIsDead( "pet" ) then return false, "Pet is dead." end

        -- If we have a target and the target is out of our pet's range, don't use pet detection.
        if not skipRange and UnitExists( "target" ) and not IsActionInRange( petSlot ) then return false, "Player has target and player's target not in range of pet." end
        return true
    end

    function Hekili:SetupPetBasedTargetDetection()
        petAction = 0
        petSlot = 0

        if not self:CanUsePetBasedTargetDetection() then return end

        local spells = petSpells[ myClass ]
        local success = false

        for i = 1, 120 do
            local slotType, spell = GetActionInfo( i )

            if slotType and spell and spells[ spell ] then
                petAction = spell
                petSlot = i
                return true
            end
        end

        return success
    end

    function Hekili:TargetIsNearPet( unit )
        return GetCachedPetRange( unit )
    end

    function Hekili:DumpPetBasedTargetInfo()
        self:Print( petAction, petSlot )
    end
end


-- Excluding enemy by NPC ID (as string).  This keeps the enemy from being counted if they are not your target.
-- = true           Always Exclude
-- = number < 0     Exclude if debuff ID abs( number ) is active on unit.
-- = number > 0     Exclude if buff ID number is active on unit.
local enemyExclusions = {
    [23775]  = true,      -- Head of the Horseman
    [120651] = true,      -- Explosives
    [156227] = true,      -- Neferset Denizen
    [160966] = true,      -- Thing from Beyond?
    [161895] = true,      -- Thing from Beyond?
    [157452] = true,      -- Nightmare Antigen in Carapace
    [158041] = 310126,    -- N'Zoth with Psychic Shell
    [164698] = true,      -- Tor'ghast Junk
    [177117] = 355790,    -- Ner'zhul: Orb of Torment (Protected by Eternal Torment)
    [176581] = true,      -- Painsmith:  Spiked Ball
    [186150] = true,      -- Soul Fragment (Gavel of the First Arbiter)
    [185685] = true,      -- Season 3 Relics
    [185680] = true,      -- Season 3 Relics
    [185683] = true,      -- Season 3 Relics
    [183501] = 367573,    -- Xy'mox: Genesis Bulwark
    [166969] = true,      -- Frieda
    [166970] = true,      -- Stavros
    [166971] = true,      -- Niklaus
    [168113] = 329606,    -- Grashaal (when shielded)
    [168112] = 329636,    -- Kaal (when shielded)
--------------------Added-by-Fengxue-20250705-----
--------------------Ulduar------------------
    [33121] = true,       -- Ignis the Furnace Master - Iron Construct
    [33453] = true,       -- Iron Rune Sentinel
    [33388] = true,       -- Dark Rune Guardian
    [33846] = true,       -- Dark Rune Watcher
    [33344] = true,       -- Razorscale - Devouring Flame Turret
    [33768] = true,       -- Kologarn - Stone Grip
    [34034] = true,       -- Auriaya - Sanctum Sentry
    [33052] = true,       -- Algalon - Living Constellation
    [33089] = true,       -- Algalon - Dark Matter
    [34097] = true,       -- Algalon - Unleashed Dark Matter
---------------------Icecrown Citadel----------------
    [38508] = true,       -- Deathbringer Saurfang - Blood Beast
    [36899] = true,       -- Rotface - Big Ooze
    [36897] = true,       -- Rotface - Small Ooze
    [37697] = true,       -- Professor Putricide - Unstable Ooze
    [37562] = true,       -- Professor Putricide - Ooze Cloud
    [36678] = true,       -- Professor Putricide
    [37972] = true,       -- Blood Council - Prince Keleseth
    [37973] = true,       -- Blood Council - Prince Taldaram
    [37970] = true,       -- Blood Council - Prince Valanar
    [38454] = true,       -- Blood Council - Kinetic Bomb
    [38369] = true,       -- Blood Council - Empowered Blood Orb
    [36980] = true,       -- Sindragosa - Frost Tomb
    [37689] = true,       -- Lich King - Shambling Horror
    [37695] = true,       -- Lich King - Ghoul Minion
}

local FindExclusionAuraByID

RegisterEvent( "NAME_PLATE_UNIT_ADDED", function( event, unit )
    if UnitIsFriend( "player", unit ) then return end

    local id = UnitGUID( unit )
    if not id then return end
    npGUIDs[unit] = id
    npUnits[id]   = unit
end )

RegisterEvent( "NAME_PLATE_UNIT_REMOVED", function( event, unit )
    if UnitIsFriend( "player", unit ) then return end

    local id = npGUIDs[ unit ] or UnitGUID( unit )
    npGUIDs[unit] = nil

    if npUnits[id] and npUnits[id] == unit then
        npUnits[id] = nil
    end
end )

RegisterEvent( "UNIT_FLAGS", function( event, unit )
    if UnitIsFriend( "player", unit ) then
        local id = UnitGUID( unit )
        if id then
            ns.eliminateUnit( id, true )
            npUnits[id] = nil
        end

        npGUIDs[unit] = nil
    end
end )


local RC = LibStub("LibRangeCheck-2.0")

local lastCount = 1
local lastStationary = 1

local guidRanges = {}

-- Performance optimization cache system
local cachedSafeAreaStatus = nil
local lastSafeAreaCheck = 0
local SAFE_AREA_CHECK_INTERVAL = 2 -- Check safe area every 2 seconds

local petRangeCache = {}
local lastPetRangeUpdate = 0
local PET_RANGE_CACHE_DURATION = 0.5 -- 500ms cache

local validUnitCache = {}
local lastValidityCheck = {}
local VALIDITY_CACHE_DURATION = 0.1 -- 100ms cache

local rangeCheckBatch = {}
local targetDataPool = {}

-- Additional optimization variables
local nameplateScanInterval = 0.15 -- 150ms scan interval
local lastNameplateScan = 0
local rangeCheckScheduled = false
local lastCleanup = 0
local maxTargetsPerFrame = 12 -- Maximum targets processed per frame

-- 训练假人缓存
local trainingDummyCache = {}
local knownDummyIDs = {
    [31144] = true, [31146] = true, [32541] = true, [32542] = true, [32543] = true,
    [46647] = true, [2673] = true, [5652] = true, [12426] = true, [17578] = true,
}

-- 职业特定优化配置
local classOptimizations = {
    HUNTER = { preferPetRange = true, petRangeWeight = 0.8, nameplateRange = 40 },
    WARLOCK = { preferPetRange = true, petRangeWeight = 0.7, nameplateRange = 40 },
    MAGE = { preferPetRange = false, nameplateRange = 40, useSpellRange = true },
    PRIEST = { preferPetRange = false, nameplateRange = 40, useSpellRange = true },
    DRUID = { preferPetRange = false, nameplateRange = 40, useSpellRange = true },
}


-- Chromie Time impacts phasing as well.
local chromieTime = false

do
    local function UpdateChromieTime()
        chromieTime = C_PlayerInfo.IsPlayerInChromieTime()
    end

    local function ChromieCheck( self, event, login, reload )
        if event ~= "PLAYER_ENTERING_WORLD" or login or reload then
            chromieTime = C_PlayerInfo.IsPlayerInChromieTime()
            C_Timer.After( 2, UpdateChromieTime )
        end
    end

    if not Hekili.IsDragonflight() and not Hekili.IsWrath() then
        RegisterEvent( "CHROMIE_TIME_OPEN", ChromieCheck )
        RegisterEvent( "CHROMIE_TIME_CLOSE", ChromieCheck )
        RegisterEvent( "PLAYER_ENTERING_WORLD", ChromieCheck )
    end
end


-- War Mode
local warmode = false

do
    local function CheckWarMode( event, login, reload )
        if event ~= "PLAYER_ENTERING_WORLD" or login or reload then
            warmode = C_PvP.IsWarModeDesired()
        end
    end

    if not Hekili.IsWrath() then
        RegisterEvent( "UI_INFO_MESSAGE", CheckWarMode )
        RegisterEvent( "PLAYER_ENTERING_WORLD", CheckWarMode )
    end
end

-- 优化的安全区域检查函数
local function GetCachedSafeAreaStatus()
    local now = GetTime()
    if not cachedSafeAreaStatus or (now - lastSafeAreaCheck) > SAFE_AREA_CHECK_INTERVAL then
        if IsInInstance() then
            cachedSafeAreaStatus = false
        elseif IsResting() then
            cachedSafeAreaStatus = true
        else
            local pvpType = GetZonePVPInfo()
            if pvpType == "sanctuary" then
                cachedSafeAreaStatus = true
            else
                local mapID = C_Map.GetBestMapForUnit("player")
                if mapID then
                    local cityMaps = {
                        [84] = true, [85] = true, [87] = true, [88] = true, [89] = true, [90] = true,
                        [103] = true, [110] = true, [111] = true, [125] = true, [627] = true, [1670] = true,
                    }
                    cachedSafeAreaStatus = cityMaps[mapID] or false
                else
                    cachedSafeAreaStatus = false
                end
            end
        end
        lastSafeAreaCheck = now
    end
    return cachedSafeAreaStatus
end

-- 优化的宠物范围检测
local function GetCachedPetRange(unit)
    local now = GetTime()
    local guid = UnitGUID(unit)
    
    if not guid then return false end
    
    local cached = petRangeCache[guid]
    -- 根据目标移动状态调整缓存时间
    local cacheTime = GetUnitSpeed(unit) > 0 and 0.3 or 0.8
    
    if cached and (now - cached.time) < cacheTime then
        return cached.inRange
    end
    
    -- 批量检测调度
    if not rangeCheckScheduled then
        rangeCheckScheduled = true
        C_Timer.After(0.05, function()
            BatchPetRangeCheck()
            rangeCheckScheduled = false
        end)
    end
    
    -- 返回缓存值或默认值
    return cached and cached.inRange or IsActionInRange(petSlot, unit)
end

-- 批量宠物范围检测
local function BatchPetRangeCheck()
    if petSlot == 0 then return end
    
    local processed = 0
    for unit, guid in pairs(npGUIDs) do
        if processed >= maxTargetsPerFrame then break end
        
        if UnitExists(unit) and not UnitIsDead(unit) then
            local inRange = IsActionInRange(petSlot, unit)
            petRangeCache[guid] = {
                inRange = inRange,
                time = GetTime()
            }
            processed = processed + 1
        end
    end
end

-- 批量范围检测优化
local function BatchRangeCheck()
    local now = GetTime()
    
    -- 检查是否需要扫描
    if (now - lastNameplateScan) < nameplateScanInterval then
        return false
    end
    
    lastNameplateScan = now
    wipe(rangeCheckBatch)
    
    local processed = 0
    for unit, guid in pairs(npGUIDs) do
        if processed >= maxTargetsPerFrame then
            -- 下一帧继续处理
            C_Timer.After(0, BatchRangeCheck)
            break
        end
        
        if UnitExists(unit) and not UnitIsDead(unit) then
            table.insert(rangeCheckBatch, {unit = unit, guid = guid})
            processed = processed + 1
        end
    end
    
    -- 批量获取范围
    for i, data in ipairs(rangeCheckBatch) do
        local _, range = RC:GetRange(data.unit)
        guidRanges[data.guid] = range
    end
    
    return true
end

-- 优化的单位有效性检查
local npcIdPattern = "(%d+)-%x-$"
local function IsValidCombatUnit(unit, guid, now)
    local lastCheck = lastValidityCheck[guid]
    if lastCheck and (now - lastCheck) < VALIDITY_CACHE_DURATION then
        return validUnitCache[guid]
    end
    
    local isValid = UnitExists(unit) and 
                   not UnitIsDead(unit) and 
                   UnitCanAttack("player", unit) and 
                   UnitInPhase(unit) and 
                   UnitHealth(unit) > 0 and 
                   (UnitIsPVP("player") or not UnitIsPlayer(unit))
    
    validUnitCache[guid] = isValid
    lastValidityCheck[guid] = now
    
    return isValid
end

-- 智能目标过滤
local function SmartTargetFilter(unit, guid, spec, checkPets, checkPlates)
    -- 快速距离预过滤
    local roughDistance = select(2, RC:GetRange(unit))
    if roughDistance and roughDistance > (spec.nameplateRange + 15) then
        return false, "too_far"
    end
    
    local npcid = tonumber(guid:match(npcIdPattern))
    local excluded = enemyExclusions[npcid]
    
    -- 检查排除条件
    if excluded and type(excluded) == "number" then
        excluded = FindExclusionAuraByID(unit, excluded)
    end
    
    if excluded then
        return false, "excluded"
    end
    
    -- 职业特定检查
    local classOpt = classOptimizations[myClass]
    if classOpt and classOpt.preferPetRange and checkPets then
        return GetCachedPetRange(unit), "pet_range"
    end
    
    -- 标准范围检查
    if checkPlates then
        local range = guidRanges[guid] or roughDistance
        return not range or range <= spec.nameplateRange, "nameplate_range"
    end
    
    return true, "valid"
end

-- 训练假人检测优化
local function IsTrainingDummy(unit, npcid)
    if trainingDummyCache[npcid] ~= nil then
        return trainingDummyCache[npcid]
    end
    
    local isDummy = false
    
    -- Check known training dummy NPC IDs
    if knownDummyIDs[npcid] then
        isDummy = true
    else
        -- Check unit name
        local unitName = UnitName(unit) or ""
        if unitName:find("训练") or unitName:find("假人") or 
           unitName:find("Training") or unitName:find("Dummy") or 
           unitName:find("Target") then
            isDummy = true
        end
    end
    
    trainingDummyCache[npcid] = isDummy
    return isDummy
end

-- 缓存清理函数
local function CleanupCaches()
    local now = GetTime()
    
    -- 清理宠物范围缓存
    for guid, data in pairs(petRangeCache) do
        if (now - data.time) > PET_RANGE_CACHE_DURATION * 3 then
            petRangeCache[guid] = nil
        end
    end
    
    -- 清理有效性缓存
    for guid, time in pairs(lastValidityCheck) do
        if (now - time) > 5 then
            lastValidityCheck[guid] = nil
            validUnitCache[guid] = nil
        end
    end
    
    -- 清理过期的GUID范围数据
    for guid, range in pairs(guidRanges) do
        if not npUnits[guid] and not counted[guid] then
            guidRanges[guid] = nil
        end
    end
    
    -- 清理训练假人缓存（定期清理避免内存泄漏）
    if (now - lastCleanup) > 30 then
        local cacheSize = 0
        for _ in pairs(trainingDummyCache) do
            cacheSize = cacheSize + 1
        end
        
        if cacheSize > 100 then
            wipe(trainingDummyCache)
        end
        lastCleanup = now
    end
end


local UnitInPhase = _G.UnitInPhase or function( unit )
    local reason = UnitPhaseReason( unit )
    local wm = not IsInInstance() and warmode

    if reason == 3 and chromieTime then return true end
    if reason == 2 and wm then return true end
    if reason == nil then return true end

    return false
end


do
    function ns.iterateTargets()
        return next, counted, nil
    end

    FindExclusionAuraByID = function( unit, spellID )
        if spellID < 0 then
            return FindUnitDebuffByID( unit, -1 * spellID ) ~= nil
        end
        return FindUnitBuffByID( unit, spellID ) ~= nil
    end

    -- New Nameplate Proximity System
    function ns.getNumberTargets( forceUpdate )
        if not forceUpdate then
            return lastCount, lastStationary
        end

        local now = GetTime()

        if now - Hekili.lastAudit > 1 then
            -- Kick start the damage-based target detection filter.
            Hekili.AuditorStalled = true
            ns.Audit()
        end

        local showNPs = GetCVar( "nameplateShowEnemies" ) == "1"

        wipe( counted )

        local count, stationary = 0, 0

        Hekili.TargetDebug = ""

        local spec = state.spec.id
        spec = spec and rawget( Hekili.DB.profile.specs, spec )

        if spec then
            local checkPets = showNPs and spec.petbased and Hekili:PetBasedTargetDetectionIsReady()
            local checkPlates = showNPs and spec.nameplates

            -- 预计算常用状态以提高性能
            local inSafeArea = GetCachedSafeAreaStatus()
            local playerInCombat = UnitAffectingCombat("player")
            local shouldCheckCombat = not inSafeArea and playerInCombat
            
            if checkPets or checkPlates then
                -- 批量范围检测优化
                if checkPlates then
                    BatchRangeCheck()
                end
                
                local processed = 0
                for unit, guid in pairs( npGUIDs ) do
                    -- 分帧处理限制
                    if processed >= maxTargetsPerFrame then
                        break
                    end
                    
                    if IsValidCombatUnit(unit, guid, now) then
                        local combatCheck = true
                        
                        -- 优化的战斗状态检查
                        if shouldCheckCombat then
                            local unitInCombat = UnitAffectingCombat(unit)
                            local threatStatus = UnitThreatSituation("player", unit)
                            combatCheck = unitInCombat or (threatStatus and threatStatus > 0)
                        end
                        
                        if combatCheck then
                            local isValid, reason = SmartTargetFilter(unit, guid, spec, checkPets, checkPlates)
                            
                            -- 始终计算玩家目标
                            if UnitIsUnit( unit, "target" ) then 
                                isValid = true 
                                reason = "player_target"
                            end

                            if isValid then
                                local rate, n = Hekili:GetTTD( unit )
                                count = count + 1
                                counted[ guid ] = true

                                local moving = GetUnitSpeed( unit ) > 0

                                if not moving then
                                    stationary = stationary + 1
                                end

                                local range = guidRanges[ guid ] or 0
                                Hekili.TargetDebug = format( "%s    %-12s - %2d - %s - %.2f - %d - %s %s [%s]\n", 
                                    Hekili.TargetDebug, unit, range, guid, rate or 0, n or 0, 
                                    unit and UnitName( unit ) or "Unknown", 
                                    ( moving and "(moving)" or "" ), reason or "unknown" )
                            end
                        end
                        processed = processed + 1
                    end

                    counted[ guid ] = counted[ guid ] or false
                end

                -- 处理标准单位ID
                for _, unit in ipairs( unitIDs ) do
                    local guid = UnitGUID( unit )

                    if guid and counted[ guid ] == nil then
                        if IsValidCombatUnit(unit, guid, now) then
                            local combatCheck = true
                            
                            if shouldCheckCombat then
                                local unitInCombat = UnitAffectingCombat(unit)
                                local threatStatus = UnitThreatSituation("player", unit)
                                combatCheck = unitInCombat or (threatStatus and threatStatus > 0)
                            end
                            
                            if combatCheck then
                                local isValid, reason = SmartTargetFilter(unit, guid, spec, checkPets, checkPlates)
                                
                                -- 对于非姓名板单位，需要手动获取范围
                                if checkPlates and not guidRanges[guid] then
                                    local _, range = RC:GetRange( unit )
                                    guidRanges[ guid ] = range
                                end

                                -- 始终计算玩家目标
                                if UnitIsUnit( unit, "target" ) then 
                                    isValid = true 
                                    reason = "player_target"
                                end

                                if isValid then
                                    local rate, n = Hekili:GetTTD(unit)
                                    count = count + 1
                                    counted[ guid ] = true

                                    local moving = GetUnitSpeed( unit ) > 0

                                    if not moving then
                                        stationary = stationary + 1
                                    end

                                    local range = guidRanges[ guid ] or 0
                                    Hekili.TargetDebug = format( "%s    %-12s - %2d - %s - %.2f - %d - %s %s [%s]\n", 
                                        Hekili.TargetDebug, unit, range, guid, rate or 0, n or 0, 
                                        unit and UnitName( unit ) or "Unknown", 
                                        ( moving and "(moving)" or "" ), reason or "unknown" )
                                end
                            end

                            counted[ guid ] = counted[ guid ] or false
                        end
                    end
                end
            end
        end

        -- 伤害检测系统 - 用于检测受到伤害的目标（包括木桩等）
        if not spec or spec.damage or ( not spec.nameplates and not spec.petbased ) or not showNPs then
            local db = spec and (spec.myTargetsOnly and myTargets or targets) or targets

            for guid, seen in pairs(db) do
                if counted[ guid ] == nil then
                    local npcid = tonumber(guid:match(npcIdPattern))
                    local excluded = enemyExclusions[ npcid ]

                    local unit

                    -- If our table has a number, unit is ruled out only if the buff is present.
                    if excluded and type( excluded ) == "number" then
                        unit = Hekili:GetUnitByGUID( guid )

                        if unit then
                            if UnitIsUnit( unit, "target" ) then
                                excluded = false
                            else
                                if excluded and type( excluded ) == "number" then
                                    excluded = FindExclusionAuraByID( unit, excluded )
                                end
                            end
                            excluded = false
                        end
                    end

                    -- 对于远程职业，使用更大的检测范围
                    local damageRange = spec.damageRange or 40
                    if spec.nameplates and spec.damage then
                        -- 如果同时启用姓名板和伤害检测，使用姓名板范围作为最大范围
                        damageRange = math.max(spec.nameplateRange or 40, spec.damageRange or 40)
                    end

                    if not excluded and ( damageRange == 0 or ( not guidRanges[ guid ] or guidRanges[ guid ] <= damageRange ) ) then
                        count = count + 1
                        counted[ guid ] = true

                        local moving = unit and GetUnitSpeed( unit ) > 0

                        if not moving then
                            stationary = stationary + 1
                        end

                        Hekili.TargetDebug = format("%s    %-12s - %2d - %s %s\n", Hekili.TargetDebug, "dmg", guidRanges[ guid ] or 0, guid, ( moving and "(moving)" or "" ) )
                    else
                        counted[ guid ] = false
                    end
                end
            end
        end

        local targetGUID = UnitGUID( "target" )
        if targetGUID then
            if counted[ targetGUID ] == nil and UnitExists("target") and not UnitIsDead("target") and UnitCanAttack("player", "target") and UnitInPhase("target") and (UnitIsPVP("player") or not UnitIsPlayer("target")) then
                count = count + 1
                counted[ targetGUID ] = true

                local moving = GetUnitSpeed( "target" ) > 0

                if not moving then
                    stationary = stationary + 1
                end

                Hekili.TargetDebug = format("%s    %-12s - %2d - %s %s\n", Hekili.TargetDebug, "target", 0, targetGUID, ( moving and "(moving)" or "" ) )
            else
                counted[ targetGUID ] = false
            end
        end

        count = max( 1, count )

        -- 定期清理缓存
        if now - lastPetRangeUpdate > 1 then
            CleanupCaches()
            lastPetRangeUpdate = now
        end

        if count ~= lastCount or stationary ~= lastStationary then
            lastCount = count
            lastStationary = stationary
            if Hekili:GetToggleState( "mode" ) == "reactive" then HekiliDisplayAOE:UpdateAlpha() end
            Hekili:ForceUpdate( "TARGET_COUNT_CHANGED" )
        end

        return count, stationary
    end

    Hekili:ProfileCPU( "GetNumberTargets", ns.getNumberTargets )

-- 性能监控和调试函数
function Hekili:GetTargetOptimizationStats()
    local stats = {
        cacheHits = {
            safeArea = cachedSafeAreaStatus ~= nil and 1 or 0,
            petRange = 0,
            validity = 0
        },
        cacheSize = {
            petRange = 0,
            validity = 0,
            guidRanges = 0,
            trainingDummy = 0
        },
        lastCleanup = lastPetRangeUpdate,
        performance = {
            nameplateScanInterval = nameplateScanInterval,
            maxTargetsPerFrame = maxTargetsPerFrame,
            lastNameplateScan = lastNameplateScan
        }
    }
    
    for _ in pairs(petRangeCache) do
        stats.cacheSize.petRange = stats.cacheSize.petRange + 1
    end
    
    for _ in pairs(validUnitCache) do
        stats.cacheSize.validity = stats.cacheSize.validity + 1
    end
    
    for _ in pairs(guidRanges) do
        stats.cacheSize.guidRanges = stats.cacheSize.guidRanges + 1
    end
    
    for _ in pairs(trainingDummyCache) do
        stats.cacheSize.trainingDummy = stats.cacheSize.trainingDummy + 1
    end
    
    return stats
end

function Hekili:ClearTargetCaches()
    wipe(petRangeCache)
    wipe(validUnitCache)
    wipe(lastValidityCheck)
    wipe(trainingDummyCache)
    cachedSafeAreaStatus = nil
    lastSafeAreaCheck = 0
    lastNameplateScan = 0
    Hekili:Print("Target detection cache cleared")
end

-- 性能调优函数
function Hekili:SetTargetOptimizationLevel(level)
    if level == "performance" then
        nameplateScanInterval = 0.1
        maxTargetsPerFrame = 15
        PET_RANGE_CACHE_DURATION = 0.3
    elseif level == "balanced" then
        nameplateScanInterval = 0.15
        maxTargetsPerFrame = 12
        PET_RANGE_CACHE_DURATION = 0.5
    elseif level == "quality" then
        nameplateScanInterval = 0.2
        maxTargetsPerFrame = 8
        PET_RANGE_CACHE_DURATION = 0.8
    end
    
    Hekili:Print("Target detection optimization level set to: " .. level)
end
end

function Hekili:GetNumTargets( forceUpdate )
    local spec = state.spec.id
    spec = spec and rawget( Hekili.DB.profile.specs, spec )
    
    -- 对于启用了姓名板和伤害检测的远程职业，使用混合检测
    if spec and spec.nameplates and spec.damage then
        return ns.getRemoteTargets( forceUpdate )
    end
    
    -- 其他情况使用原有逻辑
    return ns.getNumberTargets( forceUpdate )
end


function ns.dumpNameplateInfo()
    return counted
end

-- 专门用于远程职业的木桩和姓名板检测函数
function ns.getTrainingDummyTargets()
    local count = 0
    local showNPs = GetCVar("nameplateShowEnemies") == "1"
    
    if not showNPs then
        return 0
    end
    
    local spec = state.spec.id
    spec = spec and rawget(Hekili.DB.profile.specs, spec)
    local maxRange = spec and spec.nameplateRange or 40
    
    -- 检查姓名板中的训练假人和敌对目标
    for unit, guid in pairs(npGUIDs) do
        if UnitExists(unit) and not UnitIsDead(unit) and UnitCanAttack("player", unit) and UnitHealth(unit) > 0 then
            local npcid = tonumber(guid:match(npcIdPattern))
            
            -- 优化的训练假人检测
            local isTrainingDummy = IsTrainingDummy(unit, npcid)
            
            -- 如果是训练假人或者普通敌对目标，都计入
            if isTrainingDummy or UnitCanAttack("player", unit) then
                local _, range = RC:GetRange(unit)
                -- 使用配置的范围检测
                if not range or range <= maxRange then
                    count = count + 1
                end
            end
        end
    end
    
    return count
end

-- 为远程职业提供混合检测模式
function ns.getRemoteTargets(forceUpdate)
    if not forceUpdate then
        return lastCount, lastStationary
    end
    
    local spec = state.spec.id
    spec = spec and rawget(Hekili.DB.profile.specs, spec)
    
    if not spec then
        return ns.getNumberTargets(forceUpdate)
    end
    
    -- 如果不是远程职业或者没有启用姓名板，使用原有逻辑
    if not spec.nameplates or not spec.damage then
        return ns.getNumberTargets(forceUpdate)
    end
    
    local nameplateCount = 0
    local damageCount = 0
    local stationary = 0
    
    -- 首先通过姓名板检测（包括木桩）
    nameplateCount = ns.getTrainingDummyTargets()
    
    -- 然后通过伤害检测补充
    local db = spec and (spec.myTargetsOnly and myTargets or targets) or targets
    local damageCounted = {}
    
    for guid, seen in pairs(db) do
        if not counted[guid] then
            local npcid = tonumber(guid:match(npcIdPattern))
            local excluded = enemyExclusions[npcid]
            if not excluded then
                local range = guidRanges[guid]
                local maxRange = math.max(spec.nameplateRange or 40, spec.damageRange or 40)
                if not range or range <= maxRange then
                    damageCount = damageCount + 1
                    damageCounted[guid] = true
                end
            end
        end
    end
    
    -- 取两种检测方式的最大值
    local totalCount = math.max(nameplateCount, damageCount)
    
    -- 更新缓存
    if totalCount ~= lastCount then
        lastCount = totalCount
        lastStationary = stationary
        if Hekili:GetToggleState("mode") == "reactive" then 
            HekiliDisplayAOE:UpdateAlpha() 
        end
        Hekili:ForceUpdate("TARGET_COUNT_CHANGED")
    end
    
    return totalCount, stationary
end


function ns.updateTarget(id, time, mine)
    local spec = rawget( Hekili.DB.profile.specs, state.spec.id )
    if not spec or not spec.damage then return end

    if id == state.GUID then
        return
    end

    if time then
        if not targets[id] then
            targetCount = targetCount + 1
            targets[id] = time
            ns.updatedTargetCount = true
        else
            targets[id] = time
        end

        if mine then
            if not myTargets[id] then
                myTargetCount = myTargetCount + 1
                myTargets[id] = time
                ns.updatedTargetCount = true
            else
                myTargets[id] = time
            end
        end
    else
        if targets[id] then
            targetCount = max(0, targetCount - 1)
            targets[id] = nil
        end

        if myTargets[id] then
            myTargetCount = max(0, myTargetCount - 1)
            myTargets[id] = nil
        end

        ns.updatedTargetCount = true
    end
end

Hekili:ProfileCPU( "UpdateTarget", ns.updateTargets )

ns.reportTargets = function()
    for k, v in pairs(targets) do
        Hekili:Print("Saw " .. k .. " exactly " .. GetTime() - v .. " seconds ago.")
    end
end

ns.numTargets = function()
    return targetCount > 0 and targetCount or 1
end
ns.numMyTargets = function()
    return myTargetCount > 0 and myTargetCount or 1
end
ns.isTarget = function(id)
    return targets[id] ~= nil
end
ns.isMyTarget = function(id)
    return myTargets[id] ~= nil
end

-- MINIONS
local minions = {}

ns.updateMinion = function(id, time)
    minions[id] = time
end

ns.isMinion = function(id)
    return minions[id] ~= nil or UnitGUID("pet") == id
end

function Hekili:HasMinionID(id)
    for k, v in pairs(minions) do
        local npcID = tonumber(k:match("%-(%d+)%-[0-9A-F]+$"))

        if npcID == id and v > state.now then
            return true, v
        end
    end
end

function Hekili:DumpMinions()
    local o = ""

    for k, v in orderedPairs(minions) do
        o = o .. k .. " " .. tostring(v) .. "\n"
    end

    return o
end

local debuffs = {}
local debuffCount = {}
local debuffMods = {}

function ns.saveDebuffModifier( id, val )
    debuffMods[ id ] = val
end

ns.wipeDebuffs = function()
    for k, _ in pairs(debuffs) do
        table.wipe(debuffs[k])
        debuffCount[k] = 0
    end
end

ns.actorHasDebuff = function( target, spell )
    return ( debuffs[ spell ] and debuffs[ spell ][ target ] ~= nil ) or false
end

ns.trackDebuff = function(spell, target, time, application)
    -- Convert spellID to key, if we have one.
    if class.auras[ spell ] then spell = class.auras[ spell ].key end

    debuffs[ spell ] = debuffs[ spell ] or {}
    debuffCount[spell] = debuffCount[spell] or 0

    if not time then
        if debuffs[spell][target] then
            -- Remove it.
            debuffs[spell][target] = nil
            debuffCount[spell] = max( 0, debuffCount[spell] - 1 )
        end
    else
        if not debuffs[spell][target] then
            debuffs[spell][target] = {}
            debuffCount[spell] = debuffCount[spell] + 1
        end

        local debuff = debuffs[spell][target]

        debuff.last_seen = time
        debuff.applied = debuff.applied or time

        if application then
            debuff.pmod = debuffMods[spell]
        else
            debuff.pmod = debuff.pmod or 1
        end
    end
end

Hekili:ProfileCPU( "TrackDebuff", ns.trackDebuff )


ns.GetDebuffApplicationTime = function( spell, target )
    if class.auras[ spell ] then spell = class.auras[ spell ].key end

    if not debuffCount[ spell ] or debuffCount[ spell ] == 0 then return 0 end
    return debuffs[ spell ] and debuffs[ spell ][ target ] and ( debuffs[ spell ][ target ].applied or debuffs[ spell ][ target ].last_seen ) or 0
end

function ns.getModifier( id, target )
    if class.auras[ spell ] then spell = class.auras[ spell ].key end

    local debuff = debuffs[ id ]
    if not debuff then
        return 1
    end

    local app = debuff[target]
    if not app then
        return 1
    end

    return app.pmod or 1
end

ns.numDebuffs = function(spell)
    if class.auras[ spell ] then spell = class.auras[ spell ].key end

    return debuffCount[spell] or 0
end

ns.compositeDebuffCount = function( ... )
    local n = 0

    for i = 1, select("#", ...) do
        local debuff = select( i, ... )

        if class.auras[ debuff ] then debuff = class.auras[ debuff ].key end
        debuff = debuff and debuffs[ debuff ]

        if debuff then
            for unit in pairs( debuff ) do
                n = n + 1
            end
        end
    end

    return n
end

ns.conditionalDebuffCount = function(req1, req2, ...)
    local n = 0

    req1 = class.auras[ req1 ] and class.auras[ req1 ].key
    req2 = class.auras[ req2 ] and class.auras[ req2 ].key

    for i = 1, select( "#", ... ) do
        local debuff = select( i, ... )
        debuff = class.auras[ debuff ] and class.auras[ debuff ].key
        debuff = debuff and debuffs[debuff]

        if debuff then
            for unit in pairs( debuff ) do
                local reqExp =
                    (req1 and debuffs[req1] and debuffs[req1][unit]) or (req2 and debuffs[req2] and debuffs[req2][unit])
                if reqExp then
                    n = n + 1
                end
            end
        end
    end

    return n
end

do
    local counted = {}

    -- Useful for "count number of enemies with at least one of these debuffs applied".
    -- i.e., poisoned_enemies for Assassination Rogue.

    ns.countUnitsWithDebuffs = function( ... )
        wipe( counted )

        local n = 0

        for i = 1, select("#", ...) do
            local debuff = select( i, ... )
            debuff = class.auras[ debuff ] and class.auras[ debuff ].key
            debuff = debuff and debuffs[ debuff ]

            if debuff then
                for unit in pairs( debuff ) do
                    if not counted[ unit ] then
                        n = n + 1
                        counted[ unit ] = true
                    end
                end
            end
        end

        return n
    end
end

ns.isWatchedDebuff = function(spell)
    if class.auras[ spell ] then spell = class.auras[ spell ].key end
    return debuffs[spell] ~= nil
end

    ns.eliminateUnit = function(id, force)
        ns.updateMinion(id)
        ns.updateTarget(id)

        guidRanges[id] = nil
        
        -- 清理所有相关缓存
        petRangeCache[id] = nil
        validUnitCache[id] = nil
        lastValidityCheck[id] = nil

        if force then
            for k, v in pairs( debuffs ) do
                if v[ id ] then ns.trackDebuff( k, id ) end
            end
        end

        ns.callHook( "UNIT_ELIMINATED", id )
    end

Hekili:ProfileCPU( "EliminateUnit", ns.eliminateUnit )

local incomingDamage = {}
local incomingHealing = {}

ns.storeDamage = function(time, damage, physical)
    if damage and damage > 0 then
        table.insert(incomingDamage, {t = time, damage = damage, physical = physical})
    end
end

Hekili:ProfileCPU( "StoreDamage", ns.storeDamage )

ns.storeHealing = function(time, healing)
    table.insert(incomingHealing, {t = time, healing = healing})
end

Hekili:ProfileCPU( "StoreHealing", ns.storeHealing )

ns.damageInLast = function(t, physical)
    local dmg = 0
    local start = GetTime() - min(t, 15)

    for k, v in pairs(incomingDamage) do
        if v.t > start and (physical == nil or v.physical == physical) then
            dmg = dmg + v.damage
        end
    end

    return dmg
end

function ns.healingInLast(t)
    local heal = 0
    local start = GetTime() - min(t, 15)

    for k, v in pairs(incomingHealing) do
        if v.t > start then
            heal = heal + v.healing
        end
    end

    return heal
end

-- Auditor should clean things up for us.
Hekili.lastAudit = GetTime()
Hekili.auditInterval = 0

ns.Audit = function( special )
    if not special and not Hekili.DB.profile.enabled or not Hekili:IsValidSpec() then
        C_Timer.After( 1, ns.Audit )
        return
    end

    local now = GetTime()
    local spec = state.spec.id and rawget( Hekili.DB.profile.specs, state.spec.id )
    local nodmg = spec and ( spec.damage == false ) or false
    local grace = spec and spec.damageExpiration or 6

    Hekili.auditInterval = now - Hekili.lastAudit
    Hekili.lastAudit = now

    for aura, targets in pairs( debuffs ) do
        local a = class.auras[ aura ]
        local window = a and a.duration or grace
        local friendly = a and ( a.friendly or a.dot == "buff" ) or false
        local expires = not ( a and a.no_ticks or friendly )

        for unit, entry in pairs( targets ) do
            -- NYI: Check for dot vs. debuff, since debuffs won't 'tick'
            if expires and now - entry.last_seen > window then
                ns.trackDebuff( aura, unit )
            elseif special == "combatExit" and not friendly then
                -- Hekili:Error( format( "Auditor removed an aura %d from %s after exiting combat.", aura, unit ) )
                ns.trackDebuff( aura, unit )
            end
        end
    end

    for whom, when in pairs( targets ) do
        if nodmg or now - when > grace then
            ns.eliminateUnit( whom )
        end
    end

    local cutoff = now - 15
    for i = #incomingDamage, 1, -1 do
        local instance = incomingDamage[ i ]

        if instance.t < cutoff then
            table.remove( incomingDamage, i )
        end
    end

    for i = #incomingHealing, 1, -1 do
        local instance = incomingHealing[ i ]

        if instance.t < cutoff then
            table.remove( incomingHealing, i )
        end
    end

    Hekili:ExpireTTDs()
    C_Timer.After( 1, ns.Audit )
end
Hekili:ProfileCPU( "Audit", ns.Audit )


function Hekili:DumpDotInfo( aura )
    if not IsAddOnLoaded( "Blizzard_DebugTools" ) then
        LoadAddOn( "Blizzard_DebugTools" )
    end

    aura = aura and class.auras[ aura ] and class.auras[ aura ].id or aura

    Hekili:Print( "Current DoT Information at " .. GetTime() .. ( aura and ( " for " .. aura ) or "" ) .. ":" )
    DevTools_Dump( aura and debuffs[ aura ] or debuffs )
end

do
    -- New TTD, hopefully more aggressive and accurate than old TTD.
    Hekili.TTD = Hekili.TTD or {}
    local db = Hekili.TTD

    local recycle = {}

    local function EliminateEnemy(guid)
        local enemy = db[guid]
        if not enemy then
            return
        end

        db[guid] = nil
        wipe(enemy)
        insert(recycle, enemy)

        for k, v in pairs( debuffs ) do
            if v[ guid ] then ns.trackDebuff( k, guid ) end
        end
    end


    -- These enemies die (or encounter ends) at a health percentage greater than 0.
    -- In theory, one could also mark certain targets as dying at 1.0 and they'd be considered dead, but I don't know why I'd do that.
    local deathPercent = {
        [162099] = 0.5, -- General Kaal; Sanguine Depths
        [166608] = 0.1, -- Mueh'zala; De Other Side
        [164929] = 0.2, -- Tirnenn Villager; Mists of Tirna Scythe
        [164804] = 0.2, -- Droman Oulfarran; Mists of Tirna Scythe
    }

    local DEFAULT_TTD = 30
    local FOREVER = 300
    local TRIVIAL = 5

    local function UpdateEnemy(guid, healthPct, unit, time)
        local enemy = db[ guid ]
        time = time or GetTime()

        if not enemy then
            -- This is the first time we've seen the enemy.
            enemy = remove(recycle, 1) or {}
            db[guid] = enemy

            enemy.firstSeen = time
            enemy.firstHealth = healthPct
            enemy.lastSeen = time
            enemy.lastHealth = healthPct

            enemy.unit = unit

            enemy.rate = 0
            enemy.n = 0

            local npcid = guid:match( "(%d+)-%x-$" )
            npcid = tonumber( npcid )

            enemy.npcid = npcid
            enemy.deathPercent = npcid and deathPercent[ npcid ] or 0
            enemy.deathTime = ( UnitIsTrivial(unit) and UnitLevel(unit) > -1 ) and TRIVIAL or DEFAULT_TTD
            enemy.excluded = enemyExclusions[ npcid ]
            return
        end

        local difference = enemy.lastHealth - healthPct

        -- We don't recalculate the rate when enemies heal.
        if difference > 0 then
            local elapsed = time - enemy.lastSeen

            -- If this is our first health difference, just store it.
            if enemy.n == 0 then
                enemy.rate = difference / elapsed
                enemy.n = 1
            else
                local samples = min(enemy.n, 9)
                local newRate = enemy.rate * samples + (difference / elapsed)
                enemy.n = samples + 1
                enemy.rate = newRate / enemy.n
            end

            enemy.deathTime = ( healthPct - enemy.deathPercent ) / enemy.rate
        end

        enemy.unit = unit
        enemy.lastHealth = healthPct
        enemy.lastSeen = time
    end

    Hekili:ProfileCPU( "UpdateEnemy", ns.UpdateEnemy )

    local function CheckEnemyExclusion( guid )
        local enemy = db[ guid ]

        if not enemy or enemy.excluded == nil then return end

        -- Player target is always counted.
        if UnitIsUnit( enemy.unit, "target" ) then
            return false
        end

        if type( enemy.excluded ) == "boolean" then
            return enemy.excluded
        end

        if type( enemy.excluded ) == "number" then
            return FindExclusionAuraByID( enemy.unit, enemy.excluded )
        end

        return false
    end

    function Hekili:GetDeathClockByGUID( guid )
        local time, validUnit = 0, false

        local enemy = db[ guid ]

        if enemy then
            time = max( time, enemy.deathTime )
            validUnit = true
        end

        if not validUnit then return FOREVER end

        return time
    end

    function Hekili:GetTTD( unit, isGUID )
        local default = ( isGUID or UnitIsTrivial(unit) and UnitLevel(unit) > -1 ) and TRIVIAL or FOREVER
        local guid = isGUID and unit or UnitExists(unit) and UnitCanAttack("player", unit) and UnitGUID(unit)

        if not guid then
            return default
        end

        local enemy = db[guid]
        if not enemy then
            return default
        end

        -- Don't have enough data to predict yet.
        if enemy.n < 3 or enemy.rate == 0 then
            return default, enemy.n
        end

        local health, healthMax = UnitHealth(unit), UnitHealthMax(unit)
        health = health + UnitGetTotalAbsorbs(unit)
        local healthPct = health / healthMax

        if healthPct == 0 then
            return 1, enemy.n
        end

        return ceil(healthPct / enemy.rate), enemy.n
    end

    Hekili:ProfileCPU( "GetTTD", Hekili.GetTTD )


    function Hekili:GetTimeToPct( unit, percent )
        local default = 0.7 * ( UnitIsTrivial( unit ) and TRIVIAL or FOREVER )
        local guid = UnitExists( unit ) and UnitCanAttack( "player", unit ) and UnitGUID( unit )

        if percent >= 1 then
            percent = percent / 100
        end

        if not guid then return default end

        local enemy = db[ guid ]
        if not enemy then return default end

        local health, healthMax = UnitHealth( unit ), UnitHealthMax( unit )
        local healthPct = health / healthMax

        if healthPct <= percent then return 0, enemy.n end

        health = health + UnitGetTotalAbsorbs( unit )
        healthPct = health / healthMax

        if enemy.n < 3 or enemy.rate == 0 then
            return default, enemy.n
        end

        return ceil( ( healthPct - percent ) / enemy.rate ), enemy.n
    end

    function Hekili:GetTimeToPctByGUID( guid, percent )
        if percent >= 1 then
            percent = percent / 100
        end

        local default = percent * FOREVER

        if not guid then return default end

        local enemy = db[ guid ]
        if not enemy then return default end

        if enemy.n < 3 or enemy.rate == 0 then
            return default, enemy.n
        end

        local healthPct = enemy.lastHealth
        if healthPct <= percent then return FOREVER, enemy.n end

        return ceil( ( healthPct - percent ) / enemy.rate ), enemy.n
    end

    function Hekili:GetGreatestTTD()
        local time, validUnit, now = 0, false, GetTime()

        for k, v in pairs( db ) do
            if not CheckEnemyExclusion( k ) then
                time = max( time, max( 0, v.deathTime ) )
                validUnit = true
            end
        end

        if not validUnit then return state.boss and FOREVER or DEFAULT_TTD end

        return time
    end

    function Hekili:GetGreatestTimeToPct( percent )
        local time, validUnit, now = 0, false, GetTime()

        if percent >= 1 then
            percent = percent / 100
        end

        for k, v in pairs(db) do
            if not CheckEnemyExclusion( k ) and v.lastHealth > percent then
                time = max( time, max( 0, v.deathTime ) )
                validUnit = true
            end
        end

        if not validUnit then return FOREVER end

        return time
    end

    function Hekili:GetLowestTTD()
        local time, validUnit, now = 3600, false, GetTime()

        for k, v in pairs(db) do
            if not CheckEnemyExclusion( k ) then
                time = min( time, max( 0, v.deathTime ) )
                validUnit = true
            end
        end

        if not validUnit then
            return FOREVER
        end

        return time
    end

    function Hekili:GetNumTTDsWithin( x )
        local count, now = 0, GetTime()

        for k, v in pairs(db) do
            if not CheckEnemyExclusion( k ) and max( 0, v.deathTime ) <= x then
                count = count + 1
            end
        end

        return count
    end
    Hekili.GetNumTTDsBefore = Hekili.GetNumTTDsWithin

    function Hekili:GetNumTTDsAfter( x )
        local count = 0
        local now = GetTime()

        for k, v in pairs(db) do
            if CheckEnemyExclusion( k ) and max( 0, v.deathTime ) > x then
                count = count + 1
            end
        end

        return count
    end

    function Hekili:GetNumTargetsAboveHealthPct( amount, inclusive, minTTD )
        local count, now = 0, GetTime()

        amount = amount > 1 and ( amount / 100 ) or amount
        inclusive = inclusive or false
        minTTD = minTTD or 3

        for k, v in pairs(db) do
            if not CheckEnemyExclusion( k ) then
                if inclusive then
                    if v.lastHealth >= amount and max( 0, v.deathTime ) >= minTTD then
                        count = count + 1
                    end
                else
                    if v.lastHealth > amount and max( 0, v.deathTime ) >= minTTD then
                        count = count + 1
                    end
                end
            end
        end

        return count
    end

    function Hekili:GetNumTargetsBelowHealthPct( amount, inclusive, minTTD )
        amount = amount > 1 and ( amount / 100 ) or amount
        inclusive = inclusive or false
        minTTD = minTTD or 3

        local count, now = 0, GetTime()

        amount = amount > 1 and ( amount / 100 ) or amount
        inclusive = inclusive or false
        minTTD = minTTD or 3

        for k, v in pairs(db) do
            if not CheckEnemyExclusion( k ) then
                if inclusive then
                    if v.lastHealth <= amount and max( 0, v.deathTime ) >= minTTD then
                        count = count + 1
                    end
                else
                    if v.lastHealth < amount and max( 0, v.deathTime ) >= minTTD then
                        count = count + 1
                    end
                end
            end
        end

        return count
    end

    local bosses = {}

    function Hekili:GetAddWaveTTD()
        if not UnitExists("boss1") then
            return self:GetGreatestTTD()
        end

        wipe(bosses)

        for i = 1, 5 do
            local unit = "boss" .. i
            local guid = UnitExists(unit) and UnitGUID(unit)
            if guid then
                bosses[ guid ] = true
            end
        end

        local time = 0

        for k, v in pairs(db) do
            if not CheckEnemyExclusion( k ) and not bosses[ k ] then
                time = max( time, v.deathTime )
            end
        end

        return time
    end

    function Hekili:GetTTDInfo()
        local output = "targets:"
        local found = false

        for k, v in pairs( db ) do
            local unit = ( v.unit or "unknown" )
            local excluded = CheckEnemyExclusion( k )

            if v.n > 3 then
                output = output .. format( "\n    %-11s: %4ds [%d] #%6s%s %s", unit, v.deathTime, v.n, v.npcid, excluded and "*" or "", UnitName( v.unit ) or "Unknown" )
            else
                output = output .. format( "\n    %-11s: TBD  [%d] #%6s%s %s", unit, v.n, v.npcid, excluded and "*" or "", UnitName(v.unit) or "Unknown" )
            end
            found = true
        end

        if not found then output = output .. "  none" end

        return output
    end

    function Hekili:ExpireTTDs( all )
        local now = GetTime()

        for k, v in pairs(db) do
            if all or now - v.lastSeen > 10 then
                EliminateEnemy(k)
            end
        end
    end

    local trackedUnits = { "target", "boss1", "boss2", "boss3", "boss4", "boss5", "focus", "arena1", "arena2", "arena3", "arena4", "arena5" }
    local seen = {}

    local UpdateTTDs

    UpdateTTDs = function()
        wipe(seen)

        local now = GetTime()

        -- local updates, deletions = 0, 0

        for i, unit in ipairs(trackedUnits) do
            local guid = UnitGUID(unit)

            if guid and not seen[guid] then
                if db[ guid ] and ( not UnitExists(unit) or UnitIsDead(unit) or ( UnitHealth(unit) <= 1 and UnitHealthMax(unit) > 1 ) ) then
                    EliminateEnemy( guid )
                    -- deletions = deletions + 1
                else
                    local health, healthMax = UnitHealth(unit), UnitHealthMax(unit)
                    health = health + UnitGetTotalAbsorbs(unit)
                    healthMax = max( 1, healthMax )

                    UpdateEnemy(guid, health / healthMax, unit, now)
                    -- updates = updates + 1
                end
                seen[guid] = true
            end
        end

        for unit, guid in pairs(npGUIDs) do
            if db[guid] and (not UnitExists(unit) or UnitIsDead(unit) or not UnitCanAttack("player", unit)) then
                EliminateEnemy(guid)
                -- deletions = deletions + 1
            elseif not seen[guid] then
                local health, healthMax = UnitHealth(unit), UnitHealthMax(unit)
                UpdateEnemy(guid, health / healthMax, unit, now)
                -- updates = updates + 1
            end
            seen[guid] = true
        end

        C_Timer.After( 0.25, UpdateTTDs )
    end
    Hekili:ProfileCPU( "UpdateTTDs", UpdateTTDs )


    C_Timer.After( 0.25, UpdateTTDs )
end
