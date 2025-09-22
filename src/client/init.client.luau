-- Client bootstrap: hotbar with Axe and chopping progress UI
print("Hello world, from client!")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared:WaitForChild("Remotes"))
local HoePreview = require(script:WaitForChild("HoePreview"))
local ChopRequest: RemoteEvent = Remotes.get("ChopRequest")
local ChopFeedback: RemoteEvent = Remotes.get("ChopFeedback")

-- Simple inventory state
local selectedTool = "Axe"
local isChopping = false

-- UI: Hotbar and progress bar
local playerGui = player:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "HUD"
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local hotbar = Instance.new("Frame")
hotbar.Name = "Hotbar"
hotbar.Size = UDim2.new(0, 320, 0, 52)
hotbar.Position = UDim2.new(0.5, -160, 1, -72)
hotbar.AnchorPoint = Vector2.new(0.5, 0)
hotbar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
hotbar.BackgroundTransparency = 0.1
hotbar.BorderSizePixel = 0
hotbar.Parent = screenGui

local hbCorner = Instance.new("UICorner")
hbCorner.CornerRadius = UDim.new(0, 8)
hbCorner.Parent = hotbar

local uiList = Instance.new("UIListLayout")
uiList.FillDirection = Enum.FillDirection.Horizontal
uiList.Padding = UDim.new(0, 10)
uiList.HorizontalAlignment = Enum.HorizontalAlignment.Center
uiList.VerticalAlignment = Enum.VerticalAlignment.Center
uiList.SortOrder = Enum.SortOrder.LayoutOrder
uiList.Parent = hotbar

local iconsFolder = ReplicatedStorage:FindFirstChild("Icons")

local function applySlotStyle(btn: TextButton, isSelected: boolean)
    btn.BackgroundColor3 = isSelected and Color3.fromRGB(40, 110, 60) or Color3.fromRGB(45, 45, 45)
    local stroke = btn:FindFirstChildOfClass("UIStroke")
    if not stroke then
        stroke = Instance.new("UIStroke")
        stroke.Thickness = 2
        stroke.Parent = btn
    end
    stroke.Enabled = isSelected
    stroke.Color = isSelected and Color3.fromRGB(80, 200, 120) or Color3.fromRGB(80, 80, 80)
end

local function makeSlot(name: string, selected: boolean, hotkeyText: string, order: number)
    local b = Instance.new("TextButton")
    b.Name = name
    b.Size = UDim2.new(0, 96, 0, 40)
    b.LayoutOrder = order or 0
    b.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    b.AutoButtonColor = true
    b.Text = ""
    b.TextTransparency = 1
    b.Parent = hotbar
    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0, 6); corner.Parent = b
    local stroke = Instance.new("UIStroke"); stroke.Thickness = 2; stroke.Color = Color3.fromRGB(80,80,80); stroke.Parent = b

    local container = Instance.new("Frame"); container.Size = UDim2.new(1, -10, 1, -10); container.Position = UDim2.new(0,5,0,5); container.BackgroundTransparency=1; container.Parent = b
    local icon = Instance.new("ImageLabel"); icon.BackgroundTransparency = 1; icon.Size = UDim2.new(0, 20, 0, 20); icon.Position = UDim2.new(0, 0, 0.5, -10); icon.Parent = container
    local label = Instance.new("TextLabel"); label.BackgroundTransparency = 1; label.Size = UDim2.new(1, -26, 1, 0); label.Position = UDim2.new(0, 26, 0, 0); label.TextXAlignment = Enum.TextXAlignment.Left; label.Font = Enum.Font.Gotham; label.TextColor3 = Color3.new(1,1,1); label.TextScaled = true; label.Text = name; label.Parent = container
    local keyLbl = Instance.new("TextLabel"); keyLbl.BackgroundTransparency = 1; keyLbl.Size = UDim2.new(0, 20, 0, 16); keyLbl.Position = UDim2.new(1, -22, 0, -6); keyLbl.Text = hotkeyText; keyLbl.Font = Enum.Font.GothamBold; keyLbl.TextColor3 = Color3.fromRGB(180,180,180); keyLbl.TextScaled = true; keyLbl.Parent = b

    if iconsFolder then
        local img = iconsFolder:FindFirstChild(name)
        if img and img:IsA("ImageLabel") then
            icon.Image = img.Image
        elseif img and img:IsA("Decal") then
            icon.Image = img.Texture
        end
    end

    applySlotStyle(b, selected)

    b.MouseButton1Click:Connect(function()
        selectedTool = name
        for _, child in ipairs(hotbar:GetChildren()) do
            if child:IsA("TextButton") then
                applySlotStyle(child, child == b)
            end
        end
        if name == "Hoe" then
            HoePreview.enable()
        else
            HoePreview.disable()
        end
    end)
end

makeSlot("Axe", true, "1", 1)
makeSlot("Pickaxe", false, "2", 2)
makeSlot("Hoe", false, "3", 3)

-- Hotkeys to switch tools
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.KeyCode == Enum.KeyCode.One then
        selectedTool = "Axe"
        HoePreview.disable()
    elseif input.KeyCode == Enum.KeyCode.Two then
        selectedTool = "Pickaxe"
        HoePreview.disable()
    elseif input.KeyCode == Enum.KeyCode.Three then
        selectedTool = "Hoe"
        HoePreview.enable()
    else
        return
    end
    for _, child in ipairs(hotbar:GetChildren()) do
        if child:IsA("TextButton") then
            applySlotStyle(child, child.Name == selectedTool)
        end
    end
end)

-- Progress bar
local progressFrame = Instance.new("Frame")
    progressFrame.Name = "Progress"
    progressFrame.Size = UDim2.new(0, 200, 0, 14)
    progressFrame.Position = UDim2.new(0.5, -100, 1, -90)
    progressFrame.AnchorPoint = Vector2.new(0.5, 0)
    progressFrame.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
    progressFrame.Visible = false
    progressFrame.Parent = screenGui

local bar = Instance.new("Frame")
    bar.BackgroundColor3 = Color3.fromRGB(46, 204, 113) -- green
    bar.Size = UDim2.new(0, 0, 1, 0)
    bar.Parent = progressFrame

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 6)
corner.Parent = progressFrame
local corner2 = Instance.new("UICorner")
corner2.CornerRadius = UDim.new(0, 6)
corner2.Parent = bar

local progressLabel = Instance.new("TextLabel")
progressLabel.Size = UDim2.new(1, 0, 1, 0)
progressLabel.BackgroundTransparency = 1
progressLabel.TextColor3 = Color3.new(1,1,1)
progressLabel.TextScaled = true
progressLabel.Font = Enum.Font.GothamBold
progressLabel.Text = ""
progressLabel.Parent = progressFrame

local function startProgress(duration)
    progressFrame.Visible = true
    bar.Size = UDim2.new(0, 0, 1, 0)
    local start = os.clock()
    isChopping = true
    task.spawn(function()
        while isChopping do
            local t = os.clock() - start
            local alpha = math.clamp(t / duration, 0, 1)
            bar.Size = UDim2.new(alpha, 0, 1, 0)
            if alpha >= 1 then break end
            task.wait(0.02)
        end
    end)
end

local function stopProgress()
    isChopping = false
    progressFrame.Visible = false
end

-- Hoe ghost preview handled by HoePreview; enable on selection

-- Input: click a tree while Axe is selected to chop
UserInputService.InputBegan:Connect(function(input, gp)
    if gp then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        if isChopping then return end
        local target = mouse.Target
        if not target then return end
        -- quick heuristic: tree names start with "Tree_" or parent model under Trees
        local ok = false
        if selectedTool == "Axe" then
            if target.Name:find("Tree_") == 1 then ok = true end
            if target.Parent and target.Parent:IsA("Model") and target.Parent.Name:find("Tree_") == 1 then ok = true end
        elseif selectedTool == "Pickaxe" then
            -- Rocks
            if target.Name:find("Rock_") == 1 then ok = true end
            if target.Parent and target.Parent:IsA("Model") and target.Parent.Name:find("Rock_") == 1 then ok = true end
            -- Soil (Dirt)
            if target.Name:find("Soil_") == 1 then ok = true end
            if target.Parent and target.Parent:IsA("Model") and target.Parent.Name:find("Soil_") == 1 then ok = true end
        elseif selectedTool == "Hoe" then
            ok = true
        end
        if not ok then return end
        if selectedTool == "Hoe" then
            HoePreview.tryPlace()
        else
            -- client-side proximity hint (server enforces too)
            local hrp = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
            if hrp then
                local resourcePos = target:IsA("BasePart") and target.Position or target.Parent and target.Parent:IsA("Model") and (target.Parent :: Model):GetBoundingBox().Position
                if resourcePos and (hrp.Position - resourcePos).Magnitude > 16 then
                    return
                end
            end
            ChopRequest:FireServer(selectedTool, target)
        end
    end
end)

-- optional sounds
local soundsFolder = ReplicatedStorage:FindFirstChild("Sounds")
local function playSound(name)
    if not soundsFolder then return end
    local s = soundsFolder:FindFirstChild(name)
    if s and s:IsA("Sound") then
        local clone = s:Clone()
        clone.Parent = workspace
        clone:Play()
        game:GetService("Debris"):AddItem(clone, 5)
    end
end

ChopFeedback.OnClientEvent:Connect(function(kind, arg1, arg2)
    if kind == "ActionStarted" then
        local resourceType = arg1 -- "tree" or "rock"
        local duration = arg2 or 2
        progressLabel.Text = (resourceType == "rock") and "Minerando..." or "Cortando..."
        startProgress(duration)
        if resourceType == "rock" then
            playSound("PickaxeHit")
        else
            playSound("AxeSwing")
        end
    elseif kind == "ActionCompleted" then
        stopProgress()
        local resourceType = arg1
        if resourceType == "rock" then
            playSound("RockBreak")
        else
            playSound("TreeFall")
        end
    elseif kind == "ActionCanceled" then
        stopProgress()
    end
end)

-- Hoe feedback
local HoeFeedback: RemoteEvent = Remotes.get("HoeFeedback")
HoeFeedback.OnClientEvent:Connect(function(kind, a, b)
    if kind == "Placed" then
        if hoeGhost then
            hoeGhost.Color = Color3.fromRGB(80, 220, 90)
            task.delay(0.15, function()
                if hoeGhost then hoeGhost.Color = Color3.fromRGB(60, 180, 75) end
            end)
        end
    elseif kind == "Invalid" then
        if hoeGhost then
            hoeGhost.Color = Color3.fromRGB(220, 60, 60)
            task.delay(0.15, function()
                if hoeGhost then hoeGhost.Color = Color3.fromRGB(60, 180, 75) end
            end)
        end
    end
end)


-- Hoe progress handling
local HoeFeedback2: RemoteEvent = Remotes.get("HoeFeedback")
HoeFeedback2.OnClientEvent:Connect(function(kind, a, b)
    if kind == "ActionStarted" then
        local duration = a or 1.5
        progressLabel.Text = "Arando..."
        startProgress(duration)
    elseif kind == "Placed" then
        stopProgress()
    elseif kind == "Invalid" then
        stopProgress()
        if hoeGhost then
            hoeGhost.Color = Color3.fromRGB(220, 60, 60)
            task.delay(0.15, function()
                if hoeGhost then hoeGhost.Color = Color3.fromRGB(60, 180, 75) end
            end)
        end
    end
end)
