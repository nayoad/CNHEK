-- TalentBuilds.lua
-- Preset talent builds - maintained by author, distributed with the addon, shared by all users
-- BY Hekili Titan Edition
--
-- Format:
-- Hekili.PresetTalentBuilds["CLASS_NAME"] = {
--     ["Build Name"] = {
--         tabNames = {"Tree1", "Tree2", "Tree3"},
--         points = {tree1points, tree2points, tree3points},
--         desc = "Build description (optional)",
--         talents = {
--             [1] = {  -- Tree 1
--                 [talent_index] = { name="Talent Name", tier=tier, column=col, rank=spent, maxRank=max },
--                 ...
--             },
--             [2] = { ... },  -- Tree 2
--             [3] = { ... },  -- Tree 3
--         },
--     },
-- }
--
-- Note: The icon field does not need to be filled in, it will be automatically read from the game on load
-- tier/column can also be omitted, they will be automatically filled in on load
-- Only talents with rank > 0 need to be filled in; unspecified talents default to rank=0

local addonName, ns = ...
local Hekili = _G[ addonName ]

Hekili.PresetTalentBuilds = {}

-- ============================================================
-- Example: Death Knight (uncomment and modify data to use)
-- ============================================================
--[[ 
Hekili.PresetTalentBuilds["DEATHKNIGHT"] = {
    ["Blood DPS 51/0/20"] = {
        tabNames = {"Blood", "Frost", "Unholy"},
        points = {51, 0, 20},
        desc = "Blood DPS standard build",
        talents = {
            [1] = {  -- Blood
                [1] = { name="Butchery", rank=2, maxRank=2 },
                [2] = { name="Bladed Armor", rank=3, maxRank=3 },
                -- ... continue filling in
            },
            [2] = {},  -- Frost (no points)
            [3] = {  -- Unholy
                [1] = { name="Vicious Strikes", rank=2, maxRank=2 },
                -- ... continue filling in
            },
        },
    },
}
]]

-- ============================================================
-- Add preset talent builds for each class below
-- ============================================================

-- Death Knight
Hekili.PresetTalentBuilds["DEATHKNIGHT"] = {
}

-- Druid
Hekili.PresetTalentBuilds["DRUID"] = {
}

-- Hunter
Hekili.PresetTalentBuilds["HUNTER"] = {
    ["Beast Mastery"] = {
        tabNames = {"Beast Mastery", "Marksmanship", "Survival"},
        points = {52, 11, 8},
        desc = "Beast Mastery",
        talents = {
            [1] = {  -- Beast Mastery
                [2] = { name="Improved Aspect of the Hawk", rank=5, maxRank=5 },
                [4] = { name="Improved Mend Pet", rank=1, maxRank=2 },
                [5] = { name="Frenzy", rank=1, maxRank=1 },
                [6] = { name="Intimidation", rank=1, maxRank=1 },
                [8] = { name="Endurance Training", rank=1, maxRank=5 },
                [9] = { name="Bestial Discipline", rank=2, maxRank=2 },
                [10] = { name="Ferocity", rank=5, maxRank=5 },
                [12] = { name="Unleashed Fury", rank=5, maxRank=5 },
                [13] = { name="Frenzy", rank=4, maxRank=5 },
                [14] = { name="Focused Fire", rank=2, maxRank=2 },
                [15] = { name="Improved Revive Pet", rank=2, maxRank=2 },
                [16] = { name="Catlike Reflexes", rank=2, maxRank=2 },
                [17] = { name="Ferocious Inspiration", rank=3, maxRank=3 },
                [19] = { name="Serpent's Swiftness", rank=5, maxRank=5 },
                [20] = { name="Bestial Wrath", rank=1, maxRank=1 },
                [21] = { name="Hawk Eye", rank=1, maxRank=1 },
                [22] = { name="Cobra Strikes", rank=3, maxRank=3 },
                [23] = { name="Longevity", rank=1, maxRank=1 },
                [24] = { name="Beast Mastery", rank=1, maxRank=1 },
                [25] = { name="Kindred Spirits", rank=1, maxRank=1 },
                [26] = { name="Kindred Spirits", rank=5, maxRank=5 },
            },
            [2] = {  -- Marksmanship
                [4] = { name="Lethal Shots", rank=5, maxRank=5 },
                [9] = { name="Mortal Shots", rank=2, maxRank=5 },
                [15] = { name="Aimed Shot", rank=3, maxRank=3 },
                [18] = { name="Improved Arcane Shot", rank=1, maxRank=2 },
            },
            [3] = {  -- Survival
                [3] = { name="Trap Mastery", rank=3, maxRank=3 },
                [14] = { name="Master Tactician", rank=5, maxRank=5 },
            },
        },
    },
}

-- Mage
Hekili.PresetTalentBuilds["MAGE"] = {
}

-- Paladin
Hekili.PresetTalentBuilds["PALADIN"] = {
}

-- Priest
Hekili.PresetTalentBuilds["PRIEST"] = {
}

-- Rogue
Hekili.PresetTalentBuilds["ROGUE"] = {
}

-- Shaman
Hekili.PresetTalentBuilds["SHAMAN"] = {
}

-- Warlock
Hekili.PresetTalentBuilds["WARLOCK"] = {
}

-- Warrior
Hekili.PresetTalentBuilds["WARRIOR"] = {
}
