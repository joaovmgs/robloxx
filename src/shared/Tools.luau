-- Tools: definitions and helpers for player tools and upgrades
local Tools = {}

export type ToolId = "Axe" | "Pickaxe" | "Hoe" | string

export type ToolInfo = {
    id: ToolId,
    displayName: string,
    maxLevel: number,
    baseTimeSec: number, -- base action time at level 1
    perLevelSpeedup: number, -- percent speedup per level (e.g., 0.15 = 15%)
}

export type PlayerTools = {
    Axe: { level: number },
    Pickaxe: { level: number },
    Hoe: { level: number },
}

local CATALOG: { [ToolId]: ToolInfo } = {
    Axe = {
        id = "Axe",
        displayName = "Machado",
        maxLevel = 5,
        baseTimeSec = 2.5,
        perLevelSpeedup = 0.15, -- each level reduces time by 15%
    },
    Pickaxe = {
        id = "Pickaxe",
        displayName = "Picareta",
        maxLevel = 5,
        baseTimeSec = 3.0,
        perLevelSpeedup = 0.12,
    },
    Hoe = {
        id = "Hoe",
        displayName = "Enxada",
        maxLevel = 5,
        baseTimeSec = 1.5,
        perLevelSpeedup = 0.10,
    },
}

function Tools.getCatalog(): { [ToolId]: ToolInfo }
    return CATALOG
end

function Tools.defaultForPlayer(): PlayerTools
    return {
        Axe = { level = 1 },
        Pickaxe = { level = 1 },
        Hoe = { level = 1 },
    }
end

local function clamp(n: number, a: number, b: number): number
    if n < a then return a end
    if n > b then return b end
    return n
end

function Tools.getAxeChopTimeSec(level: number?): number
    local info = CATALOG.Axe
    local lv = clamp(level or 1, 1, info.maxLevel)
    local factor = 1 - info.perLevelSpeedup * (lv - 1)
    if factor < 0.2 then factor = 0.2 end -- don't go below 20% of base
    return info.baseTimeSec * factor
end

function Tools.getPickaxeMineTimeSec(level: number?): number
    local info = CATALOG.Pickaxe
    local lv = clamp(level or 1, 1, info.maxLevel)
    local factor = 1 - info.perLevelSpeedup * (lv - 1)
    if factor < 0.25 then factor = 0.25 end
    return info.baseTimeSec * factor
end

function Tools.getActionTime(toolId: ToolId, level: number?): number
    if toolId == "Axe" then return Tools.getAxeChopTimeSec(level) end
    if toolId == "Pickaxe" then return Tools.getPickaxeMineTimeSec(level) end
    if toolId == "Hoe" then
        local info = CATALOG.Hoe
        local lv = clamp(level or 1, 1, info.maxLevel)
        local factor = 1 - info.perLevelSpeedup * (lv - 1)
        if factor < 0.3 then factor = 0.3 end
        return info.baseTimeSec * factor
    end
    return 2.5
end

function Tools.requiredToolForResource(resourceType: string): ToolId
    if resourceType == "tree" then return "Axe" end
    if resourceType == "rock" then return "Pickaxe" end
    if resourceType == "soil" then return "Pickaxe" end
    return "Axe"
end

return Tools
