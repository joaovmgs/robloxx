-- Remotes: consistent access/creation of RemoteEvents
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

local function ensureFolder()
    local f = ReplicatedStorage:FindFirstChild("Remotes")
    if RunService:IsServer() then
        if not f then
            f = Instance.new("Folder")
            f.Name = "Remotes"
            f.Parent = ReplicatedStorage
        end
    else
        f = ReplicatedStorage:WaitForChild("Remotes")
    end
    return f
end

local cache: { [string]: RemoteEvent } = {}

function Remotes.get(name: string): RemoteEvent
    if cache[name] then return cache[name] end
    local folder = ensureFolder()
    local ev = folder:FindFirstChild(name)
    if RunService:IsServer() then
        if not ev then
            ev = Instance.new("RemoteEvent")
            ev.Name = name
            ev.Parent = folder
        end
    else
        ev = folder:WaitForChild(name)
    end
    cache[name] = ev :: any
    return ev :: any
end

return Remotes

