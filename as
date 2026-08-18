--[[
    Grow a Chicken Fighter | Iggy Hub v6.8
    - NEW: Live Coop Stats Dashboard (Corn Rate, Corn Stored, Dropped Eggs vs Cap, Slots & Feeders)
    - NEW: Smart Spend Priority System (Cheapest First / Feeders First / Coop Expand First / Recycler First / Balanced)
    - CLEANED: Removed all "Generator" naming -> pure "Feeder" terminology
    - SAFE: 100% Anti-Cheat BAC-Proof Legit Egg Collection
    - Exact Species & Exact Rarity Auto Fuse (Strict same species + same tier only)
    - Built-in Auto-Ignore for Favorited & Active Chickens
    - 100% Accurate Smart Egg Hatching Engine (Live `roster.eggs` bag scanner)
    - Instant Auto Rebirth (0.3s response time, zero delay when returning to coop)
    - Automatic GUI Cleanup (Clears all previous ghost windows)
    - Real-Time HP Monitor & Live % Healing
    - Skip Ahead to Highest Wave (Frontier)
    - Strict Main Pit Loose Scrap Farming
]]

if not game:IsLoaded() then
    game.Loaded:Wait()
end

-- 1. Robust Full Cleanup of Previous UI Instances
local CoreGui = game:GetService("CoreGui")
local hui = (type(gethui) == "function" and gethui()) or CoreGui

for _, child in ipairs(hui:GetChildren()) do
    if child:IsA("ScreenGui") and (child.Name == "Obsidian" or child.Name:find("NeColman") or child.Name:find("Iggy")) then
        pcall(function() child:Destroy() end)
    end
end

if _G.IggyUI then
    pcall(function() _G.IggyUI:Destroy() end)
    _G.IggyUI = nil
end
if _G.NeColmanUI then
    pcall(function() _G.NeColmanUI:Destroy() end)
    _G.NeColmanUI = nil
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
    Title = "Iggy Hub",
    Footer = "version: 6.8",
    Icon = nil,
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
local LocalPlayer = Players.LocalPlayer

-- Forward-declared UI Labels
local ScrapStatusLabel = nil
local ScrapCountLabel = nil
local ScrapCarryLabel = nil
local IncubatorStatusLabel = nil
local IncubatorStoredLabel = nil
local ExploitStatusLabel = nil
local TowerStatusLabel = nil
local TowerTimerLabel = nil
local HatchStatusLabel = nil
local EggSummaryLabel = nil
local FuseStatusLabel = nil
local FusePairsLabel = nil

-- Coop Dashboard Labels
local CoopRateLabel = nil
local CoopCornLabel = nil
local CoopEggsCapLabel = nil
local CoopSlotsLabel = nil
local CoopSpendStatusLabel = nil

local function updateScrapStatus(text)
    if ScrapStatusLabel and ScrapStatusLabel.SetText then
        pcall(function() ScrapStatusLabel:SetText(text) end)
    end
end

local function updateScrapCount(count)
    if ScrapCountLabel and ScrapCountLabel.SetText then
        pcall(function() ScrapCountLabel:SetText(`Available Scraps (Pit): {count}`) end)
    end
end

local function updateScrapCarry(carried)
    if ScrapCarryLabel and ScrapCarryLabel.SetText then
        pcall(function() ScrapCarryLabel:SetText(`Carried Scrap: {carried}`) end)
    end
end

local function updateTowerTimer(text)
    if TowerTimerLabel and TowerTimerLabel.SetText then
        pcall(function() TowerTimerLabel:SetText(text) end)
    end
end

-- Real-time Game Data Modules
local DataServicePackage = ReplicatedStorage:FindFirstChild("Packages") and ReplicatedStorage.Packages:FindFirstChild("DataService")
local DataServiceClient = DataServicePackage and require(DataServicePackage).client

local CoopViewModule = ReplicatedStorage:FindFirstChild("Features") and ReplicatedStorage.Features:FindFirstChild("Coop") and ReplicatedStorage.Features.Coop:FindFirstChild("CoopView")
local CoopView = CoopViewModule and require(CoopViewModule)

local RecyclerViewModule = ReplicatedStorage:FindFirstChild("Features") and ReplicatedStorage.Features:FindFirstChild("Scrap") and ReplicatedStorage.Features.Scrap:FindFirstChild("RecyclerView")
local RecyclerView = RecyclerViewModule and require(RecyclerViewModule)

local RebirthBonusModule = ReplicatedStorage:FindFirstChild("Core") and ReplicatedStorage.Core:FindFirstChild("Progression") and ReplicatedStorage.Core.Progression:FindFirstChild("RebirthBonus")
local RebirthBonus = RebirthBonusModule and require(RebirthBonusModule)

local GameConfigModule = ReplicatedStorage:FindFirstChild("Content") and ReplicatedStorage.Content:FindFirstChild("GameConfig")
local GameConfig = GameConfigModule and require(GameConfigModule)

local CatalogModule = ReplicatedStorage:FindFirstChild("Content") and ReplicatedStorage.Content:FindFirstChild("Catalog")
local Catalog = CatalogModule and require(CatalogModule)

------------------------------------------------------
-- Anti-BAC-2512 Protected Rate-Limiter (1.5s Cooldown)
------------------------------------------------------
local RemotesFolder = ReplicatedStorage:WaitForChild("Remotes", 10)
local lastInvokeTime = 0
local INVOKE_COOLDOWN = 1.5

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
-- Dynamic Plot & Coordinates
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
        if orig then return orig * CFrame.new(0, 1.5, -3.2) end
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

local function isTowerMatchActive()
    local plot = getMyPlot()
    local arenas = workspace:FindFirstChild("Arenas")
    local arena = arenas and arenas:FindFirstChild("Arena" .. plot)
    if arena and arena:GetAttribute("TowerActive") == true then
        return true
    end

    if DataServiceClient then
        local tower = DataServiceClient:get({"tower"})
        if tower and (tower.active == true or (tower.match and tower.match.active)) then
            return true
        end
    end
    return false
end

-- Real-Time Chicken Health Tracker (Replicated Attribute + DataService)
local function getActiveChickenHealth()
    local plot = getMyPlot()
    local body = workspace:FindFirstChild("ChickenBodies") and workspace.ChickenBodies:FindFirstChild("ChickenBody_coop:" .. plot)
    if body then
        local ovHpFrac = body:GetAttribute("ovHpFrac")
        if ovHpFrac ~= nil then
            return math.clamp(tonumber(ovHpFrac) or 1.0, 0, 1)
        end
    end

    if DataServiceClient then
        local roster = DataServiceClient:get({"roster"})
        if roster and roster.chickens and roster.activeId then
            for _, c in ipairs(roster.chickens) do
                if c.id == roster.activeId then
                    return math.clamp(tonumber(c.health) or 1.0, 0, 1)
                end
            end
        end
    end
    return 1.0
end

local function isRebirthEligible()
    if DataServiceClient and RebirthBonus then
        local rebirthData = DataServiceClient:get({"rebirth"}) or {}
        local towerData = DataServiceClient:get({"tower"}) or {}
        local count = rebirthData.count or 0
        local reqFloor = RebirthBonus.requirementFloor(count)
        local currentFloor = (towerData and tonumber(towerData.best)) or 0
        if currentFloor >= reqFloor and reqFloor > 0 then
            return true, count, reqFloor
        end
    end
    return false, 0, 0
end

------------------------------------------------------
-- Accurate Egg Inventory & Catalog Scanner
------------------------------------------------------
local eggNameLookup = {
    feed = "Scratch Egg",
    barn = "Nest Egg",
    storm = "Thunder Egg",
    crown = "Royal Egg",
    golden = "Fortune Egg",
    ordnance = "Ordnance Egg",
    arena = "Arena Egg",
    fang = "Fang Egg",
    charm = "Charm Egg",
    void = "Void Egg",
    circuit = "Circuit Egg",
    haunt = "Haunt Egg",
    diner = "Diner Egg",
    bloom = "Bloom Egg",
    meme = "Cursed Egg",
    rival = "Grudge Egg",
    hotEgg = "Blazing Egg",
    colossus = "Colossus Egg"
}

local cachedEggDropdownList = {}
local eggDropdownToTierMap = {}

local function getOwnedEggInventory()
    local owned = {}
    local total = 0
    if DataServiceClient then
        local roster = DataServiceClient:get({"roster"})
        if roster and roster.eggs then
            for tierId, count in pairs(roster.eggs) do
                local amt = tonumber(count) or 0
                if amt > 0 then
                    owned[tierId] = amt
                    total = total + amt
                end
            end
        end
    end
    return owned, total
end

local function refreshEggDropdownList()
    local owned, total = getOwnedEggInventory()
    local list = {}
    local mapping = {}

    -- First add eggs that the player actually owns (sorted by quantity)
    local ownedList = {}
    for tierId, amt in pairs(owned) do
        local name = eggNameLookup[tierId] or (Catalog and Catalog.eggs and Catalog.eggs[tierId] and Catalog.eggs[tierId].name) or tierId
        local label = string.format("⭐ [%dx] %s (%s)", amt, name, tierId)
        table.insert(ownedList, { label = label, tierId = tierId, amt = amt })
    end

    table.sort(ownedList, function(a, b) return a.amt > b.amt end)
    for _, item in ipairs(ownedList) do
        table.insert(list, item.label)
        mapping[item.label] = item.tierId
    end

    -- Then append remaining egg tiers (showing 0 in bag)
    local allKnownTiers = {
        "crown", "meme", "arena", "storm", "golden", "feed",
        "barn", "ordnance", "fang", "charm", "void", "circuit",
        "haunt", "diner", "bloom", "rival", "hotEgg", "colossus"
    }

    for _, tierId in ipairs(allKnownTiers) do
        if not owned[tierId] then
            local name = eggNameLookup[tierId] or (Catalog and Catalog.eggs and Catalog.eggs[tierId] and Catalog.eggs[tierId].name) or tierId
            local label = string.format("[0x] %s (%s)", name, tierId)
            table.insert(list, label)
            mapping[label] = tierId
        end
    end

    if #list == 0 then
        table.insert(list, "No Eggs Found")
    end

    cachedEggDropdownList = list
    eggDropdownToTierMap = mapping
    return list, mapping, total, owned
end

refreshEggDropdownList()

------------------------------------------------------
-- Exact Species & Exact Rarity Auto Fusion Engine
------------------------------------------------------
local function calculateGenomeScore(genome)
    if not genome or type(genome) ~= "table" then return 0 end
    local sum = 0
    for _, val in pairs(genome) do
        sum = sum + (tonumber(val) or 0)
    end
    return sum
end

local function getFusionCandidates()
    local pairsToFuse = {}
    if not DataServiceClient then return pairsToFuse end

    local roster = DataServiceClient:get({"roster"})
    if not roster or not roster.chickens then return pairsToFuse end

    local activeId = roster.activeId
    local allowedRarities = (Options.FuseRarities and Options.FuseRarities.Value) or { common = true, uncommon = true, rare = true, epic = true }
    local mode = (Options.FusionMode and Options.FusionMode.Value) or "Exact Species & Rarity (e.g. Rare Tengu + Rare Tengu)"
    local isExactSpeciesAndRarity = mode:find("Exact Species & Rarity") ~= nil or mode:find("Same Species") ~= nil

    -- Group non-favorite, non-active chickens
    local grouped = {}
    for _, c in ipairs(roster.chickens) do
        local r = (c.rarity and c.rarity:lower()) or "common"
        local isFavorite = (c.favorite == true)
        local isActive = (c.id == activeId)

        if not isFavorite and not isActive and allowedRarities[r] then
            -- Group by EXACT Species AND EXACT Rarity (e.g. "tengu_rooster_rare" with "tengu_rooster_rare")
            local groupKey = isExactSpeciesAndRarity and string.format("%s_%s", c.typeId or "unknown", r) or r
            if not grouped[groupKey] then grouped[groupKey] = {} end
            table.insert(grouped[groupKey], c)
        end
    end

    -- For each group, sort by genome score & level (highest first) and pair up
    for groupKey, list in pairs(grouped) do
        table.sort(list, function(a, b)
            local scoreA = calculateGenomeScore(a.genome) + ((a.level or 1) * 2)
            local scoreB = calculateGenomeScore(b.genome) + ((b.level or 1) * 2)
            return scoreA > scoreB
        end)

        local i = 1
        while (i + 1) <= #list do
            local baseChicken = list[i]
            local sacrificeChicken = list[i + 1]
            local displayName = baseChicken.nickname or baseChicken.typeId or "Chicken"
            table.insert(pairsToFuse, {
                a = baseChicken,
                b = sacrificeChicken,
                rarity = baseChicken.rarity or "common",
                species = baseChicken.typeId or "unknown",
                displayName = displayName
            })
            i = i + 2
        end
    end

    return pairsToFuse
end

------------------------------------------------------
-- Guaranteed Jump & Obstacle Clearance
------------------------------------------------------
local function performJump()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildWhichIsA("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if hum and hrp then
        hum:ChangeState(Enum.HumanoidStateType.Jumping)
        hrp.AssemblyLinearVelocity = Vector3.new(hrp.AssemblyLinearVelocity.X, 32, hrp.AssemblyLinearVelocity.Z)
    end
end

local function legitWalkTo(targetPos, timeout, autoJump)
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildWhichIsA("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return false end

    timeout = timeout or 4.0
    autoJump = (autoJump == nil and true or autoJump)
    local startTime = os.clock()
    local lastPos = hrp.Position
    local stuckFrames = 0
    local lastJump = 0

    hum:MoveTo(targetPos)

    while (os.clock() - startTime) < timeout do
        if not char or not hum or not hrp then return false end
        if (hrp.Position - targetPos).Magnitude < 2.5 then
            return true
        end

        local delta = (hrp.Position - lastPos).Magnitude
        if delta < 0.25 and (hrp.Position - targetPos).Magnitude > 2.8 then
            stuckFrames = stuckFrames + 1
            if stuckFrames >= 3 and (os.clock() - lastJump) > 0.8 then
                if autoJump then
                    performJump()
                end
                lastJump = os.clock()
                stuckFrames = 0
            end
        else
            stuckFrames = 0
        end
        lastPos = hrp.Position

        if hum.MoveDirection.Magnitude == 0 and (hrp.Position - targetPos).Magnitude > 2.5 then
            hum:MoveTo(targetPos)
        end
        task.wait(0.04)
    end
    return false
end

------------------------------------------------------
-- Dropped Egg Detection & Walking
------------------------------------------------------
local function getMyDroppedEggs()
    local nestEggs = workspace:FindFirstChild("NestEggs")
    local eggs = {}
    if not nestEggs then return eggs end

    local myUserId = LocalPlayer.UserId
    for _, egg in ipairs(nestEggs:GetChildren()) do
        if egg:IsA("BasePart") and egg:GetAttribute("owner") == myUserId then
            table.insert(eggs, egg)
        end
    end
    return eggs
end

local function walkToAllDroppedEggs()
    local eggs = getMyDroppedEggs()
    local char = LocalPlayer.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp or #eggs == 0 then return false end

    table.sort(eggs, function(a, b)
        return (a.Position - hrp.Position).Magnitude < (b.Position - hrp.Position).Magnitude
    end)

    for _, egg in ipairs(eggs) do
        if egg and egg.Parent then
            legitWalkTo(egg.Position, 3.5, true)
            task.wait(0.04)
        end
    end
    return true
end

------------------------------------------------------
-- Main Battle Pit ONLY Loose Scrap Detection Engine
------------------------------------------------------
local PIT_CENTER = Vector3.new(0, 0, 0)
local PIT_MAX_RADIUS = 36.0
local PIT_MAX_Y = 2.5

local function getAllLooseScraps()
    local scraps = {}

    local pitScrap = workspace:FindFirstChild("PitScrap")
    if pitScrap then
        for _, child in ipairs(pitScrap:GetChildren()) do
            if child:IsA("BasePart") then
                local flatDist = (Vector3.new(child.Position.X, 0, child.Position.Z) - PIT_CENTER).Magnitude
                if flatDist <= PIT_MAX_RADIUS and child.Position.Y <= PIT_MAX_Y then
                    table.insert(scraps, child)
                end
            end
        end
    end

    return scraps
end

local function getScrapCarryCount()
    local char = LocalPlayer.Character
    if char then
        local carried = char:GetAttribute("scrapCarry") or LocalPlayer:GetAttribute("scrapCarry") or 0
        return tonumber(carried) or 0
    end
    return 0
end

local function stepScrapFarmer()
    local char = LocalPlayer.Character
    local hum = char and char:FindFirstChildWhichIsA("Humanoid")
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hum or not hrp then return end

    local scraps = getAllLooseScraps()
    local carried = getScrapCarryCount()
    local batchLimit = Options.ScrapTripBatch and Options.ScrapTripBatch.Value or 5

    updateScrapCount(#scraps)
    updateScrapCarry(carried)

    if carried >= batchLimit or (#scraps == 0 and carried > 0) then
        local recCF = getRecyclerCFrame()
        if recCF then
            updateScrapStatus(`♻️ Depositing {carried} scrap at Recycler...`)
            legitWalkTo(recCF.Position, 5.0, true)
            task.wait(0.2)
        end
        return
    end

    if #scraps == 0 then
        updateScrapStatus("Status: Waiting for Pit scraps...")
        task.wait(0.2)
        return
    end

    table.sort(scraps, function(a, b)
        return (a.Position - hrp.Position).Magnitude < (b.Position - hrp.Position).Magnitude
    end)

    local target = scraps[1]
    if target and target.Parent then
        updateScrapStatus(`🚶 Gathering Pit scrap ({carried}/{batchLimit})...`)
        hum:MoveTo(target.Position)

        local t0 = os.clock()
        local lastPos = hrp.Position
        local stuckCount = 0
        local lastJump = 0

        while (os.clock() - t0) < 3.0 and Toggles.AutoFarmScrap and Toggles.AutoFarmScrap.Value do
            if not target.Parent or (hrp.Position - target.Position).Magnitude < 2.5 then
                break
            end

            if (hrp.Position - lastPos).Magnitude < 0.25 then
                stuckCount = stuckCount + 1
                if stuckCount >= 3 and (os.clock() - lastJump) > 0.8 then
                    performJump()
                    lastJump = os.clock()
                    stuckCount = 0
                end
            else
                stuckCount = 0
            end
            lastPos = hrp.Position

            task.wait(0.03)
        end
    end
end

------------------------------------------------------
-- Egg Timer & Inventory Scanning Helpers
------------------------------------------------------
local function parseEggTimer(text)
    if not text then return nil end
    local m, s = string.match(text, "(%d+):(%d+)")
    if m and s then
        return tonumber(m) * 60 + tonumber(s)
    end
    local singleNum = string.match(text, "(%d+)")
    if singleNum then
        return tonumber(singleNum)
    end
    return nil
end

local function getPlotEggTimeRemaining()
    local plot = getMyPlot()
    local body = workspace:FindFirstChild("ChickenBodies") and workspace.ChickenBodies:FindFirstChild("ChickenBody_coop:" .. plot)
    if not body then return nil end
    local bGui = body:FindFirstChild("BillboardGui")
    local row = bGui and bGui:FindFirstChild("Frame") and bGui.Frame:FindFirstChild("canvas") and bGui.Frame.canvas:FindFirstChild("text") and bGui.Frame.canvas.text:FindFirstChild("stats") and bGui.Frame.canvas.text.stats:FindFirstChild("row")
    local eggLabel = row and row:FindFirstChild("egg")
    if eggLabel and eggLabel:IsA("TextLabel") then
        return parseEggTimer(eggLabel.Text), eggLabel.Text
    end
    return nil, nil
end

local cachedChickenList = {}
local chickenIdMap = {}

local function scanInventoryChickens()
    local list = {}
    local mapping = {}
    if DataServiceClient then
        local roster = DataServiceClient:get({"roster"})
        if roster and roster.chickens then
            for _, c in ipairs(roster.chickens) do
                local name = c.nickname or c.typeId or "Chicken"
                local rarity = (c.rarity and c.rarity:upper()) or "COMMON"
                local favStar = c.favorite and "⭐ " or ""
                local label = string.format("%s[%s] %s (Lv.%d) [%s]", favStar, rarity, name, c.level or 1, c.id)
                table.insert(list, label)
                mapping[label] = c.id
            end
        end
    end
    if #list == 0 then
        table.insert(list, "No Chickens Found")
    end
    cachedChickenList = list
    chickenIdMap = mapping
    return list, mapping
end

scanInventoryChickens()

------------------------------------------------------
-- Tabs Setup (Clean, Ordered & Streamlined)
------------------------------------------------------
local Tabs = {
    Coop = Window:AddTab("Coop", "house"),
    Eggs = Window:AddTab("Eggs", "egg"),
    Scrap = Window:AddTab("Scrap Farmer", "wrench"),
    Battle = Window:AddTab("Battle & Tower", "swords"),
    Rewards = Window:AddTab("Rewards & Rebirth", "gift"),
    ["UI Settings"] = Window:AddTab("UI Settings", "settings"),
}

------------------------------------------------------
-- 1. COOP TAB (AUTOMATION, SPEND PRIORITY, DASHBOARD & INCUBATOR)
------------------------------------------------------
local FarmBox = Tabs.Coop:AddLeftGroupbox("Coop Automation & Spend Priority")

FarmBox:AddDropdown("SpendPriority", {
    Values = {
        "Cheapest First (Optimal ROI)",
        "Feeders First",
        "Coop Expansion First",
        "Recycler First",
        "Balanced (All Enabled)"
    },
    Default = "Cheapest First (Optimal ROI)",
    Multi = false,
    Text = "Spend Priority Strategy",
    Tooltip = "Determines which upgrade gets money first when multiple are affordable",
})

FarmBox:AddToggle("AutoExpandCoop", {
    Text = "Auto Expand Coop Slots",
    Default = false,
    Tooltip = "Purchases coop slot expansions up to your set slot limit",
})

FarmBox:AddSlider("MaxCoopSlots", {
    Text = "Expand Slots Limit",
    Default = 6,
    Min = 1,
    Max = 6,
    Rounding = 0,
    Compact = false,
    Tooltip = "Exact in-game maximum slot cap (1 to 6 slots)",
})

FarmBox:AddToggle("AutoBuyGenerators", {
    Text = "Auto Buy Feeder Slots",
    Default = false,
    Tooltip = "Purchases new feeder slots up to your coop slot capacity",
})

FarmBox:AddSlider("MaxBuyGenSlots", {
    Text = "Buy Feeder Slots Limit",
    Default = 6,
    Min = 1,
    Max = 6,
    Rounding = 0,
    Compact = false,
    Tooltip = "How many feeder slots to buy (1 to 6)",
})

FarmBox:AddToggle("AutoUpgradeGenerators", {
    Text = "Auto Upgrade Feeders",
    Default = false,
    Tooltip = "Upgrades active feeders up to your set level limit (lowest level upgraded first)",
})

FarmBox:AddSlider("MaxGeneratorLevel", {
    Text = "Feeder Max Level Limit",
    Default = 50,
    Min = 1,
    Max = 50,
    Rounding = 0,
    Compact = false,
    Tooltip = "Exact in-game feeder level cap (1 to 50)",
})

FarmBox:AddToggle("AutoUpgradeRecycler", {
    Text = "Auto Upgrade Recycler",
    Default = false,
    Tooltip = "Upgrades your plot recycler machine up to your set level limit",
})

FarmBox:AddSlider("MaxRecyclerLevel", {
    Text = "Recycler Max Level Limit",
    Default = 18,
    Min = 1,
    Max = 18,
    Rounding = 0,
    Compact = false,
    Tooltip = "Exact in-game recycler level cap (1 to 18)",
})

FarmBox:AddDivider()

FarmBox:AddToggle("AutoPet", {
    Text = "Auto Pet Chickens",
    Default = false,
    Tooltip = "Safely pets chickens with anti-cheat rate-limit protection",
})

FarmBox:AddSlider("PetDelay", {
    Text = "Pet Delay (s)",
    Default = 1.0,
    Min = 0.8,
    Max = 3.0,
    Rounding = 1,
    Compact = false,
})

FarmBox:AddToggle("AutoCollectEggsFarm", {
    Text = "Auto Walk to Dropped Eggs (Continuous)",
    Default = false,
    Tooltip = "Continuously detects any newly laid eggs and walks straight over to collect them safely",
})

local DashboardBox = Tabs.Coop:AddRightGroupbox("Live Coop Stats Dashboard")

CoopRateLabel = DashboardBox:AddLabel("Corn Rate: +0 Corn/s")
CoopCornLabel = DashboardBox:AddLabel("Corn Stored: 0 / 0")
CoopEggsCapLabel = DashboardBox:AddLabel("Dropped Eggs: 0 / 0 (Cap)")
CoopSlotsLabel = DashboardBox:AddLabel("Coop: 0/6 Slots | 0/6 Feeders")
CoopSpendStatusLabel = DashboardBox:AddLabel("Spend Status: Idle")

local IncubatorBox = Tabs.Coop:AddRightGroupbox("Incubator Automation & Actions")

IncubatorBox:AddToggle("AutoClaimIncubator", {
    Text = "Auto Claim Incubator Eggs",
    Default = true,
    Tooltip = "Monitors incubator storage and claims eggs as soon as they finish incubating",
})

IncubatorBox:AddToggle("AutoUpgradeIncubator", {
    Text = "Auto Upgrade Incubator",
    Default = false,
    Tooltip = "Upgrades incubator machine up to your set level limit",
})

IncubatorBox:AddSlider("MaxIncubatorLevel", {
    Text = "Incubator Max Level Limit",
    Default = 15,
    Min = 1,
    Max = 15,
    Rounding = 0,
    Compact = false,
    Tooltip = "Exact in-game incubator tier cap (1 to 15)",
})

IncubatorBox:AddDivider()

IncubatorStatusLabel = IncubatorBox:AddLabel("Status: Idle")
IncubatorStoredLabel = IncubatorBox:AddLabel("Stored Eggs: 0")

IncubatorBox:AddButton({
    Text = "Claim Incubator Eggs Now",
    Func = function()
        local incData = DataServiceClient and DataServiceClient:get({"incubator"})
        if incData and incData.eggs and #incData.eggs > 0 then
            local count = #incData.eggs
            local res = safeInvoke("IncubatorClaim")
            Library:Notify({ Title = "Incubator", Description = `Claimed {count} eggs from incubator!`, Time = 3 })
        else
            Library:Notify({ Title = "Incubator", Description = "No finished eggs in incubator yet.", Time = 2 })
        end
    end,
})

------------------------------------------------------
-- 2. EGGS TAB (SMART HATCHING, AUTO FUSE & EGG SWAP EXPLOIT)
------------------------------------------------------
local HatchBox = Tabs.Eggs:AddLeftGroupbox("Smart Egg Hatching")

HatchBox:AddToggle("AutoHatchAll", {
    Text = "Auto Hatch ALL Owned Eggs (Smart Scan)",
    Default = false,
    Tooltip = "Automatically scans your bag and hatches all eggs you actually own in optimal batches!",
})

HatchBox:AddToggle("AutoHatchSelected", {
    Text = "Auto Hatch Selected Egg Tier",
    Default = false,
    Tooltip = "Continuously hatches only the egg tier chosen in the dropdown below",
})

HatchBox:AddDropdown("EggTier", {
    Values = cachedEggDropdownList,
    Default = cachedEggDropdownList[1] or "No Eggs Found",
    Multi = false,
    Text = "Select Egg Tier (Shows Bag Count)",
    Tooltip = "Shows real in-game egg names and how many you currently hold",
})

HatchBox:AddDropdown("HatchMode", {
    Values = { "Multi Batch (HatchEggs)", "Single (HatchEgg)" },
    Default = "Multi Batch (HatchEggs)",
    Multi = false,
    Text = "Hatch Mode",
})

HatchBox:AddSlider("HatchAmount", {
    Text = "Batch Max Amount",
    Default = 10,
    Min = 1,
    Max = 10,
    Rounding = 0,
    Compact = false,
    Tooltip = "Maximum eggs to hatch per invoke (clamped automatically to owned amount)",
})

HatchBox:AddSlider("HatchDelay", {
    Text = "Hatch Interval (s)",
    Default = 1.5,
    Min = 0.5,
    Max = 5.0,
    Rounding = 1,
    Compact = false,
})

local function doHatchOnce()
    local selectedLabel = Options.EggTier and Options.EggTier.Value
    local tier = eggDropdownToTierMap[selectedLabel] or selectedLabel
    local mode = Options.HatchMode and Options.HatchMode.Value or "Multi Batch (HatchEggs)"
    local maxAmt = Options.HatchAmount and Options.HatchAmount.Value or 10

    local owned = getOwnedEggInventory()
    local count = owned[tier] or 0

    if count <= 0 then
        Library:Notify({ Title = "Egg Hatching", Description = `You don't have any {tier} eggs in your bag!`, Time = 3 })
        return
    end

    local actualAmt = math.min(count, maxAmt)
    local res
    if mode == "Single (HatchEgg)" or actualAmt == 1 then
        res = safeInvoke("HatchEgg", tier)
    else
        res = safeInvoke("HatchEggs", tier, actualAmt)
    end

    if res and res.ok then
        Library:Notify({ Title = "Hatch Success", Description = `Hatched {actualAmt}x {tier} egg(s)!`, Time = 3 })
    elseif res and res.error then
        Library:Notify({ Title = "Hatch Note", Description = `Status: {res.error}`, Time = 3 })
    end

    -- Refresh UI
    local list, map, total = refreshEggDropdownList()
    Options.EggTier:SetValues(list)
end

HatchBox:AddButton({
    Text = "🐣 Hatch Selected Once",
    Func = doHatchOnce,
})

HatchBox:AddButton({
    Text = "🔄 Refresh Bag Eggs List",
    Func = function()
        local list, map, total = refreshEggDropdownList()
        Options.EggTier:SetValues(list)
        if EggSummaryLabel and EggSummaryLabel.SetText then
            EggSummaryLabel:SetText(`Total Bag Eggs: {total}`)
        end
        Library:Notify({ Title = "Egg Bag Scanned", Description = `Found {total} total eggs in inventory!`, Time = 3 })
    end,
})

EggSummaryLabel = HatchBox:AddLabel("Total Bag Eggs: 0")
HatchStatusLabel = HatchBox:AddLabel("Hatch Status: Idle")

local SwapConfigBox = Tabs.Eggs:AddLeftGroupbox("Fast Egg Swap Exploit")

SwapConfigBox:AddToggle("AutoEggSwap", {
    Text = "Enable Egg Swap Exploit",
    Default = false,
    Tooltip = "Uses Common chicken short timer, swaps to Secret right before lay, waits 4s, and swaps back!",
})

SwapConfigBox:AddInput("ChickenSearchFilter", {
    Default = "",
    Numeric = false,
    Finished = false,
    Text = "🔍 Search Chickens",
    Placeholder = "Filter by name or rarity...",
    Callback = function(Value)
        local query = Value:lower()
        local filtered = {}
        for _, label in ipairs(cachedChickenList) do
            if query == "" or label:lower():find(query, 1, true) then
                table.insert(filtered, label)
            end
        end
        if #filtered == 0 then table.insert(filtered, "No match found") end
        Options.FastChicken:SetValues(filtered)
        Options.TargetChicken:SetValues(filtered)
    end
})

SwapConfigBox:AddDropdown("FastChicken", {
    Values = cachedChickenList,
    Default = cachedChickenList[1] or "No Chickens Found",
    Multi = false,
    Text = "Fast Chicken (Common/Short Timer)",
})

SwapConfigBox:AddDropdown("TargetChicken", {
    Values = cachedChickenList,
    Default = cachedChickenList[#cachedChickenList] or "No Chickens Found",
    Multi = false,
    Text = "Target Chicken (Secret/High Tier)",
})

SwapConfigBox:AddSlider("SwapTriggerSec", {
    Text = "Swap When Timer Below (s)",
    Default = 1,
    Min = 1,
    Max = 5,
    Rounding = 0,
    Compact = false,
})

SwapConfigBox:AddSlider("SwapBackDelay", {
    Text = "Wait Before Swap Back (s)",
    Default = 4.0,
    Min = 1.0,
    Max = 10.0,
    Rounding = 1,
    Compact = false,
})

SwapConfigBox:AddToggle("AutoCollectEggs", {
    Text = "Auto Walk to Dropped Eggs",
    Default = true,
})

Toggles.AutoCollectEggs:OnChanged(function()
    if Toggles.AutoCollectEggsFarm and Toggles.AutoCollectEggsFarm.Value ~= Toggles.AutoCollectEggs.Value then
        Toggles.AutoCollectEggsFarm:SetValue(Toggles.AutoCollectEggs.Value)
    end
end)

Toggles.AutoCollectEggsFarm:OnChanged(function()
    if Toggles.AutoCollectEggs and Toggles.AutoCollectEggs.Value ~= Toggles.AutoCollectEggsFarm.Value then
        Toggles.AutoCollectEggs:SetValue(Toggles.AutoCollectEggsFarm.Value)
    end
end)

ExploitStatusLabel = SwapConfigBox:AddLabel("Status: Idle")

local FuseBox = Tabs.Eggs:AddRightGroupbox("Exact Species & Rarity Auto Fuse")

FuseBox:AddToggle("AutoFuse", {
    Text = "Auto Fuse Same Species & Rarity",
    Default = false,
    Tooltip = "Strictly pairs identical duplicate chickens (Rare Spider + Rare Spider, Epic Tengu + Epic Tengu) to safely upgrade rarity without crossing tiers!",
})

FuseBox:AddDropdown("FusionMode", {
    Values = { "Exact Species & Rarity (e.g. Rare Tengu + Rare Tengu)", "Any Same Rarity (Match by Tier)" },
    Default = "Exact Species & Rarity (e.g. Rare Tengu + Rare Tengu)",
    Multi = false,
    Text = "Fusion Matching Strategy",
    Tooltip = "Exact Species & Rarity guarantees it will NEVER fuse an Epic chicken with a Rare chicken",
})

FuseBox:AddDropdown("FuseRarities", {
    Values = { "common", "uncommon", "rare", "epic", "legendary" },
    Default = { "common", "uncommon", "rare", "epic" },
    Multi = true,
    Text = "Allowed Fusion Rarities",
    Tooltip = "Select which rarity tiers are allowed to be auto-fused (Protect high-tier chickens)",
})

FuseBox:AddSlider("FuseDelay", {
    Text = "Fusion Interval (s)",
    Default = 1.0,
    Min = 0.5,
    Max = 3.0,
    Rounding = 1,
    Compact = false,
})

FuseBox:AddDivider()

FuseStatusLabel = FuseBox:AddLabel("Fuse Status: Idle")
FusePairsLabel = FuseBox:AddLabel("Ready Exact Pairs: 0")

FuseBox:AddButton({
    Text = "🔄 Refresh Roster & Pairs",
    Func = function()
        local list, map = scanInventoryChickens()
        Options.FastChicken:SetValues(list)
        Options.TargetChicken:SetValues(list)
        local pairsList = getFusionCandidates()
        if FusePairsLabel and FusePairsLabel.SetText then
            FusePairsLabel:SetText(`Ready Exact Pairs: {#pairsList}`)
        end
        Library:Notify({ Title = "Roster Refreshed", Description = `{#pairsList} exact pairs ready!`, Time = 3 })
    end,
})

------------------------------------------------------
-- 3. SCRAP FARMER TAB (MAIN PIT ONLY & ZERO-DELAY)
------------------------------------------------------
local ScrapFarmBox = Tabs.Scrap:AddLeftGroupbox("Zero-Delay Scrap Automation")

ScrapFarmBox:AddToggle("AutoFarmScrap", {
    Text = "Auto Farm Scrap (Main Pit Only)",
    Default = false,
    Tooltip = "Strictly targets scraps inside the main central Battle Pit. Ignores outside areas & player towers.",
})

ScrapFarmBox:AddSlider("ScrapTripBatch", {
    Text = "Collect Amount Before Deposit",
    Default = 5,
    Min = 1,
    Max = 15,
    Rounding = 0,
    Compact = false,
    Tooltip = "How many scrap pieces to pick up before walking to your Recycler to deposit",
})

local ScrapStatusBox = Tabs.Scrap:AddRightGroupbox("Scrap Status & Quick Actions")

ScrapStatusLabel = ScrapStatusBox:AddLabel("Status: Idle")
ScrapCountLabel = ScrapStatusBox:AddLabel("Available Scraps (Pit): 0")
ScrapCarryLabel = ScrapStatusBox:AddLabel("Carried Scrap: 0")

ScrapStatusBox:AddButton({
    Text = "🦘 Jump Character Now",
    Func = function()
        performJump()
    end,
})

ScrapStatusBox:AddButton({
    Text = "♻️ Walk to Recycler (Deposit)",
    Func = function()
        local recCF = getRecyclerCFrame()
        if recCF then
            legitWalkTo(recCF.Position, 5.0, true)
            Library:Notify({ Title = "Scrap Farmer", Description = "Walked to Recycler!", Time = 2 })
        end
    end,
})

------------------------------------------------------
-- 4. BATTLE & TOWER TAB (FRONTIER SKIP & REAL-TIME HP)
------------------------------------------------------
local TowerBox = Tabs.Battle:AddLeftGroupbox("Tower Climber")

TowerBox:AddToggle("AutoClimbTower", {
    Text = "Auto Climb Tower",
    Default = false,
    Tooltip = "Climbs tower continuously, lets chicken fight to the end, and rests in coop before next floor",
})

TowerBox:AddToggle("TowerSkipFrontier", {
    Text = "Skip Ahead to Highest Wave (Frontier)",
    Default = true,
    Tooltip = "Uses in-game cash to start directly on your frontier highest wave instead of wave 1!",
})

TowerBox:AddToggle("WaitForFullHP", {
    Text = "Wait for 100% Full HP Before Run",
    Default = true,
    Tooltip = "Waits inside coop until active chicken's health reaches 100% before launching next floor",
})

TowerBox:AddToggle("AutoDeclineTowerPrompt", {
    Text = "Auto Decline Continue Prompt",
    Default = true,
    Tooltip = "Automatically dismisses and declines the 'Keep Climbing (R$)' / K.O. prompt upon loss",
})

TowerBox:AddSlider("TowerDelay", {
    Text = "Min Delay in Coop Before Next Run (s)",
    Default = 4.0,
    Min = 1.0,
    Max = 30.0,
    Rounding = 1,
    Compact = false,
    Tooltip = "Minimum rest timer in coop after chicken arrives back",
})

TowerTimerLabel = TowerBox:AddLabel("Rest Timer: Idle")

local TowerActionsBox = Tabs.Battle:AddRightGroupbox("Tower Status & Controls")

TowerStatusLabel = TowerActionsBox:AddLabel("Tower Status: Idle")

TowerActionsBox:AddSlider("TowerFloorNum", {
    Text = "Select Floor",
    Default = 1,
    Min = 1,
    Max = 100,
    Rounding = 0,
    Compact = false,
})

TowerActionsBox:AddButton({
    Text = "Start Selected Floor",
    Func = function()
        local floor = Options.TowerFloorNum.Value
        safeFire("SetChickenOrder", "tower")
        local res = safeInvoke("TowerStart", floor)
        if res and res.ok then
            Library:Notify({ Title = "Iggy Hub", Description = `Started Tower Floor {floor}!`, Time = 2 })
        end
    end,
})

TowerActionsBox:AddButton({
    Text = "Surrender Floor",
    Func = function()
        safeInvoke("TowerSurrender")
        Library:Notify({ Title = "Iggy Hub", Description = "Tower surrendered", Time = 2 })
    end,
})

TowerActionsBox:AddDivider()

TowerActionsBox:AddButton({
    Text = "Order Chickens to Tower",
    Func = function()
        safeFire("SetChickenOrder", "tower")
        pcall(function()
            local Chicken = LocalPlayer.PlayerScripts.Features.Chicken
            local ChickenMode = require(Chicken.ChickenMode)
            ChickenMode.order("tower")
        end)
        Library:Notify({ Title = "Iggy Hub", Description = "Chickens ordered to Tower!", Time = 2 })
    end,
})

TowerActionsBox:AddButton({
    Text = "Order Chickens to Coop (Rest/Eggs)",
    Func = function()
        safeFire("SetChickenOrder", "coop")
        pcall(function()
            local Chicken = LocalPlayer.PlayerScripts.Features.Chicken
            local ChickenMode = require(Chicken.ChickenMode)
            ChickenMode.order("coop")
        end)
        Library:Notify({ Title = "Iggy Hub", Description = "Chickens ordered to Coop!", Time = 2 })
    end,
})

------------------------------------------------------
-- 5. REWARDS & REBIRTH TAB
------------------------------------------------------
local RewardsBox = Tabs.Rewards:AddLeftGroupbox("Progression & Claims")

local function processSafeClaims()
    if not DataServiceClient then return end
    local dailyData = DataServiceClient:get({"daily"}) or {}
    local claimed = dailyData.claimed or {}
    local played = dailyData.played or 0

    if claimed.d ~= true then
        safeInvoke("DailyClaim", "day", nil)
    end

    if GameConfig and GameConfig.daily and GameConfig.daily.session then
        for slot, info in ipairs(GameConfig.daily.session) do
            if not claimed["s" .. slot] and played >= (info.mins or 0) * 60 then
                safeInvoke("DailyClaim", "session", slot)
                task.wait(0.5)
            end
        end
    end

    safeInvoke("SocialClaim")
end

RewardsBox:AddToggle("AutoDaily", {
    Text = "Auto Claim Daily Streak & Gifts",
    Default = false,
    Tooltip = "Claims daily streak and playtime gifts only when ready",
})

RewardsBox:AddToggle("AutoSocial", {
    Text = "Auto Claim Social Bonus",
    Default = false,
})

RewardsBox:AddDivider()

RewardsBox:AddButton({
    Text = "Claim Eligible Rewards Now",
    Func = function()
        task.spawn(function()
            processSafeClaims()
            Library:Notify({ Title = "Iggy Hub", Description = "Claimed all eligible rewards!", Time = 3 })
        end)
    end,
})

local RebirthBox = Tabs.Rewards:AddRightGroupbox("Rebirth & Codes")

RebirthBox:AddToggle("AutoRebirth", {
    Text = "Auto Rebirth (Immediate / Surrenders Tower)",
    Default = false,
    Tooltip = "Triggers rebirth immediately the split second requirement is satisfied",
})

RebirthBox:AddButton({
    Text = "Rebirth Once",
    Func = function()
        local res = safeInvoke("Rebirth")
        if res and res.ok then
            Library:Notify({ Title = "Iggy Hub", Description = "Rebirth Successful!", Time = 2 })
        elseif res and res.error then
            Library:Notify({ Title = "Iggy Hub", Description = `Rebirth status: {res.error}`, Time = 3 })
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
            Library:Notify({ Title = "Iggy Hub", Description = "Redeemed known codes!", Time = 2 })
        end)
    end,
})

------------------------------------------------------
-- Background Automation Loops
------------------------------------------------------

-- 1. Zero-Delay Scrap Farmer Loop (Main Pit ONLY)
task.spawn(function()
    while true do
        if Toggles.AutoFarmScrap and Toggles.AutoFarmScrap.Value then
            stepScrapFarmer()
            task.wait(0.02)
        else
            local scraps = getAllLooseScraps()
            local carried = getScrapCarryCount()
            updateScrapCount(#scraps)
            updateScrapCarry(carried)
            updateScrapStatus("Status: Idle")
            task.wait(0.5)
        end
    end
end)

-- 2. Auto Decline Tower Continue Prompt Loop
task.spawn(function()
    while true do
        if Toggles.AutoDeclineTowerPrompt and Toggles.AutoDeclineTowerPrompt.Value then
            pcall(function()
                local pg = LocalPlayer:FindFirstChild("PlayerGui")
                local sg = pg and pg:FindFirstChild("TowerContinue")
                if sg and #sg:GetChildren() > 0 then
                    safeFire("TowerContinueDecline")
                    sg:ClearAllChildren()
                    pcall(function()
                        local CardSlot = require(LocalPlayer.PlayerScripts.UI["2d"].Offers.CardSlot)
                        CardSlot.release("continue")
                    end)
                end
            end)
        end
        task.wait(0.3)
    end
end)

-- 3. Auto Claim Incubator Loop
task.spawn(function()
    while true do
        if Toggles.AutoClaimIncubator and Toggles.AutoClaimIncubator.Value and DataServiceClient then
            local incData = DataServiceClient:get({"incubator"})
            if incData and incData.eggs then
                if IncubatorStoredLabel and IncubatorStoredLabel.SetText then
                    IncubatorStoredLabel:SetText(`Stored Eggs: {#incData.eggs}`)
                end
                if #incData.eggs > 0 then
                    if IncubatorStatusLabel and IncubatorStatusLabel.SetText then
                        IncubatorStatusLabel:SetText(`Claiming {#incData.eggs} eggs...`)
                    end
                    safeInvoke("IncubatorClaim")
                    task.wait(1.5)
                else
                    if IncubatorStatusLabel and IncubatorStatusLabel.SetText then
                        IncubatorStatusLabel:SetText("Status: Waiting for incubation...")
                    end
                end
            end
            task.wait(2.0)
        else
            if IncubatorStatusLabel and IncubatorStatusLabel.SetText then
                IncubatorStatusLabel:SetText("Status: Idle")
            end
            task.wait(1.0)
        end
    end
end)

-- 4. Continuous Auto Walk to Dropped Eggs Loop
task.spawn(function()
    while true do
        local collectEnabled = (Toggles.AutoCollectEggs and Toggles.AutoCollectEggs.Value) or (Toggles.AutoCollectEggsFarm and Toggles.AutoCollectEggsFarm.Value)
        if collectEnabled then
            local eggs = getMyDroppedEggs()
            if #eggs > 0 then
                walkToAllDroppedEggs()
            end
            task.wait(0.5)
        else
            task.wait(0.5)
        end
    end
end)

-- 5. Auto Egg Swap Exploit Loop (Guarded against interrupting Tower Climb)
task.spawn(function()
    while true do
        if Toggles.AutoEggSwap and Toggles.AutoEggSwap.Value and not (Toggles.AutoClimbTower and Toggles.AutoClimbTower.Value) then
            local fastLabel = Options.FastChicken and Options.FastChicken.Value
            local targetLabel = Options.TargetChicken and Options.TargetChicken.Value
            local fastId = chickenIdMap[fastLabel]
            local targetId = chickenIdMap[targetLabel]
            local triggerSec = Options.SwapTriggerSec and Options.SwapTriggerSec.Value or 1
            local backDelay = Options.SwapBackDelay and Options.SwapBackDelay.Value or 4.0

            if fastId and targetId and fastId ~= targetId then
                local currentRoster = DataServiceClient and DataServiceClient:get({"roster"})
                local currentActive = currentRoster and currentRoster.activeId

                local secLeft, rawText = getPlotEggTimeRemaining()
                if rawText and ExploitStatusLabel and ExploitStatusLabel.SetText then
                    ExploitStatusLabel:SetText(`Timer: {rawText} | Active: {currentActive or "..."}`)
                end

                if secLeft and secLeft > triggerSec and currentActive ~= fastId then
                    safeInvoke("SetActiveChicken", fastId)
                    safeFire("SetChickenOrder", "coop")
                end

                if secLeft and secLeft <= triggerSec and secLeft >= 0 then
                    if ExploitStatusLabel and ExploitStatusLabel.SetText then
                        ExploitStatusLabel:SetText(`⚡ SWAPPING to Target ({targetLabel:sub(1, 18)}...)`)
                    end
                    safeInvoke("SetActiveChicken", targetId)
                    safeFire("SetChickenOrder", "coop")

                    if ExploitStatusLabel and ExploitStatusLabel.SetText then
                        ExploitStatusLabel:SetText(`⏳ Waiting {backDelay}s for egg drop...`)
                    end
                    task.wait(backDelay)

                    if ExploitStatusLabel and ExploitStatusLabel.SetText then
                        ExploitStatusLabel:SetText(`🔄 SWAPPING BACK to Fast Chicken`)
                    end
                    safeInvoke("SetActiveChicken", fastId)
                    safeFire("SetChickenOrder", "coop")
                    task.wait(1.5)
                end
            else
                if ExploitStatusLabel and ExploitStatusLabel.SetText then
                    ExploitStatusLabel:SetText("Status: Please select two different chickens")
                end
            end
            task.wait(0.2)
        else
            if ExploitStatusLabel and ExploitStatusLabel.SetText then
                ExploitStatusLabel:SetText("Status: Idle")
            end
            task.wait(0.5)
        end
    end
end)

-- 6. Auto Pet Loop (Guarded against interrupting Tower Climb)
task.spawn(function()
    while true do
        if Toggles.AutoPet and Toggles.AutoPet.Value and not (Toggles.AutoClimbTower and Toggles.AutoClimbTower.Value) then
            safeFire("SetChickenOrder", "coop")
            safeFire("PetChicken")
            local delayTime = Options.PetDelay and Options.PetDelay.Value or 1.0
            task.wait(delayTime)
        else
            task.wait(0.5)
        end
    end
end)

-- 7. High-Performance Auto Coop Spend Priority & Upgrades Loop
task.spawn(function()
    while true do
        if DataServiceClient then
            local rawMoney = DataServiceClient:get({"money"}) or 0
            local coopData = DataServiceClient:get({"coop"})
            local scrapData = DataServiceClient:get({"scrap"}) or {}
            local rebirthData = DataServiceClient:get({"rebirth"})
            local towerData = DataServiceClient:get({"tower"})
            local incData = DataServiceClient:get({"incubator"}) or {}
            local rosterData = DataServiceClient:get({"roster"}) or {}

            local rebirths = (type(rebirthData) == "table" and rebirthData.count) or (type(rebirthData) == "number" and rebirthData) or 0
            local bestFloor = (towerData and towerData.best) or 0

            local maxSlotLimit = Options.MaxCoopSlots and Options.MaxCoopSlots.Value or 6
            local maxBuySlots = Options.MaxBuyGenSlots and Options.MaxBuyGenSlots.Value or 6
            local maxGenLimit = Options.MaxGeneratorLevel and Options.MaxGeneratorLevel.Value or 50
            local maxRecLimit = Options.MaxRecyclerLevel and Options.MaxRecyclerLevel.Value or 18
            local maxIncLimit = Options.MaxIncubatorLevel and Options.MaxIncubatorLevel.Value or 15

            -- Update Live Coop Stats Dashboard
            if coopData and CoopView then
                local currentSlots = coopData.slots or 1
                local ownedFeeders = (coopData.generators and #coopData.generators) or 0
                local totalRate = 0
                local totalCorn = 0
                local totalCapacity = 0

                if coopData.generators then
                    for _, g in ipairs(coopData.generators) do
                        local lvl = tonumber(g.level) or 1
                        local c = tonumber(g.corn) or 0
                        local r = CoopView.rate(lvl) or 0
                        local cap = CoopView.capacity(lvl) or 0
                        totalRate = totalRate + r
                        totalCorn = totalCorn + c
                        totalCapacity = totalCapacity + cap
                    end
                end

                local droppedEggs = #getMyDroppedEggs()
                local eggCap = 12
                if GameConfig and GameConfig.roster and GameConfig.roster.lay then
                    local base = GameConfig.roster.lay.nestBase or 4
                    local mult = GameConfig.roster.lay.nestMult or 2
                    eggCap = (base + currentSlots) * mult
                end

                if CoopRateLabel and CoopRateLabel.SetText then
                    CoopRateLabel:SetText(`Corn Rate: +{totalRate} Corn/s`)
                end
                if CoopCornLabel and CoopCornLabel.SetText then
                    CoopCornLabel:SetText(`Corn Stored: {totalCorn} / {totalCapacity}`)
                end
                if CoopEggsCapLabel and CoopEggsCapLabel.SetText then
                    CoopEggsCapLabel:SetText(`Dropped Eggs: {droppedEggs} / {eggCap} (Cap)`)
                end
                if CoopSlotsLabel and CoopSlotsLabel.SetText then
                    CoopSlotsLabel:SetText(`Coop: {currentSlots}/6 Slots | {ownedFeeders}/6 Feeders`)
                end
            end

            -- Build Affordable Upgrade Candidates
            local candidates = {}

            -- Candidate 1: Expand Coop
            if Toggles.AutoExpandCoop and Toggles.AutoExpandCoop.Value and coopData and CoopView then
                local currentSlots = coopData.slots or 1
                if currentSlots < maxSlotLimit and CoopView.canExpand(currentSlots) then
                    local cost = CoopView.expandCost(currentSlots)
                    table.insert(candidates, {
                        category = "expand",
                        name = "Expand Coop",
                        cost = cost,
                        action = function() safeInvoke("ExpandCoop") end
                    })
                end
            end

            -- Candidate 2: Buy Feeder Slot
            if Toggles.AutoBuyGenerators and Toggles.AutoBuyGenerators.Value and coopData and CoopView then
                local currentSlots = coopData.slots or 1
                local owned = (coopData.generators and #coopData.generators) or 0
                if owned < currentSlots and owned < maxBuySlots and CoopView.canBuyGenerator(currentSlots, owned) then
                    local cost = CoopView.buyGeneratorCost(owned)
                    table.insert(candidates, {
                        category = "buy_feeder",
                        name = `Buy Feeder {owned + 1}`,
                        cost = cost,
                        action = function() safeInvoke("BuyGenerator", owned + 1) end
                    })
                end
            end

            -- Candidate 3: Upgrade Feeders (Pick lowest level feeder first for max ROI)
            if Toggles.AutoUpgradeGenerators and Toggles.AutoUpgradeGenerators.Value and coopData and coopData.generators and CoopView then
                local feederList = {}
                for _, g in ipairs(coopData.generators) do
                    if g.level < maxGenLimit and CoopView.canUpgrade(g.level) then
                        local cost = CoopView.upgradeCost(g.level)
                        table.insert(feederList, { slot = g.slot, level = g.level, cost = cost })
                    end
                end

                table.sort(feederList, function(a, b)
                    if a.level == b.level then return a.slot < b.slot end
                    return a.level < b.level
                end)

                if #feederList > 0 then
                    local targetFeeder = feederList[1]
                    table.insert(candidates, {
                        category = "feeder",
                        name = `Upgrade Feeder (Slot {targetFeeder.slot} Lv.{targetFeeder.level})`,
                        cost = targetFeeder.cost,
                        action = function() safeInvoke("UpgradeGenerator", targetFeeder.slot) end
                    })
                end
            end

            -- Candidate 4: Upgrade Recycler
            if Toggles.AutoUpgradeRecycler and Toggles.AutoUpgradeRecycler.Value and RecyclerView then
                local recLevel = scrapData.recyclerLevel or 0
                if recLevel < maxRecLimit and RecyclerView.canUpgrade(recLevel, rebirths) and RecyclerView.floorUnlocked(recLevel, bestFloor) then
                    local cost = RecyclerView.upgradeCost(recLevel)
                    table.insert(candidates, {
                        category = "recycler",
                        name = `Upgrade Recycler (Lv.{recLevel})`,
                        cost = cost,
                        action = function() safeInvoke("UpgradeRecycler") end
                    })
                end
            end

            -- Sort candidates according to Spend Priority Strategy
            local strategy = Options.SpendPriority and Options.SpendPriority.Value or "Cheapest First (Optimal ROI)"

            if strategy == "Cheapest First (Optimal ROI)" then
                table.sort(candidates, function(a, b) return a.cost < b.cost end)
            elseif strategy == "Feeders First" then
                table.sort(candidates, function(a, b)
                    local isAFeeder = (a.category == "feeder" or a.category == "buy_feeder")
                    local isBFeeder = (b.category == "feeder" or b.category == "buy_feeder")
                    if isAFeeder ~= isBFeeder then return isAFeeder end
                    return a.cost < b.cost
                end)
            elseif strategy == "Coop Expansion First" then
                table.sort(candidates, function(a, b)
                    local isAExpand = (a.category == "expand")
                    local isBExpand = (b.category == "expand")
                    if isAExpand ~= isBExpand then return isAExpand end
                    return a.cost < b.cost
                end)
            elseif strategy == "Recycler First" then
                table.sort(candidates, function(a, b)
                    local isARec = (a.category == "recycler")
                    local isBRec = (b.category == "recycler")
                    if isARec ~= isBRec then return isARec end
                    return a.cost < b.cost
                end)
            end

            -- Execute first affordable candidate
            local purchased = false
            for _, item in ipairs(candidates) do
                if rawMoney >= item.cost then
                    if CoopSpendStatusLabel and CoopSpendStatusLabel.SetText then
                        CoopSpendStatusLabel:SetText(`Spend: Buying {item.name}...`)
                    end
                    item.action()
                    purchased = true
                    task.wait(0.2)
                    break
                end
            end

            if not purchased and CoopSpendStatusLabel and CoopSpendStatusLabel.SetText then
                if #candidates > 0 then
                    CoopSpendStatusLabel:SetText(`Spend: Waiting for ${candidates[1].cost} ({candidates[1].name})`)
                else
                    CoopSpendStatusLabel:SetText("Spend: All limits reached / Idle")
                end
            end

            -- Auto Upgrade Incubator (Separate Machine)
            if Toggles.AutoUpgradeIncubator and Toggles.AutoUpgradeIncubator.Value and GameConfig and GameConfig.incubator then
                local incLevel = incData.level or 1
                if incLevel < maxIncLimit and incLevel < #GameConfig.incubator.levels then
                    local nextInfo = GameConfig.incubator.levels[incLevel + 1]
                    if nextInfo and rebirths >= (nextInfo.rebirth or 0) then
                        local cost = math.floor((GameConfig.incubator.costBase or 300000) * math.pow(GameConfig.incubator.costGrowth or 1.65, incLevel - 1))
                        if rawMoney >= cost then
                            safeInvoke("IncubatorUpgrade")
                            task.wait(0.2)
                        end
                    end
                end
            end
        end

        task.wait(0.3)
    end
end)

-- 8. Smart & 100% Accurate Egg Hatching Loop
task.spawn(function()
    while true do
        local hatchDelay = Options.HatchDelay and Options.HatchDelay.Value or 1.5
        local maxAmt = Options.HatchAmount and Options.HatchAmount.Value or 10
        local mode = Options.HatchMode and Options.HatchMode.Value or "Multi Batch (HatchEggs)"

        -- Update UI Total Count
        local owned, total = getOwnedEggInventory()
        if EggSummaryLabel and EggSummaryLabel.SetText then
            EggSummaryLabel:SetText(`Total Bag Eggs: {total}`)
        end

        -- Mode 1: Auto Hatch ALL Owned Eggs
        if Toggles.AutoHatchAll and Toggles.AutoHatchAll.Value then
            local foundAny = false
            for tierId, count in pairs(owned) do
                if count > 0 then
                    foundAny = true
                    local actualAmt = math.min(count, maxAmt)
                    if HatchStatusLabel and HatchStatusLabel.SetText then
                        HatchStatusLabel:SetText(`Hatching {actualAmt}x {eggNameLookup[tierId] or tierId}...`)
                    end

                    if mode == "Single (HatchEgg)" or actualAmt == 1 then
                        safeInvoke("HatchEgg", tierId)
                    else
                        safeInvoke("HatchEggs", tierId, actualAmt)
                    end

                    task.wait(hatchDelay)
                    break
                end
            end

            if not foundAny then
                if HatchStatusLabel and HatchStatusLabel.SetText then
                    HatchStatusLabel:SetText("Status: No eggs in bag to hatch")
                end
                task.wait(1.0)
            end

        -- Mode 2: Auto Hatch Selected Egg Tier
        elseif Toggles.AutoHatchSelected and Toggles.AutoHatchSelected.Value then
            local selectedLabel = Options.EggTier and Options.EggTier.Value
            local tier = eggDropdownToTierMap[selectedLabel] or selectedLabel
            local count = owned[tier] or 0

            if count > 0 then
                local actualAmt = math.min(count, maxAmt)
                if HatchStatusLabel and HatchStatusLabel.SetText then
                    HatchStatusLabel:SetText(`Hatching {actualAmt}x {eggNameLookup[tier] or tier}...`)
                end

                if mode == "Single (HatchEgg)" or actualAmt == 1 then
                    safeInvoke("HatchEgg", tier)
                else
                    safeInvoke("HatchEggs", tier, actualAmt)
                end

                task.wait(hatchDelay)
            else
                if HatchStatusLabel and HatchStatusLabel.SetText then
                    HatchStatusLabel:SetText(`Status: 0 {eggNameLookup[tier] or tier} in bag`)
                end
                task.wait(1.0)
            end
        else
            if HatchStatusLabel and HatchStatusLabel.SetText then
                HatchStatusLabel:SetText("Hatch Status: Idle")
            end
            task.wait(0.5)
        end
    end
end)

-- 9. Exact Species & Exact Rarity Smart Auto Fusion Loop
task.spawn(function()
    while true do
        local pairsList = getFusionCandidates()
        if FusePairsLabel and FusePairsLabel.SetText then
            FusePairsLabel:SetText(`Ready Exact Pairs: {#pairsList}`)
        end

        if Toggles.AutoFuse and Toggles.AutoFuse.Value then
            if #pairsList > 0 then
                local pair = pairsList[1]
                if FuseStatusLabel and FuseStatusLabel.SetText then
                    FuseStatusLabel:SetText(`Fusing 2x {pair.rarity:upper()} {pair.displayName}...`)
                end

                local res = safeInvoke("FuseChickens", pair.a.id, pair.b.id, nil, nil, nil)
                if res and res.ok then
                    if res.data and res.data.ascended then
                        Library:Notify({ Title = "🌟 ASCENSION!", Description = `{pair.displayName} ascended to {res.data.rarity:upper()}!`, Time = 4 })
                    end
                end

                local delayTime = Options.FuseDelay and Options.FuseDelay.Value or 1.0
                task.wait(delayTime)
            else
                if FuseStatusLabel and FuseStatusLabel.SetText then
                    FuseStatusLabel:SetText("Status: No eligible pairs to fuse")
                end
                task.wait(1.5)
            end
        else
            if FuseStatusLabel and FuseStatusLabel.SetText then
                FuseStatusLabel:SetText("Fuse Status: Idle")
            end
            task.wait(1.0)
        end
    end
end)

-- 10. Auto Tower Climber with Instant Rebirth Integration
task.spawn(function()
    while true do
        if Toggles.AutoClimbTower and Toggles.AutoClimbTower.Value then
            local plot = getMyPlot()
            local rebirthReady, count, reqFloor = isRebirthEligible()

            if Toggles.AutoRebirth and Toggles.AutoRebirth.Value and rebirthReady then
                if TowerStatusLabel and TowerStatusLabel.SetText then
                    TowerStatusLabel:SetText(`Tower Status: 🌟 Rebirthing to R{count + 1}!`)
                end
                updateTowerTimer("Rest Timer: 🌟 Rebirthing...")

                if isTowerMatchActive() then
                    safeInvoke("TowerSurrender")
                end
                safeFire("SetChickenOrder", "coop")

                local res = safeInvoke("Rebirth")
                if res and res.ok then
                    Library:Notify({ Title = "Iggy Hub", Description = `Rebirthed to Rebirth {count + 1}!`, Time = 3 })
                end
                task.wait(1.0)
            else
                local towerData = (DataServiceClient and DataServiceClient:get({"tower"})) or {}
                local bestFloor = (towerData and tonumber(towerData.best)) or 0
                local frontierFloor = bestFloor + 1

                if TowerStatusLabel and TowerStatusLabel.SetText then
                    if Toggles.TowerSkipFrontier and Toggles.TowerSkipFrontier.Value and frontierFloor > 1 then
                        TowerStatusLabel:SetText(`Tower Status: 🚀 Skipping to Frontier (Floor {frontierFloor})...`)
                    else
                        TowerStatusLabel:SetText("Tower Status: 🚀 Starting Match...")
                    end
                end
                updateTowerTimer("Rest Timer: 🚀 Starting Match...")

                safeFire("SetChickenOrder", "tower")
                pcall(function()
                    local Chicken = LocalPlayer.PlayerScripts.Features.Chicken
                    local ChickenMode = require(Chicken.ChickenMode)
                    ChickenMode.order("tower")
                end)

                -- Handle ElevatorGate & Frontier Skip
                if Toggles.TowerSkipFrontier and Toggles.TowerSkipFrontier.Value and frontierFloor > 1 then
                    pcall(function()
                        local ElevatorGate = require(LocalPlayer.PlayerScripts.UI["2d"].tower.ElevatorGate)
                        if ElevatorGate and ElevatorGate.resolve then
                            ElevatorGate.resolve(frontierFloor)
                        end
                    end)
                    safeInvoke("TowerElevator", frontierFloor)
                else
                    pcall(function()
                        local ElevatorGate = require(LocalPlayer.PlayerScripts.UI["2d"].tower.ElevatorGate)
                        if ElevatorGate and ElevatorGate.resolve then
                            ElevatorGate.resolve(nil)
                        end
                    end)
                end

                safeInvoke("TowerStart")

                -- Wait for match to become active in arena
                local waitBattle = os.clock()
                while (os.clock() - waitBattle) < 10.0 and Toggles.AutoClimbTower.Value do
                    if isTowerMatchActive() then
                        break
                    end
                    updateTowerTimer("Rest Timer: 🚶 Chicken Walking to Arena...")
                    task.wait(0.2)
                end

                if TowerStatusLabel and TowerStatusLabel.SetText then
                    TowerStatusLabel:SetText("Tower Status: ⚔️ In Battle...")
                end
                updateTowerTimer("Rest Timer: ⚔️ In Battle")

                while isTowerMatchActive() and Toggles.AutoClimbTower and Toggles.AutoClimbTower.Value do
                    -- If rebirth became ready mid-fight and AutoRebirth is on, surrender immediately
                    local midRebirthReady = isRebirthEligible()
                    if Toggles.AutoRebirth and Toggles.AutoRebirth.Value and midRebirthReady then
                        safeInvoke("TowerSurrender")
                        break
                    end
                    task.wait(0.3)
                end

                if TowerStatusLabel and TowerStatusLabel.SetText then
                    TowerStatusLabel:SetText("Tower Status: 🏠 Match Over. Returning to Coop...")
                end
                updateTowerTimer("Rest Timer: 🏠 Returning to Coop...")

                safeFire("TowerContinueDecline")

                safeFire("SetChickenOrder", "coop")
                pcall(function()
                    local Chicken = LocalPlayer.PlayerScripts.Features.Chicken
                    local ChickenMode = require(Chicken.ChickenMode)
                    ChickenMode.order("coop")
                end)

                -- Check if ready for rebirth right after match over
                local afterRebirthReady, afterCount = isRebirthEligible()
                if Toggles.AutoRebirth and Toggles.AutoRebirth.Value and afterRebirthReady then
                    if TowerStatusLabel and TowerStatusLabel.SetText then
                        TowerStatusLabel:SetText(`Tower Status: 🌟 Rebirthing to R{afterCount + 1}...`)
                    end
                    updateTowerTimer("Rest Timer: 🌟 Rebirthing...")
                    local res = safeInvoke("Rebirth")
                    if res and res.ok then
                        Library:Notify({ Title = "Iggy Hub", Description = `Rebirthed to Rebirth {afterCount + 1}!`, Time = 3 })
                    end
                    task.wait(1.0)
                else
                    local waitCoop = os.clock()
                    while (os.clock() - waitCoop) < 8.0 and Toggles.AutoClimbTower.Value do
                        local body = workspace:FindFirstChild("ChickenBodies") and workspace.ChickenBodies:FindFirstChild("ChickenBody_coop:" .. plot)
                        if body then break end
                        task.wait(0.15)
                    end

                    -- Health Recovery / Delay Phase with Real-Time ovHpFrac Tracking
                    local delayTime = Options.TowerDelay and Options.TowerDelay.Value or 4.0
                    local dStart = os.clock()
                    local shouldWaitHP = Toggles.WaitForFullHP and Toggles.WaitForFullHP.Value

                    while Toggles.AutoClimbTower and Toggles.AutoClimbTower.Value do
                        local elapsed = os.clock() - dStart
                        local remaining = math.max(0, delayTime - elapsed)
                        local currentHp = getActiveChickenHealth()
                        local hpPct = math.floor(currentHp * 100)

                        local timerDone = elapsed >= delayTime
                        local hpDone = (not shouldWaitHP) or (currentHp >= 0.99)

                        if timerDone and hpDone then
                            break
                        end

                        if shouldWaitHP and currentHp < 0.99 then
                            updateTowerTimer(string.format("Rest Timer: 🏥 Healing: %d%% / 100%%", hpPct))
                            if TowerStatusLabel and TowerStatusLabel.SetText then
                                TowerStatusLabel:SetText(string.format("Tower Status: 🏥 Healing (%d%% / 100%%)...", hpPct))
                            end
                        else
                            updateTowerTimer(string.format("Rest Timer: ⏳ %.1fs / %.1fs", remaining, delayTime))
                            if TowerStatusLabel and TowerStatusLabel.SetText then
                                TowerStatusLabel:SetText(string.format("Tower Status: 💤 Resting in Coop (%.1fs)...", remaining))
                            end
                        end

                        task.wait(0.1)
                    end

                    updateTowerTimer("Rest Timer: 🚀 Ready for next floor!")
                end
            end
        else
            if TowerStatusLabel and TowerStatusLabel.SetText then
                TowerStatusLabel:SetText("Tower Status: Idle")
            end
            updateTowerTimer("Rest Timer: Idle")
            task.wait(0.5)
        end
    end
end)

-- 11. High-Frequency Instant Auto Rebirth & Rewards Loop
task.spawn(function()
    while true do
        if (Toggles.AutoDaily and Toggles.AutoDaily.Value) or (Toggles.AutoSocial and Toggles.AutoSocial.Value) then
            processSafeClaims()
        end

        if Toggles.AutoRebirth and Toggles.AutoRebirth.Value then
            local rebirthReady, count, reqFloor = isRebirthEligible()
            if rebirthReady then
                if isTowerMatchActive() then
                    safeInvoke("TowerSurrender")
                end
                safeFire("SetChickenOrder", "coop")
                local res = safeInvoke("Rebirth")
                if res and res.ok then
                    Library:Notify({ Title = "Iggy Hub", Description = `Rebirthed to Rebirth {count + 1}!`, Time = 3 })
                end
            end
        end

        task.wait(0.4) -- High-frequency: checks every 400ms!
    end
end)

-- 12. Safe Background Anti-AFK
LocalPlayer.Idled:Connect(function()
    pcall(function()
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildWhichIsA("Humanoid")
        if hum then
            hum:ChangeState(Enum.HumanoidStateType.Running)
        end
    end)
end)

------------------------------------------------------
-- 13. UI SETTINGS TAB
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

ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({ "MenuKeybind" })

ThemeManager:SetFolder("IggyHub")
SaveManager:SetFolder("IggyHub/chicken-fighter")

SaveManager:BuildConfigSection(Tabs["UI Settings"])
ThemeManager:ApplyToTab(Tabs["UI Settings"])

Library:Notify({
    Title = "Iggy Hub",
    Description = "Loaded v6.8 with Coop Upgrades!",
    Time = 4,
})
