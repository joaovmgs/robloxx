-- Config: centralizes world/grid/tool parameters (reusable)
local Config = {}

-- Grid/tile
Config.CellSize = 10 -- studs per cell (snap granularity)
Config.GridSize = 50 -- cells per axis inside a plot
Config.TileThickness = 1 -- Y size for tilled soil parts
Config.TileName = "Soil" -- folder name under Plot for tilled tiles
Config.TileModelName = "Dirt" -- optional template in ServerStorage

-- Tool ranges and timings
Config.ToolMaxRange = 16 -- generic interaction range
Config.MoveCancelRange = 5 -- movement distance that cancels actions

-- Preview visuals (client)
Config.PreviewGoodColor = Color3.fromRGB(60, 180, 75)
Config.PreviewBadColor = Color3.fromRGB(200, 60, 60)
Config.PreviewTransparencyOK = 0.4
Config.PreviewTransparencyBad = 0.7
Config.PreviewYOffset = 0.2 -- lift ghost a bit for visibility

-- Optional Studio-authored ghost asset (ReplicatedStorage)
Config.GhostFolder = "Assets" -- folder under ReplicatedStorage (optional)
Config.GhostModelName = "DirtGhost" -- Model or Part to use as ghost
Config.GhostUseHighlight = true -- add a Highlight outline for visibility

return Config
