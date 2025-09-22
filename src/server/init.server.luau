-- Bootstrap server: per-player terrain generation and spawn

local Players = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("[BOOT] Server starting...")

-- TerrainHandler can be under this Script (when folder collapses) or under the parent Folder
local TerrainHandler = require(script:WaitForChild("TerrainHandler"))
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Remotes = require(Shared:WaitForChild("Remotes"))
local SpecsPublisher = require(script:WaitForChild("SpecsPublisher"))
local HoeService = require(script:WaitForChild("HoeService"))

-- Ensure workspace container for player terrains
local terrainsFolder = workspace:FindFirstChild("PlayerTerrains")
if not terrainsFolder then
    terrainsFolder = Instance.new("Folder")
    terrainsFolder.Name = "PlayerTerrains"
    terrainsFolder.Parent = workspace
end

-- Remotes setup via shared helper
local ChopRequest: RemoteEvent = Remotes.get("ChopRequest")
local ChopFeedback: RemoteEvent = Remotes.get("ChopFeedback")
local _HoeRequest: RemoteEvent = Remotes.get("HoeRequest")
local HoeFeedback: RemoteEvent = Remotes.get("HoeFeedback")

local Tools = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Tools"))

local function onPlayerAdded(player: Player)
    print(string.format("[JOIN] Player %s (%d) joined", player.Name, player.UserId))

    -- Resolve a deterministic seed (Studio players may have UserId <= 0)
    local seed = TerrainHandler.getSeedForPlayer(player.UserId, player.Name)
    print(string.format("[SEED] %s uid=%d -> seed=%d", player.Name, player.UserId, seed))

    -- Prepare per-player container (use seed to avoid collisions in Studio)
    local playerContainer = Instance.new("Folder")
    playerContainer.Name = tostring(seed)
    playerContainer.Parent = terrainsFolder

    -- Only generation + logs for now
    print("[TERRAIN] Generating terrain for player seed", seed)

    -- Build base plot + terrain contents (procedural)
    local plot = TerrainHandler.ensurePlayerPlotForSeed(seed, playerContainer)
    TerrainHandler.generateInitialTerrainForSeed(seed, plot)

    -- Teleport player to their plot on spawn (prefer SpawnPoint inside Plot)
    local spawnCFrame = (function()
        local plotModel = playerContainer:FindFirstChild("Plot")
        if plotModel and plotModel:IsA("Model") then
            local spawnPart = plotModel:FindFirstChild("SpawnPoint", true)
            if spawnPart and spawnPart:IsA("BasePart") then
                print("[SPAWN] Using Plot.SpawnPoint for", player.Name)
                return spawnPart.CFrame + Vector3.new(0, 3, 0)
            end
        end
        print("[SPAWN] Using plot center for", player.Name)
        return TerrainHandler.getSpawnCFrameForSeed(seed)
    end)()
    do
        local p = spawnCFrame.Position
        print(string.format("[SPAWN] %s spawn at (%.1f, %.1f, %.1f)", player.Name, p.X, p.Y, p.Z))
    end
    local function teleport(char: Model)
        local hrp = char:WaitForChild("HumanoidRootPart", 10)
        if hrp then
            hrp.CFrame = spawnCFrame
        end
    end
    player.CharacterAdded:Connect(function(char)
        teleport(char)
    end)
    if player.Character then teleport(player.Character) end
end

local function onPlayerRemoving(player: Player)
    print(string.format("[LEAVE] Player %s (%d) leaving.", player.Name, player.UserId))
    -- Clean player container
    local seed = TerrainHandler.getSeedForPlayer(player.UserId, player.Name)
    local container = terrainsFolder:FindFirstChild(tostring(seed))
    if container then
        container:Destroy()
    end
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

-- Publish specs for clients and start hoe placement service
SpecsPublisher.publish()
HoeService.start()

print("[BOOT] Server systems initialized (Terrain/Hoe)")

-- In-memory state: simple per-player chopping guard
local choppingState: {[number]: boolean} = {}
local hoePending: {[number]: {[string]: boolean}} = {}

local function getWorldCenter(inst: Instance): (Vector3?)
    if inst:IsA("BasePart") then
        return (inst :: BasePart).Position
    elseif inst:IsA("Model") then
        local m = inst :: Model
        local cf, size = m:GetBoundingBox()
        return cf.Position
    end
    return nil
end

local function getPlayerPlot(player: Player)
    local seed = TerrainHandler.getSeedForPlayer(player.UserId, player.Name)
    local container = terrainsFolder:FindFirstChild(tostring(seed))
    if not container then return nil end
    local plot = container:FindFirstChild("Plot")
    return plot
end

local function getPlotBaseAndGround(plot: Instance): (Vector3?, BasePart?)
    if not plot or not plot:IsA("Model") then return nil, nil end
    local ground = plot:FindFirstChild("Ground", true)
    if ground and ground:IsA("BasePart") then
        local size = ground.Size
        local pos = ground.Position
        local baseOffset = Vector3.new(pos.X - size.X/2, 0, pos.Z - size.Z/2)
        return baseOffset, ground
    end
    -- fallback: use PrimaryPart or bounding box
    local m = plot
    local cf, size = m:GetBoundingBox()
    local baseOffset = Vector3.new(cf.Position.X - size.X/2, 0, cf.Position.Z - size.Z/2)
    return baseOffset, nil
end

local CELL_SIZE = Config.CellSize
local GRID_SIZE = Config.GridSize

local function inBox(cf: CFrame, size: Vector3, worldPos: Vector3, margin: number?): boolean
    local lp = cf:PointToObjectSpace(worldPos)
    local m = margin or 0
    return math.abs(lp.X) <= size.X/2 + m and math.abs(lp.Z) <= size.Z/2 + m
end

-- Hoe handler
HoeRequest.OnServerEvent:Connect(function(player: Player, cellX: number, cellZ: number)
    local plot = getPlayerPlot(player)
    if not plot then return end
    if cellX < 1 or cellX > GRID_SIZE or cellZ < 1 or cellZ > GRID_SIZE then
        HoeFeedback:FireClient(player, "Invalid", "OutOfBounds")
        return
    end
    local baseOffset, ground = getPlotBaseAndGround(plot)
    if not baseOffset then return end
    local center = baseOffset + Vector3.new((cellX-0.5)*CELL_SIZE, 0, (cellZ-0.5)*CELL_SIZE)
    local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
    if not hrp or (hrp.Position - center).Magnitude > 12 then
        HoeFeedback:FireClient(player, "Invalid", "TooFar")
        return
    end
    -- Build exclusion boxes
    local excludeBoxes = {}
    local function addBoxFromModel(m: Model, margin: number?)
        local cf, size = m:GetBoundingBox()
        table.insert(excludeBoxes, { cf = cf, size = size, m = margin or 0 })
    end
    local function addBoxFromPart(p: BasePart, margin: number?)
        table.insert(excludeBoxes, { cf = p.CFrame, size = p.Size, m = margin or 0 })
    end
    local house = plot:FindFirstChild("House", true)
    if house and house:IsA("Model") then addBoxFromModel(house, 1.0) end
    for _, inst in ipairs(plot:GetDescendants()) do
        if inst:IsA("BasePart") and (inst.Name == "NoGenerate" or inst.Name == "NoTreesBox" or inst.Name == "TreeBlocker" or inst.Name == "NoSpawnBox") then
            addBoxFromPart(inst, 0.5)
        end
    end
    local gen = plot:FindFirstChild("Generated")
    if gen then
        local function addBoxFromFolder(folderName: string)
            local f = gen:FindFirstChild(folderName)
            if not f then return end
            for _, child in ipairs(f:GetChildren()) do
                if child:IsA("Model") then
                    local cf2, size2 = child:GetBoundingBox()
                    table.insert(excludeBoxes, { cf = cf2, size = size2, m = 0.2 })
                elseif child:IsA("BasePart") then
                    table.insert(excludeBoxes, { cf = child.CFrame, size = child.Size, m = 0.2 })
                end
            end
        end
        addBoxFromFolder("Trees")
        addBoxFromFolder("Rocks")
    end
    for _, b in ipairs(excludeBoxes) do
        if (function(cf, size, worldPos, margin)
            local lp = cf:PointToObjectSpace(worldPos)
            local m = margin or 0
            return math.abs(lp.X) <= size.X/2 + m and math.abs(lp.Z) <= size.Z/2 + m
        end)(b.cf, b.size, center, b.m) then
            HoeFeedback:FireClient(player, "Invalid", "Blocked")
            return
        end
--[[ HoeRequest handler moved to HoeService: disabled
    end
    -- Prevent duplicate tilling on same tile (reserve)
    local seed = TerrainHandler.getSeedForPlayer(player.UserId, player.Name)
    hoePending[seed] = hoePending[seed] or {}
    local key = string.format("%d,%d", cellX, cellZ)
    local soilFolderExisting = plot:FindFirstChild("Soil")
    if (soilFolderExisting and soilFolderExisting:FindFirstChild("Soil_"..key)) or hoePending[seed][key] then
        HoeFeedback:FireClient(player, "Invalid", "Already")
        return
    end
    hoePending[seed][key] = true

    -- Duration + cancel-on-move
    local duration = Tools.getActionTime("Hoe", 1)
    HoeFeedback:FireClient(player, "ActionStarted", duration)
    local startPos = hrp.Position
    local MAX_RANGE = 16
    local MOVE_CANCEL = 5
    local startTime = os.clock()
    task.spawn(function()
        local canceled = false
        while os.clock() - startTime < duration do
            task.wait(0.05)
            local c = player.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if not r then canceled = true break end
            if (r.Position - center).Magnitude > MAX_RANGE or (r.Position - startPos).Magnitude > MOVE_CANCEL then
                canceled = true
                break
            end
        end
        if canceled then
            HoeFeedback:FireClient(player, "Invalid", "Moved")
            if hoePending[seed] then hoePending[seed][key] = nil end
            return
        end
        -- Place soil
        local soilFolder = plot:FindFirstChild("Soil")
        if not soilFolder then soilFolder = Instance.new("Folder"); soilFolder.Name = "Soil"; soilFolder.Parent = plot end
        local name = string.format("Soil_%d,%d", cellX, cellZ)
        if soilFolder:FindFirstChild(name) then
            HoeFeedback:FireClient(player, "Invalid", "Already")
            if hoePending[seed] then hoePending[seed][key] = nil end
            return
        end
        local groundY = (ground and ground.Position.Y) or 0
        local dirtTemplate = game:GetService("ServerStorage"):FindFirstChild("Dirt")
        if dirtTemplate then
            local inst = dirtTemplate:Clone(); inst.Name = name
            if inst:IsA("Model") then
                if not inst.PrimaryPart then inst.PrimaryPart = inst:FindFirstChildWhichIsA("BasePart", true) end
                local cf3, size3 = inst:GetBoundingBox()
                local bottomY = cf3.Position.Y - size3.Y/2
                local deltaY = groundY - bottomY + 0.01
                local newPos = Vector3.new(center.X, cf3.Position.Y + deltaY, center.Z)
                inst:PivotTo(CFrame.new(newPos))
                inst.Parent = soilFolder
            elseif inst:IsA("BasePart") then
                inst.Anchored = true
                inst.Position = Vector3.new(center.X, groundY + inst.Size.Y/2 + 0.01, center.Z)
                inst.Parent = soilFolder
            else
                inst.Parent = soilFolder
            end
        else
            local soil = Instance.new("Part")
            soil.Name = name
            soil.Anchored = true
            soil.Material = Enum.Material.Ground
            soil.Color = Color3.fromRGB(125, 86, 62)
            soil.Size = Vector3.new(CELL_SIZE, 0.5, CELL_SIZE)
            soil.Position = Vector3.new(center.X, groundY + 0.25, center.Z)
            soil.Parent = soilFolder
        end
        HoeFeedback:FireClient(player, "Placed", cellX, cellZ)
        if hoePending[seed] then hoePending[seed][key] = nil end
    end)
end)


-- Validate if instance is player's own tree and return the model to remove
local function resolvePlayerResource(player: Player, inst: Instance): (string, Instance?)
    if not inst then return "", nil end
    local seed = TerrainHandler.getSeedForPlayer(player.UserId, player.Name)
    local container = terrainsFolder:FindFirstChild(tostring(seed))
    if not container then return "", nil end
    local plot = container:FindFirstChild("Plot")
    if not plot then return "", nil end
    local gen = plot:FindFirstChild("Generated")
    if not gen then return "", nil end

    local target = inst
    -- Trees
    local treesFolder = gen:FindFirstChild("Trees")
    if treesFolder then
        if target:IsA("BasePart") and target.Parent and target.Parent:IsA("Model") and target.Parent.Parent == treesFolder then
            return "tree", target.Parent
        end
        if target:IsA("Model") and target.Parent == treesFolder then
            return "tree", target
        end
        if target:IsA("BasePart") and target.Parent == treesFolder then
            return "tree", target
        end
    end
    -- Rocks
    local rocksFolder = gen:FindFirstChild("Rocks")
    if rocksFolder then
        if target:IsA("BasePart") and target.Parent and target.Parent:IsA("Model") and target.Parent.Parent == rocksFolder then
            return "rock", target.Parent
        end
        if target:IsA("Model") and target.Parent == rocksFolder then
            return "rock", target
        end
        if target:IsA("BasePart") and target.Parent == rocksFolder then
            return "rock", target
        end
    end
    -- Soil (allow BasePart inside Model under Soil)
    local soilFolder = plot:FindFirstChild("Soil")
    if soilFolder then
        if inst:IsA("BasePart") and inst.Parent and inst.Parent:IsA("Model") and inst.Parent.Parent == soilFolder then
            return "soil", inst.Parent
        end
        if inst:IsA("BasePart") and inst.Parent == soilFolder then
            return "soil", inst
        end
        if inst:IsA("Model") and inst.Parent == soilFolder then
            return "soil", inst
        end
    end
    return "", nil
end

ChopRequest.OnServerEvent:Connect(function(player: Player, toolId: string, target: Instance)
    if choppingState[player.UserId] then
        return
    end
    local resourceType, resource = resolvePlayerResource(player, target)
    if resourceType == "" or not resource then
        return
    end
    -- Validate tool vs resource
    local required = Tools.requiredToolForResource(resourceType)
    if string.lower(required) ~= string.lower(toolId or "") then
        return
    end
    choppingState[player.UserId] = true
    -- Range check and movement cancel
    local pos = getWorldCenter(resource)
    local char = player.Character
    local hrp: BasePart? = char and (char:FindFirstChild("HumanoidRootPart") :: BasePart)
    if not pos or not hrp then
        choppingState[player.UserId] = nil
        return
    end
    local MAX_RANGE = 16
    if (hrp.Position - pos).Magnitude > MAX_RANGE then
        choppingState[player.UserId] = nil
        ChopFeedback:FireClient(player, "ActionCanceled", "OutOfRange")
        return
    end
    local duration = Tools.getActionTime(required, 1)
    print(string.format("[TOOL] %s using %s on %s (%s) for %.2fs", player.Name, required, (resource :: any).Name, resourceType, duration))
    ChopFeedback:FireClient(player, "ActionStarted", resourceType, duration)

    local startPos = hrp.Position
    local MOVE_CANCEL = 5 -- studs
    local startTime = os.clock()
    local canceled = false
    task.spawn(function()
        while os.clock() - startTime < duration do
            task.wait(0.05)
            if not player.Parent then canceled = true break end
            local c = player.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if not r then canceled = true break end
            if (r.Position - pos).Magnitude > MAX_RANGE or (r.Position - startPos).Magnitude > MOVE_CANCEL then
                canceled = true
                break
            end
            -- ensure resource still exists
            if not resource or not (resource :: any).Parent then
                canceled = true
                break
            end
        end
        if canceled then
            ChopFeedback:FireClient(player, "ActionCanceled", "Moved")
            choppingState[player.UserId] = nil
            return
]] -- end moved handler
        end
        -- success, remove resource
        if resource and (resource :: any).Parent then
            local inst: Instance = resource
            if inst:IsA("Model") then inst:Destroy() elseif inst:IsA("BasePart") then inst:Destroy() end
        end
        ChopFeedback:FireClient(player, "ActionCompleted", resourceType)
        choppingState[player.UserId] = nil
    end)
end)



