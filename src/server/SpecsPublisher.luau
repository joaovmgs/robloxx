-- SpecsPublisher: publishes grid/tile specs under ReplicatedStorage for clients
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local SpecsPublisher = {}

local function ensureFolder()
    local f = ReplicatedStorage:FindFirstChild("Specs")
    if not f then
        f = Instance.new("Folder")
        f.Name = "Specs"
        f.Parent = ReplicatedStorage
    end
    return f
end

local function ensureNumber(parent: Instance, name: string, value: number)
    local nv = parent:FindFirstChild(name)
    if not nv then
        nv = Instance.new("NumberValue")
        nv.Name = name
        nv.Parent = parent
    end
    (nv :: any).Value = value
end

function SpecsPublisher.publish()
    local specs = ensureFolder()

    -- Grid specs
    ensureNumber(specs, "GridCellSize", Config.CellSize)
    ensureNumber(specs, "GridSize", Config.GridSize)

    -- Dirt/tile specs (from template if present, otherwise Config)
    local sizeX, sizeZ, height = Config.CellSize, Config.CellSize, Config.TileThickness
    local dirt = ServerStorage:FindFirstChild(Config.TileModelName)
    if dirt then
        if dirt:IsA("Model") then
            local cf, size = dirt:GetBoundingBox()
            sizeX, sizeZ, height = size.X, size.Z, size.Y
        elseif dirt:IsA("BasePart") then
            sizeX, sizeZ, height = dirt.Size.X, dirt.Size.Z, dirt.Size.Y
        end
    end
    ensureNumber(specs, "DirtSizeX", sizeX)
    ensureNumber(specs, "DirtSizeZ", sizeZ)
    ensureNumber(specs, "DirtHeight", height)
end

return SpecsPublisher

