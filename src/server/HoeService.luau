-- HoeService: grid-aligned tilling with occupancy and validation
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Grid = require(Shared:WaitForChild("Grid"))
local Remotes = require(Shared:WaitForChild("Remotes"))

export type PlotCtx = {
    model: Model,
    baseOffset: Vector3,
    groundY: number,
}

local HoeService = {}

local HoeRequest = Remotes.get("HoeRequest")
local HoeFeedback = Remotes.get("HoeFeedback")

-- Reserve operations per player/plot to avoid double placement during progress
local pending: { [number]: { [string]: boolean } } = {}

local function getPlotBaseAndGround(plot: Model): (Vector3?, BasePart?)
    local ground = plot:FindFirstChild("Ground", true)
    if ground and ground:IsA("BasePart") then
        local size = ground.Size
        local pos = ground.Position
        local baseOffset = Vector3.new(pos.X - size.X/2, 0, pos.Z - size.Z/2)
        return baseOffset, ground
    end
    local cf, size = plot:GetBoundingBox()
    local baseOffset = Vector3.new(cf.Position.X - size.X/2, 0, cf.Position.Z - size.Z/2)
    return baseOffset, nil
end

local function getPlayerPlot(player: Player): Model?
    local terrains = workspace:FindFirstChild("PlayerTerrains")
    if not terrains then return nil end
    -- player plots are stored under a folder named by seed in init.server
    -- Find the closest Plot to the player as a fallback
    local char = player.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    local best: Model? = nil
    local bestDist = math.huge
    for _, folder in ipairs(terrains:GetChildren()) do
        local plot = folder:FindFirstChild("Plot")
        if plot and plot:IsA("Model") then
            local ground = plot:FindFirstChild("Ground", true)
            local pos = ground and ground:IsA("BasePart") and ground.Position or plot:GetBoundingBox().Position
            if hrp then
                local d = (hrp.Position - pos).Magnitude
                if d < bestDist then bestDist = d; best = plot end
            else
                best = plot
            end
        end
    end
    return best
end

local function ensureSoilFolder(plot: Model): Folder
    local soil = plot:FindFirstChild(Config.TileName)
    if not soil then
        soil = Instance.new("Folder")
        soil.Name = Config.TileName
        soil.Parent = plot
    end
    return soil
end

local function placeTile(plot: Model, center: Vector3)
    local soil = ensureSoilFolder(plot)
    local dirtTemplate = ServerStorage:FindFirstChild(Config.TileModelName)
    if dirtTemplate then
        local inst = dirtTemplate:Clone()
        inst.Name = string.format("%s_%d", Config.TileModelName, math.floor(os.clock()*1000)%100000)
        if inst:IsA("Model") then
            inst:PivotTo(CFrame.new(center))
        elseif inst:IsA("BasePart") then
            local p = inst :: BasePart
            p.Anchored = true
            p.Position = center
        end
        inst.Parent = soil
        return inst
    else
        local p = Instance.new("Part")
        p.Name = "SoilTile"
        p.Anchored = true
        p.Size = Vector3.new(Config.CellSize, Config.TileThickness, Config.CellSize)
        p.Material = Enum.Material.Ground
        p.Color = Color3.fromRGB(101, 67, 33)
        p.Position = center
        p.Parent = soil
        return p
    end
end

local function isCellOccupied(plot: Model, ix: number, iz: number): boolean
    local soil = plot:FindFirstChild(Config.TileName)
    if not soil then return false end
    local key = Grid.key(ix, iz)
    -- tiles may be named Soil_x,z or nested; just check any child with suffix
    for _, child in ipairs(soil:GetChildren()) do
        if string.find(child.Name, key, 1, true) then
            return true
        end
    end
    return false
end

function HoeService.start()
    HoeRequest.OnServerEvent:Connect(function(player: Player, worldPos: Vector3)
        local plot = getPlayerPlot(player)
        if not plot then return end
        local baseOffset, ground = getPlotBaseAndGround(plot)
        if not baseOffset then return end

        -- Use raycast to compute ground Y at XZ
        local origin = Vector3.new(worldPos.X, 1000, worldPos.Z)
        local params = RaycastParams.new()
        params.FilterType = Enum.RaycastFilterType.Exclude
        if player.Character then params.FilterDescendantsInstances = { player.Character } end
        local hit = workspace:Raycast(origin, Vector3.new(0, -5000, 0), params)
        local groundY = (hit and hit.Position.Y) or (ground and ground.Position.Y) or 0

        local snapped, ix, iz = Grid.snap(worldPos, baseOffset, Config.CellSize, 0)
        if ix < 1 or ix > Config.GridSize or iz < 1 or iz > Config.GridSize then
            HoeFeedback:FireClient(player, "Invalid", "OutOfBounds")
            return
        end
        local center = Vector3.new(snapped.X, groundY + Config.TileThickness/2, snapped.Z)

        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        if not hrp or (hrp.Position - center).Magnitude > Config.ToolMaxRange then
            HoeFeedback:FireClient(player, "Invalid", "TooFar")
            return
        end

        local seed = player.UserId -- acceptable for reservation; can be improved with Terrain seed
        pending[seed] = pending[seed] or {}
        local key = Grid.key(ix, iz)
        if pending[seed][key] or isCellOccupied(plot, ix, iz) then
            HoeFeedback:FireClient(player, "Invalid", "Already")
            return
        end
        pending[seed][key] = true

        -- Simulate action progress on server; let client show progress too
        local duration = 1.2 -- consider using Tools.getActionTime("Hoe", level)
        HoeFeedback:FireClient(player, "ActionStarted", duration)

        local startPos = hrp.Position
        local startTime = os.clock()
        task.spawn(function()
            local canceled = false
            while os.clock() - startTime < duration do
                task.wait(0.05)
                local c = player.Character
                local r = c and c:FindFirstChild("HumanoidRootPart")
                if not r then canceled = true break end
                if (r.Position - center).Magnitude > Config.ToolMaxRange or (r.Position - startPos).Magnitude > Config.MoveCancelRange then
                    canceled = true
                    break
                end
            end
            if canceled then
                HoeFeedback:FireClient(player, "Invalid", "Moved")
                pending[seed][key] = nil
                return
            end

            if isCellOccupied(plot, ix, iz) then
                HoeFeedback:FireClient(player, "Invalid", "Already")
                pending[seed][key] = nil
                return
            end

            local inst = placeTile(plot, center)
            inst.Name = string.format("%s_%s", Config.TileName, key)
            HoeFeedback:FireClient(player, "Placed", ix, iz)
            pending[seed][key] = nil
        end)
    end)
end

return HoeService

