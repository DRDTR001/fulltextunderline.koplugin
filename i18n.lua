local gettext = require("gettext")
local logger = require("logger")

-- KOReader only loads its core l10n/<lang>/koreader.mo catalog
-- automatically. Load this plugin's catalog explicitly, using the same
-- gettext implementation, when the current UI language is Simplified Chinese.
local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
    source = source:sub(2)
end
local plugin_dir = source:match("^(.*)[/\\][^/\\]+$")

local MO = plugin_dir and (plugin_dir .. "/locale/zh_CN/fulltextunderline.mo")

-- Load (or reload) our Simplified-Chinese catalog into the shared
-- GetText.context table. Safe to call repeatedly.
local function loadCatalog()
    if not MO then return false end
    local ok = gettext.loadMO(MO)
    logger.info("fulltextunderline: loadMO ->", tostring(ok), MO)
    return ok
end

local function maybeLoad()
    if gettext.current_lang and gettext.current_lang:match("^zh_CN") then
        loadCatalog()
    end
end

-- Initial load at plugin-init time (current_lang is already "zh_CN" here,
-- because reader.lua calls changeLang() before plugins are loaded).
maybeLoad()

-- Defensive: any later changeLang() call (core UI or another plugin) wipes
-- GetText.context and reloads only the core koreader.mo. Re-load our catalog
-- immediately afterwards so our context survives.
local orig_changeLang = gettext.changeLang
gettext.changeLang = function(new_lang)
    local r = orig_changeLang(new_lang)
    maybeLoad()
    return r
end

-- Defensive + diagnostic: if a FullTextUnderline lookup ever misses (context
-- wiped, not-yet-loaded, or any other runtime surprise), reload the catalog
-- and retry once. Also log the very first FullTextUnderline translation that
-- is actually requested at runtime, so we can read the real outcome from
-- crash.log (Chinese hit vs English fallback).
local orig_pgettext = gettext.pgettext
local probed = false
gettext.pgettext = function(msgctxt, msgid)
    local r = orig_pgettext(msgctxt, msgid)
    if msgctxt == "FullTextUnderline" then
        if r == msgid then
            -- Missed: reload and retry once.
            maybeLoad()
            r = orig_pgettext(msgctxt, msgid)
            if not probed then
                probed = true
                logger.warn("fulltextunderline: RUNTIME MISS for ", msgid,
                    " -> after reload: ", r,
                    " (current_lang=", tostring(gettext.current_lang), ")")
            end
        elseif not probed then
            probed = true
            logger.info("fulltextunderline: runtime probe ", msgid, " => ", r)
        end
    end
    return r
end

return gettext
