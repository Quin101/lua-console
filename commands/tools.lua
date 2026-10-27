-- Terminal shortcuts for the side-panel tools.
return {
    {
        name = "board",
        help = "open the case board",
        category = "map",
        run = function(t) t.ui.show_tab("BOARD"); t.print("{accent}▸{} case board") end,
    },
    {
        name = "password",
        aliases = { "pass", "pw" },
        help = "open the password forge",
        category = "tools",
        run = function(t) t.ui.show_tab("KEYS"); t.print("{accent}▸{} password forge") end,
    },
}
