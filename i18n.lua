local gettext = require("gettext")

-- KOReader only loads its core l10n/<lang>/koreader.mo catalog
-- automatically. Load this plugin's catalog explicitly, using the same
-- gettext implementation, when the current UI language is Simplified Chinese.
local source = debug.getinfo(1, "S").source
if source:sub(1, 1) == "@" then
    source = source:sub(2)
end
local plugin_dir = source:match("^(.*)[/\\][^/\\]+$")

if plugin_dir and gettext.current_lang
        and gettext.current_lang:match("^zh_CN") then
    gettext.loadMO(plugin_dir .. "/locale/zh_CN/fulltextunderline.mo")
end

return gettext
