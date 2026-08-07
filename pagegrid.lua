local Blitbuffer = require("ffi/blitbuffer")
local Screen = require("device").screen
local logger = require("logger")

local PageGrid = {}

PageGrid.VIEW_MODULE_NAME = "fulltextunderline_line_aligned_full_width_v1"

local BOTTOM_DEDUPE_TOLERANCE = 2

local HEADING_TAGS = {
    h1 = true,
    h2 = true,
    h3 = true,
    h4 = true,
    h5 = true,
    h6 = true,
    title = true,
    chapter = true,
    chaptertitle = true,
    ["chapter-title"] = true,
}

-- UI position 0 preserves V1.2's verified -2px drawing position.
-- Positive UI values move the line up: draw_y = line_bottom - resolved_offset.
local BASE_POSITION_OFFSET = 2

local SPECIAL_TAGS = {
    figure = true,
    figcaption = true,
    aside = true,
    blockquote = true,
    details = true,
    summary = true,
    dialog = true,
    img = true,
    image = true,
    svg = true,
    canvas = true,
    video = true,
    table = true,
    pre = true,
    code = true,
    math = true,
}

local SPECIAL_KEYWORDS = {
    "figure", "figcaption", "aside", "blockquote", "block-quote",
    "notice", "note", "warning", "tip", "caution", "alert",
    "callout", "panel", "box", "boxed", "message", "special",
    "dark", "black", "inverse", "shaded", "highlight", "admonition",
    "quote-box", "info", "important", "card", "banner", "caption-box",
    "sidebar", "side-bar", "infobox", "info-box", "hint", "danger",
    "error", "success", "question", "example", "remark", "attention",
    "advice", "announcement", "dialog", "alertdialog", "alert-dialog",
    "status", "complementary", "tooltip", "pullquote",
    "pull-quote", "epigraph", "marginalia", "annotation",
}

local function clamp(value, minimum, maximum)
    if value < minimum then return minimum end
    if value > maximum then return maximum end
    return value
end

local function safeNumber(value, fallback)
    return type(value) == "number" and value or fallback
end

function PageGrid.register(plugin)
    local view = plugin.ui and plugin.ui.view
    if not view or not view.registerViewModule then return false end
    local existing = view.view_modules and view.view_modules[PageGrid.VIEW_MODULE_NAME]
    if existing and existing ~= plugin then return false end
    view:registerViewModule(PageGrid.VIEW_MODULE_NAME, plugin)
    return view.view_modules[PageGrid.VIEW_MODULE_NAME] == plugin
end

function PageGrid.unregister(plugin)
    local view = plugin.ui and plugin.ui.view
    if view and view.view_modules
        and view.view_modules[PageGrid.VIEW_MODULE_NAME] == plugin then
        view.view_modules[PageGrid.VIEW_MODULE_NAME] = nil
    end
end

function PageGrid.invalidate(plugin)
    plugin._page_grid_cache_key = nil
    plugin._page_grid_cache = nil
end

local function getContentAreas(plugin)
    local view = plugin.ui.view
    local document = plugin.ui.document
    local visible = view.visible_area
    local offset = view.state and view.state.offset or { x = 0, y = 0 }
    local margins = document:getPageMargins() or {}
    local left_margin = safeNumber(margins.left, 0)
    local right_margin = safeNumber(margins.right, 0)
    local top_margin = safeNumber(margins.top, 0)
    local bottom_margin = safeNumber(margins.bottom, 0)
    local header_height = view.view_mode == "page"
        and safeNumber(document:getHeaderHeight(), 0) or 0

    local content_top = offset.y
    local content_bottom = offset.y + visible.h
    if view.view_mode == "page" then
        content_top = content_top + top_margin + header_height
        content_bottom = content_bottom - bottom_margin
    end
    if view.footer_visible and view.footer then
        content_bottom = math.min(content_bottom,
            view.dimen.h - view.footer:getHeight())
    end

    local areas = {}
    local visible_pages = document:getVisiblePageCount()
    if view.view_mode == "page" and visible_pages > 1 then
        local current_page = document:getCurrentPage(true)
        local page2_x = document:getPageOffsetX(current_page + 1)
        if type(page2_x) ~= "number" or page2_x <= 0 or page2_x >= visible.w then
            page2_x = math.floor(visible.w / 2)
        end
        if page2_x > 0 and page2_x < visible.w then
            areas[#areas + 1] = {
                left = offset.x + left_margin,
                right = offset.x + page2_x - right_margin,
                top = content_top,
                bottom = content_bottom,
            }
            areas[#areas + 1] = {
                left = offset.x + page2_x + left_margin,
                right = offset.x + visible.w - right_margin,
                top = content_top,
                bottom = content_bottom,
            }
        end
    end
    if #areas == 0 then
        areas[1] = {
            left = offset.x + left_margin,
            right = offset.x + visible.w - right_margin,
            top = content_top,
            bottom = content_bottom,
        }
    end

    for index = #areas, 1, -1 do
        local area = areas[index]
        area.left = math.floor(clamp(area.left, 0, view.dimen.w))
        area.right = math.ceil(clamp(area.right, 0, view.dimen.w))
        area.top = math.floor(clamp(area.top, 0, view.dimen.h))
        area.bottom = math.ceil(clamp(area.bottom, 0, view.dimen.h))
        if area.right <= area.left or area.bottom <= area.top then
            table.remove(areas, index)
        end
    end
    return areas, margins, header_height
end

local function getTextBoxes(plugin, area)
    local result = plugin.ui.document:getTextFromPositions(
        { x = area.left, y = area.top },
        { x = area.right - 1, y = area.bottom - 1 },
        true)
    local boxes = {}
    for _, box in ipairs(result and result.sboxes or {}) do
        local x = safeNumber(box.x)
        local y = safeNumber(box.y)
        local w = safeNumber(box.w, 0)
        local h = safeNumber(box.h, 0)
        if x and y and w > 0 and h > 0
            and y < area.bottom and y + h > area.top then
            boxes[#boxes + 1] = {
                x = x,
                y = y,
                w = w,
                h = h,
                bottom = y + h,
                center = y + h / 2,
            }
        end
    end
    table.sort(boxes, function(first, second)
        if first.center == second.center then return first.x < second.x end
        return first.center < second.center
    end)
    return boxes
end


local function belongsToVisualLine(line, box, merge_tolerance)
    if math.abs(box.bottom - line.bottom) <= merge_tolerance
        or math.abs(box.y - line.top) <= merge_tolerance then
        return true
    end

    local overlap = math.min(line.bottom, box.bottom) - math.max(line.top, box.y)
    if overlap <= 0 then return false end
    local line_height = line.bottom - line.top
    local minimum_height = math.min(line_height, box.h)
    local center = (line.top + line.bottom) / 2
    return overlap >= minimum_height * 0.45
        and math.abs(box.center - center) <= math.max(line_height, box.h) * 0.55
end

local function mergeVisualLines(boxes)
    local merge_tolerance = math.max(2, Screen:scaleBySize(2))
    local lines = {}

    for _, box in ipairs(boxes) do
        local line = lines[#lines]
        if not line or not belongsToVisualLine(line, box, merge_tolerance) then
            line = {
                top = box.y,
                bottom = box.bottom,
                left = box.x,
                right = box.x + box.w,
            }
            lines[#lines + 1] = line
        else
            line.top = math.min(line.top, box.y)
            line.bottom = math.max(line.bottom, box.bottom)
            line.left = math.min(line.left, box.x)
            line.right = math.max(line.right, box.x + box.w)
        end
    end

    table.sort(lines, function(first, second)
        return first.bottom < second.bottom
    end)

    local merged = {}
    for _, line in ipairs(lines) do
        local previous = merged[#merged]
        if previous
            and math.abs(line.bottom - previous.bottom) <= BOTTOM_DEDUPE_TOLERANCE then
            previous.top = math.min(previous.top, line.top)
            previous.bottom = math.max(previous.bottom, line.bottom)
            previous.left = math.min(previous.left, line.left)
            previous.right = math.max(previous.right, line.right)
        else
            merged[#merged + 1] = line
        end
    end
    return merged
end

local function getOpeningElement(html)
    if type(html) ~= "string" then return nil, nil end
    local opening = html:match("^%s*(<[^>]+>)")
    if not opening then return nil, nil end
    local tag = opening:lower():match("^<%s*([%w_:%-]+)")
    if tag then tag = tag:match("([^:]+)$") end
    return opening, tag
end

local function getAttribute(opening, attribute)
    if not opening then return nil end
    opening = opening:lower()
    attribute = attribute:lower()
    local escaped = attribute:gsub("([^%w])", "%%%1")
    return opening:match(escaped .. "%s*=%s*['\"]([^'\"]*)['\"]")
        or opening:match(escaped .. "%s*=%s*([^%s>]+)")
end

local function hasKeyword(value)
    if not value then return false end
    local normalized = value:lower():gsub("[^%w_-]+", " ")
    for _, keyword in ipairs(SPECIAL_KEYWORDS) do
        local escaped = keyword:gsub("([^%w])", "%%%1")
        if normalized:match("^" .. escaped .. "$")
            or normalized:match("^" .. escaped .. "[%s_-]")
            or normalized:match("[%s_-]" .. escaped .. "$")
            or normalized:match("[%s_-]" .. escaped .. "[%s_-]") then
            return true
        end
    end
    return false
end

local function isOrdinaryBackground(value)
    local compact = value:lower():gsub("%s+", ""):gsub("!important", "")
    return compact == "" or compact == "none" or compact == "transparent"
        or compact == "inherit" or compact == "initial" or compact == "unset"
        or compact == "white" or compact == "#fff" or compact == "#ffffff"
        or compact == "rgb(255,255,255)" or compact == "rgba(255,255,255,1)"
        or compact == "rgba(255,255,255,0)" or compact:match(",0%)$") ~= nil
end

local function hasSpecialInlineStyle(style)
    if not style then return false end
    for declaration in style:gmatch("[^;]+") do
        local property, value = declaration:match(
            "^%s*([%w%-]+)%s*:%s*(.-)%s*$")
        if property and value then
            property = property:lower()
            if property == "background" or property == "background-color"
                or property == "background-image" then
                if not isOrdinaryBackground(value) then return true end
            elseif property:match("^border") then
                local compact = value:lower():gsub("%s+", "")
                    :gsub("!important", "")
                if compact ~= "" and compact ~= "0" and compact ~= "0px"
                    and compact ~= "none" and compact ~= "transparent"
                    and compact ~= "inherit" and compact ~= "initial"
                    and compact ~= "unset"
                    and not compact:find("transparent", 1, true) then
                    return true
                end
            elseif property == "box-shadow" then
                local compact = value:lower():gsub("%s+", "")
                    :gsub("!important", "")
                if compact ~= "" and compact ~= "none" and compact ~= "0"
                    and compact ~= "inherit" and compact ~= "initial"
                    and compact ~= "unset" then
                    return true
                end
            end
        end
    end
    return false
end

local function xpointerHasSpecialTag(xpointer)
    if type(xpointer) ~= "string" then return false end
    local lower = xpointer:lower()
    for tag in pairs(SPECIAL_TAGS) do
        if lower:find("/" .. tag .. "[", 1, true)
            or lower:find("/" .. tag .. "/", 1, true) then
            return true
        end
    end
    return false
end

local function classifyDomFragment(html, xpointer)
    local opening, tag = getOpeningElement(html)
    local is_heading = HEADING_TAGS[tag] == true
    local is_special = SPECIAL_TAGS[tag] == true
        or xpointerHasSpecialTag(xpointer)

    if not is_special and opening then
        is_special = hasSpecialInlineStyle(getAttribute(opening, "style"))
        if not is_special then
            for _, attribute in ipairs({
                "class", "id", "role", "epub:type", "type",
            }) do
                if hasKeyword(getAttribute(opening, attribute)) then
                    is_special = true
                    break
                end
            end
        end
    end
    return {
        is_heading = is_heading,
        is_special_region = is_special,
    }
end

local function getLineDomInfo(plugin, line, fragment_cache)
    local document = plugin.ui.document
    local position = {
        x = math.floor(line.left + 1),
        y = math.floor((line.top + line.bottom) / 2),
    }
    local ok_word, word = pcall(document.getWordFromPosition,
        document, position, true)
    if not ok_word or not word or not word.pos0 then return {} end

    local ok_html, html = pcall(document.getHTMLFromXPointer,
        document, word.pos0, 0x1001, true)
    if not ok_html or type(html) ~= "string" then
        return { representative_xpointer = word.pos0 }
    end

    -- Cache only DOM classification for this page. The XPointer and HTML are
    -- read-only metadata and never participate in V1 line detection/layout.
    local opening = html:match("^%s*(<[^>]+>)") or ""
    local cache_key = opening:lower()
    local classification = fragment_cache[cache_key]
    if not classification then
        local _, tag = getOpeningElement(html)
        classification = { is_heading = HEADING_TAGS[tag] == true }
        fragment_cache[cache_key] = classification
    end
    return {
        representative_xpointer = word.pos0,
        is_heading = classification.is_heading,
    }
end

local function makeCacheKey(plugin, areas, margins, header_height)
    local view = plugin.ui.view
    local document = plugin.ui.document
    local values = {}
    local function add(value)
        values[#values + 1] = tostring(value == nil and "-" or value)
    end

    add(view.dimen.w); add(view.dimen.h); add(view.view_mode)
    add(view.visible_area.x); add(view.visible_area.y)
    add(view.visible_area.w); add(view.visible_area.h)
    add(view.state and view.state.page); add(view.state and view.state.pos)
    add(view.state and view.state.offset and view.state.offset.x)
    add(view.state and view.state.offset and view.state.offset.y)
    add(document:getCurrentPage()); add(document:getVisiblePageCount())
    add(margins.left); add(margins.right); add(margins.top); add(margins.bottom)
    add(header_height); add(plugin.settings.style)
    add(plugin.settings.include_headings)
    add(plugin.ui.rolling and plugin.ui.rolling.rendering_hash)
    for _, area in ipairs(areas) do
        add(area.left); add(area.right); add(area.top); add(area.bottom)
    end
    return table.concat(values, "|")
end

local function getLineGeometry(plugin)
    local areas, margins, header_height = getContentAreas(plugin)
    local key = makeCacheKey(plugin, areas, margins, header_height)
    if key == plugin._page_grid_cache_key and plugin._page_grid_cache then
        return plugin._page_grid_cache
    end

    local fragment_cache = {}
    local needs_dom = not plugin.settings.include_headings
    for _, area in ipairs(areas) do
        area.lines = mergeVisualLines(getTextBoxes(plugin, area))
        if needs_dom then
            for _, line in ipairs(area.lines) do
                local dom_info = getLineDomInfo(plugin, line, fragment_cache)
                line.representative_xpointer = dom_info.representative_xpointer
                line.is_heading = dom_info.is_heading == true
            end
        end
    end
    plugin._page_grid_cache_key = key
    plugin._page_grid_cache = areas
    return areas
end

local function drawSolidLine(bb, left, right, line_y, line_width)
    bb:paintRect(left, line_y, right - left, line_width,
        Blitbuffer.COLOR_BLACK)
end

local function drawDashedLine(bb, left, right, line_y, line_width,
        dash_length, gap_length)
    local segment_x = left
    while segment_x < right do
        local width = math.min(dash_length, right - segment_x)
        bb:paintRect(segment_x, line_y, width, line_width,
            Blitbuffer.COLOR_BLACK)
        segment_x = segment_x + dash_length + gap_length
    end
end

local function drawDottedLine(bb, left, right, line_y, line_width)
    local dot_size = line_width
    local dot_gap = math.max(dot_size, Screen:scaleBySize(3))
    local available_width = right - left
    if available_width < dot_size then return 0 end

    local point_count = math.floor(
        (available_width + dot_gap) / (dot_size + dot_gap))
    local pattern_width = point_count * dot_size
        + (point_count - 1) * dot_gap
    local point_x = left + math.floor((available_width - pattern_width) / 2)
    local radius = math.floor(dot_size / 2)
    for _ = 1, point_count do
        bb:paintRoundedRect(point_x, line_y, dot_size, dot_size,
            Blitbuffer.COLOR_BLACK, radius)
        point_x = point_x + dot_size + dot_gap
    end
    return point_count
end

local function drawLines(plugin, bb, paint_x, paint_y)
    local areas = getLineGeometry(plugin)
    local resolved_offset = BASE_POSITION_OFFSET
        + safeNumber(plugin.settings.line_position, 0)
    local line_width = math.max(1, Screen:scaleBySize(
        safeNumber(plugin.settings.line_width_level, 2)))
    local user_length_adjust = safeNumber(
        plugin.settings.line_length_adjust, 0)
    local effective_length_adjust = user_length_adjust * 3
    local dash_length = math.max(1, Screen:scaleBySize(
        safeNumber(plugin.settings.dash_length, 8)))
    local gap_length = math.max(1, Screen:scaleBySize(
        safeNumber(plugin.settings.gap_length, 4)))
    local line_count, segment_count = 0, 0

    for _, area in ipairs(areas) do
        local drawn_y = {}
        for _, line in ipairs(area.lines) do
            local draw_heading = plugin.settings.include_headings
                or not line.is_heading
            if draw_heading then
                local line_y = math.floor(line.bottom + 0.5)
                    - resolved_offset
                local duplicate_y = drawn_y[line_y - 1]
                    or drawn_y[line_y] or drawn_y[line_y + 1]
                if line_y >= area.top and line_y + line_width <= area.bottom
                    and not duplicate_y then
                    local line_left, line_right = area.left, area.right
                    if plugin.settings.line_mode == "text" then
                        line_left = math.max(area.left,
                            math.floor(safeNumber(line.left, area.left) - 3))
                        line_right = math.min(area.right,
                            math.ceil(safeNumber(line.right, area.right) + 3))
                    end
                    line_left = line_left - effective_length_adjust
                    line_right = line_right + effective_length_adjust
                    if line_right > line_left then
                        local left = paint_x + line_left
                        local right = paint_x + line_right
                        local y = paint_y + line_y
                        if plugin.settings.style == "solid" then
                            drawSolidLine(bb, left, right, y, line_width)
                            segment_count = segment_count + 1
                        elseif plugin.settings.style == "dashed" then
                            drawDashedLine(bb, left, right, y, line_width,
                                dash_length, gap_length)
                            segment_count = segment_count + math.ceil(
                                (right - left) / (dash_length + gap_length))
                        else
                            segment_count = segment_count + drawDottedLine(
                                bb, left, right, y, line_width)
                        end
                        drawn_y[line_y] = true
                        line_count = line_count + 1
                    end
                end
            end
        end
    end

    plugin.last_grid_stats = {
        lines = line_count,
        segments = segment_count,
        areas = #areas,
        extra_refresh_requests = 0,
    }
end

function PageGrid.paint(plugin, bb, x, y)
    local ok, error_message = pcall(drawLines, plugin, bb, x, y)
    if not ok then
        logger.warn("fulltextunderline line-aligned draw failed:", error_message)
    end
end

return PageGrid
