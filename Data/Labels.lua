-- UI filter / display labels (shared across History, Roster, UI).
local ADDON_NAME, ns = ...

ns.ui = ns.ui or {}

-- Filter label tables
ns.ui.BRACKET_LABELS = {
    ALL     = "All Brackets",
    Shuffle = "Solo Shuffle",
    Blitz   = "Battleground Blitz",
    ["2v2"] = "2v2 Arena",
    ["3v3"] = "3v3 Arena",
}
ns.ui.RESULT_LABELS = {
    ALL    = "Any Result",
    WINS   = "Wins Only",
    LOSSES = "Losses Only",
    DRAWS  = "Draws Only",
}
ns.ui.DATE_LABELS = {
    ALL         = "All Time",
    TODAY       = "Last 24 Hours",
    THISWEEK    = "Last 7 Days",
    THISMONTH   = "Last 30 Days",
    LAST3MONTHS = "Last 3 Months",
    LAST6MONTHS = "Last 6 Months",
}
ns.ui.SEASON_LABELS = {
    ALL     = "All Seasons",
    CURRENT = "Current Season",
    LAST    = "Last Season",
}
ns.ui.DATE_CUTOFFS = {
    TODAY       = 24 * 3600,
    THISWEEK    = 7 * 24 * 3600,
    THISMONTH   = 30 * 24 * 3600,
    LAST3MONTHS = 90 * 24 * 3600,
    LAST6MONTHS = 180 * 24 * 3600,
}