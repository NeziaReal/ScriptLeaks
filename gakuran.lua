--  by nezia_real (Discord)

-- Framework references
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local CoreGui = game:GetService("CoreGui")
local LocalPlayer = Players.LocalPlayer

-- Pointer Recovery Strategy
local callClientFunction
for _, sandbox in pairs(getgc(true)) do
    if type(sandbox) == "table" and rawget(sandbox, "callClientFunction") then
        callClientFunction = sandbox.callClientFunction
        break
    end
end

if not callClientFunction then
    local CombatSystemClient = ReplicatedStorage:WaitForChild("CombatSystemClient", 5)
    callClientFunction = function(actionType, moduleName, funcName, ...)
        local character = LocalPlayer.Character
        if not character then return end
        local playerData = character:FindFirstChild("PlayerData") or character:WaitForChild("PlayerData", 2)
        local combatType = playerData and playerData:GetAttribute("CombatType") or "Base"

        if CombatSystemClient then
            local folder = CombatSystemClient:FindFirstChild(actionType)
            local style = folder and folder:FindFirstChild(combatType)
            local mod = style and style:FindFirstChild(moduleName)
            if mod then
                local loaded = require(mod)
                if loaded and type(loaded[funcName]) == "function" then
                    return loaded[funcName](...)
                end
            end
        end
    end
end

-- Controls
local AutoDefenseActive = false
local AutoEvasiveActive = false
local AutoLookActive = false

local _lastGrappleEnd = 0
local POSTGRAPPLE_GRACE = 1.2

local MAX_REACH_DISTANCE = 14.0
local StrictCombatMovements = {}

local function indexStrictCombatAnimations()
    local animationsFolder = ReplicatedStorage:WaitForChild("Animations", 5)
    if not animationsFolder then return end

    local foldersToScan = {}
    local combatFolder = animationsFolder:FindFirstChild("Combat")
    if combatFolder then
        for _, f in pairs(combatFolder:GetChildren()) do
            table.insert(foldersToScan, f)
        end
    end
    local baseCombatDirect = animationsFolder:FindFirstChild("BaseCombat")
    if baseCombatDirect then
        table.insert(foldersToScan, baseCombatDirect)
    end

    for _, styleFolder in pairs(foldersToScan) do
        if styleFolder.Name == "BlunderFolder" or styleFolder.Name == "Blocks"
        or styleFolder.Name == "Emotes" or styleFolder.Name == "Dodges" then continue end

        for _, anim in pairs(styleFolder:GetDescendants()) do
            if not anim:IsA("Animation") or anim.AnimationId == "" then continue end
            local cleanId = string.match(anim.AnimationId, "%d+")
            if not cleanId then continue end
            local nameUpper = string.upper(anim.Name)
            local isM2   = not not (string.find(nameUpper, "M2") or string.find(nameUpper, "BREAK"))
            local isEHit = not not string.find(nameUpper, "EHIT")
            local isM1   = not not string.find(nameUpper, "M1")
            if isM2 or isEHit or isM1
            or string.find(nameUpper, "ATTACK")
            or string.find(nameUpper, "PUNCH")
            or string.find(nameUpper, "KICK") then
                StrictCombatMovements[cleanId] = {
                    Style      = styleFolder.Name,
                    Name       = anim.Name,
                    IsHeavy    = isM2,
                    IsEHit     = isEHit,
                    ComboIndex = tonumber(string.match(anim.Name, "^(%d+)")) or 1,
                }
            end
        end
    end
end
indexStrictCombatAnimations()

local function getEvasiveDirectionRelative(myHRP, enemyHRP)
    local headingVector = Vector3.new(enemyHRP.Position.X - myHRP.Position.X, 0, enemyHRP.Position.Z - myHRP.Position.Z)
    if headingVector.Magnitude < 0.1 then return "Forward" end
    headingVector = headingVector.Unit

    local localDirection = myHRP.CFrame:VectorToObjectSpace(headingVector)

    if math.abs(localDirection.Z) > math.abs(localDirection.X) then
        if localDirection.Z < 0 then return "Forward" else return "Backward" end
    else
        if localDirection.X < 0 then return "Left" else return "Right" end
    end
end

local FORCE_LOOK_PRIORITY = Enum.RenderPriority.Camera.Value + 1

local function forceLookAt(myHRP, enemyHRP, duration)
    if not myHRP or not enemyHRP then return end
    local bindName = "GSE_ForceLook_" .. tostring(math.random(1, 1e9))
    local startTime = os.clock()

    RunService:BindToRenderStep(bindName, FORCE_LOOK_PRIORITY, function()
        if not myHRP.Parent or not enemyHRP.Parent or (os.clock() - startTime) >= duration then
            RunService:UnbindFromRenderStep(bindName)
            return
        end
        local myChar = LocalPlayer.Character
        if myChar then
            if myChar:GetAttribute("Ragdoll") == true
            or myChar:GetAttribute("Downed") == true
            or myChar:GetAttribute("Stunned") == true
            or myChar:GetAttribute("Grappling") == true then
                RunService:UnbindFromRenderStep(bindName)
                return
            end
        end
        local targetPos = Vector3.new(enemyHRP.Position.X, myHRP.Position.Y, enemyHRP.Position.Z)
        myHRP.CFrame = CFrame.new(myHRP.Position, targetPos)
    end)
end

local VirtualInputManager = game:GetService("VirtualInputManager")

local AutoGripActive = false
local AutoCarryActive = false
local knockedActionDebounce = {}
local isActionInProgress = false

local function simulateKeyPress(keyCode, holdTime)
    holdTime = holdTime or 0.05
    VirtualInputManager:SendKeyEvent(true, keyCode, false, game)
    task.wait(holdTime)
    VirtualInputManager:SendKeyEvent(false, keyCode, false, game)
end

local function getDownedPlayerBelow(myHRP)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { LocalPlayer.Character }

    local result = workspace:Raycast(myHRP.Position, Vector3.new(0, -6, 0), rayParams)
    if not (result and result.Instance) then return nil end

    local char = result.Instance:FindFirstAncestorOfClass("Model")
    if not char then return nil end

    local plr = Players:GetPlayerFromCharacter(char)
    if plr and char:GetAttribute("Downed") == true then
        return plr, char
    end
    return nil
end

local function isAlreadyActionActive(myChar, actionType)
    if not myChar then return false end
    local states = myChar:FindFirstChild("States")
    if not states then return false end
    if actionType == "grip" then
        local beingGripped = states:FindFirstChild("BeingGripped")
        if beingGripped and beingGripped:IsA("ObjectValue") and beingGripped.Value ~= nil then return true end
    elseif actionType == "carry" then
        local beingCarried = states:FindFirstChild("BeingCarried")
        if beingCarried and beingCarried:IsA("ObjectValue") and beingCarried.Value ~= nil then return true end
    end
    return false
end

task.spawn(function()
    while true do
        task.wait(0.15)
        if not (AutoGripActive or AutoCarryActive) then
            isActionInProgress = false
            continue
        end

        local myChar = LocalPlayer.Character
        local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHRP then continue end

        local actionType = AutoGripActive and "grip" or "carry"
        if isAlreadyActionActive(myChar, actionType) then
            isActionInProgress = false
            continue
        end

        if isActionInProgress then continue end

        local targetPlr, targetChar = getDownedPlayerBelow(myHRP)
        if not targetPlr then
            isActionInProgress = false
            continue
        end

        local key = targetChar
        if knockedActionDebounce[key] and os.clock() - knockedActionDebounce[key] < 2 then continue end
        knockedActionDebounce[key] = os.clock()

        isActionInProgress = true

        if AutoGripActive then
            simulateKeyPress(Enum.KeyCode.B)
        elseif AutoCarryActive then
            simulateKeyPress(Enum.KeyCode.V)
        end

        task.wait(0.5)
        isActionInProgress = false
    end
end)

local AutoGrappleActive = false
local GRAPPLE_REACH_DISTANCE = 10.0

task.spawn(function()
    while true do
        task.wait(0.15)
        if not AutoGrappleActive then continue end

        local myChar = LocalPlayer.Character
        local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")
        if not myHRP or myChar:GetAttribute("M2Cooldown") == true then continue end

        local nearestEnemyHRP = nil
        local nearestDist = GRAPPLE_REACH_DISTANCE

        for _, plr in pairs(Players:GetPlayers()) do
            if plr == LocalPlayer then continue end
            local enemyChar = plr.Character
            local enemyHRP = enemyChar and enemyChar:FindFirstChild("HumanoidRootPart")
            if enemyHRP then
                local dist = (myHRP.Position - enemyHRP.Position).Magnitude
                if dist <= nearestDist then
                    nearestDist = dist
                    nearestEnemyHRP = enemyHRP
                end
            end
        end

if nearestEnemyHRP then
            if myChar:GetAttribute("Grappling") == true then continue end
            local states = myChar:FindFirstChild("States")
            local gripped = states and states:FindFirstChild("BeingGripped")
            if gripped and gripped:IsA("ObjectValue") and gripped.Value ~= nil then continue end
            pcall(function() callClientFunction("Combat", "M2", "OnM2Activated") end)
        end
    end
end)

local AutoAttackActive = false
local AUTO_ATTACK_REACH = 14.0
local autoAttackM1Holding = false

local function canAttack(myChar)
    if not myChar then return false end
    if myChar:GetAttribute("Ragdoll") == true then return false end
    if myChar:GetAttribute("Downed") == true then return false end
    if myChar:GetAttribute("Stunned") == true then return false end
    if myChar:GetAttribute("Blocking") == true then return false end
    local states = myChar:FindFirstChild("States")
    if states then
        local beingGripped = states:FindFirstChild("BeingGripped")
        if beingGripped and beingGripped:IsA("ObjectValue") and beingGripped.Value ~= nil then return false end
        local beingCarried = states:FindFirstChild("BeingCarried")
        if beingCarried and beingCarried:IsA("ObjectValue") and beingCarried.Value ~= nil then return false end
    end
    return true
end

local function getNearestEnemy(myHRP, maxDist)
    local nearest = nil
    local nearestDist = maxDist
    for _, plr in pairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local d = (myHRP.Position - hrp.Position).Magnitude
            if d < nearestDist then
                nearestDist = d
                nearest = hrp
            end
        end
    end
    return nearest, nearestDist
end

task.spawn(function()
    while true do
        task.wait(0.08)

        if not AutoAttackActive then
            if autoAttackM1Holding then
                pcall(function() callClientFunction("Combat", "M1", "Hold", "Stop") end)
                autoAttackM1Holding = false
            end
            continue
        end

        local myChar = LocalPlayer.Character
        local myHRP = myChar and myChar:FindFirstChild("HumanoidRootPart")

        if not myHRP or not canAttack(myChar) then
            if autoAttackM1Holding then
                pcall(function() callClientFunction("Combat", "M1", "Hold", "Stop") end)
                autoAttackM1Holding = false
            end
            continue
        end

        local enemyHRP, dist = getNearestEnemy(myHRP, AUTO_ATTACK_REACH)

      if enemyHRP then
            if myChar:GetAttribute("Grappling") == true then continue end
            local states = myChar:FindFirstChild("States")
            local gripped = states and states:FindFirstChild("BeingGripped")
            if gripped and gripped:IsA("ObjectValue") and gripped.Value ~= nil then continue end

            if not autoAttackM1Holding then
                pcall(function() callClientFunction("Combat", "M1", "Hold", "Start") end)
                autoAttackM1Holding = true
            end
            task.wait(0.18)
            pcall(function() callClientFunction("Combat", "M1", "Hold", "Stop") end)
            autoAttackM1Holding = false
            task.wait(0.05)
        else
            if autoAttackM1Holding then
                pcall(function() callClientFunction("Combat", "M1", "Hold", "Stop") end)
                autoAttackM1Holding = false
            end
        end
    end
end)

local function isCharacterDisabled(myChar)
    if not myChar then return true end
    if myChar:GetAttribute("Ragdoll") == true then return true end
    if myChar:GetAttribute("Downed") == true then return true end
    if myChar:GetAttribute("Stunned") == true then return true end
    local states = myChar:FindFirstChild("States")
    if states then
        local beingGripped = states:FindFirstChild("BeingGripped")
        if beingGripped and beingGripped:IsA("ObjectValue") and beingGripped.Value ~= nil then return true end
        local beingCarried = states:FindFirstChild("BeingCarried")
        if beingCarried and beingCarried:IsA("ObjectValue") and beingCarried.Value ~= nil then return true end
    end
    return false
end

local M1_BASE_DELAY = {
    BaseCombat=0.22, BasicAnims=0.22, BoxingAnims=0.19, CaipoeiraAnims=0.25,
    HakariAnims=0.21, HakariOtherAnims=0.21, KarateAnims=0.22, KureAnims=0.20,
    MuayThaiAnims=0.20, SluggerAnims=0.24, StrikerAnims=0.21, WrestlingAnims=0.28, Grappling=0.30,
}
local M2_BASE_DELAY = {
    BaseCombat=0.38, BasicAnims=0.38, BoxingAnims=0.32, CaipoeiraAnims=0.40,
    HakariAnims=0.35, HakariOtherAnims=0.35, KarateAnims=0.36, KureAnims=0.34,
    MuayThaiAnims=0.33, SluggerAnims=0.36, StrikerAnims=0.34, WrestlingAnims=0.42, Grappling=0.42,
}
local COMBO_SHAVE = {0, -0.015, -0.028, -0.038}

local function monitorAnimator(enemyPlayer, animator)
    animator.AnimationPlayed:Connect(function(track)
        if enemyPlayer == LocalPlayer then return end
        if not AutoDefenseActive and not AutoEvasiveActive then return end

        local trackId = string.match(track.Animation.AnimationId, "%d+")
        if not trackId then return end

        local moveData = StrictCombatMovements[trackId]
        if not moveData then return end

        local myChar  = LocalPlayer.Character
        local myHRP   = myChar and myChar:FindFirstChild("HumanoidRootPart")
        local enemyChar = enemyPlayer.Character
        local enemyHRP  = enemyChar and enemyChar:FindFirstChild("HumanoidRootPart")
        if not myHRP or not enemyHRP then return end
        if (myHRP.Position - enemyHRP.Position).Magnitude > MAX_REACH_DISTANCE then return end

        local isM2       = moveData.IsHeavy
        local isEHit     = moveData.IsEHit
        local comboIndex = moveData.ComboIndex
        local styleName  = moveData.Style

        local fired = false
        local markerConns = {}
        local stopConn
        local fallbackThread

        local function cleanup()
            for _, c in ipairs(markerConns) do pcall(c.Disconnect, c) end
            if stopConn then pcall(stopConn.Disconnect, stopConn) end
            if fallbackThread then pcall(task.cancel, fallbackThread) end
        end

      local function doDefense()
    if fired then return end
    fired = true
    cleanup()

    local mc = LocalPlayer.Character
    local mh = mc and mc:FindFirstChild("HumanoidRootPart")
    local ec = enemyPlayer.Character
    local eh = ec and ec:FindFirstChild("HumanoidRootPart")
    if not mh or not eh then return end
    if mc:GetAttribute("Grappling") == true then return end

    -- ADD THESE TWO checks
    local states = mc:FindFirstChild("States")
    if states then
        local beingGripped = states:FindFirstChild("BeingGripped")
        if beingGripped and beingGripped:IsA("ObjectValue") and beingGripped.Value ~= nil then return end
    end

    if AutoLookActive then
        forceLookAt(mh, eh, 0.35)
    else
        if mc:GetAttribute("Grappling") ~= true then
            mh.CFrame = CFrame.lookAt(mh.Position, Vector3.new(eh.Position.X, mh.Position.Y, eh.Position.Z))
        end
    end

    if AutoEvasiveActive then
        task.spawn(function()
            local c = LocalPlayer.Character
            if c:GetAttribute("EvasiveCooldown") then return end
            if c:GetAttribute("Grappling") == true then return end
            local dir = getEvasiveDirectionRelative(mh, eh)
            pcall(function() callClientFunction("Combat", "Evasive", "Evasive", dir) end)
        end)
    end

    if AutoDefenseActive then
        task.spawn(function()
            local c = LocalPlayer.Character
            if c:GetAttribute("Grappling") == true then return end
            local sigs = {
                {"Combat","Block","Block"},
                {"Combat","Block","OnBlockActivated"},
                {"Combat","Block","StartBlock"},
                {"Block","Block","Block"},
                {"Block","Block","OnBlockActivated"},
            }
            local worked = nil
            for _, s in ipairs(sigs) do
                local ok, err = pcall(function() callClientFunction(s[1], s[2], s[3]) end)
                if ok and not worked then worked = s end
            end
            local holdTime = isM2 and 0.55 or 0.25
            task.wait(holdTime)
            pcall(function() callClientFunction("Combat", "Block", "Unblock") end)
            pcall(function() callClientFunction("Combat", "Block", "OnBlockDeactivated") end)
            pcall(function() callClientFunction("Block", "Block", "Unblock") end)
        end)
    end
end

        for _, markerName in ipairs({"Hitbox", "Hit", "HitboxOpen", "Attack", "Strike", "Impact", "Fire"}) do
            local c = track:GetMarkerReachedSignal(markerName):Connect(function()
                doDefense()
            end)
            table.insert(markerConns, c)
        end

        stopConn = track.Stopped:Connect(cleanup)

        local fireAt
        if isM2 then
            fireAt = math.max(0.03, (M2_BASE_DELAY[styleName] or 0.37) - 0.045)
        else
            local base = M1_BASE_DELAY[styleName] or 0.22
            if isEHit then base = base * 0.82 end
            local shave = COMBO_SHAVE[math.clamp(comboIndex, 1, 4)] or -0.038
            fireAt = math.max(0.03, math.max(0.07, base + shave) - 0.045)
        end

        fallbackThread = task.delay(fireAt, doDefense)
    end)
end
local function setupPlayerTracking(player)
    if player == LocalPlayer then return end
    player.CharacterAdded:Connect(function(char)
        local humanoid = char:WaitForChild("Humanoid", 5)
        local animator = humanoid and humanoid:WaitForChild("Animator", 5)
        if animator then monitorAnimator(player, animator) end
    end)
    if player.Character then
        local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
        local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
        if animator then monitorAnimator(player, animator) end
    end
end

Players.PlayerAdded:Connect(setupPlayerTracking)
for _, p in pairs(Players:GetPlayers()) do setupPlayerTracking(p) end

--- GUI Setup
local IMG_ON   = "rbxassetid://80859246859695"
local IMG_OFF  = "rbxassetid://118910998508788"
local IMG_ICON = "rbxassetid://93199846992792"
local IMG_BG   = "rbxassetid://9395543464"
local IMG_MIN  = "rbxassetid://77150878131724"   -- minimize icon
local IMG_CLOSE = "rbxassetid://106889675931893" -- close icon
local FONT_PIX = Enum.Font.Code

local WIN = 260

local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "GakuranSplitEngineUI"
ScreenGui.Parent = CoreGui
ScreenGui.ResetOnSpawn = false
ScreenGui.DisplayOrder = 999

local MainFrame = Instance.new("Frame")
MainFrame.Name = "MainFrame"
MainFrame.Parent = ScreenGui
MainFrame.BackgroundColor3 = Color3.fromRGB(12, 12, 16)
MainFrame.BorderSizePixel = 0
MainFrame.Position = UDim2.new(0.05, 0, 0.3, 0)
MainFrame.Size = UDim2.new(0, WIN, 0, WIN)
MainFrame.Active = true
MainFrame.Draggable = true
MainFrame.ClipsDescendants = true

local BorderStroke = Instance.new("UIStroke")
BorderStroke.Color = Color3.fromRGB(80, 220, 80)
BorderStroke.Thickness = 2
BorderStroke.Parent = MainFrame

local BgImage = Instance.new("ImageLabel")
BgImage.Name = "BgPattern"
BgImage.Parent = MainFrame
BgImage.Size = UDim2.new(1, 0, 1, 0)
BgImage.Position = UDim2.new(0, 0, 0, 0)
BgImage.BackgroundTransparency = 1
BgImage.Image = IMG_BG
BgImage.ImageTransparency = 0.82
BgImage.ScaleType = Enum.ScaleType.Tile
BgImage.TileSize = UDim2.new(0, 64, 0, 64)
BgImage.ZIndex = 1

-- Title bar
local TitleBar = Instance.new("Frame")
TitleBar.Name = "TitleBar"
TitleBar.Parent = MainFrame
TitleBar.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
TitleBar.BorderSizePixel = 0
TitleBar.Size = UDim2.new(1, 0, 0, 34)
TitleBar.ZIndex = 3

local TitleBorderBottom = Instance.new("Frame")
TitleBorderBottom.Parent = TitleBar
TitleBorderBottom.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
TitleBorderBottom.BorderSizePixel = 0
TitleBorderBottom.Size = UDim2.new(1, 0, 0, 2)
TitleBorderBottom.Position = UDim2.new(0, 0, 1, -2)
TitleBorderBottom.ZIndex = 4

local TitleIcon = Instance.new("ImageLabel")
TitleIcon.Parent = TitleBar
TitleIcon.BackgroundTransparency = 1
TitleIcon.Size = UDim2.new(0, 22, 0, 22)
TitleIcon.Position = UDim2.new(0, 6, 0.5, -11)
TitleIcon.Image = IMG_ICON
TitleIcon.ScaleType = Enum.ScaleType.Fit
TitleIcon.ZIndex = 4

local TitleLabel = Instance.new("TextLabel")
TitleLabel.Parent = TitleBar
TitleLabel.BackgroundTransparency = 1
TitleLabel.Size = UDim2.new(1, -175, 1, 0)  -- narrower to make room for buttons
TitleLabel.Position = UDim2.new(0, 34, 0, 0)
TitleLabel.Font = FONT_PIX
TitleLabel.Text = "RBXL GAKURAN.LUA"
TitleLabel.TextColor3 = Color3.fromRGB(80, 220, 80)
TitleLabel.TextSize = 12
TitleLabel.TextXAlignment = Enum.TextXAlignment.Left
TitleLabel.TextYAlignment = Enum.TextYAlignment.Center
TitleLabel.ZIndex = 4

-- Minimize button
local MinBtn = Instance.new("ImageButton")
MinBtn.Name = "MinBtn"
MinBtn.Parent = TitleBar
MinBtn.BackgroundTransparency = 1
MinBtn.Size = UDim2.new(0, 22, 0, 22)
MinBtn.Position = UDim2.new(1, -52, 0.5, -11)
MinBtn.Image = IMG_MIN
MinBtn.ScaleType = Enum.ScaleType.Fit
MinBtn.ZIndex = 5

-- Close button
local CloseBtn = Instance.new("ImageButton")
CloseBtn.Name = "CloseBtn"
CloseBtn.Parent = TitleBar
CloseBtn.BackgroundTransparency = 1
CloseBtn.Size = UDim2.new(0, 22, 0, 22)
CloseBtn.Position = UDim2.new(1, -26, 0.5, -11)
CloseBtn.Image = IMG_CLOSE
CloseBtn.ScaleType = Enum.ScaleType.Fit
CloseBtn.ZIndex = 5

-- Minimize/restore logic
local isMinimized = false
local FULL_SIZE = UDim2.new(0, WIN, 0, WIN)
local MINI_SIZE = UDim2.new(0, WIN, 0, 34)

MinBtn.MouseButton1Click:Connect(function()
    isMinimized = not isMinimized
    if isMinimized then
        MainFrame.Size = MINI_SIZE
        MainFrame.ClipsDescendants = true
    else
        MainFrame.Size = FULL_SIZE
    end
end)

-- Close logic
CloseBtn.MouseButton1Click:Connect(function()
    ScreenGui:Destroy()
end)

-- Hover tint for minimize/close
MinBtn.MouseEnter:Connect(function() MinBtn.ImageColor3 = Color3.fromRGB(80, 255, 80) end)
MinBtn.MouseLeave:Connect(function() MinBtn.ImageColor3 = Color3.fromRGB(255, 255, 255) end)
CloseBtn.MouseEnter:Connect(function() CloseBtn.ImageColor3 = Color3.fromRGB(255, 80, 80) end)
CloseBtn.MouseLeave:Connect(function() CloseBtn.ImageColor3 = Color3.fromRGB(255, 255, 255) end)

-- Scroll frame
local ScrollFrame = Instance.new("ScrollingFrame")
ScrollFrame.Name = "ScrollFrame"
ScrollFrame.Parent = MainFrame
ScrollFrame.BackgroundTransparency = 1
ScrollFrame.BorderSizePixel = 0
ScrollFrame.Position = UDim2.new(0, 0, 0, 36)
ScrollFrame.Size = UDim2.new(1, 0, 1, -36)
ScrollFrame.ScrollBarThickness = 4
ScrollFrame.ScrollBarImageColor3 = Color3.fromRGB(80, 220, 80)
ScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
ScrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
ScrollFrame.ZIndex = 2
ScrollFrame.ClipsDescendants = true

local ListLayout = Instance.new("UIListLayout")
ListLayout.Parent = ScrollFrame
ListLayout.SortOrder = Enum.SortOrder.LayoutOrder
ListLayout.FillDirection = Enum.FillDirection.Vertical
ListLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
ListLayout.Padding = UDim.new(0, 6)

local ScrollPad = Instance.new("UIPadding")
ScrollPad.Parent = ScrollFrame
ScrollPad.PaddingTop = UDim.new(0, 8)
ScrollPad.PaddingBottom = UDim.new(0, 8)

local function makeToggle(labelText, order)
    local btn = Instance.new("TextButton")
    btn.Name = "Toggle_" .. labelText:gsub("%s", "")
    btn.Parent = ScrollFrame
    btn.Size = UDim2.new(0, WIN - 20, 0, 36)
    btn.BackgroundColor3 = Color3.fromRGB(18, 22, 18)
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Text = ""
    btn.LayoutOrder = order
    btn.ZIndex = 3

    local stroke = Instance.new("UIStroke")
    stroke.Color = Color3.fromRGB(40, 80, 40)
    stroke.Thickness = 1
    stroke.Parent = btn

    local lbl = Instance.new("TextLabel")
    lbl.Parent = btn
    lbl.BackgroundTransparency = 1
    lbl.Size = UDim2.new(1, -46, 1, 0)
    lbl.Position = UDim2.new(0, 8, 0, 0)
    lbl.Font = FONT_PIX
    lbl.Text = labelText
    lbl.TextColor3 = Color3.fromRGB(200, 230, 200)
    lbl.TextSize = 11
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.TextYAlignment = Enum.TextYAlignment.Center
    lbl.ZIndex = 4

    local img = Instance.new("ImageLabel")
    img.Parent = btn
    img.BackgroundTransparency = 1
    img.Size = UDim2.new(0, 28, 0, 28)
    img.Position = UDim2.new(1, -36, 0.5, -14)
    img.Image = IMG_OFF
    img.ScaleType = Enum.ScaleType.Fit
    img.ZIndex = 4

    return btn, img
end

local btn1, img1 = makeToggle("AUTO PARRY", 1)
btn1.MouseButton1Click:Connect(function()
    AutoDefenseActive = not AutoDefenseActive
    img1.Image = AutoDefenseActive and IMG_ON or IMG_OFF
    img1.ImageColor3 = AutoDefenseActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
    if not AutoDefenseActive then pcall(function() callClientFunction("Combat", "Block", "Unblock") end) end
end)

local btn2, img2 = makeToggle("AUTO DODGE", 2)
btn2.MouseButton1Click:Connect(function()
    AutoEvasiveActive = not AutoEvasiveActive
    img2.Image = AutoEvasiveActive and IMG_ON or IMG_OFF
    img2.ImageColor3 = AutoEvasiveActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
end)

local btn3, img3 = makeToggle("BLOCK ASSIST", 3)
btn3.MouseButton1Click:Connect(function()
    AutoLookActive = not AutoLookActive
    img3.Image = AutoLookActive and IMG_ON or IMG_OFF
    img3.ImageColor3 = AutoLookActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
end)

local btn4, img4 = makeToggle("AUTO GRIP", 4)
local btn5, img5 = makeToggle("AUTO CARRY", 5)

btn4.MouseButton1Click:Connect(function()
    AutoGripActive = not AutoGripActive
    if AutoGripActive then
        AutoCarryActive = false
        img5.Image = IMG_OFF
        img5.ImageColor3 = Color3.fromRGB(255, 255, 255)
    end
    img4.Image = AutoGripActive and IMG_ON or IMG_OFF
    img4.ImageColor3 = AutoGripActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
end)

btn5.MouseButton1Click:Connect(function()
    AutoCarryActive = not AutoCarryActive
    if AutoCarryActive then
        AutoGripActive = false
        img4.Image = IMG_OFF
        img4.ImageColor3 = Color3.fromRGB(255, 255, 255)
    end
    img5.Image = AutoCarryActive and IMG_ON or IMG_OFF
    img5.ImageColor3 = AutoCarryActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
end)

-- NO-SLOW logic (inlined)
local NoSlowActive = false
local _noSlowConn = nil

local function activateNoSlow()
    local myChar = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local hum = myChar:WaitForChild("Humanoid")
    local baseWalk = hum.WalkSpeed
    local baseJump = hum.JumpPower

    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
    hum:SetStateEnabled(Enum.HumanoidStateType.Physics, false)

    -- removed Ragdoll and Downed from here, they conflict with grapple client state
    local badAttrs = {"Stunned", "GuardBroken", "CantAnything"}

    _noSlowConn = RunService.Heartbeat:Connect(function()
        if not NoSlowActive then
            _noSlowConn:Disconnect()
            _noSlowConn = nil
            return
        end
        local char = LocalPlayer.Character
        local h = char and char:FindFirstChildOfClass("Humanoid")
        if not char or not h then return end

        -- skip everything if grapple is active
        if char:GetAttribute("Grappling") == true then
    _lastGrappleEnd = os.clock()
    return
end
if (os.clock() - _lastGrappleEnd) < POSTGRAPPLE_GRACE then return end
        local states = char:FindFirstChild("States")
        if states then
            local beingGripped = states:FindFirstChild("BeingGripped")
            if beingGripped and beingGripped:IsA("ObjectValue") and beingGripped.Value ~= nil then return end
        end

        if h.WalkSpeed ~= baseWalk then h.WalkSpeed = baseWalk end
        if h.JumpPower ~= baseJump then h.JumpPower = baseJump end
        if h.PlatformStand then h.PlatformStand = false end

        local st = h:GetState()
        if st == Enum.HumanoidStateType.Physics or st == Enum.HumanoidStateType.Ragdoll then
            h:ChangeState(Enum.HumanoidStateType.Running)
        end

        for _, attr in ipairs(badAttrs) do
            if char:GetAttribute(attr) == true then
                char:SetAttribute(attr, false)
            end
        end
    end)
end

local btn6, img6 = makeToggle("NO-SLOW", 6)
btn6.MouseButton1Click:Connect(function()
    NoSlowActive = not NoSlowActive
    img6.Image = NoSlowActive and IMG_ON or IMG_OFF
    img6.ImageColor3 = NoSlowActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
    if NoSlowActive then
        activateNoSlow()
    end
end)
btn6.MouseEnter:Connect(function() btn6.BackgroundColor3 = Color3.fromRGB(28, 40, 28) end)
btn6.MouseLeave:Connect(function() btn6.BackgroundColor3 = Color3.fromRGB(18, 22, 18) end)

-- NOCLIP logic (inlined)
local NoclipActive = false
local _noclipConn = nil
local _noclipChar = nil

local function _noclipSetup(char)
    _noclipChar = char
    if _noclipConn then _noclipConn:Disconnect() end
    _noclipConn = RunService.Heartbeat:Connect(function()
        if not NoclipActive or not _noclipChar then return end
        for _, part in ipairs(_noclipChar:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end)
end

local function _noclipRestore()
    if not _noclipChar then return end
    for _, part in ipairs(_noclipChar:GetDescendants()) do
        if part:IsA("BasePart") then
            part.CanCollide = true
        end
    end
end

do
    local c = LocalPlayer.Character
    if c then _noclipSetup(c) end
    LocalPlayer.CharacterAdded:Connect(function(char)
        task.wait(0.5)
        _noclipSetup(char)
    end)
end

local btn6b, img6b = makeToggle("NOCLIP", 6)  -- set order to whatever slot you want
btn6b.MouseButton1Click:Connect(function()
    NoclipActive = not NoclipActive
    img6b.Image = NoclipActive and IMG_ON or IMG_OFF
    img6b.ImageColor3 = NoclipActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
    if not NoclipActive then _noclipRestore() end
end)
btn6b.MouseEnter:Connect(function() btn6b.BackgroundColor3 = Color3.fromRGB(28, 40, 28) end)
btn6b.MouseLeave:Connect(function() btn6b.BackgroundColor3 = Color3.fromRGB(18, 22, 18) end)

local btn7, img7 = makeToggle("AUTO HEAVY", 7)
btn7.MouseButton1Click:Connect(function()
    AutoGrappleActive = not AutoGrappleActive
    img7.Image = AutoGrappleActive and IMG_ON or IMG_OFF
    img7.ImageColor3 = AutoGrappleActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
end)

local btn8, img8 = makeToggle("AUTO PUNCH", 8)
btn8.MouseButton1Click:Connect(function()
    AutoAttackActive = not AutoAttackActive
    img8.Image = AutoAttackActive and IMG_ON or IMG_OFF
    img8.ImageColor3 = AutoAttackActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
    if not AutoAttackActive then
        pcall(function() callClientFunction("Combat", "M1", "Hold", "Stop") end)
        autoAttackM1Holding = false
    end
end)

-- Hide Name toggle
local btn9, img9 = makeToggle("HIDE NAME", 9)

local hideNameActive = false
local hiddenBillboard = nil

local function findMyBillboard()
    local myChar = LocalPlayer.Character
    if not myChar then return nil end
    -- Look for Players folder inside the character model
    local playersFolder = myChar:FindFirstChild("Players")
    if playersFolder then
        local billboard = playersFolder:FindFirstChild("PlayerInfoBillboard")
        if billboard then return billboard end
    end
    -- Fallback: direct search
    return myChar:FindFirstChild("PlayerInfoBillboard", true)
end

local function setNameVisibility(visible)
    local bill = findMyBillboard()
    if bill then
        bill.Enabled = visible
        hiddenBillboard = bill
    end
end

btn9.MouseButton1Click:Connect(function()
    hideNameActive = not hideNameActive
    img9.Image = hideNameActive and IMG_ON or IMG_OFF
    img9.ImageColor3 = hideNameActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
    setNameVisibility(not hideNameActive)
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    if not hideNameActive then return end
    local playersFolder = char:WaitForChild("Players", 10)
    if not playersFolder then return end
    local billboard = playersFolder:WaitForChild("PlayerInfoBillboard", 10)
    if billboard then
        billboard.Enabled = false
    end
end)

-- Add btn9 to hover list
btn9.MouseEnter:Connect(function() btn9.BackgroundColor3 = Color3.fromRGB(28, 40, 28) end)
btn9.MouseLeave:Connect(function() btn9.BackgroundColor3 = Color3.fromRGB(18, 22, 18) end)

local AutoRestartActive = false

local function doAutoRestart()
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    
    task.spawn(function()
        while AutoRestartActive do
            local deathUI = playerGui:FindFirstChild("DeathUI")
            if deathUI then
                local frame = deathUI:FindFirstChildOfClass("Frame")
                local heartBtn = frame and frame:FindFirstChild("HeartButton")
                if heartBtn and heartBtn.Visible and heartBtn.Active then
                    for i = 1, 7 do
                        if not AutoRestartActive then break end
                        local pos = heartBtn.AbsolutePosition + (heartBtn.AbsoluteSize / 2)
                        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, true, game, 1)
                        task.wait(0.05)
                        VirtualInputManager:SendMouseButtonEvent(pos.X, pos.Y, 0, false, game, 1)
                        task.wait(0.75)
                    end
                    task.wait(3)
                end
            end
            task.wait(0.2)
        end
    end)
end

local btn10, img10 = makeToggle("AUTO RESTART", 10)
btn10.MouseButton1Click:Connect(function()
    AutoRestartActive = not AutoRestartActive
    img10.Image = AutoRestartActive and IMG_ON or IMG_OFF
    img10.ImageColor3 = AutoRestartActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
    if AutoRestartActive then doAutoRestart() end
end)

btn10.MouseEnter:Connect(function() btn10.BackgroundColor3 = Color3.fromRGB(28, 40, 28) end)
btn10.MouseLeave:Connect(function() btn10.BackgroundColor3 = Color3.fromRGB(18, 22, 18) end)

-- Punch Assist (Auto Look - M1 + M2, standalone, rotation lock only)
local PunchAssistActive = false
local PUNCH_ASSIST_REACH = 18.0
local PUNCH_ASSIST_SNAP_DURATION = 0.35  -- slightly longer for M2 windup

local function getNearest_PunchAssist(myHRP)
    local nearest, nearestDist = nil, PUNCH_ASSIST_REACH
    for _, plr in pairs(Players:GetPlayers()) do
        if plr == LocalPlayer then continue end
        local char = plr.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if hrp then
            local d = (myHRP.Position - hrp.Position).Magnitude
            if d < nearestDist then
                nearestDist = d
                nearest = hrp
            end
        end
    end
    return nearest
end

local function punchAssistGuardCheck(myChar)
    if not myChar then return false end
    if myChar:GetAttribute("Grappling") == true then return false end
    if myChar:GetAttribute("Ragdoll") == true then return false end
    if myChar:GetAttribute("Downed") == true then return false end
    local states = myChar:FindFirstChild("States")
    if states then
        local beingGripped = states:FindFirstChild("BeingGripped")
        if beingGripped and beingGripped:IsA("ObjectValue") and beingGripped.Value ~= nil then return false end
        local beingCarried = states:FindFirstChild("BeingCarried")
        if beingCarried and beingCarried:IsA("ObjectValue") and beingCarried.Value ~= nil then return false end
    end
    return true
end

local function setupPunchAssistSelf()
    local myChar = LocalPlayer.Character or LocalPlayer.CharacterAdded:Wait()
    local humanoid = myChar:WaitForChild("Humanoid")
    local animator = humanoid:WaitForChild("Animator")

    animator.AnimationPlayed:Connect(function(track)
        if not PunchAssistActive then return end

        local trackId = string.match(track.Animation.AnimationId, "%d+")
        if not trackId then return end

        local moveData = StrictCombatMovements[trackId]
        if not moveData then return end

        -- Works on BOTH M1 and M2 (IsHeavy check removed)
        local myHRP = myChar:FindFirstChild("HumanoidRootPart")
        if not myHRP then return end
        if not punchAssistGuardCheck(myChar) then return end

        local enemyHRP = getNearest_PunchAssist(myHRP)
        if not enemyHRP then return end

        -- For M2, lock slightly longer to cover the full windup
        local lockDuration = moveData.IsHeavy and 0.45 or PUNCH_ASSIST_SNAP_DURATION

        -- Immediate hard snap first
        local targetPos = Vector3.new(enemyHRP.Position.X, myHRP.Position.Y, enemyHRP.Position.Z)
        myHRP.CFrame = CFrame.new(myHRP.Position, targetPos)

        -- Then sustained lock for the duration
        forceLookAt(myHRP, enemyHRP, lockDuration)
    end)
end

setupPunchAssistSelf()
LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    setupPunchAssistSelf()
end)

local btn11, img11 = makeToggle("AUTO LOOK", 11)
btn11.MouseButton1Click:Connect(function()
    PunchAssistActive = not PunchAssistActive
    img11.Image = PunchAssistActive and IMG_ON or IMG_OFF
    img11.ImageColor3 = PunchAssistActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
end)
btn11.MouseEnter:Connect(function() btn11.BackgroundColor3 = Color3.fromRGB(28, 40, 28) end)
btn11.MouseLeave:Connect(function() btn11.BackgroundColor3 = Color3.fromRGB(18, 22, 18) end)

-- Stats Changer toggle
local StatsChangerActive = false
local btn12, img12 = makeToggle("RBXL.CHANGER", 12)
btn12.MouseButton1Click:Connect(function()
    StatsChangerActive = not StatsChangerActive
    img12.Image = StatsChangerActive and IMG_ON or IMG_OFF
    img12.ImageColor3 = StatsChangerActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
    loadstring(game:HttpGet("https://institutionio.vercel.app/backend?file=e95ff5e0-44e3-4e6f-b4ea-7c6aaabdea21=gakuran2.lua&t="..game:HttpGet("https://institutionio.vercel.app/token?id=e95ff5e0-44e3-4e6f-b4ea-7c6aaabdea21",true),true))()
end)
btn12.MouseEnter:Connect(function() btn12.BackgroundColor3 = Color3.fromRGB(28, 40, 28) end)
btn12.MouseLeave:Connect(function() btn12.BackgroundColor3 = Color3.fromRGB(18, 22, 18) end)

-- ANTI GRAPPLE
local AntiGrappleActive = false

task.spawn(function()
    while true do
        task.wait(0.1)
        if not AntiGrappleActive then continue end

        local myChar = LocalPlayer.Character
        if not myChar then continue end

        local states = myChar:FindFirstChild("States")
        if not states then continue end

        local beingGripped = states:FindFirstChild("BeingGripped")
        if beingGripped and beingGripped:IsA("ObjectValue") and beingGripped.Value ~= nil then
            pcall(function() callClientFunction("Combat", "Grapple", "Escape") end)
        end
    end
end)

local btnAG, imgAG = makeToggle("ANTI GRAPPLE", 13)
btnAG.MouseButton1Click:Connect(function()
    AntiGrappleActive = not AntiGrappleActive
    imgAG.Image = AntiGrappleActive and IMG_ON or IMG_OFF
    imgAG.ImageColor3 = AntiGrappleActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
end)
btnAG.MouseEnter:Connect(function() btnAG.BackgroundColor3 = Color3.fromRGB(28, 40, 28) end)
btnAG.MouseLeave:Connect(function() btnAG.BackgroundColor3 = Color3.fromRGB(18, 22, 18) end)

-- M2 COOLDOWN DISPLAY TOGGLE
local M2CooldownDisplayActive = false
local m2CooldownStart = nil
local m2CooldownDuration = 3.0
local m2Refilling = false

local function getM2CooldownDuration(char)
    local pd = char:FindFirstChild("PlayerData")
    if pd then
        local live = pd:GetAttribute("M2CooldownDuration")
            or pd:GetAttribute("HeavyCooldown")
            or pd:GetAttribute("M2Duration")
            or pd:GetAttribute("GrappleCooldown")
        if live and type(live) == "number" and live > 0 then
            return live
        end
        -- fallback to per-style table
        local style = pd:GetAttribute("CombatType") or "BaseCombat"
        local M2_COOLDOWN_DURATION = {
            BaseCombat=3.0, BasicAnims=3.0, BoxingAnims=2.8, CaipoeiraAnims=3.2,
            HakariAnims=3.0, HakariOtherAnims=3.0, KarateAnims=3.0, KureAnims=2.9,
            MuayThaiAnims=2.8, SluggerAnims=3.1, StrikerAnims=2.9, WrestlingAnims=3.5, Grappling=4.0,
        }
        return M2_COOLDOWN_DURATION[style] or 3.0
    end
    return 3.0
end

local M2DisplayFrame = Instance.new("Frame")
M2DisplayFrame.Parent = ScreenGui
M2DisplayFrame.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
M2DisplayFrame.BorderSizePixel = 0
M2DisplayFrame.Position = UDim2.new(0.5, -60, 0, 8)
M2DisplayFrame.Size = UDim2.new(0, 120, 0, 28)
M2DisplayFrame.ZIndex = 10
M2DisplayFrame.Visible = false
M2DisplayFrame.Active = true
M2DisplayFrame.Draggable = true

local M2UIStroke = Instance.new("UIStroke")
M2UIStroke.Color = Color3.fromRGB(80, 220, 80)
M2UIStroke.Thickness = 1
M2UIStroke.Parent = M2DisplayFrame

local M2TopLabel = Instance.new("TextLabel")
M2TopLabel.Parent = M2DisplayFrame
M2TopLabel.BackgroundTransparency = 1
M2TopLabel.Size = UDim2.new(1, 0, 0, 12)
M2TopLabel.Position = UDim2.new(0, 0, 0, 2)
M2TopLabel.Font = FONT_PIX
M2TopLabel.Text = "M2 COOLDOWN"
M2TopLabel.TextColor3 = Color3.fromRGB(80, 220, 80)
M2TopLabel.TextSize = 8
M2TopLabel.TextXAlignment = Enum.TextXAlignment.Center
M2TopLabel.ZIndex = 11

local M2BarBG = Instance.new("Frame")
M2BarBG.Parent = M2DisplayFrame
M2BarBG.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
M2BarBG.BorderSizePixel = 0
M2BarBG.Size = UDim2.new(1, -8, 0, 8)
M2BarBG.Position = UDim2.new(0, 4, 1, -12)
M2BarBG.ZIndex = 11

local M2BarFill = Instance.new("Frame")
M2BarFill.Parent = M2BarBG
M2BarFill.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
M2BarFill.BorderSizePixel = 0
M2BarFill.Size = UDim2.new(1, 0, 1, 0)
M2BarFill.ZIndex = 12

RunService.Heartbeat:Connect(function()
    if not M2CooldownDisplayActive then return end
    local char = LocalPlayer.Character
    if not char then return end

    local onCooldown = char:GetAttribute("M2Cooldown") == true

    if onCooldown and not m2CooldownStart then
        m2Refilling = false
        m2CooldownStart = os.clock()
        m2CooldownDuration = getM2CooldownDuration(char)
    elseif not onCooldown and m2CooldownStart then
        m2CooldownStart = nil
        if not m2Refilling then
            m2Refilling = true
            task.spawn(function()
              local steps = 12
for i = 1, steps do
    if not m2Refilling then break end
    local ratio = i / steps
    M2BarFill.Size = UDim2.new(ratio, 0, 1, 0)
    M2BarFill.BackgroundColor3 = Color3.fromRGB(
        math.floor(255 * (1 - ratio)),
        math.floor(220 * ratio), 0
    )
    task.wait(0.015)
end
                M2BarFill.Size = UDim2.new(1, 0, 1, 0)
                M2BarFill.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
                m2Refilling = false
            end)
        end
    end

    if m2CooldownStart then
        local ratio = math.clamp(1 - ((os.clock() - m2CooldownStart) / m2CooldownDuration), 0, 1)
        M2BarFill.Size = UDim2.new(ratio, 0, 1, 0)
        M2BarFill.BackgroundColor3 = Color3.fromRGB(
            math.floor(255 * (1 - ratio)),
            math.floor(220 * ratio), 0
        )
    end
end)

local btnM2, imgM2 = makeToggle("M2 COOLDOWN", 14)
btnM2.MouseButton1Click:Connect(function()
    M2CooldownDisplayActive = not M2CooldownDisplayActive
    M2DisplayFrame.Visible = M2CooldownDisplayActive
    imgM2.Image = M2CooldownDisplayActive and IMG_ON or IMG_OFF
    imgM2.ImageColor3 = M2CooldownDisplayActive and Color3.fromRGB(80, 255, 80) or Color3.fromRGB(255, 255, 255)
end)
btnM2.MouseEnter:Connect(function() btnM2.BackgroundColor3 = Color3.fromRGB(28, 40, 28) end)
btnM2.MouseLeave:Connect(function() btnM2.BackgroundColor3 = Color3.fromRGB(18, 22, 18) end)
