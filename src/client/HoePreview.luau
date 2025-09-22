-- HoePreview: client-side ghost preview and input for hoe placement
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Grid = require(Shared:WaitForChild("Grid"))
local Remotes = require(Shared:WaitForChild("Remotes"))

local HoeRequest = Remotes.get("HoeRequest")

local HoePreview = {}

local state = {
    enabled = false,
    ghost = nil :: BasePart?,
    gridCellSize = Config.CellSize,
    gridSize = Config.GridSize,
    tileHeight = Config.TileThickness,
}

local function readSpecs()
    local specs = ReplicatedStorage:FindFirstChild("Specs")
    if not specs then return end
    local gx = specs:FindFirstChild("GridCellSize")
    local gz = specs:FindFirstChild("GridSize")
    local th = specs:FindFirstChild("DirtHeight")
    if gx and gx:IsA("NumberValue") then state.gridCellSize = gx.Value end
    if gz and gz:IsA("NumberValue") then state.gridSize = gz.Value end
    if th and th:IsA("NumberValue") then state.tileHeight = th.Value end
end

local function getPlayerPlot(): Model?
    local terrains = workspace:FindFirstChild("PlayerTerrains")
    if not terrains then return nil end
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

local function getBaseOffsetAndGround(plot: Model): (Vector3, BasePart?)
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

local function ensureGhost(): BasePart
    if state.ghost and state.ghost.Parent then return state.ghost end
    local p = Instance.new("Part")
    p.Name = "HoeGhost"
    p.Anchored = true
    p.CanCollide = false
    p.CanQuery = false
    p.Transparency = Config.PreviewTransparencyOK
    p.Color = Config.PreviewGoodColor
    p.Material = Enum.Material.ForceField
    p.Size = Vector3.new(state.gridCellSize, math.max(0.2, math.min(1, state.tileHeight)), state.gridCellSize)
    p.Parent = workspace
    state.ghost = p
    return p
end

local curIx, curIz: number?, number?

local function setGhostVisual(ok: boolean)
    if not state.ghost then return end
    state.ghost.Color = ok and Config.PreviewGoodColor or Config.PreviewBadColor
    state.ghost.Transparency = ok and Config.PreviewTransparencyOK or Config.PreviewTransparencyBad
end

local stepConn: RBXScriptConnection? = nil

function HoePreview.enable()
    if state.enabled then return end
    state.enabled = true
    readSpecs()
    local ghost = ensureGhost()
    if stepConn then stepConn:Disconnect() end
    stepConn = RunService.RenderStepped:Connect(function()
        local plot = getPlayerPlot()
        if not plot then return end
        local baseOffset, ground = getBaseOffsetAndGround(plot)
        local worldPos = mouse.Hit and mouse.Hit.Position or nil
        if not worldPos then return end
        -- snap on XZ, use mouse Y as hint, server will raycast
        local snapped, ix, iz = Grid.snap(worldPos, baseOffset, state.gridCellSize, worldPos.Y)
        if ix < 1 or ix > state.gridSize or iz < 1 or iz > state.gridSize then
            setGhostVisual(false)
            curIx, curIz = nil, nil
            return
        end
        local groundY = (ground and ground.Position.Y) or 0
        local center = Vector3.new(snapped.X, groundY + state.tileHeight/2, snapped.Z)
        ghost.Size = Vector3.new(state.gridCellSize, math.max(0.2, math.min(1, state.tileHeight)), state.gridCellSize)
        ghost.CFrame = CFrame.new(center)
        curIx, curIz = ix, iz
        -- simplistic occupancy check by name
        local soil = plot:FindFirstChild("Soil") or plot:FindFirstChild("Tilled")
        local occupied = soil and soil:FindFirstChild(string.format("Soil_%d,%d", ix, iz)) ~= nil
        local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
        local near = hrp and ((hrp.Position - center).Magnitude <= Config.ToolMaxRange) or false
        setGhostVisual(near and not occupied)
    end)
end

function HoePreview.disable()
    state.enabled = false
    if stepConn then stepConn:Disconnect() end
    stepConn = nil
    if state.ghost then state.ghost:Destroy() end
    state.ghost = nil
    curIx, curIz = nil, nil
end

function HoePreview.tryPlace()
    if not curIx or not curIz then return end
    -- Fire with world position for server snap/raycast authority
    local worldPos = mouse.Hit and mouse.Hit.Position
    if not worldPos then return end
    HoeRequest:FireServer(worldPos)
end

return HoePreview

