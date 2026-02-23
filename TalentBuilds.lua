-- TalentBuilds.lua
-- 预设天赋方案 - 作者维护，随插件分发，所有用户共享
-- BY Hekili 泰坦特供版
--
-- 格式说明:
-- Hekili.PresetTalentBuilds[职业英文名] = {
--     ["方案名称"] = {
--         tabNames = {"天赋树1", "天赋树2", "天赋树3"},
--         points = {树1点数, 树2点数, 树3点数},
--         desc = "方案说明(可选)",
--         talents = {
--             [1] = {  -- 天赋树1
--                 [天赋序号] = { name="天赋名", tier=层, column=列, rank=已点, maxRank=最大 },
--                 ...
--             },
--             [2] = { ... },  -- 天赋树2
--             [3] = { ... },  -- 天赋树3
--         },
--     },
-- }
--
-- 注意: icon 字段不需要填写，会在加载时自动从游戏读取
-- tier/column 也可以省略，加载时会自动补全
-- 只需要填写 rank > 0 的天赋即可，未填写的默认 rank=0

local addonName, ns = ...
local Hekili = _G[ addonName ]

Hekili.PresetTalentBuilds = {}

-- ============================================================
-- 示例: 死亡骑士 (取消注释并修改数据即可使用)
-- ============================================================
--[[ 
Hekili.PresetTalentBuilds["DEATHKNIGHT"] = {
    ["鲜血DPS 51/0/20"] = {
        tabNames = {"鲜血", "冰霜", "邪恶"},
        points = {51, 0, 20},
        desc = "鲜血DPS标准天赋",
        talents = {
            [1] = {  -- 鲜血
                [1] = { name="屠夫", rank=2, maxRank=2 },
                [2] = { name="亡者之躯", rank=3, maxRank=3 },
                -- ... 继续填写
            },
            [2] = {},  -- 冰霜 (无点数)
            [3] = {  -- 邪恶
                [1] = { name="恶毒打击", rank=2, maxRank=2 },
                -- ... 继续填写
            },
        },
    },
}
]]

-- ============================================================
-- 在下方添加各职业的预设天赋方案
-- ============================================================

-- 死亡骑士
Hekili.PresetTalentBuilds["DEATHKNIGHT"] = {
}

-- 德鲁伊
Hekili.PresetTalentBuilds["DRUID"] = {
}

-- 猎人
Hekili.PresetTalentBuilds["HUNTER"] = {
    ["兽王"] = {
        tabNames = {"野兽控制", "射击", "生存"},
        points = {52, 11, 8},
        desc = "兽王",
        talents = {
            [1] = {  -- 野兽控制
                [2] = { name="强化雄鹰守护", rank=5, maxRank=5 },
                [4] = { name="强化治疗宠物", rank=1, maxRank=2 },
                [5] = { name="狂野怒火", rank=1, maxRank=1 },
                [6] = { name="胁迫", rank=1, maxRank=1 },
                [8] = { name="耐久训练", rank=1, maxRank=5 },
                [9] = { name="野兽戒律", rank=2, maxRank=2 },
                [10] = { name="凶暴", rank=5, maxRank=5 },
                [12] = { name="狂怒释放", rank=5, maxRank=5 },
                [13] = { name="狂乱", rank=4, maxRank=5 },
                [14] = { name="火力集中", rank=2, maxRank=2 },
                [15] = { name="强化复活宠物", rank=2, maxRank=2 },
                [16] = { name="驭兽者", rank=2, maxRank=2 },
                [17] = { name="凶猛灵感", rank=3, maxRank=3 },
                [19] = { name="蛇之迅捷", rank=5, maxRank=5 },
                [20] = { name="野兽之心", rank=1, maxRank=1 },
                [21] = { name="雄鹰射击", rank=1, maxRank=1 },
                [22] = { name="眼镜蛇打击", rank=3, maxRank=3 },
                [23] = { name="守护掌握", rank=1, maxRank=1 },
                [24] = { name="野兽主宰", rank=1, maxRank=1 },
                [25] = { name="豪猪诱饵", rank=1, maxRank=1 },
                [26] = { name="志趣相投", rank=5, maxRank=5 },
            },
            [2] = {  -- 射击
                [4] = { name="夺命射击", rank=5, maxRank=5 },
                [9] = { name="致死射击", rank=2, maxRank=5 },
                [15] = { name="精确瞄准", rank=3, maxRank=3 },
                [18] = { name="直取要害", rank=1, maxRank=2 },
            },
            [3] = {  -- 生存
                [3] = { name="陷阱掌握", rank=3, maxRank=3 },
                [14] = { name="强化追踪", rank=5, maxRank=5 },
            },
        },
    },
}

-- 法师
Hekili.PresetTalentBuilds["MAGE"] = {
}

-- 圣骑士
Hekili.PresetTalentBuilds["PALADIN"] = {
}

-- 牧师
Hekili.PresetTalentBuilds["PRIEST"] = {
}

-- 盗贼
Hekili.PresetTalentBuilds["ROGUE"] = {
}

-- 萨满
Hekili.PresetTalentBuilds["SHAMAN"] = {
}

-- 术士
Hekili.PresetTalentBuilds["WARLOCK"] = {
}

-- 战士
Hekili.PresetTalentBuilds["WARRIOR"] = {
}
