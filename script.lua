--[[
    ╔══════════════════════════════════════════╗
    ║       FREECAM HUB MOBILE v1.0           ║
    ║   FIXED Camera Auto Align               ║
    ║   + Feedback System                     ║
    ║   Optimized for Delta Executor          ║
    ╚══════════════════════════════════════════╝
]]

-------------------------------------------------
-- SERVICES
-------------------------------------------------
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")

local Player = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

-------------------------------------------------
-- SAFE CHARACTER ACCESS
-------------------------------------------------
local function getCharacter()
    local char = Player.Character
    if not char then
        char = Player.CharacterAdded:Wait()
    end
    return char
end

local function getHumanoid()
    local char = getCharacter()
    if not char then return nil end
    return char:FindFirstChildOfClass("Humanoid")
end

local function getHRP()
    local char = getCharacter()
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

-------------------------------------------------
-- LOAD RAYFIELD
-------------------------------------------------
local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()

-------------------------------------------------
-- STATE
-------------------------------------------------
local State = {
    FreecamEnabled = false,
    FreecamSpeed = 50,
    FreecamGoingUp = false,
    FreecamGoingDown = false,
    CinematicMode = false,
    GhostMode = false,
    DynamicSpeed = true,
    AutoAlignCamera = false,
    AutoAlignStrength = 0.03,

    CameraRotationUIEnabled = false,
    CameraRotSpeed = 2,
    RotatingUp = false,
    RotatingDown = false,
    RotatingLeft = false,
    RotatingRight = false,

    FOV = 70,
    DynamicFOV = false,
    CameraShake = false,

    SmoothTeleport = false,

    NoclipEnabled = false,
    WalkSpeedValue = 16,
    JumpPowerValue = 50,
    InfiniteJump = false,

    FollowTarget = nil,
    LockTarget = nil,

    SavedCameraPos = nil,
    SavedCameraLook = nil,

    ChaosMode = false,
    ScanHighlights = {},
    ScanRange = 200,

    Connections = {},

    CameraPitch = 0,
    CameraYaw = 0,

    -- Feedback
    LastFeedbackTime = 0,
    FeedbackCooldown = 600,
    FeedbackText = "",
}

local freecamPosition = Vector3.zero
local freecamVelocity = Vector3.zero

-------------------------------------------------
-- CONNECTION MANAGER
-------------------------------------------------
local function disconnectKey(key)
    local conn = State.Connections[key]
    if conn then
        if typeof(conn) == "RBXScriptConnection" then
            if conn.Connected then
                conn:Disconnect()
            end
        end
        State.Connections[key] = nil
    end
end

local function disconnectAll()
    for key, conn in pairs(State.Connections) do
        if typeof(conn) == "RBXScriptConnection" and conn.Connected then
            conn:Disconnect()
        end
    end
    State.Connections = {}
end

-------------------------------------------------
-- NOTIFY HELPER
-------------------------------------------------
local function notify(title, content, duration)
    pcall(function()
        Rayfield:Notify({
            Title = title or "Info",
            Content = content or "",
            Duration = duration or 4,
        })
    end)
end

-------------------------------------------------
-- CHARACTER HELPERS
-------------------------------------------------
local function getMoveDirection()
    local hum = getHumanoid()
    if hum then
        return hum.MoveDirection
    end
    return Vector3.zero
end

local function anchorCharacter(anchor)
    pcall(function()
        local char = Player.Character
        if not char then return end
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Anchored = anchor
            end
        end
    end)
end

local function setCharacterVisible(visible)
    pcall(function()
        local char = Player.Character
        if not char then return end
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Transparency = visible and 0 or 1
            elseif part:IsA("Decal") then
                part.Transparency = visible and 0 or 1
            end
        end
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            hrp.Transparency = 1
        end
    end)
end

-------------------------------------------------
-- MATH HELPERS (FOR AUTO ALIGN FIX)
-------------------------------------------------
local function normalizeAngle(angle)
    -- Normalize angle to [-pi, pi]
    while angle > math.pi do
        angle = angle - 2 * math.pi
    end
    while angle < -math.pi do
        angle = angle + 2 * math.pi
    end
    return angle
end

local function shortestAngleDiff(from, to)
    -- Returns shortest rotation from 'from' to 'to'
    local diff = normalizeAngle(to - from)
    return diff
end

local function lerpAngle(from, to, alpha)
    -- Lerp between angles using shortest path
    local diff = shortestAngleDiff(from, to)
    return from + diff * math.clamp(alpha, 0, 1)
end

-------------------------------------------------
-- CAMERA ROTATION UI (FIXED VERSION)
-------------------------------------------------
local CameraRotationGui = nil
local FlyButtonsGui = nil

local function isValidTouch(input)
    local t = input.UserInputType
    return t == Enum.UserInputType.Touch
        or t == Enum.UserInputType.MouseButton1
end

local function makeButton(parent, name, text, size, position, color)
    local btn = Instance.new("TextButton")
    btn.Name = name
    btn.Size = size
    btn.Position = position
    btn.BackgroundColor3 = color
    btn.Text = text
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.TextSize = 20
    btn.Font = Enum.Font.GothamBold
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Parent = parent

    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 10)
    corner.Parent = btn

    return btn
end

local function hookHoldButton(btn, stateKey, pressColor, releaseColor)
    local holding = false

    btn.MouseButton1Down:Connect(function()
        holding = true
        State[stateKey] = true
        btn.BackgroundColor3 = pressColor
    end)

    btn.MouseButton1Up:Connect(function()
        holding = false
        State[stateKey] = false
        btn.BackgroundColor3 = releaseColor
    end)

    btn.InputEnded:Connect(function(input)
        if isValidTouch(input) then
            if holding then
                holding = false
                State[stateKey] = false
                btn.BackgroundColor3 = releaseColor
            end
        end
    end)

    btn.MouseLeave:Connect(function()
        if holding then
            holding = false
            State[stateKey] = false
            btn.BackgroundColor3 = releaseColor
        end
    end)
end

local function createFlyButtons()
    if FlyButtonsGui then
        FlyButtonsGui:Destroy()
        FlyButtonsGui = nil
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "FreecamFlyButtons"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 101

    local container = Instance.new("Frame")
    container.Name = "FlyContainer"
    container.Size = UDim2.new(0, 110, 0, 155)
    container.Position = UDim2.new(0, 12, 1, -290)
    container.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
    container.BackgroundTransparency = 0.25
    container.BorderSizePixel = 0
    container.Parent = gui
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 14)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 28)
    title.Position = UDim2.new(0, 0, 0, 2)
    title.BackgroundTransparency = 1
    title.Text = "🛫 Fly"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold
    title.Parent = container

    local upBtn = makeButton(
        container, "FlyUp", "🔼 UP",
        UDim2.new(0.82, 0, 0, 48),
        UDim2.new(0.09, 0, 0, 32),
        Color3.fromRGB(50, 120, 255)
    )
    hookHoldButton(upBtn, "FreecamGoingUp",
        Color3.fromRGB(80, 160, 255),
        Color3.fromRGB(50, 120, 255)
    )

    local downBtn = makeButton(
        container, "FlyDown", "🔽 DOWN",
        UDim2.new(0.82, 0, 0, 48),
        UDim2.new(0.09, 0, 0, 88),
        Color3.fromRGB(220, 60, 60)
    )
    hookHoldButton(downBtn, "FreecamGoingDown",
        Color3.fromRGB(255, 100, 100),
        Color3.fromRGB(220, 60, 60)
    )

    gui.Parent = Player:FindFirstChildOfClass("PlayerGui")
    FlyButtonsGui = gui
end

local function createCameraRotationUI()
    if CameraRotationGui then
        CameraRotationGui:Destroy()
        CameraRotationGui = nil
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "FreecamCamRotUI"
    gui.ResetOnSpawn = false
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    gui.DisplayOrder = 101

    local container = Instance.new("Frame")
    container.Name = "RotContainer"
    container.Size = UDim2.new(0, 210, 0, 210)
    container.Position = UDim2.new(1, -225, 1, -290)
    container.BackgroundColor3 = Color3.fromRGB(15, 15, 25)
    container.BackgroundTransparency = 0.25
    container.BorderSizePixel = 0
    container.Parent = gui
    Instance.new("UICorner", container).CornerRadius = UDim.new(0, 14)

    local title = Instance.new("TextLabel")
    title.Size = UDim2.new(1, 0, 0, 28)
    title.Position = UDim2.new(0, 0, 0, 2)
    title.BackgroundTransparency = 1
    title.Text = "📷 Camera"
    title.TextColor3 = Color3.fromRGB(255, 255, 255)
    title.TextSize = 13
    title.Font = Enum.Font.GothamBold
    title.Parent = container

    local btnColor = Color3.fromRGB(45, 45, 75)
    local btnPress = Color3.fromRGB(80, 80, 140)
    local btnSize = UDim2.new(0, 60, 0, 52)

    local upBtn = makeButton(container, "RotUp", "⬆️", btnSize,
        UDim2.new(0.5, -30, 0, 32), btnColor)
    hookHoldButton(upBtn, "RotatingUp", btnPress, btnColor)

    local downBtn = makeButton(container, "RotDown", "⬇️", btnSize,
        UDim2.new(0.5, -30, 0, 142), btnColor)
    hookHoldButton(downBtn, "RotatingDown", btnPress, btnColor)

    local leftBtn = makeButton(container, "RotLeft", "⬅️", btnSize,
        UDim2.new(0, 12, 0, 87), btnColor)
    hookHoldButton(leftBtn, "RotatingLeft", btnPress, btnColor)

    local rightBtn = makeButton(container, "RotRight", "➡️", btnSize,
        UDim2.new(1, -72, 0, 87), btnColor)
    hookHoldButton(rightBtn, "RotatingRight", btnPress, btnColor)

    gui.Parent = Player:FindFirstChildOfClass("PlayerGui")
    CameraRotationGui = gui
end

local function destroyCameraRotationUI()
    State.RotatingUp = false
    State.RotatingDown = false
    State.RotatingLeft = false
    State.RotatingRight = false

    if CameraRotationGui then
        CameraRotationGui:Destroy()
        CameraRotationGui = nil
    end
end

local function destroyFlyButtons()
    State.FreecamGoingUp = false
    State.FreecamGoingDown = false

    if FlyButtonsGui then
        FlyButtonsGui:Destroy()
        FlyButtonsGui = nil
    end
end

local function destroyAllFreecamUI()
    destroyCameraRotationUI()
    destroyFlyButtons()
end

-------------------------------------------------
-- FREECAM SYSTEM (FIXED AUTO ALIGN)
-------------------------------------------------
local function enableFreecam()
    if State.FreecamEnabled then return end
    State.FreecamEnabled = true

    disconnectKey("FreecamRender")

    local camCF = Camera.CFrame
    freecamPosition = camCF.Position
    freecamVelocity = Vector3.zero

    local lookDir = camCF.LookVector
    State.CameraYaw = math.atan2(-lookDir.X, -lookDir.Z)
    State.CameraPitch = math.asin(math.clamp(lookDir.Y, -1, 1))

    Camera.CameraType = Enum.CameraType.Scriptable
    anchorCharacter(true)

    if State.GhostMode then
        setCharacterVisible(false)
    end

    createFlyButtons()

    if State.CameraRotationUIEnabled then
        createCameraRotationUI()
    end

    State.Connections["FreecamRender"] = RunService.RenderStepped:Connect(function(dt)
        if not State.FreecamEnabled then return end

        -------------------------------------------
        -- STEP 1: CAMERA ROTATION (from UI buttons)
        -- This is COMPLETELY SEPARATE from movement
        -------------------------------------------
        local rotSpeed = State.CameraRotSpeed * dt

        if State.RotatingLeft then
            State.CameraYaw = State.CameraYaw + rotSpeed
        end
        if State.RotatingRight then
            State.CameraYaw = State.CameraYaw - rotSpeed
        end
        if State.RotatingUp then
            State.CameraPitch = math.clamp(
                State.CameraPitch + rotSpeed,
                -math.rad(85), math.rad(85)
            )
        end
        if State.RotatingDown then
            State.CameraPitch = math.clamp(
                State.CameraPitch - rotSpeed,
                -math.rad(85), math.rad(85)
            )
        end

        -- Normalize yaw to prevent overflow
        State.CameraYaw = normalizeAngle(State.CameraYaw)

        -------------------------------------------
        -- STEP 2: BUILD CAMERA FRAME FROM YAW/PITCH
        -------------------------------------------
        local camRotation = CFrame.Angles(0, State.CameraYaw, 0)
            * CFrame.Angles(State.CameraPitch, 0, 0)
        local camLook = camRotation.LookVector
        local camRight = camRotation.RightVector
        local camUp = Vector3.new(0, 1, 0)

        -------------------------------------------
        -- STEP 3: MOVEMENT (completely separate from rotation)
        -------------------------------------------
        local moveDir = getMoveDirection()
        local moveVec = Vector3.zero
        local isMoving = false

        if moveDir.Magnitude > 0.01 then
            isMoving = true

            -- Get flat camera directions for decomposition
            local camForwardFlat = Vector3.new(camLook.X, 0, camLook.Z)
            if camForwardFlat.Magnitude > 0.001 then
                camForwardFlat = camForwardFlat.Unit
            else
                camForwardFlat = Vector3.new(0, 0, -1)
            end

            local camRightFlat = Vector3.new(camRight.X, 0, camRight.Z)
            if camRightFlat.Magnitude > 0.001 then
                camRightFlat = camRightFlat.Unit
            else
                camRightFlat = Vector3.new(1, 0, 0)
            end

            -- Decompose joystick MoveDirection into camera-relative amounts
            local dotForward = moveDir:Dot(camForwardFlat)
            local dotRight = moveDir:Dot(camRightFlat)

            -- Use full 3D look for forward (so looking down = fly down)
            moveVec = (camLook * dotForward) + (camRight * dotRight)
        end

        -- Vertical from buttons
        if State.FreecamGoingUp then
            moveVec = moveVec + camUp
            isMoving = true
        end
        if State.FreecamGoingDown then
            moveVec = moveVec - camUp
            isMoving = true
        end

        -- Clamp magnitude
        if moveVec.Magnitude > 1 then
            moveVec = moveVec.Unit
        end

        -- Speed
        local speed = State.FreecamSpeed

        if State.DynamicSpeed and moveDir.Magnitude > 0.01 then
            speed = speed * math.clamp(moveDir.Magnitude, 0.1, 1)
        end

        if State.CinematicMode then
            speed = speed * 0.3
        end

        -- Apply velocity
        local targetVelocity = moveVec * speed

        if State.CinematicMode then
            freecamVelocity = freecamVelocity:Lerp(targetVelocity, 0.08)
        else
            freecamVelocity = targetVelocity
        end

        freecamPosition = freecamPosition + freecamVelocity * dt

        -------------------------------------------
        -- STEP 4: AUTO ALIGN (FIXED - separate pass)
        -- Only adjusts yaw, never pitch
        -- Only when actively moving horizontally
        -- Uses shortest angle path to prevent 180° spin
        -------------------------------------------
        if State.AutoAlignCamera and isMoving and not State.FollowTarget and not State.LockTarget then
            -- Only align yaw based on horizontal movement
            local horizontalVel = Vector3.new(freecamVelocity.X, 0, freecamVelocity.Z)

            if horizontalVel.Magnitude > 1 then
                local targetYaw = math.atan2(-horizontalVel.X, -horizontalVel.Z)

                -- Use shortest angle difference to prevent 180° spin bug
                local angleDiff = shortestAngleDiff(State.CameraYaw, targetYaw)

                -- Only align if the difference is meaningful (avoid jitter)
                if math.abs(angleDiff) > 0.01 then
                    -- Apply with small strength so it doesn't fight manual rotation
                    local strength = State.AutoAlignStrength
                    State.CameraYaw = State.CameraYaw + angleDiff * strength
                    State.CameraYaw = normalizeAngle(State.CameraYaw)
                end
            end

            -- NEVER touch pitch in auto align - this prevents the spinning bug
        end

        -------------------------------------------
        -- STEP 5: FOLLOW / LOCK TARGET
        -------------------------------------------
        if State.FollowTarget then
            local tp = Players:FindFirstChild(State.FollowTarget)
            if tp and tp.Character then
                local thrp = tp.Character:FindFirstChild("HumanoidRootPart")
                if thrp then
                    freecamPosition = thrp.Position + Vector3.new(0, 10, 15)
                    local dir = (thrp.Position - freecamPosition)
                    if dir.Magnitude > 0.1 then
                        dir = dir.Unit
                        local targetYaw = math.atan2(-dir.X, -dir.Z)
                        local targetPitch = math.asin(math.clamp(dir.Y, -1, 1))
                        State.CameraYaw = lerpAngle(State.CameraYaw, targetYaw, 0.1)
                        State.CameraPitch = State.CameraPitch + (targetPitch - State.CameraPitch) * 0.1
                    end
                end
            end
        end

        if State.LockTarget then
            local tp = Players:FindFirstChild(State.LockTarget)
            if tp and tp.Character then
                local thrp = tp.Character:FindFirstChild("HumanoidRootPart")
                if thrp then
                    local dir = (thrp.Position - freecamPosition)
                    if dir.Magnitude > 0.1 then
                        dir = dir.Unit
                        local targetYaw = math.atan2(-dir.X, -dir.Z)
                        local targetPitch = math.asin(math.clamp(dir.Y, -1, 1))
                        State.CameraYaw = lerpAngle(State.CameraYaw, targetYaw, 0.15)
                        State.CameraPitch = State.CameraPitch + (targetPitch - State.CameraPitch) * 0.15
                        State.CameraPitch = math.clamp(State.CameraPitch, -math.rad(85), math.rad(85))
                    end
                end
            end
        end

        -------------------------------------------
        -- STEP 6: EFFECTS (Dynamic FOV, Shake, Chaos)
        -------------------------------------------
        if State.DynamicFOV then
            local speedMag = freecamVelocity.Magnitude
            local targetFOV = math.clamp(State.FOV + speedMag * 0.3, 30, 120)
            Camera.FieldOfView = Camera.FieldOfView + (targetFOV - Camera.FieldOfView) * 0.1
        end

        local shakeOffset = Vector3.zero
        if State.CameraShake and freecamVelocity.Magnitude > 5 then
            local intensity = math.clamp(freecamVelocity.Magnitude / State.FreecamSpeed, 0, 1) * 0.15
            shakeOffset = Vector3.new(
                (math.random() - 0.5) * intensity,
                (math.random() - 0.5) * intensity,
                (math.random() - 0.5) * intensity
            )
        end

        if State.ChaosMode then
            Camera.FieldOfView = math.random(40, 110)
            shakeOffset = shakeOffset + Vector3.new(
                (math.random() - 0.5) * 0.5,
                (math.random() - 0.5) * 0.5,
                0
            )
            State.CameraYaw = State.CameraYaw + (math.random() - 0.5) * 0.02
        end

        -------------------------------------------
        -- STEP 7: FINAL CAMERA APPLY
        -------------------------------------------
        -- Clamp pitch one final time for safety
        State.CameraPitch = math.clamp(State.CameraPitch, -math.rad(85), math.rad(85))

        local finalRot = CFrame.Angles(0, State.CameraYaw, 0)
            * CFrame.Angles(State.CameraPitch, 0, 0)
        Camera.CFrame = CFrame.new(freecamPosition + shakeOffset) * finalRot
    end)

    notify("Freecam", "Freecam ON ✅\nJoystick = move\nButtons = rotate & fly", 5)
end

local function disableFreecam()
    if not State.FreecamEnabled then return end
    State.FreecamEnabled = false

    disconnectKey("FreecamRender")

    State.FreecamGoingUp = false
    State.FreecamGoingDown = false
    State.RotatingUp = false
    State.RotatingDown = false
    State.RotatingLeft = false
    State.RotatingRight = false
    freecamVelocity = Vector3.zero

    anchorCharacter(false)

    if State.GhostMode then
        setCharacterVisible(true)
    end

    Camera.CameraType = Enum.CameraType.Custom
    pcall(function()
        Camera.CameraSubject = getHumanoid()
    end)

    if not State.DynamicFOV and not State.ChaosMode then
        Camera.FieldOfView = State.FOV
    end

    destroyAllFreecamUI()

    notify("Freecam", "Freecam OFF ❌", 3)
end

-------------------------------------------------
-- NOCLIP
-------------------------------------------------
local function enableNoclip()
    disconnectKey("NoclipStep")
    State.NoclipEnabled = true

    State.Connections["NoclipStep"] = RunService.Stepped:Connect(function()
        if not State.NoclipEnabled then return end
        local char = Player.Character
        if not char then return end
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)

    notify("Noclip", "Noclip ON ✅", 3)
end

local function disableNoclip()
    State.NoclipEnabled = false
    disconnectKey("NoclipStep")

    pcall(function()
        local char = Player.Character
        if not char then return end
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
                part.CanCollide = true
            end
        end
    end)

    notify("Noclip", "Noclip OFF ❌", 3)
end

-------------------------------------------------
-- INFINITE JUMP
-------------------------------------------------
local function setupInfiniteJump()
    disconnectKey("InfJump")
    State.Connections["InfJump"] = UserInputService.JumpRequest:Connect(function()
        if not State.InfiniteJump then return end
        local hum = getHumanoid()
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end)
end
setupInfiniteJump()

-------------------------------------------------
-- RESPAWN PERSISTENCE
-------------------------------------------------
Player.CharacterAdded:Connect(function(char)
    task.wait(0.5)

    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    if State.WalkSpeedValue ~= 16 then
        hum.WalkSpeed = State.WalkSpeedValue
    end
    if State.JumpPowerValue ~= 50 then
        hum.JumpPower = State.JumpPowerValue
        hum.UseJumpPower = true
    end

    if State.NoclipEnabled then
        enableNoclip()
    end

    setupInfiniteJump()

    if State.FreecamEnabled then
        disableFreecam()
    end
end)

-------------------------------------------------
-- SCAN / HIGHLIGHT
-------------------------------------------------
local function clearHighlights()
    for _, h in pairs(State.ScanHighlights) do
        pcall(function()
            if h and h.Parent then h:Destroy() end
        end)
    end
    State.ScanHighlights = {}
end

local function scanNearbyPlayers(range)
    clearHighlights()
    range = range or State.ScanRange

    local pos
    if State.FreecamEnabled then
        pos = freecamPosition
    else
        local hrp = getHRP()
        pos = hrp and hrp.Position or Vector3.zero
    end

    local count = 0
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= Player and p.Character then
            local hrp2 = p.Character:FindFirstChild("HumanoidRootPart")
            if hrp2 and (hrp2.Position - pos).Magnitude <= range then
                local hl = Instance.new("Highlight")
                hl.FillColor = Color3.fromRGB(255, 255, 0)
                hl.OutlineColor = Color3.fromRGB(255, 100, 0)
                hl.FillTransparency = 0.5
                hl.Adornee = p.Character
                hl.Parent = p.Character
                table.insert(State.ScanHighlights, hl)
                count = count + 1
            end
        end
    end

    notify("Scan", "Found " .. count .. " players within " .. range .. " studs", 3)

    task.delay(10, function()
        clearHighlights()
    end)
end

-------------------------------------------------
-- PLAYER LIST
-------------------------------------------------
local function getPlayerList()
    local list = {"None"}
    for _, p in pairs(Players:GetPlayers()) do
        if p ~= Player then
            table.insert(list, p.Name)
        end
    end
    if #list == 1 then
        table.insert(list, "No Players")
    end
    return list
end

-------------------------------------------------
-- TELEPORT
-------------------------------------------------
local function teleportToCamera(safe)
    local hrp = getHRP()
    if not hrp then
        notify("Error", "No character found", 3)
        return
    end

    local wasFreecam = State.FreecamEnabled
    if wasFreecam then
        disableFreecam()
        task.wait(0.15)
    end

    local targetPos = freecamPosition
    if safe then
        targetPos = targetPos + Vector3.new(0, 5, 0)
    end

    if State.SmoothTeleport then
        local tween = TweenService:Create(
            hrp,
            TweenInfo.new(1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
            {CFrame = CFrame.new(targetPos)}
        )
        tween:Play()
        notify("Teleport", "Smooth teleporting...", 2)
    else
        hrp.CFrame = CFrame.new(targetPos)
        notify("Teleport", safe and "Safe teleported! ✅" or "Teleported! ✅", 2)
    end
end

-------------------------------------------------
-- FEEDBACK SYSTEM (DISCORD WEBHOOK)
-------------------------------------------------
local WEBHOOK_URL = "https://discord.com/api/webhooks/1446147402275749916/m5eZ12l6RKrjSGJKuVnxRyKBb4mQIqlVQJloX9dhfQ6Ue1lCNRwYwjJxGuqCdGh2MrDO"

local function sendFeedback(text)
    if not text or text == "" or #text < 3 then
        notify("❌ Feedback", "Please enter at least 3 characters!", 3)
        return
    end

    -- Rate limit check
    local now = tick()
    local timeSinceLast = now - State.LastFeedbackTime
    if timeSinceLast < State.FeedbackCooldown then
        local remaining = math.ceil(State.FeedbackCooldown - timeSinceLast)
        local mins = math.floor(remaining / 60)
        local secs = remaining % 60
        notify("⏳ Cooldown", "Please wait " .. mins .. "m " .. secs .. "s before sending again", 4)
        return
    end

    -- Build payload
    local playerName = Player.Name or "Unknown"
    local displayName = Player.DisplayName or playerName
    local userId = tostring(Player.UserId or 0)

    local payload = {
        embeds = {
            {
                title = "📩 New Feedback - Freecam Hub v1.0",
                description = text,
                color = 3447003,
                fields = {
                    {
                        name = "👤 Player",
                        value = displayName .. " (@" .. playerName .. ")",
                        inline = true,
                    },
                    {
                        name = "🆔 User ID",
                        value = userId,
                        inline = true,
                    },
                    {
                        name = "🎮 Game",
                        value = tostring(game.PlaceId) .. " / " .. tostring(game.JobId):sub(1, 8),
                        inline = true,
                    },
                },
                footer = {
                    text = "Freecam Hub Mobile v1.0 • Feedback System",
                },
                timestamp = os.date("!%Y-%m-%dT%H:%M:%SZ"),
            }
        }
    }

    local jsonPayload = HttpService:JSONEncode(payload)

    -- Send request
    local success, err = pcall(function()
        -- Try multiple methods for executor compatibility
        if request then
            request({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = jsonPayload,
            })
        elseif http_request then
            http_request({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = jsonPayload,
            })
        elseif syn and syn.request then
            syn.request({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = jsonPayload,
            })
        elseif http and http.request then
            http.request({
                Url = WEBHOOK_URL,
                Method = "POST",
                Headers = {["Content-Type"] = "application/json"},
                Body = jsonPayload,
            })
        else
            error("No HTTP request function available")
        end
    end)

    if success then
        State.LastFeedbackTime = tick()
        State.FeedbackText = ""
        notify("✅ Feedback Sent!", "Thank you for your feedback!\nNext feedback available in 10 minutes.", 5)
    else
        notify("❌ Error", "Failed to send feedback: " .. tostring(err), 4)
    end
end

-------------------------------------------------
-- RAYFIELD WINDOW
-------------------------------------------------
local Window = Rayfield:CreateWindow({
    Name = "🎮 Freecam Hub Mobile v1.0",
    LoadingTitle = "Loading Freecam Hub...",
    LoadingSubtitle = "Mobile Optimized • v1.0",
    ConfigurationSaving = { Enabled = false },
    Discord = { Enabled = false },
    KeySystem = false,
})

-------------------------------------------------
-- TAB: MOVEMENT
-------------------------------------------------
local MovementTab = Window:CreateTab("🏃 Movement", 4483362458)

MovementTab:CreateSection("✈️ Freecam")

MovementTab:CreateToggle({
    Name = "✈️ Enable Freecam",
    CurrentValue = false,
    Flag = "FreecamToggle",
    Callback = function(v)
        if v then enableFreecam() else disableFreecam() end
    end,
})

MovementTab:CreateSlider({
    Name = "🚀 Fly Speed",
    Range = {5, 200},
    Increment = 5,
    Suffix = " studs/s",
    CurrentValue = 50,
    Flag = "FlySpeed",
    Callback = function(v) State.FreecamSpeed = v end,
})

MovementTab:CreateToggle({
    Name = "📊 Dynamic Speed",
    CurrentValue = true,
    Flag = "DynSpeed",
    Callback = function(v) State.DynamicSpeed = v end,
})

MovementTab:CreateToggle({
    Name = "🎬 Cinematic Mode",
    CurrentValue = false,
    Flag = "Cinematic",
    Callback = function(v)
        State.CinematicMode = v
        if v then notify("Cinematic", "Smooth movement ON", 3) end
    end,
})

MovementTab:CreateToggle({
    Name = "👻 Ghost Mode",
    CurrentValue = false,
    Flag = "Ghost",
    Callback = function(v)
        State.GhostMode = v
        if State.FreecamEnabled then
            setCharacterVisible(not v)
        end
    end,
})

MovementTab:CreateToggle({
    Name = "🧭 Auto Align Camera (Fixed)",
    CurrentValue = false,
    Flag = "AutoAlign",
    Callback = function(v)
        State.AutoAlignCamera = v
        if v then
            notify("Auto Align", "Camera will gently follow movement direction\nYaw only - no pitch spinning", 4)
        end
    end,
})

MovementTab:CreateSlider({
    Name = "🧭 Auto Align Strength",
    Range = {1, 10},
    Increment = 1,
    Suffix = "%",
    CurrentValue = 3,
    Flag = "AlignStrength",
    Callback = function(v)
        State.AutoAlignStrength = v / 100
    end,
})

MovementTab:CreateSection("🔧 Character")

MovementTab:CreateToggle({
    Name = "👤 Noclip",
    CurrentValue = false,
    Flag = "Noclip",
    Callback = function(v)
        if v then enableNoclip() else disableNoclip() end
    end,
})

MovementTab:CreateSlider({
    Name = "🏃 WalkSpeed",
    Range = {0, 500},
    Increment = 1,
    Suffix = "",
    CurrentValue = 16,
    Flag = "WalkSpeed",
    Callback = function(v)
        State.WalkSpeedValue = v
        local hum = getHumanoid()
        if hum then hum.WalkSpeed = v end
    end,
})

MovementTab:CreateSlider({
    Name = "⬆️ JumpPower",
    Range = {0, 500},
    Increment = 1,
    Suffix = "",
    CurrentValue = 50,
    Flag = "JumpPower",
    Callback = function(v)
        State.JumpPowerValue = v
        local hum = getHumanoid()
        if hum then
            hum.JumpPower = v
            hum.UseJumpPower = true
        end
    end,
})

MovementTab:CreateToggle({
    Name = "♾️ Infinite Jump",
    CurrentValue = false,
    Flag = "InfJump",
    Callback = function(v)
        State.InfiniteJump = v
        notify("Infinite Jump", v and "ON ✅" or "OFF ❌", 3)
    end,
})

-------------------------------------------------
-- TAB: CAMERA
-------------------------------------------------
local CameraTab = Window:CreateTab("📷 Camera", 4483362458)

CameraTab:CreateSection("📱 Camera Controls")

CameraTab:CreateToggle({
    Name = "📱 Camera Rotation UI",
    CurrentValue = false,
    Flag = "CamRotUI",
    Callback = function(v)
        State.CameraRotationUIEnabled = v
        if State.FreecamEnabled then
            if v then
                createCameraRotationUI()
            else
                destroyCameraRotationUI()
            end
        end
    end,
})

CameraTab:CreateSlider({
    Name = "🔄 Rotation Speed",
    Range = {5, 50},
    Increment = 1,
    Suffix = "",
    CurrentValue = 20,
    Flag = "RotSpeed",
    Callback = function(v)
        State.CameraRotSpeed = v / 10
    end,
})

CameraTab:CreateSection("🔭 FOV & Effects")

CameraTab:CreateSlider({
    Name = "🔭 FOV",
    Range = {30, 120},
    Increment = 1,
    Suffix = "°",
    CurrentValue = 70,
    Flag = "FOV",
    Callback = function(v)
        State.FOV = v
        if not State.DynamicFOV and not State.ChaosMode then
            Camera.FieldOfView = v
        end
    end,
})

CameraTab:CreateToggle({
    Name = "📐 Dynamic FOV",
    CurrentValue = false,
    Flag = "DynFOV",
    Callback = function(v)
        State.DynamicFOV = v
        if not v then Camera.FieldOfView = State.FOV end
    end,
})

CameraTab:CreateToggle({
    Name = "📳 Camera Shake",
    CurrentValue = false,
    Flag = "CamShake",
    Callback = function(v) State.CameraShake = v end,
})

CameraTab:CreateSection("🎯 Target")

CameraTab:CreateDropdown({
    Name = "👁️ Follow Player",
    Options = getPlayerList(),
    CurrentOption = {"None"},
    MultiOption = false,
    Flag = "FollowPlayer",
    Callback = function(v)
        local sel = v[1] or v
        if sel == "None" or sel == "No Players" then
            State.FollowTarget = nil
        else
            State.FollowTarget = sel
            notify("Follow", "Following: " .. sel, 3)
        end
    end,
})

CameraTab:CreateDropdown({
    Name = "🔒 Lock Target",
    Options = getPlayerList(),
    CurrentOption = {"None"},
    MultiOption = false,
    Flag = "LockTarget",
    Callback = function(v)
        local sel = v[1] or v
        if sel == "None" or sel == "No Players" then
            State.LockTarget = nil
        else
            State.LockTarget = sel
            notify("Lock", "Locked on: " .. sel, 3)
        end
    end,
})

CameraTab:CreateSection("💾 Save / Load")

CameraTab:CreateButton({
    Name = "💾 Save Camera Position",
    Callback = function()
        if State.FreecamEnabled then
            State.SavedCameraPos = freecamPosition
            State.SavedCameraLook = {
                yaw = State.CameraYaw,
                pitch = State.CameraPitch
            }
        else
            State.SavedCameraPos = Camera.CFrame.Position
            local look = Camera.CFrame.LookVector
            State.SavedCameraLook = {
                yaw = math.atan2(-look.X, -look.Z),
                pitch = math.asin(math.clamp(look.Y, -1, 1))
            }
        end
        notify("Save", "Position saved! ✅", 3)
    end,
})

CameraTab:CreateButton({
    Name = "📂 Load Camera Position",
    Callback = function()
        if not State.SavedCameraPos then
            notify("Load", "No saved position! ❌", 3)
            return
        end
        if State.FreecamEnabled then
            freecamPosition = State.SavedCameraPos
            if State.SavedCameraLook then
                State.CameraYaw = State.SavedCameraLook.yaw
                State.CameraPitch = State.SavedCameraLook.pitch
            end
            notify("Load", "Position loaded! ✅", 3)
        else
            notify("Load", "Enable Freecam first!", 3)
        end
    end,
})

-------------------------------------------------
-- TAB: PLAYER
-------------------------------------------------
local PlayerTab = Window:CreateTab("👤 Player", 4483362458)

PlayerTab:CreateSection("🚀 Teleport")

PlayerTab:CreateButton({
    Name = "📍 Teleport to Camera",
    Callback = function() teleportToCamera(false) end,
})

PlayerTab:CreateButton({
    Name = "🛡️ Safe Teleport",
    Callback = function() teleportToCamera(true) end,
})

PlayerTab:CreateToggle({
    Name = "🌊 Smooth Teleport",
    CurrentValue = false,
    Flag = "SmoothTP",
    Callback = function(v) State.SmoothTeleport = v end,
})

PlayerTab:CreateSection("👤 Character")

PlayerTab:CreateButton({
    Name = "💀 Reset Character",
    Callback = function()
        if State.FreecamEnabled then disableFreecam() end
        local hum = getHumanoid()
        if hum then hum.Health = 0 end
        notify("Reset", "Character reset!", 2)
    end,
})

PlayerTab:CreateButton({
    Name = "📊 Player Info",
    Callback = function()
        local hum = getHumanoid()
        local hrp = getHRP()
        if hum and hrp then
            local p = hrp.Position
            notify("Player Info",
                "Speed: " .. math.floor(hum.WalkSpeed)
                .. "\nJump: " .. math.floor(hum.JumpPower)
                .. "\nHP: " .. math.floor(hum.Health) .. "/" .. math.floor(hum.MaxHealth)
                .. "\nPos: " .. math.floor(p.X) .. ", " .. math.floor(p.Y) .. ", " .. math.floor(p.Z),
                6
            )
        end
    end,
})

-------------------------------------------------
-- TAB: FUN
-------------------------------------------------
local FunTab = Window:CreateTab("🎮 Fun", 4483362458)

FunTab:CreateToggle({
    Name = "🌀 Chaos Mode",
    CurrentValue = false,
    Flag = "Chaos",
    Callback = function(v)
        State.ChaosMode = v
        if not v then Camera.FieldOfView = State.FOV end
        if v then notify("CHAOS", "🌀 CHAOS ACTIVATED!", 3) end
    end,
})

FunTab:CreateButton({
    Name = "🔍 Scan Nearby Players",
    Callback = function() scanNearbyPlayers(State.ScanRange) end,
})

FunTab:CreateSlider({
    Name = "📏 Scan Range",
    Range = {50, 500},
    Increment = 10,
    Suffix = " studs",
    CurrentValue = 200,
    Flag = "ScanRange",
    Callback = function(v) State.ScanRange = v end,
})

FunTab:CreateButton({
    Name = "❌ Clear Highlights",
    Callback = function()
        clearHighlights()
        notify("Scan", "Cleared!", 2)
    end,
})

-------------------------------------------------
-- TAB: SETTINGS (with Feedback)
-------------------------------------------------
local SettingsTab = Window:CreateTab("⚙️ Settings", 4483362458)

SettingsTab:CreateSection("📩 Feedback / Góp ý")

SettingsTab:CreateInput({
    Name = "✏️ Your Feedback",
    PlaceholderText = "Enter your feedback here...",
    RemoveTextAfterFocusLost = false,
    Flag = "FeedbackInput",
    Callback = function(text)
        State.FeedbackText = text
    end,
})

SettingsTab:CreateButton({
    Name = "📨 Send Feedback",
    Callback = function()
        local text = State.FeedbackText
        if not text or text == "" then
            -- Try to get from flag
            if Rayfield and Rayfield.Flags and Rayfield.Flags["FeedbackInput"] then
                text = Rayfield.Flags["FeedbackInput"].CurrentValue or ""
            end
        end
        sendFeedback(text)
    end,
})

SettingsTab:CreateParagraph({
    Title = "ℹ️ Feedback Info",
    Content = "Your feedback will be sent to the developer via Discord.\nRate limit: 1 message per 10 minutes.\nPlease be constructive! 🙏"
})

SettingsTab:CreateSection("🔧 System")

SettingsTab:CreateButton({
    Name = "🔄 Reset All Settings",
    Callback = function()
        if State.FreecamEnabled then disableFreecam() end
        if State.NoclipEnabled then disableNoclip() end

        State.InfiniteJump = false
        State.ChaosMode = false
        State.DynamicFOV = false
        State.CameraShake = false
        State.GhostMode = false
        State.CinematicMode = false
        State.AutoAlignCamera = false
        State.DynamicSpeed = true
        State.SmoothTeleport = false
        State.FollowTarget = nil
        State.LockTarget = nil
        State.WalkSpeedValue = 16
        State.JumpPowerValue = 50
        State.FOV = 70

        local hum = getHumanoid()
        if hum then
            hum.WalkSpeed = 16
            hum.JumpPower = 50
        end

        Camera.FieldOfView = 70
        Camera.CameraType = Enum.CameraType.Custom
        clearHighlights()

        notify("Reset", "All settings reset! ✅", 4)
    end,
})

SettingsTab:CreateSection("📖 Guide")

SettingsTab:CreateParagraph({
    Title = "📱 Mobile Guide",
    Content = [[
✈️ FREECAM:
1. Camera tab → Enable "Camera Rotation UI"
2. Movement tab → Enable "Freecam"
3. Joystick = Move (follows camera)
4. ⬆️⬇️⬅️➡️ = Rotate camera
5. 🔼🔽 = Fly up/down

🧭 AUTO ALIGN (FIXED):
• Only rotates yaw (horizontal)
• Never touches pitch (no spinning!)
• Uses shortest angle path (no 180° bug)
• Adjust strength with slider

📷 CAMERA: FOV, Follow, Lock, Save/Load
🏃 MOVEMENT: Noclip, Speed, Jump
📩 FEEDBACK: Send suggestions to developer
    ]]
})

SettingsTab:CreateParagraph({
    Title = "Freecam Hub Mobile v1.0",
    Content = "Optimized for Delta Executor\nFull mobile support\nNo keyboard required"
})

-------------------------------------------------
-- CLEANUP
-------------------------------------------------
pcall(function()
    game:GetService("CoreGui").ChildRemoved:Connect(function(child)
        if child.Name == "Rayfield" then
            if State.FreecamEnabled then disableFreecam() end
            if State.NoclipEnabled then disableNoclip() end
            disconnectAll()
            destroyAllFreecamUI()
            clearHighlights()
            Camera.CameraType = Enum.CameraType.Custom
            Camera.FieldOfView = 70
            anchorCharacter(false)
            setCharacterVisible(true)
            pcall(function()
                local hum = getHumanoid()
                if hum then
                    hum.WalkSpeed = 16
                    hum.JumpPower = 50
                end
            end)
        end
    end)
end)

-------------------------------------------------
-- INIT
-------------------------------------------------
Camera.FieldOfView = State.FOV

notify("✅ Freecam Hub v1.0", "Loaded successfully!\n1. Camera tab → Rotation UI\n2. Movement tab → Freecam\n3. Settings → Send Feedback!", 7)
