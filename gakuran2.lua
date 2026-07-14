-- by nezia_real on discord

--[[
    owe hub changer 12037429922
    Run once to show UI, run again to hide/show toggle.
]]

-- ── Toggle if already loaded ──────────────────────────────────────────────────
if _G.rbxlChangerGui then
    _G.rbxlChangerGui.Enabled = not _G.rbxlChangerGui.Enabled
    return
end
-- ─────────────────────────────────────────────────────────────────────────────

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LocalPlayer = Players.LocalPlayer
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local IMG_ON    = "rbxassetid://80859246859695"
local IMG_OFF   = "rbxassetid://118910998508788"
local IMG_MIN   = "rbxassetid://77150878131724"
local IMG_CLOSE = "rbxassetid://106889675931893"
local IMG_TITLE = "rbxassetid://12037429922"

local Character  = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
local CombatAnimationUtils = require(ReplicatedStorage.Shared.Utils.CombatAnimationUtils)
local PlayerData = Character:WaitForChild("PlayerData")
local Humanoid   = Character:WaitForChild("Humanoid")

local allStyles    = CombatAnimationUtils.GetAllCombatStyles()
local currentStyle = PlayerData:GetAttribute("CombatStyle") or "Basic"
local currentHeight = 50
local currentTab   = "styles"

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "rbxlChanger"
screenGui.ResetOnSpawn = false
screenGui.Parent = LocalPlayer:WaitForChild("PlayerGui")

-- Store reference globally so re-running toggles visibility
_G.rbxlChangerGui = screenGui

local W, H = 240, 340

local mainFrame = Instance.new("Frame")
mainFrame.Parent = screenGui
mainFrame.Size = UDim2.new(0, W, 0, H)
mainFrame.Position = UDim2.new(0.5, -W/2, 0.5, -H/2)
mainFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 22)
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Active = true
Instance.new("UICorner", mainFrame).CornerRadius = UDim.new(0, 8)

-- Title Bar
local titleBar = Instance.new("Frame")
titleBar.Parent = mainFrame
titleBar.Size = UDim2.new(1, 0, 0, 30)
titleBar.BackgroundColor3 = Color3.fromRGB(26, 26, 32)
titleBar.BorderSizePixel = 0
Instance.new("UICorner", titleBar).CornerRadius = UDim.new(0, 8)

-- Title icon
local titleIcon = Instance.new("ImageLabel")
titleIcon.Parent = titleBar
titleIcon.Size = UDim2.new(0, 18, 0, 18)
titleIcon.Position = UDim2.new(0, 6, 0.5, -9)
titleIcon.BackgroundTransparency = 1
titleIcon.Image = IMG_TITLE
titleIcon.ScaleType = Enum.ScaleType.Fit
titleIcon.BorderSizePixel = 0

local titleLabel = Instance.new("TextLabel")
titleLabel.Parent = titleBar
titleLabel.Size = UDim2.new(1, -88, 1, 0)
titleLabel.Position = UDim2.new(0, 28, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "rbxl.lua changer"
titleLabel.TextColor3 = Color3.fromRGB(230, 230, 230)
titleLabel.TextSize = 11
titleLabel.Font = Enum.Font.Code
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.TextYAlignment = Enum.TextYAlignment.Center
titleLabel.TextTruncate = Enum.TextTruncate.AtEnd

-- Min button
local minimized = false
local minBtn = Instance.new("ImageButton")
minBtn.Parent = titleBar
minBtn.Size = UDim2.new(0, 18, 0, 18)
minBtn.Position = UDim2.new(1, -42, 0.5, -9)
minBtn.BackgroundTransparency = 1
minBtn.Image = IMG_MIN
minBtn.ScaleType = Enum.ScaleType.Fit
minBtn.BorderSizePixel = 0

-- Close button (hides UI, keeps it re-runnable)
local closeBtn = Instance.new("ImageButton")
closeBtn.Parent = titleBar
closeBtn.Size = UDim2.new(0, 18, 0, 18)
closeBtn.Position = UDim2.new(1, -20, 0.5, -9)
closeBtn.BackgroundTransparency = 1
closeBtn.Image = IMG_CLOSE
closeBtn.ScaleType = Enum.ScaleType.Fit
closeBtn.BorderSizePixel = 0

-- Close now hides instead of destroying, so re-run can toggle it back
closeBtn.MouseButton1Click:Connect(function()
    screenGui.Enabled = false
end)

-- Drag
local dragging, dragStart, startPos = false, nil, nil
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging  = true
        dragStart = input.Position
        startPos  = mainFrame.Position
        input.Changed:Connect(function()
            if input.UserInputState == Enum.UserInputState.End then dragging = false end
        end)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local d = input.Position - dragStart
        mainFrame.Position = UDim2.new(
            startPos.X.Scale, startPos.X.Offset + d.X,
            startPos.Y.Scale, startPos.Y.Offset + d.Y
        )
    end
end)

-- Tab Bar
local tabBar = Instance.new("Frame")
tabBar.Parent = mainFrame
tabBar.Size = UDim2.new(1, -14, 0, 26)
tabBar.Position = UDim2.new(0, 7, 0, 33)
tabBar.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
tabBar.BorderSizePixel = 0
Instance.new("UICorner", tabBar).CornerRadius = UDim.new(0, 6)

do
    local tl = Instance.new("UIListLayout")
    tl.Parent = tabBar
    tl.FillDirection = Enum.FillDirection.Horizontal
    tl.Padding = UDim.new(0, 2)
    tl.SortOrder = Enum.SortOrder.LayoutOrder
    local tp = Instance.new("UIPadding")
    tp.Parent = tabBar
    tp.PaddingLeft   = UDim.new(0, 2)
    tp.PaddingRight  = UDim.new(0, 2)
    tp.PaddingTop    = UDim.new(0, 2)
    tp.PaddingBottom = UDim.new(0, 2)
end

local tabs = {}
local function setActiveTab(name)
    for n, btn in pairs(tabs) do
        if n == name then
            btn.BackgroundColor3 = Color3.fromRGB(46, 46, 58)
            btn.TextColor3 = Color3.fromRGB(255, 255, 255)
        else
            btn.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
            btn.TextColor3 = Color3.fromRGB(140, 140, 155)
        end
    end
end

for _, name in ipairs({"styles", "height"}) do
    local btn = Instance.new("TextButton")
    btn.Parent = tabBar
    btn.Size = UDim2.new(0.5, -2, 1, 0)
    btn.BackgroundColor3 = Color3.fromRGB(28, 28, 34)
    btn.Text = name
    btn.TextColor3 = Color3.fromRGB(140, 140, 155)
    btn.TextSize = 11
    btn.Font = Enum.Font.Code
    btn.BorderSizePixel = 0
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 5)
    tabs[name] = btn
end
setActiveTab("styles")

-- Scroll list
local SCROLL_TOP = 63
local styleList = Instance.new("ScrollingFrame")
styleList.Parent = mainFrame
styleList.Position = UDim2.new(0, 6, 0, SCROLL_TOP)
styleList.Size = UDim2.new(1, -12, 0, H - SCROLL_TOP - 6)
styleList.BackgroundTransparency = 1
styleList.BorderSizePixel = 0
styleList.ScrollBarThickness = 3
styleList.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 100)
styleList.ScrollingDirection = Enum.ScrollingDirection.Y
styleList.CanvasSize = UDim2.new(0, 0, 0, 0)
styleList.AutomaticCanvasSize = Enum.AutomaticSize.Y
styleList.ElasticBehavior = Enum.ElasticBehavior.Never

do
    local ul = Instance.new("UIListLayout")
    ul.Parent = styleList
    ul.Padding = UDim.new(0, 3)
    ul.SortOrder = Enum.SortOrder.LayoutOrder
    local up = Instance.new("UIPadding")
    up.Parent = styleList
    up.PaddingTop    = UDim.new(0, 3)
    up.PaddingBottom = UDim.new(0, 3)
    up.PaddingLeft   = UDim.new(0, 1)
    up.PaddingRight  = UDim.new(0, 1)
end

-- Style row
local function createStyleButton(styleName, isSelected)
    local row = Instance.new("Frame")
    row.Parent = styleList
    row.Name = styleName
    row.Size = UDim2.new(1, 0, 0, 30)
    row.BackgroundColor3 = Color3.fromRGB(24, 24, 30)
    row.BorderSizePixel = 0
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 5)

    local lbl = Instance.new("TextLabel")
    lbl.Parent = row
    lbl.Size = UDim2.new(1, -50, 1, 0)
    lbl.Position = UDim2.new(0, 10, 0, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = styleName:lower()
    lbl.TextColor3 = Color3.fromRGB(210, 210, 218)
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Code
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextYAlignment = Enum.TextYAlignment.Center

    local toggle = Instance.new("ImageLabel")
    toggle.Parent = row
    toggle.Size = UDim2.new(0, 30, 0, 16)
    toggle.Position = UDim2.new(1, -38, 0.5, -8)
    toggle.BackgroundTransparency = 1
    toggle.Image = isSelected and IMG_ON or IMG_OFF
    toggle.ScaleType = Enum.ScaleType.Fit
    toggle.BorderSizePixel = 0

    local hitbox = Instance.new("TextButton")
    hitbox.Parent = row
    hitbox.Size = UDim2.new(1, 0, 1, 0)
    hitbox.BackgroundTransparency = 1
    hitbox.Text = ""
    hitbox.ZIndex = 3
    hitbox.BorderSizePixel = 0

    hitbox.MouseButton1Click:Connect(function()
        local newStyle = (currentStyle == styleName) and "Basic" or styleName
        PlayerData:SetAttribute("CombatStyle", newStyle)
        currentStyle = newStyle
        UpdateTabContent("styles")
    end)
end

local function createHeightSlider()
    local KNOB_D = 16
    local KNOB_R = KNOB_D / 2
    local SIDE   = KNOB_R + 4

    local container = Instance.new("Frame")
    container.Parent = styleList
    container.Size = UDim2.new(1, 0, 0, 80)
    container.BackgroundTransparency = 1
    container.BorderSizePixel = 0
    container.ClipsDescendants = false

    local lbl = Instance.new("TextLabel")
    lbl.Name = "HeightLabel"
    lbl.Parent = container
    lbl.Size = UDim2.new(1, 0, 0, 20)
    lbl.Position = UDim2.new(0, 0, 0, 2)
    lbl.BackgroundTransparency = 1
    lbl.Text = "height: " .. math.floor(currentHeight) .. "%"
    lbl.TextColor3 = Color3.fromRGB(210, 210, 218)
    lbl.TextSize = 11
    lbl.Font = Enum.Font.Code
    lbl.TextXAlignment = Enum.TextXAlignment.Center

    local track = Instance.new("Frame")
    track.Parent = container
    track.Size = UDim2.new(1, -(SIDE * 2), 0, 4)
    track.Position = UDim2.new(0, SIDE, 0, 34)
    track.BackgroundColor3 = Color3.fromRGB(50, 50, 62)
    track.BorderSizePixel = 0
    Instance.new("UICorner", track).CornerRadius = UDim.new(0, 2)

    local fill = Instance.new("Frame")
    fill.Parent = track
    fill.Size = UDim2.new(currentHeight / 100, 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(160, 160, 200)
    fill.BorderSizePixel = 0
    Instance.new("UICorner", fill).CornerRadius = UDim.new(0, 2)

    local knob = Instance.new("Frame")
    knob.Parent = container
    knob.Size = UDim2.new(0, KNOB_D, 0, KNOB_D)
    knob.AnchorPoint = Vector2.new(0.5, 0.5)
    knob.BackgroundColor3 = Color3.fromRGB(210, 210, 220)
    knob.BorderSizePixel = 0
    knob.ZIndex = 4
    Instance.new("UICorner", knob).CornerRadius = UDim.new(0, KNOB_R)
    do
        local s = Instance.new("UIStroke")
        s.Parent = knob
        s.Color = Color3.fromRGB(130, 130, 145)
        s.Thickness = 1.5
    end

    local indicator = Instance.new("TextLabel")
    indicator.Parent = container
    indicator.Size = UDim2.new(0, 36, 0, 14)
    indicator.AnchorPoint = Vector2.new(0.5, 0)
    indicator.BackgroundTransparency = 1
    indicator.TextColor3 = Color3.fromRGB(180, 180, 200)
    indicator.TextSize = 9
    indicator.Font = Enum.Font.Code
    indicator.TextXAlignment = Enum.TextXAlignment.Center
    indicator.ZIndex = 4

    local function applyFrac(frac)
        frac = math.clamp(frac, 0, 1)
        local p = math.floor(frac * 100)
        fill.Size = UDim2.new(frac, 0, 1, 0)
        knob.Position      = UDim2.new(frac, SIDE * (1 - 2 * frac), 0, 36)
        indicator.Position = UDim2.new(frac, SIDE * (1 - 2 * frac), 0, 36 + KNOB_R + 3)
        indicator.Text = p .. "%"
        lbl.Text = "height: " .. p .. "%"
        currentHeight = p
    end

    local function updateFromX(x)
        local absX = track.AbsolutePosition.X
        local absW = track.AbsoluteSize.X
        if absW <= 0 then return end
        local frac = math.clamp((x - absX) / absW, 0, 1)
        applyFrac(frac)
        if Humanoid and Character then
            Character:ScaleTo(0.7 + frac * 0.6)
        end
    end

    applyFrac(currentHeight / 100)

    local hitbox = Instance.new("TextButton")
    hitbox.Parent = container
    hitbox.Size = UDim2.new(1, 0, 0, KNOB_D + 16)
    hitbox.Position = UDim2.new(0, 0, 0, 36 - KNOB_R - 8)
    hitbox.BackgroundTransparency = 1
    hitbox.Text = ""
    hitbox.ZIndex = 5
    hitbox.BorderSizePixel = 0

    hitbox.InputBegan:Connect(function(input)
        local isMouse = input.UserInputType == Enum.UserInputType.MouseButton1
        local isTouch = input.UserInputType == Enum.UserInputType.Touch
        if not (isMouse or isTouch) then return end

        styleList.ScrollingEnabled = false
        updateFromX(input.Position.X)

        local moveConn, endConn

        moveConn = UserInputService.InputChanged:Connect(function(inp)
            if inp == input or inp.UserInputType == Enum.UserInputType.MouseMovement then
                updateFromX(inp.Position.X)
            end
        end)

        endConn = UserInputService.InputEnded:Connect(function(inp)
            if inp == input or inp.UserInputType == Enum.UserInputType.MouseButton1 then
                styleList.ScrollingEnabled = true
                moveConn:Disconnect()
                endConn:Disconnect()
            end
        end)
    end)

    return container
end

function UpdateTabContent(tab)
    for _, c in ipairs(styleList:GetChildren()) do
        if not c:IsA("UIListLayout") and not c:IsA("UIPadding") then
            c:Destroy()
        end
    end
    if tab == "styles" then
        for _, name in ipairs(allStyles) do
            createStyleButton(name, name == currentStyle)
        end
    elseif tab == "height" then
        createHeightSlider()
    end
end

for name, btn in pairs(tabs) do
    btn.MouseButton1Click:Connect(function()
        currentTab = name
        setActiveTab(name)
        UpdateTabContent(name)
    end)
end

minBtn.MouseButton1Click:Connect(function()
    minimized = not minimized
    local targetH = minimized and 30 or H
    TweenService:Create(mainFrame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), {
        Size = UDim2.new(0, W, 0, targetH)
    }):Play()
    tabBar.Visible    = not minimized
    styleList.Visible = not minimized
end)

UpdateTabContent("styles")

LocalPlayer.CharacterAdded:Connect(function(newChar)
    Character  = newChar
    PlayerData = Character:WaitForChild("PlayerData")
    Humanoid   = Character:WaitForChild("Humanoid")
    currentStyle  = PlayerData:GetAttribute("CombatStyle") or "Basic"
    currentHeight = 50
    UpdateTabContent(currentTab)
end)
