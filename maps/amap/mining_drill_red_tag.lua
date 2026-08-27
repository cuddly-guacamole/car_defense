-- mining_drill_red_tag.lua
-- 矿挖完自动给挖掘机标红图（2026-08-28 玩家反馈）
-- 触发：defines.events.on_resource_depleted（矿资源格被采空至 0 时引擎触发）
-- 判定"矿挖完了"：耗尽格位于挖掘机采矿区内，且该挖掘机采矿区内已无任何剩余可采矿（amount > 0）
-- 满足 → 对挖掘机执行 order_deconstruction（标为"待拆除"红图），建筑机器人自动拆除
-- 说明：红图 = deconstruction planner 标记（待拆除），非地图标签（chart tag）
-- 防重复：to_be_deconstructed() 已标记则跳过；软重置 new_surface.clear(true) 销毁实体时标记自然消失

local Event = require 'utils.event'

-- 只处理玩家会用来采尽有限矿的三种挖掘机（pumpjack 同为 type='mining-drill' 但采无限油井，永不触发本事件，且须排除）
local KNOWN_DRILLS = {
    ['burner-mining-drill'] = true,
    ['electric-mining-drill'] = true,
    ['big-mining-drill'] = true,
}

-- 采矿半径兜底（runtime 优先用 prototype.mining_drill_radius，字段缺失时回退；wiki 覆盖尺寸 / 2）
local DRILL_RADIUS_FALLBACK = {
    ['burner-mining-drill'] = 1.0,     -- 2×2
    ['electric-mining-drill'] = 2.5,   -- 5×5
    ['big-mining-drill'] = 6.5,        -- 13×13
}

local function drill_mining_radius(drill)
    local proto = drill.prototype
    if proto then
        local r = proto.mining_drill_radius
        if r then return r end
    end
    return DRILL_RADIUS_FALLBACK[drill.name] or 2.5
end

-- 采矿区内是否还有剩余可采矿（amount > 0）
local function drill_has_remaining_ore(drill)
    local half = math.ceil(drill_mining_radius(drill) + 0.5)
    local pos = drill.position
    local ores = drill.surface.find_entities_filtered({
        type = 'resource',
        area = {
            {pos.x - half, pos.y - half},
            {pos.x + half, pos.y + half},
        },
    })
    for _, ore in pairs(ores) do
        if ore.valid and ore.amount and ore.amount > 0 then
            return true
        end
    end
    return false
end

-- 把挖掘机标记为"待拆除"（红图），防重复
local function mark_for_deconstruction(drill)
    if not drill.valid then return end
    if drill.force ~= game.forces.player then return end       -- 仅玩家势力
    if drill.to_be_deconstructed() then return end             -- 已标红不重复
    drill.order_deconstruction(game.forces.player)
end

-- 某资源格耗尽：把"耗尽格在其采矿区内且已无剩余矿"的挖掘机标红图
local function on_resource_depleted(event)
    local entity = event.entity
    if not entity or not entity.valid then return end
    local surface = entity.surface
    if not surface.valid then return end
    local pos = entity.position

    -- 反查可能覆盖该矿格的挖掘机（大矿机采矿半径 6.5，取 8 格保守范围）
    local drills = surface.find_entities_filtered({
        type = 'mining-drill',
        area = {
            {pos.x - 8, pos.y - 8},
            {pos.x + 8, pos.y + 8},
        },
    })
    for _, drill in pairs(drills) do
        if drill.valid and KNOWN_DRILLS[drill.name] then
            local radius = drill_mining_radius(drill) + 0.5
            local dx = math.abs(drill.position.x - pos.x)
            local dy = math.abs(drill.position.y - pos.y)
            if dx <= radius and dy <= radius and not drill_has_remaining_ore(drill) then
                mark_for_deconstruction(drill)
            end
        end
    end
end

Event.add(defines.events.on_resource_depleted, on_resource_depleted)

return {
    mark_for_deconstruction = mark_for_deconstruction,
}