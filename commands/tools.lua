-- Terminal shortcuts for the side-panel tools.
return {
    {
        name = "board",
        help = "open the case board",
        category = "map",
        run = function(t) t.ui.show_tab("BOARD"); t.print("{accent}▸{} case board") end,
    },
    {
        name = "timeline",
        help = "toggle the map timeline",
        category = "map",
        run = function(t)
            t.ui.show_tab("MAP")
            for _, w in ipairs(t.ui.widgets) do if w.title == "WORLD MAP" then w.timeline = not w.timeline end end
            t.print("{accent}▸{} timeline toggled")
        end,
    },
    {
        name = "password",
        aliases = { "pass", "pw" },
        help = "open the password forge",
        category = "tools",
        run = function(t) t.ui.show_tab("KEYS"); t.print("{accent}▸{} password forge") end,
    },
}
