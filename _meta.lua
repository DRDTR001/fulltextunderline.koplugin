local gettext = require("i18n")

local function _(msgid)
    return gettext.pgettext("FullTextUnderline", msgid)
end

return {
    fullname = _("Full Text Underline"),
    description = _("Draw configurable reading lines under visible text in reflowable documents."),
}
