-- TerrainHandler: creates per-player plot and generates procedural contents
local TerrainHandler = {}

export type CellType = "tree" | "rock" | "bush" | "water" | "empty"

local CELL_SIZE = 4 -- studs per cell
local GRID_SIZE = 50 -- 50x50
local PLOT_HEIGHT = 0 -- y level for ground
local TILE_SPACING = 1000 -- distance between player plots
local SAFE_RADIUS_CELLS = 0 -- center cells kept free (0 = disabled)
local TREE_DENSITY = 0.06 -- 6% cells become trees
local ROCK_DENSITY = 0.03 -- 3% cells become rocks

local ServerStorage = game:GetService("ServerStorage")

local function cellKey(x: number, z: number): string
    return tostring(x)..","..tostring(z)
end

local function pickType(rng: Random, x: number, z: number): CellType
    local r = rng:NextNumber()
    if r < TREE_DENSITY then
        return 'tree'
    elseif r < (TREE_DENSITY + ROCK_DENSITY) then
        return 'rock'
    else
        return 'empty'
    end
end

local function cloneTreeModel(): Instance?
    local inst = ServerStorage:FindFirstChild('TreeModel')
    if inst then return inst:Clone() end
    return nil
end

local function cloneRockModel(): Instance?
    local inst = ServerStorage:FindFirstChild('Rock')
    if inst then return inst:Clone() end
    return nil
end

local function getPlotOffsetFromSeed(seed: number): Vector3
    local a = (seed % 31)
    local b = (math.floor(seed / 31) % 31)
    local x = a * TILE_SPACING
    local z = b * TILE_SPACING
    return Vector3.new(x, 0, z)
end

local function createGround(parent: Instance, baseOffset: Vector3)
    local size = Vector3.new(GRID_SIZE * CELL_SIZE, 1, GRID_SIZE * CELL_SIZE)
    local ground: BasePart = Instance.new("Part")
    ground.Name = "Ground"
    ground.Anchored = true
    ground.Size = size
    ground.Material = Enum.Material.Grass
    ground.Color = Color3.fromRGB(106, 127, 63)
    ground.Parent = parent
    ground.Position = baseOffset + Vector3.new(size.X/2, PLOT_HEIGHT, size.Z/2)
    return ground
end

local function createPlaceholder(name: string, color: Color3, size: Vector3, position: Vector3)
    local p = Instance.new("Part")
    p.Name = name
    p.Anchored = true
    p.Color = color
    p.Size = size
    p.Position = position
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    return p
end

function TerrainHandler.getSeedForPlayer(userId: number, name: string?): number
    if userId and userId > 0 then
        return userId
    end
    local s = tostring(name or "Player")
    local hash = 5381
    for i = 1, #s do
        hash = bit32.bxor(hash * 33, string.byte(s, i)) % 2147483647
    end
    if hash < 0 then hash = -hash end
    return hash
end

function TerrainHandler.ensurePlayerPlotForSeed(seed: number, parent: Instance): Model
    local existing = parent:FindFirstChild("Plot")
    if existing and existing:IsA("Model") then
        return existing
    end
    print("[PLOT] Creating base plot for seed", seed)
    local baseOffset = getPlotOffsetFromSeed(seed)

    local template = ServerStorage:FindFirstChild("BasePlotTemplate")
    if template and template:IsA("Model") then
        local plot = template:Clone()
        plot.Name = "Plot"
        plot.Parent = parent
        if not plot.PrimaryPart then
            plot.PrimaryPart = plot:FindFirstChildWhichIsA("BasePart", true)
        end
        local sizeX = GRID_SIZE * CELL_SIZE
        local sizeZ = GRID_SIZE * CELL_SIZE
        local center = baseOffset + Vector3.new(sizeX/2, PLOT_HEIGHT, sizeZ/2)
        if plot.PrimaryPart then
            plot:PivotTo(CFrame.new(center))
        end
        return plot
    end

    local plot = Instance.new("Model")
    plot.Name = "Plot"
    plot.Parent = parent
    local ground = createGround(plot, baseOffset)
    plot.PrimaryPart = ground
    return plot
end

function TerrainHandler.generateInitialTerrainForSeed(seed: number, plot: Model): Model
    local oldGen = plot:FindFirstChild("Generated")
    if oldGen then oldGen:Destroy() end

    print("[GEN] Generating terrain with seed", seed)
    local rng = Random.new(seed)

    local folder = Instance.new("Folder")
    folder.Name = "Generated"
    folder.Parent = plot

    local fTree = Instance.new("Folder")
    fTree.Name = "Trees"
    fTree.Parent = folder

    local fRock = Instance.new('Folder')
    fRock.Name = 'Rocks'
    fRock.Parent = folder

    local placedTrees = 0

    local placedRocks = 0

    -- Exclusions: around SpawnPoint, NoTreesZone parts, and optional boxes (House/NoTreesBox/TreeBlocker)
    local EXCLUDE_SPAWN_RADIUS = 24
    local excludeCircles = {}
    local excludeBoxes = {}
    do
        local spawn = plot:FindFirstChild("SpawnPoint", true)
        if spawn and spawn:IsA("BasePart") then
            table.insert(excludeCircles, { pos = spawn.Position, radius = EXCLUDE_SPAWN_RADIUS })
            print("[GEN] Excluding circle around SpawnPoint radius", EXCLUDE_SPAWN_RADIUS)
        end
        -- Designer circles
        for _, inst in ipairs(plot:GetDescendants()) do
            if inst:IsA("BasePart") and inst.Name == "NoTreesZone" then
                local r = math.max(inst.Size.X, inst.Size.Z) * 0.5
                table.insert(excludeCircles, { pos = inst.Position, radius = r })
                print("[GEN] Excluding NoTreesZone radius", r)
            end
        end
        -- Boxes by Model/Part names
        local function addBoxFromModel(m: Model, margin: number?)
            local cf, size = m:GetBoundingBox()
            table.insert(excludeBoxes, { cf = cf, size = size, margin = margin or 1.0 })
            print("[GEN] Excluding box for model", m.Name)
        end
        local function addBoxFromPart(p: BasePart, margin: number?)
            table.insert(excludeBoxes, { cf = p.CFrame, size = p.Size, margin = margin or 1.0 })
            print("[GEN] Excluding box for part", p.Name)
        end
        local house = plot:FindFirstChild("House", true)
        if house and house:IsA("Model") then
            addBoxFromModel(house, 1.5)
        end
        for _, inst in ipairs(plot:GetDescendants()) do
            if inst:IsA("BasePart") and (inst.Name == "NoTreesBox" or inst.Name == "TreeBlocker" or inst.Name == "NoGenerate" or inst.Name == "NoSpawnBox") then
                addBoxFromPart(inst, 1.0)
            end
        end
    end

    local function isBlocked(pos: Vector3): boolean
        -- circle excludes
        for _, circ in ipairs(excludeCircles) do
            local dxz = Vector2.new(pos.X - circ.pos.X, pos.Z - circ.pos.Z)
            if dxz.Magnitude <= circ.radius then
                return true
            end
        end
        -- oriented box excludes
        for _, box in ipairs(excludeBoxes) do
            local lp = box.cf:PointToObjectSpace(pos)
            local m = box.margin or 0
            if math.abs(lp.X) <= box.size.X/2 + m and math.abs(lp.Z) <= box.size.Z/2 + m then
                -- ignore Y to allow placing next to tall structures
                return true
            end
        end
        return false
    end

    local baseOffset = getPlotOffsetFromSeed(seed)
    local centerCellX = GRID_SIZE/2
    local centerCellZ = GRID_SIZE/2
    for x = 1, GRID_SIZE do
        for z = 1, GRID_SIZE do
            local ctype = pickType(rng, x, z)
            if ctype ~= "empty" then
                local center = baseOffset + Vector3.new((x-0.5) * CELL_SIZE, PLOT_HEIGHT + 1.5, (z-0.5) * CELL_SIZE)

                -- Optional: keep a safe circular area at plot center (disabled when 0)
                if SAFE_RADIUS_CELLS > 0 then
                    local dx = x - centerCellX
                    local dz = z - centerCellZ
                    local dist = math.sqrt(dx*dx + dz*dz)
                    if dist <= SAFE_RADIUS_CELLS then
                        ctype = "empty"
                    end
                end

                -- Exclude dynamic blockers (house, spawn area, custom zones)
                if ctype ~= "empty" and isBlocked(center) then
                    ctype = "empty"
                end

                if ctype == "tree" then
                    local treeTemplate = cloneTreeModel()
                    if treeTemplate and treeTemplate:IsA("Model") then
                        local m = treeTemplate
                        m.Name = "Tree_"..cellKey(x,z)
                        m:PivotTo(CFrame.new(center))
                        m.Parent = fTree
                    else
                        local tree = createPlaceholder("Tree_"..cellKey(x,z), Color3.fromRGB(66, 118, 52), Vector3.new(2, 3, 2), center)
                        tree.Parent = fTree
                    end
                    placedTrees += 1
                elseif ctype == 'rock' then
                    local rockTemplate = cloneRockModel()
                    if rockTemplate then
                        if rockTemplate:IsA('Model') then
                            rockTemplate.Name = 'Rock_'..cellKey(x,z)
                            rockTemplate:PivotTo(CFrame.new(center))
                            rockTemplate.Parent = fRock
                        elseif rockTemplate:IsA('BasePart') then
                            local p = rockTemplate
                            p.Name = 'Rock_'..cellKey(x,z)
                            p.Anchored = true
                            p.Position = center
                            p.Parent = fRock
                        end
                    else
                        local rock = createPlaceholder('Rock_'..cellKey(x,z), Color3.fromRGB(130,130,130), Vector3.new(2,2,2), center)
                        rock.Parent = fRock
                    end
                    placedRocks += 1
                end
            end
        end
    end

    print(string.format("[GEN] Terrain generation complete. Trees: %d, Rocks: %d", placedTrees, placedRocks))
    return folder
end

function TerrainHandler.getSpawnCFrameForSeed(seed: number): CFrame
    local baseOffset = getPlotOffsetFromSeed(seed)
    local center = baseOffset + Vector3.new((GRID_SIZE * CELL_SIZE)/2, PLOT_HEIGHT + 6, (GRID_SIZE * CELL_SIZE)/2)
    return CFrame.new(center)
end

function TerrainHandler.getPlotBounds()
    return GRID_SIZE, CELL_SIZE
end

-- Backwards-compatible wrappers
function TerrainHandler.ensurePlayerPlot(userId: number, parent: Instance): Model
    return TerrainHandler.ensurePlayerPlotForSeed(userId, parent)
end

function TerrainHandler.generateInitialTerrain(userId: number, plot: Model): Model
    return TerrainHandler.generateInitialTerrainForSeed(userId, plot)
end

function TerrainHandler.getSpawnCFrame(userId: number): CFrame
    return TerrainHandler.getSpawnCFrameForSeed(userId)
end

return TerrainHandler











