--[[
    Grow a Chicken Fighter | NeColman Hub v2.2
    Built with Obsidian UI Library (LinoriaLib Fork)
    Features: Smooth Flight Scrap Collector & Auto Deposit, Rate-Limit Protected Automation
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

------------------------------------------------------
-- UI Library Setup (Obsidian)
------------------------------------------------------
local repo = "https://raw.githubusercontent.com/deividcomsono/Obsidian/main/"
local Library = loadstring(game:HttpGet(repo .. "Library.lua"))()
local ThemeManager = loadstring(game:HttpGet(repo .. "addons/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet(repo .. "addons/SaveManager.lua"))()

local Options = Library.Options
local Toggles = Library.Toggles

Library.ForceCheckbox = false
Library.ShowToggleFrameInKeybinds = true

local Window = Library:CreateWindow({
    Title = "Grow a Chicken Fighter | NeColman Hub",
    Footer = "version: 2.2 (Smooth Flight Edition)",
    Icon = 95816097006870,
    NotifySide = "Right",
    ShowCustomCursor = false,
})

------------------------------------------------------
-- Services & Local Player
------------------------------------------------------
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local VirtualUser = game:GetService("VirtualUser")
local LocalPlayer = Players.LocalPlayer

-- Real-time Game Data & Cost Engine
local DataServicePackage = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("DataService")
local DataServiceClient = DataServicePackage and require(DataServicePackage).client

local CoopViewModule = ReplicatedStorage:FindFirstChild("Features") and ReplicatedStorage.Features:FindFirstChild("Coop") and ReplicatedStorage.Features.Coop:FindFirstChild("CoopView")
local CoopView = CoopViewModule and require(CoopViewModule)

local RecyclerViewModule = ReplicatedStorage:FindFirstChild("Features") and ReplicatedStorage.Features:FindFirstChild("Scrap") and ReplicatedStorage.Features.Scrap:FindFirstChild("RecyclerView")
local RecyclerView = RecyclerViewModule and require(RecyclerViewModule)

local RebirthBonusModule = ReplicatedStorage:FindFirstChild("Core") and ReplicatedStorage.Core:FindFirstChild("Progression") and ReplicatedStorage.Core.Progression:FindFirstChild("RebirthBonus")
local RebirthBonus = RebirthBonusModule and require(RebirthBonusModule)

------------------------------------------------------
-- Synchronized Remote Queue & Rate-Limiter
------------------------------------------------------
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
local lastInvokeTime = 0
local INVOKE_COOLDOWN = 0.95 -- Game server enforces ~0.9s cooldown between RemoteFunction calls

local function safeInvoke(name, ...)
    if not RemotesFolder then return nil end
    local r = RemotesFolder:FindFirstChild(name)
    if not r or not r:IsA("RemoteFunction") then return nil end

    local now = os.clock()
    local elapsed = now - lastInvokeTime
    if elapsed < INVOKE_COOLDOWN then
        task.wait(INVOKE_COOLDOWN - elapsed)
    end

    lastInvokeTime = os.clock()
    local success, result = pcall(function(...)
        return r:InvokeServer(...)
    end, ...)

    if success then
        return result
    end
    return nil
end

local function safeFire(name, ...)
    if not RemotesFolder then return end
    local r = RemotesFolder:FindFirstChild(name)
    if r and r:IsA("RemoteEvent") then
        r:FireServer(...)
    end
end

------------------------------------------------------
-- Dynamic Plot & World Coordinate Helpers
------------------------------------------------------
local function getMyPlot()
    return LocalPlayer:GetAttribute("Plot") or 1
end

local function parseOrigin(origin)
    if typeof(origin) == "CFrame" then
        return origin
    elseif typeof(origin) == "string" then
        local components = {}
        for num in string.gmatch(origin, "[-?%d%.%e]+") do
            table.insert(components, tonumber(num))
        end
        if #components == 12 then
            return CFrame.new(table.unpack(components))
        end
    end
    return nil
end

local function getCoopCFrame()
    local plot = getMyPlot()
    local coops = workspace:FindFirstChild("Coops")
    local coop = coops and coops:FindFirstChild("Coop" .. plot)
    if coop then
        local orig = parseOrigin(coop:GetAttribute("Origin"))
        if orig then return orig * CFrame.new(0, 3.5, 0) end
        local cf = coop:GetBoundingBox()
        return cf * CFrame.new(0, 3.5, 0)
    end
    return CFrame.new(0, 4, -95)
end

local function getRecyclerCFrame()
    local plot = getMyPlot()
    local recyclers = workspace:FindFirstChild("Recyclers")
    local rec = recyclers and recyclers:FindFirstChild("Recycler" .. plot)
    if rec then
        local orig = parseOrigin(rec:GetAttribute("Origin"))
        if orig then
            return orig * CFrame.new(0, 1.5, -3.2)
        end
        local cf = rec:GetBoundingBox()
        return cf * CFrame.new(0, 1.5, -3.2)
    end
    return CFrame.new(-9, 2.5, -75.8)
end

local function getArenaCFrame()
    local plot = getMyPlot()
    local arenas = workspace:FindFirstChild("Arenas")
    local arena = arenas and arenas:FindFirstChild("Arena" .. plot)
    if arena then
        local orig = parseOrigin(arena:GetAttribute("Origin"))
        if orig then return orig * CFrame.new(0, 3.5, 0) end
        local cf = arena:GetBoundingBox()
        return cf * CFrame.new(0, 3.5, 0)
    end
    return CFrame.new(0, 4, -165)
end

------------------------------------------------------
-- Smooth Flight Movement System
------------------------------------------------------
local function smoothFlyTo(targetPos, customSpeed)
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then return end

    local startPos = hrp.Position
    local distance = (targetPos - startPos).Magnitude
    if distance < 0.5 then return end

    local flySpeed = customSpeed or (Options.ScrapFlySpeed and Options.ScrapFlySpeed.Value or 65)
    local duration = math.clamp(distance / flySpeed, 0.08, 1.5)
    local steps = math.max(6, math.floor(duration * 35))

    -- Temporarily disable collision to glide through fences and obstacles
    for _, p in ipairs(char:GetDescendants()) do
        if p:IsA("BasePart") then
            p.CanCollide = false
        end
    end

    for i = 1, steps do
        local alpha = i / steps
        local current = startPos:Lerp(targetPos, alpha)
        hrp.CFrame = CFrame.new(current)
        hrp.AssemblyLinearVelocity = (targetPos - startPos).Unit * flySpeed
        task.wait(duration / steps)
    end

    hrp.CFrame = CFrame.new(targetPos)
    hrp.AssemblyLinearVelocity = Vector3.zero
end

------------------------------------------------------
-- Tabs Setup
------------------------------------------------------
local Tabs = {
    Main = Window:AddTab("Farm & Coop", "hammer"),
    Hatch = Window:AddTab("Eggs & Roster", "egg"),
    Battle = Window:AddTab("Battle & Tower", "swords"),
    Rewards = Window:AddTab("Rewards & Rebirth", "gift"),
    Teleports = Window:AddTab("Teleports & Misc", "map-pin"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

------------------------------------------------------
-- 1. FARM & COOP TAB
------------------------------------------------------
local FarmBox = Tabs.Main:AddLeftGroupbox("Coop Automation")

FarmBox:AddToggle("AutoPet", {
    Text = "Auto Pet Chickens",
    Default = false,
    Tooltip = "Orders chickens to coop & pets them continuously for egg speed & passive corn",
})

FarmBox:AddSlider("PetDelay", {
    Text = "Pet Delay (s)",
    Default = 0.2,
    Min = 0.1,
    Max = 1.0,
    Rounding = 2,
    Compact = false,
})

FarmBox:AddToggle("AutoCollectEggs", {
    Text = "Auto Collect Laid Eggs",
    Default = false,
    Tooltip = "Picks up eggs laid in your coop nests and adds them to inventory",
})

FarmBox:AddDivider()

FarmBox:AddToggle("AutoExpandCoop", {
    Text = "Auto Expand Coop",
    Default = false,
    Tooltip = "Purchases coop expansions when affordable",
})

FarmBox:AddToggle("AutoBuyGenerators", {
    Text = "Auto Buy Generators",
    Default = false,
    Tooltip = "Purchases free generator slots automatically",
})

FarmBox:AddToggle("AutoUpgradeGenerators", {
    Text = "Auto Upgrade Generators",
    Default = false,
    Tooltip = "Upgrades active generator slots with rate-limit protection",
})

FarmBox:AddToggle("AutoUpgradeRecycler", {
    Text = "Auto Upgrade Recycler",
    Default = false,
    Tooltip = "Upgrades your plot recycler machine whenever requirements are met",
})

local ActionsBox = Tabs.Main:AddRightGroupbox("Coop Quick Actions")

ActionsBox:AddButton({
    Text = "Pet Chickens Once",
    Func = function()
        safeFire("SetChickenOrder", "coop")
        safeFire("PetChicken")
        Library:Notify({ Title = "NeColman Hub", Description = "Petted Chickens!", Time = 2 })
    end,
})

ActionsBox:AddButton({
    Text = "Collect Laid Eggs Once",
    Func = function()
        local eggsFolder = workspace:FindFirstChild("NestEggs")
        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local count = 0
        if eggsFolder and hrp then
            local myUserId = LocalPlayer.UserId
            for _, egg in ipairs(eggsFolder:GetChildren()) do
                if egg:IsA("BasePart") then
                    local owner = egg:GetAttribute("owner")
                    if owner == nil or owner == myUserId then
                        egg.CFrame = hrp.CFrame
                        count = count + 1
                    end
                end
            end
        end
        Library:Notify({ Title = "NeColman Hub", Description = `Collected {count} laid eggs!`, Time = 2 })
    end,
})

------------------------------------------------------
-- 2. EGGS & ROSTER TAB
------------------------------------------------------
local HatchBox = Tabs.Hatch:AddLeftGroupbox("Egg Hatching")

local eggTierList = {
    "feed", "barn", "storm", "crown", "golden",
    "ordnance", "arena", "fang", "charm", "void",
    "circuit", "haunt", "diner", "bloom", "meme",
    "rival", "hotEgg"
}

HatchBox:AddDropdown("EggTier", {
    Values = eggTierList,
    Default = "feed",
    Multi = false,
    Text = "Select Egg Tier",
    Tooltip = "Choose which egg tier to hatch (ensure you collected eggs from your coop first!)",
})

HatchBox:AddDropdown("HatchMode", {
    Values = { "Multi Batch (HatchEggs)", "Single (HatchEgg)" },
    Default = "Single (HatchEgg)",
    Multi = false,
    Text = "Hatch Mode",
})

HatchBox:AddSlider("HatchAmount", {
    Text = "Batch Amount",
    Default = 10,
    Min = 1,
    Max = 10,
    Rounding = 0,
    Compact = false,
})

HatchBox:AddSlider("HatchDelay", {
    Text = "Hatch Interval (s)",
    Default = 1.0,
    Min = 0.9,
    Max = 4.0,
    Rounding = 2,
    Compact = false,
})

HatchBox:AddDivider()

HatchBox:AddToggle("AutoHatch", {
    Text = "Auto Hatch Eggs",
    Default = false,
    Tooltip = "Hatches eggs from your inventory continuously",
})

HatchBox:AddButton({
    Text = "Hatch Once (Selected Tier)",
    Func = function()
        local tier = Options.EggTier.Value
        local mode = Options.HatchMode.Value
        local amount = Options.HatchAmount.Value
        local res
        if mode == "Single (HatchEgg)" then
            res = safeInvoke("HatchEgg", tier)
        else
            res = safeInvoke("HatchEggs", tier, amount)
        end
        if res and res.ok then
            Library:Notify({ Title = "NeColman Hub", Description = `Successfully hatched {tier} egg!`, Time = 3 })
        elseif res and res.error then
            Library:Notify({ Title = "NeColman Hub", Description = `Hatch note: {res.error}`, Time = 3 })
        end
    end,
})

local RosterBox = Tabs.Hatch:AddRightGroupbox("Chicken Roster & Fusion")

RosterBox:AddToggle("AutoFuse", {
    Text = "Auto Fuse Chickens",
    Default = false,
    Tooltip = "Automatically fuses non-favorite chickens to mutate higher tiers",
})

RosterBox:AddToggle("AutoEquipBest", {
    Text = "Auto Equip Best Chicken",
    Default = false,
    Tooltip = "Equips your strongest chicken for battle",
})

RosterBox:AddDivider()

local rarityList = { "common", "uncommon", "rare", "epic", "legendary", "mythic" }

RosterBox:AddDropdown("AutoSellRarities", {
    Values = rarityList,
    Default = { "common" },
    Multi = true,
    Text = "Auto-Sell Rarities",
    Tooltip = "Rarities that will be automatically sold",
})

RosterBox:AddToggle("AutoSell", {
    Text = "Auto Sell Selected Rarities",
    Default = false,
    Tooltip = "Automatically sells unequipped and non-favorite chickens matching chosen rarities",
})

------------------------------------------------------
-- 3. BATTLE & TOWER TAB
------------------------------------------------------
local TowerBox = Tabs.Battle:AddLeftGroupbox("Tower Climber")

TowerBox:AddToggle("AutoClimbTower", {
    Text = "Auto Climb Tower",
    Default = false,
    Tooltip = "Continuously climbs tower floors and advances automatically",
})

TowerBox:AddToggle("AutoDeclineTowerContinue", {
    Text = "Auto Skip 'No Thanks' on Loss",
    Default = true,
    Tooltip = "Automatically dismisses the continue offer when defeated on a tower floor so you don't waste time waiting.",
})

TowerBox:AddSlider("TowerDelay", {
    Text = "Delay Between Tower Runs (s)",
    Default = 3.0,
    Min = 0.5,
    Max = 15.0,
    Rounding = 1,
    Compact = false,
    Tooltip = "Cooldown time to wait after a tower match finishes before starting the next floor.",
})

TowerBox:AddDivider()

TowerBox:AddSlider("TowerFloorNum", {
    Text = "Select Floor",
    Default = 1,
    Min = 1,
    Max = 100,
    Rounding = 0,
    Compact = false,
})

TowerBox:AddButton({
    Text = "Start Selected Floor",
    Func = function()
        local floor = Options.TowerFloorNum.Value
        safeFire("SetChickenOrder", "tower")
        local res = safeInvoke("TowerStart", floor)
        if res and res.ok then
            Library:Notify({ Title = "NeColman Hub", Description = `Started Tower Floor {floor}!`, Time = 2 })
        end
    end,
})

TowerBox:AddButton({
    Text = "Surrender Floor",
    Func = function()
        safeInvoke("TowerSurrender")
        Library:Notify({ Title = "NeColman Hub", Description = "Tower surrendered", Time = 2 })
    end,
})

local BattleBox = Tabs.Battle:AddRightGroupbox("Pit & World Events")

BattleBox:AddToggle("AutoGoose", {
    Text = "Auto Goose Boss Damage",
    Default = false,
    Tooltip = "Automatically deals damage to the Goose Boss event",
})

BattleBox:AddToggle("AutoHotEgg", {
    Text = "Auto Hot Egg Event Claim",
    Default = false,
    Tooltip = "Automatically claims rewards from Blazing Hot Egg events",
})

BattleBox:AddDivider()

BattleBox:AddButton({
    Text = "Set Chicken Mode: Tower",
    Func = function()
        safeFire("SetChickenOrder", "tower")
        Library:Notify({ Title = "NeColman Hub", Description = "Ordered Chickens to Tower", Time = 2 })
    end,
})

BattleBox:AddButton({
    Text = "Set Chicken Mode: Pit",
    Func = function()
        safeFire("SetChickenOrder", "pit")
        Library:Notify({ Title = "NeColman Hub", Description = "Ordered Chickens to Pit", Time = 2 })
    end,
})

BattleBox:AddButton({
    Text = "Set Chicken Mode: Coop / Rest",
    Func = function()
        safeFire("SetChickenOrder", "coop")
        Library:Notify({ Title = "NeColman Hub", Description = "Ordered Chickens to Coop", Time = 2 })
    end,
})

------------------------------------------------------
-- 4. REWARDS & REBIRTH TAB
------------------------------------------------------
local RewardsBox = Tabs.Rewards:AddLeftGroupbox("Progression & Claims")

RewardsBox:AddToggle("AutoDaily", {
    Text = "Auto Claim Daily Streak",
    Default = false,
    Tooltip = "Claims daily streak rewards automatically",
})

RewardsBox:AddToggle("AutoPlaytimeGifts", {
    Text = "Auto Claim Playtime Gifts",
    Default = false,
    Tooltip = "Claims playtime gift milestones (slots 1-12) with safe spacing",
})

RewardsBox:AddToggle("AutoMissions", {
    Text = "Auto Claim Missions",
    Default = false,
    Tooltip = "Automatically claims finished daily, weekly, and life missions",
})

RewardsBox:AddToggle("AutoPass", {
    Text = "Auto Claim Battle Pass",
    Default = false,
    Tooltip = "Claims free battle pass tiers",
})

RewardsBox:AddToggle("AutoSocial", {
    Text = "Auto Claim Social Bonus",
    Default = false,
    Tooltip = "Claims group join and social rewards",
})

RewardsBox:AddDivider()

RewardsBox:AddButton({
    Text = "Claim All Rewards Now",
    Func = function()
        task.spawn(function()
            safeInvoke("DailyClaim", "day", nil)
            for slot = 1, 12 do
                safeInvoke("DailyClaim", "session", slot)
            end
            safeInvoke("SocialClaim")
            for tier = 1, 50 do
                safeInvoke("PassClaim", tier, "free")
            end
            Library:Notify({ Title = "NeColman Hub", Description = "Processed all available reward claims!", Time = 3 })
        end)
    end,
})

local RebirthBox = Tabs.Rewards:AddRightGroupbox("Rebirth & Codes")

RebirthBox:AddToggle("AutoRebirth", {
    Text = "Auto Rebirth (Surrenders Tower)",
    Default = false,
    Tooltip = "Instantly surrenders current tower floor and triggers rebirth the moment requirement is met",
})

RebirthBox:AddToggle("AutoSurrenderOnRebirth", {
    Text = "Auto Surrender Tower on Rebirth",
    Default = true,
    Tooltip = "Exits the active tower floor immediately when the rebirth requirement is satisfied so you can rebirth immediately.",
})

RebirthBox:AddButton({
    Text = "Rebirth Once",
    Func = function()
        local res = safeInvoke("Rebirth")
        if res and res.ok then
            Library:Notify({ Title = "NeColman Hub", Description = "Rebirth Successful!", Time = 2 })
        elseif res and res.error then
            Library:Notify({ Title = "NeColman Hub", Description = `Rebirth requirement: {res.error}`, Time = 3 })
        end
    end,
})

RebirthBox:AddDivider()

RebirthBox:AddButton({
    Text = "Redeem Working Codes",
    Func = function()
        task.spawn(function()
            local codes = { "WELCOME" }
            for _, c in ipairs(codes) do
                safeInvoke("RedeemCode", c)
            end
            Library:Notify({ Title = "NeColman Hub", Description = "Redeemed known codes!", Time = 2 })
        end)
    end,
})

------------------------------------------------------
-- 5. TELEPORTS & MISC TAB
------------------------------------------------------
local TpBox = Tabs.Teleports:AddLeftGroupbox("World Teleports")

TpBox:AddButton({
    Text = "Teleport to My Coop",
    Func = function()
        local cf = getCoopCFrame()
        if cf then
            smoothFlyTo(cf.Position, 75)
        end
    end,
})

TpBox:AddButton({
    Text = "Teleport to My Recycler",
    Func = function()
        local cf = getRecyclerCFrame()
        if cf then
            smoothFlyTo(cf.Position, 75)
        end
    end,
})

TpBox:AddButton({
    Text = "Teleport to My Arena / Tower",
    Func = function()
        local cf = getArenaCFrame()
        if cf then
            smoothFlyTo(cf.Position, 75)
        end
    end,
})

TpBox:AddButton({
    Text = "Teleport to Battle Pit",
    Func = function()
        smoothFlyTo(Vector3.new(0.16, 3.6, -0.1), 75)
    end,
})

local PlayerBox = Tabs.Teleports:AddRightGroupbox("Player Utilities")

PlayerBox:AddToggle("WalkSpeedToggle", {
    Text = "Enable Custom WalkSpeed",
    Default = false,
    Tooltip = "Toggle custom movement speed (press keybind to toggle)",
}):AddKeyPicker("WalkSpeedKeybind", {
    Default = "Q",
    SyncToggleState = true,
    Mode = "Toggle",
    Text = "Custom WalkSpeed",
    NoUI = false,
})

PlayerBox:AddSlider("WalkSpeedSlider", {
    Text = "WalkSpeed",
    Default = 16,
    Min = 16,
    Max = 250,
    Rounding = 0,
    Compact = false,
})

PlayerBox:AddToggle("JumpPowerToggle", {
    Text = "Enable Custom JumpPower",
    Default = false,
})

PlayerBox:AddSlider("JumpPowerSlider", {
    Text = "JumpPower",
    Default = 50,
    Min = 50,
    Max = 300,
    Rounding = 0,
    Compact = false,
})

PlayerBox:AddToggle("InfJump", {
    Text = "Infinite Jump",
    Default = false,
})

PlayerBox:AddToggle("Noclip", {
    Text = "Noclip",
    Default = false,
})

PlayerBox:AddToggle("AntiAFK", {
    Text = "Anti-AFK (Stay Online)",
    Default = true,
    Tooltip = "Prevents Roblox's 20-minute idle disconnect so you can farm continuously without being kicked.",
})

local defaultWalkSpeed = 16
local defaultJumpPower = 50

local function updateWalkSpeed()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildWhichIsA("Humanoid")
    if hum then
        if Toggles.WalkSpeedToggle and Toggles.WalkSpeedToggle.Value then
            hum.WalkSpeed = Options.WalkSpeedSlider and Options.WalkSpeedSlider.Value or defaultWalkSpeed
        else
            hum.WalkSpeed = defaultWalkSpeed
        end
    end
end

local function updateJumpPower()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildWhichIsA("Humanoid")
    if hum then
        if Toggles.JumpPowerToggle and Toggles.JumpPowerToggle.Value then
            hum.UseJumpPower = true
            hum.JumpPower = Options.JumpPowerSlider and Options.JumpPowerSlider.Value or defaultJumpPower
        else
            hum.UseJumpPower = true
            hum.JumpPower = defaultJumpPower
        end
    end
end

Toggles.WalkSpeedToggle:OnChanged(function()
    updateWalkSpeed()
end)

Options.WalkSpeedSlider:OnChanged(function()
    updateWalkSpeed()
end)

Toggles.JumpPowerToggle:OnChanged(function()
    updateJumpPower()
end)

Options.JumpPowerSlider:OnChanged(function()
    updateJumpPower()
end)

LocalPlayer.CharacterAdded:Connect(function(char)
    local hum = char:WaitForChild("Humanoid", 5)
    if hum then
        task.wait(0.2)
        updateWalkSpeed()
        updateJumpPower()
    end
end)

-- Continuous player modifier handlers
RunService.Stepped:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end

    local hum = char:FindFirstChildWhichIsA("Humanoid")
    if hum then
        if Toggles.WalkSpeedToggle and Toggles.WalkSpeedToggle.Value then
            hum.WalkSpeed = Options.WalkSpeedSlider and Options.WalkSpeedSlider.Value or defaultWalkSpeed
        end
        if Toggles.JumpPowerToggle and Toggles.JumpPowerToggle.Value then
            hum.UseJumpPower = true
            hum.JumpPower = Options.JumpPowerSlider and Options.JumpPowerSlider.Value or defaultJumpPower
        end
    end

    if Toggles.Noclip and Toggles.Noclip.Value then
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") and part.CanCollide then
                part.CanCollide = false
            end
        end
    end
end)

UserInputService.JumpRequest:Connect(function()
    if Toggles.InfJump and Toggles.InfJump.Value then
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildWhichIsA("Humanoid")
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Jumping)
        end
    end
end)

-- Anti-AFK System (Signal Interceptor + Periodic Keepalive)
LocalPlayer.Idled:Connect(function()
    if Toggles.AntiAFK and Toggles.AntiAFK.Value then
        pcall(function()
            VirtualUser:CaptureController()
            VirtualUser:ClickButton2(Vector2.zero)
        end)
    end
end)

task.spawn(function()
    while true do
        task.wait(480) -- Every 8 minutes
        if Toggles.AntiAFK and Toggles.AntiAFK.Value then
            pcall(function()
                VirtualUser:CaptureController()
                VirtualUser:ClickButton2(Vector2.zero)
            end)
        end
    end
end)

------------------------------------------------------
-- Background Automation Loops (Rate-Limit Protected)
------------------------------------------------------

-- 1. Auto Pet Loop
task.spawn(function()
    while true do
        if Toggles.AutoPet and Toggles.AutoPet.Value then
            safeFire("SetChickenOrder", "coop")
            safeFire("PetChicken")
            local delayTime = Options.PetDelay and Options.PetDelay.Value or 0.2
            task.wait(delayTime)
        else
            task.wait(0.5)
        end
    end
end)

-- 2. Auto Collect Laid Eggs
task.spawn(function()
    while true do
        if Toggles.AutoCollectEggs and Toggles.AutoCollectEggs.Value then
            local eggsFolder = workspace:FindFirstChild("NestEggs")
            local char = LocalPlayer.Character
            local hrp = char and char:FindFirstChild("HumanoidRootPart")
            if eggsFolder and hrp then
                local myUserId = LocalPlayer.UserId
                for _, egg in ipairs(eggsFolder:GetChildren()) do
                    if egg:IsA("BasePart") then
                        local owner = egg:GetAttribute("owner")
                        if owner == nil or owner == myUserId then
                            egg.CFrame = hrp.CFrame
                        end
                    end
                end
            end
            task.wait(1.0)
        else
            task.wait(0.5)
        end
    end
end)

-- 3. Fast Accurate Auto Coop / Generator / Recycler Upgrades (Spread Level Engine)
task.spawn(function()
    while true do
        local acted = false
        if DataServiceClient then
            local rawMoney = DataServiceClient:get({"money"}) or 0
            local coopData = DataServiceClient:get({"coop"})
            local scrapData = DataServiceClient:get({"scrap"}) or {}
            local rebirthData = DataServiceClient:get({"rebirth"})
            local towerData = DataServiceClient:get({"tower"})

            local rebirths = (type(rebirthData) == "table" and rebirthData.count) or (type(rebirthData) == "number" and rebirthData) or 0
            local bestFloor = (towerData and towerData.best) or 0

            -- Priority 1: Buy new generator slots if available and affordable
            if not acted and Toggles.AutoBuyGenerators and Toggles.AutoBuyGenerators.Value and coopData and CoopView then
                local owned = #coopData.generators
                if owned < coopData.slots and CoopView.canBuyGenerator(coopData.slots, owned) then
                    local buyCost = CoopView.buyGeneratorCost(owned)
                    if rawMoney >= buyCost then
                        safeInvoke("BuyGenerator", owned + 1)
                        acted = true
                    end
                end
            end

            -- Priority 2: Spread-level generator upgrades (prioritize lowest level slot first)
            if not acted and Toggles.AutoUpgradeGenerators and Toggles.AutoUpgradeGenerators.Value and coopData and coopData.generators and CoopView then
                local candidates = {}
                for _, g in ipairs(coopData.generators) do
                    if CoopView.canUpgrade(g.level) then
                        local cost = CoopView.upgradeCost(g.level)
                        table.insert(candidates, {
                            slot = g.slot,
                            level = g.level,
                            cost = cost
                        })
                    end
                end

                -- Sort by level ascending (spread leveling)
                table.sort(candidates, function(a, b)
                    if a.level == b.level then
                        return a.slot < b.slot
                    end
                    return a.level < b.level
                end)

                -- Upgrade the lowest-level generator that we can afford
                for _, cand in ipairs(candidates) do
                    if rawMoney >= cand.cost then
                        safeInvoke("UpgradeGenerator", cand.slot)
                        acted = true
                        break
                    end
                end
            end

            -- Priority 3: Expand coop when all current slots are filled and affordable
            if not acted and Toggles.AutoExpandCoop and Toggles.AutoExpandCoop.Value and coopData and CoopView then
                if CoopView.canExpand(coopData.slots) and #coopData.generators >= coopData.slots then
                    local expandCost = CoopView.expandCost(coopData.slots)
                    if rawMoney >= expandCost then
                        safeInvoke("ExpandCoop")
                        acted = true
                    end
                end
            end

            -- Priority 4: Upgrade Recycler when requirements and costs are met
            if not acted and Toggles.AutoUpgradeRecycler and Toggles.AutoUpgradeRecycler.Value and RecyclerView then
                local recLevel = scrapData.recyclerLevel or 0
                if RecyclerView.canUpgrade(recLevel, rebirths) and RecyclerView.floorUnlocked(recLevel, bestFloor) then
                    local recCost = RecyclerView.upgradeCost(recLevel)
                    if rawMoney >= recCost then
                        safeInvoke("UpgradeRecycler")
                        acted = true
                    end
                end
            end
        end

        -- Fast polling rate (0.15s when waiting for money, paced safely by safeInvoke when acting)
        task.wait(0.15)
    end
end)

-- 5. Auto Hatch Loop
task.spawn(function()
    while true do
        if Toggles.AutoHatch and Toggles.AutoHatch.Value then
            local tier = Options.EggTier and Options.EggTier.Value or "feed"
            local mode = Options.HatchMode and Options.HatchMode.Value or "Single (HatchEgg)"
            local amount = Options.HatchAmount and Options.HatchAmount.Value or 10
            if mode == "Single (HatchEgg)" then
                safeInvoke("HatchEgg", tier)
            else
                safeInvoke("HatchEggs", tier, amount)
            end
            local delayTime = Options.HatchDelay and Options.HatchDelay.Value or 1.0
            task.wait(delayTime)
        else
            task.wait(0.5)
        end
    end
end)

-- 6. Auto Tower Climber & Auto Decline Continue
local towerOfferRemote = RemotesFolder and RemotesFolder:FindFirstChild("TowerContinueOffer")
if towerOfferRemote and towerOfferRemote:IsA("RemoteEvent") then
    towerOfferRemote.OnClientEvent:Connect(function()
        if Toggles.AutoDeclineTowerContinue and Toggles.AutoDeclineTowerContinue.Value then
            task.wait(0.2)
            safeFire("TowerContinueDecline")
        end
    end)
end

task.spawn(function()
    while true do
        if Toggles.AutoClimbTower and Toggles.AutoClimbTower.Value then
            -- Check if already ready to rebirth before starting another floor
            local rebirthReady = false
            if Toggles.AutoRebirth and Toggles.AutoRebirth.Value and DataServiceClient and RebirthBonus then
                local rebirthData = DataServiceClient:get({"rebirth"}) or {}
                local towerData = DataServiceClient:get({"tower"}) or {}
                local count = rebirthData.count or 0
                local reqFloor = RebirthBonus.requirementFloor(count)
                local currentFloor = (towerData and tonumber(towerData.best)) or 0
                if currentFloor >= reqFloor and reqFloor > 0 then
                    rebirthReady = true
                end
            end

            if not rebirthReady then
                safeFire("SetChickenOrder", "tower")
                safeInvoke("TowerStart")
                local delayTime = Options.TowerDelay and Options.TowerDelay.Value or 3.0
                task.wait(delayTime)
            else
                task.wait(1.0)
            end
        else
            task.wait(0.5)
        end
    end
end)

-- 7. Auto Boss Damage / Event Claim Loop
task.spawn(function()
    while true do
        if Toggles.AutoGoose and Toggles.AutoGoose.Value then
            safeFire("GooseDamage")
        end
        if Toggles.AutoHotEgg and Toggles.AutoHotEgg.Value then
            safeFire("HotEggReward")
        end
        task.wait(0.5)
    end
end)

-- 8. Auto Claims & Rebirth Loop
task.spawn(function()
    while true do
        if Toggles.AutoDaily and Toggles.AutoDaily.Value then
            safeInvoke("DailyClaim", "day", nil)
        end
        if Toggles.AutoPlaytimeGifts and Toggles.AutoPlaytimeGifts.Value then
            for slot = 1, 12 do
                if not (Toggles.AutoPlaytimeGifts and Toggles.AutoPlaytimeGifts.Value) then break end
                safeInvoke("DailyClaim", "session", slot)
            end
        end
        if Toggles.AutoSocial and Toggles.AutoSocial.Value then
            safeInvoke("SocialClaim")
        end
        if Toggles.AutoPass and Toggles.AutoPass.Value then
            for tier = 1, 30 do
                if not (Toggles.AutoPass and Toggles.AutoPass.Value) then break end
                safeInvoke("PassClaim", tier, "free")
            end
        end

        -- Instant Auto Rebirth with Tower Surrender
        if Toggles.AutoRebirth and Toggles.AutoRebirth.Value and DataServiceClient and RebirthBonus then
            local rebirthData = DataServiceClient:get({"rebirth"}) or {}
            local towerData = DataServiceClient:get({"tower"}) or {}
            local count = rebirthData.count or 0
            local reqFloor = RebirthBonus.requirementFloor(count)
            local currentFloor = (towerData and tonumber(towerData.best)) or 0

            if currentFloor >= reqFloor and reqFloor > 0 then
                if isTowerMatchActive() and (Toggles.AutoSurrenderOnRebirth == nil or Toggles.AutoSurrenderOnRebirth.Value) then
                    safeInvoke("TowerSurrender")
                end
                safeFire("SetChickenOrder", "coop")
                task.wait(0.2)
                local res = safeInvoke("Rebirth")
                if res and res.ok then
                    Library:Notify({ Title = "NeColman Hub", Description = `Rebirthed to Rebirth {count + 1}!`, Time = 3 })
                end
            end
        end

        task.wait(1.5)
    end
end)

------------------------------------------------------
-- 6. UI SETTINGS TAB
------------------------------------------------------
local MenuGroup = Tabs["UI Settings"]:AddLeftGroupbox("Menu Settings")

MenuGroup:AddButton("Unload Menu", function()
    Library:Unload()
end)

MenuGroup:AddLabel("Menu Keybind"):AddKeyPicker("MenuKeybind", {
    Default = "LeftControl",
    NoUI = true,
    Text = "Menu keybind",
})

Library.ToggleKeybind = Options.MenuKeybind

-- Theme & Save Manager Configuration
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

ThemeManager:SetFolder("NeColmanHub")
SaveManager:SetFolder("NeColmanHub/chicken-fighter")

SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

SaveManager:LoadAutoloadConfig()

Library:Notify({
    Title = "NeColman Hub Loaded",
    Description = "Grow a Chicken Fighter v2.3 is active! Press LeftControl to toggle UI, Q for WalkSpeed.",
    Time = 5,
})
