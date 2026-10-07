-- Minecraft HUD for Monster Hunter Wilds
-- An REFramework script that draws a blocky, Minecraft-style HUD over the hunt:
--   * hearts      = your health (10 hearts, half-heart steps, shake when low, flash on damage)
--   * drumsticks  = your max stamina, which shrinks over time and refills when you eat
--   * green bar   = your current stamina, where Minecraft's experience bar sits
-- All pixel art is original and drawn with REFramework's draw API; no game files are shipped.

local MOD_NAME = "Minecraft HUD"
local CONFIG_FILE = "minecraft_hud.json"

-- Wilds' highest possible stamina; a full row of drumsticks.
local STAMINA_CAP = 150.0

local config = {
    enabled = true,
    scale = 3,
    bottom_margin = 40,
    show_hearts = true,
    show_hunger = true,
    show_stamina_bar = true,
    low_health_shake = true,
}

local function load_config()
    local ok, saved = pcall(json.load_file, CONFIG_FILE)
    if ok and type(saved) == "table" then
        for k, v in pairs(saved) do
            if config[k] ~= nil and type(config[k]) == type(v) then
                config[k] = v
            end
        end
    end
end

local function save_config()
    pcall(json.dump_file, CONFIG_FILE, config)
end

load_config()

---------------------------------------------------------------------------
-- Sprites
---------------------------------------------------------------------------

-- Colors are ImGui ABGR (0xAABBGGRR).
local COLOR = {
    outline       = 0xFF101010,
    outline_flash = 0xFFFFFFFF,
    empty         = 0xFF303030,
    heart         = 0xFF2020D8,
    heart_shine   = 0xFF9090FF,
    meat          = 0xFF2E5CB0,
    meat_shine    = 0xFF6A9AE0,
    bone          = 0xFFE0EEF0,
    bar_back      = 0xFF202020,
    bar_fill      = 0xFF30E080,
    bar_shine     = 0xFF90FFC0,
}

-- 'X' body, 'H' shine, 'B' bone, '.' transparent. An outline is added around every
-- non-transparent pixel automatically.
local HEART = {
    ".XX.XX.",
    "XHXXXXX",
    "XXXXXXX",
    ".XXXXX.",
    "..XXX..",
    "...X...",
}

local DRUMSTICK = {
    "....XX.",
    "...XHXX",
    "..XXXXX",
    ".XXXX..",
    "BB.....",
    "B......",
}

-- Pre-computes horizontal pixel runs so each icon is a handful of rectangles.
-- Coordinates are in sprite pixels, offset by 1 to leave room for the outline.
local function build_sprite(rows)
    local w, h = #rows[1], #rows
    local solid = {}
    for y = 1, h do
        solid[y] = {}
        for x = 1, w do
            solid[y][x] = rows[y]:sub(x, x) ~= "."
        end
    end

    local function is_solid(x, y)
        return solid[y] ~= nil and solid[y][x] == true
    end

    local function is_edge(x, y)
        return not is_solid(x, y)
            and (is_solid(x - 1, y) or is_solid(x + 1, y) or is_solid(x, y - 1) or is_solid(x, y + 1))
    end

    local outline, body = {}, {}
    for y = 0, h + 1 do
        local x = 0
        while x <= w + 1 do
            if is_edge(x, y) then
                local start = x
                while x + 1 <= w + 1 and is_edge(x + 1, y) do
                    x = x + 1
                end
                table.insert(outline, { x = start, y = y, w = x - start + 1 })
            end
            x = x + 1
        end
    end

    for y = 1, h do
        local x = 1
        while x <= w do
            local c = rows[y]:sub(x, x)
            if c ~= "." then
                local start = x
                while x + 1 <= w and rows[y]:sub(x + 1, x + 1) == c do
                    x = x + 1
                end
                table.insert(body, { x = start, y = y, w = x - start + 1, kind = c })
            end
            x = x + 1
        end
    end

    return { w = w + 2, h = h + 2, outline = outline, body = body }
end

local heart_sprite = build_sprite(HEART)
local drumstick_sprite = build_sprite(DRUMSTICK)

-- fill: "full", "half" or "empty". half_side: "left" or "right" (which half stays filled).
local function draw_icon(sprite, ox, oy, s, fill, half_side, palette, outline_color)
    for _, r in ipairs(sprite.outline) do
        draw.filled_rect(ox + r.x * s, oy + r.y * s, r.w * s, s, outline_color)
    end

    local mid = (#HEART[1] + 1) / 2
    for _, r in ipairs(sprite.body) do
        local color = palette[r.kind]
        if fill == "empty" then
            draw.filled_rect(ox + r.x * s, oy + r.y * s, r.w * s, s, COLOR.empty)
        elseif fill == "full" then
            draw.filled_rect(ox + r.x * s, oy + r.y * s, r.w * s, s, color)
        else
            -- Paint the run pixel by pixel so it can be split down the middle.
            for px = r.x, r.x + r.w - 1 do
                local lit = (half_side == "left" and px <= mid) or (half_side == "right" and px >= mid)
                draw.filled_rect(ox + px * s, oy + r.y * s, s, s, lit and color or COLOR.empty)
            end
        end
    end
end

local HEART_PALETTE = { X = COLOR.heart, H = COLOR.heart_shine }
local MEAT_PALETTE = { X = COLOR.meat, H = COLOR.meat_shine, B = COLOR.bone }

---------------------------------------------------------------------------
-- Reading the hunter's state (every call is guarded so a game update can only
-- hide the HUD, never crash the game)
---------------------------------------------------------------------------

local function try_call(obj, ...)
    if obj == nil then return nil end
    for _, name in ipairs({ ... }) do
        local ok, result = pcall(obj.call, obj, name)
        if ok and result ~= nil then
            return result
        end
    end
    return nil
end

local function get_hunter()
    local manager = sdk.get_managed_singleton("app.PlayerManager")
    local info = try_call(manager, "getMasterPlayer")
    return try_call(info, "get_Character")
end

local function read_stats()
    local hunter = get_hunter()
    if hunter == nil then return nil end

    local health_owner = try_call(hunter, "get_HunterHealth")
    local health_mgr = try_call(health_owner, "get_HealthMgr", "get_HealthManager")
    local health = try_call(health_mgr, "get_Health")
    local max_health = try_call(health_mgr, "get_MaxHealth", "get_HealthMax")
    if health == nil or max_health == nil or max_health <= 0 then
        return nil
    end

    local stamina_owner = try_call(hunter, "get_HunterStamina")
    local stamina = try_call(stamina_owner, "get_Stamina")
    local max_stamina = try_call(stamina_owner, "get_MaxStamina", "get_StaminaMax")

    return {
        health = health,
        max_health = max_health,
        stamina = stamina,
        max_stamina = max_stamina,
    }
end

---------------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------------

local function screen_size()
    local ok, size = pcall(imgui.get_display_size)
    if ok and size ~= nil and size.x > 0 then
        return size.x, size.y
    end
    local ok2, w, h = pcall(function()
        local scene_manager = sdk.get_native_singleton("via.SceneManager")
        local scene_manager_type = sdk.find_type_definition("via.SceneManager")
        local view = sdk.call_native_func(scene_manager, scene_manager_type, "get_MainView")
        local window = view:call("get_WindowSize")
        return window.w, window.h
    end)
    if ok2 and w ~= nil then
        return w, h
    end
    return nil
end

---------------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------------

local ICON_STEP = 8      -- sprite pixels between icons (outlines overlap, like Minecraft)
local ICONS_PER_ROW = 10
local BAR_WIDTH = 182    -- sprite pixels, matches the width of two icon rows plus the gap
local BAR_HEIGHT = 5

local last_health = nil
local flash_frames = 0

local function draw_hud(stats)
    local sw, sh = screen_size()
    if sw == nil then return end

    local s = math.max(1, math.floor(config.scale))
    local bar_w = BAR_WIDTH * s
    local left = math.floor((sw - bar_w) / 2)
    local bar_y = sh - config.bottom_margin - BAR_HEIGHT * s
    local icons_y = bar_y - (heart_sprite.h + 1) * s

    -- Damage flash
    if last_health ~= nil and stats.health < last_health - 0.5 then
        flash_frames = 12
    end
    last_health = stats.health
    local outline = COLOR.outline
    if flash_frames > 0 then
        flash_frames = flash_frames - 1
        if flash_frames % 4 >= 2 then
            outline = COLOR.outline_flash
        end
    end

    -- Hearts, left to right
    if config.show_hearts then
        local frac = math.max(0, math.min(1, stats.health / stats.max_health))
        local halves = math.ceil(frac * ICONS_PER_ROW * 2)
        local shaking = config.low_health_shake and frac <= 0.2
        for i = 0, ICONS_PER_ROW - 1 do
            local fill = "empty"
            if halves >= i * 2 + 2 then
                fill = "full"
            elseif halves == i * 2 + 1 then
                fill = "half"
            end
            local jitter = shaking and (math.random(0, 1) * s) or 0
            draw_icon(heart_sprite, left + i * ICON_STEP * s, icons_y + jitter, s, fill, "left", HEART_PALETTE, outline)
        end
    end

    -- Drumsticks, right to left
    if config.show_hunger and stats.max_stamina ~= nil then
        local frac = math.max(0, math.min(1, stats.max_stamina / STAMINA_CAP))
        local halves = math.floor(frac * ICONS_PER_ROW * 2 + 0.5)
        local right = left + bar_w - drumstick_sprite.w * s
        for i = 0, ICONS_PER_ROW - 1 do
            local fill = "empty"
            if halves >= i * 2 + 2 then
                fill = "full"
            elseif halves == i * 2 + 1 then
                fill = "half"
            end
            draw_icon(drumstick_sprite, right - i * ICON_STEP * s, icons_y, s, fill, "right", MEAT_PALETTE, COLOR.outline)
        end
    end

    -- Stamina bar in the experience-bar slot
    if config.show_stamina_bar and stats.stamina ~= nil and stats.max_stamina ~= nil and stats.max_stamina > 0 then
        local frac = math.max(0, math.min(1, stats.stamina / stats.max_stamina))
        draw.filled_rect(left - s, bar_y - s, bar_w + 2 * s, (BAR_HEIGHT + 2) * s, COLOR.outline)
        draw.filled_rect(left, bar_y, bar_w, BAR_HEIGHT * s, COLOR.bar_back)
        local fill_w = math.floor(bar_w * frac)
        if fill_w > 0 then
            draw.filled_rect(left, bar_y, fill_w, BAR_HEIGHT * s, COLOR.bar_fill)
            draw.filled_rect(left, bar_y, fill_w, s, COLOR.bar_shine)
        end
        -- Segment notches, like the experience bar
        for n = 1, 17 do
            local nx = left + math.floor(n * bar_w / 18)
            draw.filled_rect(nx, bar_y, s, BAR_HEIGHT * s, COLOR.outline)
        end
    end
end

re.on_frame(function()
    if not config.enabled then return end
    local ok, stats = pcall(read_stats)
    if not ok or stats == nil then
        last_health = nil
        return
    end
    draw_hud(stats)
end)

---------------------------------------------------------------------------
-- Settings (REFramework menu: Insert key -> Script Generated UI)
---------------------------------------------------------------------------

re.on_draw_ui(function()
    if not imgui.tree_node(MOD_NAME) then return end
    local changed = false
    local c

    c, config.enabled = imgui.checkbox("Enabled", config.enabled); changed = changed or c
    c, config.show_hearts = imgui.checkbox("Hearts (health)", config.show_hearts); changed = changed or c
    c, config.show_hunger = imgui.checkbox("Drumsticks (max stamina)", config.show_hunger); changed = changed or c
    c, config.show_stamina_bar = imgui.checkbox("Green bar (stamina)", config.show_stamina_bar); changed = changed or c
    c, config.low_health_shake = imgui.checkbox("Shake hearts at low health", config.low_health_shake); changed = changed or c
    c, config.scale = imgui.slider_int("Pixel size", config.scale, 1, 8); changed = changed or c
    c, config.bottom_margin = imgui.slider_int("Distance from bottom", config.bottom_margin, 0, 600); changed = changed or c

    if changed then save_config() end
    imgui.tree_pop()
end)
