local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

-- Chờ nhân vật tải xong (tránh lỗi nil khi chạy trong Auto-Execute)
while not Players.LocalPlayer do
    task.wait(0.5)
end
local LocalPlayer = Players.LocalPlayer

-- Cấu hình API Endpoint qua Cloudflare Tunnel (Không giới hạn băng thông)
local API_URL = "https://processors-train-early-telecharger.trycloudflare.com/api/accounts"
local UPDATE_INTERVAL = 35 -- Đồng bộ mỗi 35 giây

-- Lấy hàm HTTP Request & tên máy từ Config an toàn
local env = (type(getgenv) == "function" and getgenv()) or _G
local httpRequest = (type(env.syn) == "table" and env.syn.request)
    or (type(env.http) == "table" and env.http.request)
    or env.http_request
    or (type(env.fluxus) == "table" and env.fluxus.request)
    or env.request
    or request

if type(httpRequest) ~= "function" then
    warn("[Tracker] Executor của bạn không hỗ trợ HTTP Request!")
    return
end

local function getMachineName()
    local name = env.MachineName or _G.MachineName
    if type(name) == "string" and name ~= "" then
        return name
    end
    return "PC"
end

local matchStats = {
    wins = 0,
    losses = 0,
    lastResult = "Playing",
    matchTime = "00:00",
    countedCurrentMatch = false
}

-- Biến lưu Cache bảng dữ liệu trong RAM & Level gần nhất
local cachedPlayerTable = nil
local cachedUnitsTable = nil
local lastKnownLv = 0

local function formatSeconds(sec)
    sec = math.floor(tonumber(sec) or 0)
    local mins = math.floor(sec / 60)
    local secs = sec % 60
    return string.format("%02d:%02d", mins, secs)
end

local function getAccountLevel()
    local pGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    if not pGui then return lastKnownLv end

    local spawnUnits = pGui:FindFirstChild("spawn_units")
    local lives = spawnUnits and spawnUnits:FindFirstChild("Lives")
    local main = lives and lives:FindFirstChild("Main")
    local desc = main and main:FindFirstChild("Desc")
    local levelLabel = desc and desc:FindFirstChild("Level")

    if levelLabel and levelLabel:IsA("TextLabel") then
        local lvStr = tostring(levelLabel.Text):match("Level%s*(%d+)")
        local parsed = tonumber(lvStr)
        if parsed and parsed > 0 then
            lastKnownLv = parsed
        end
    end

    return lastKnownLv
end

local function updateMatchStatus()
    local mapConfig = Workspace:FindFirstChild("_MAP_CONFIG")
    local isLobby = mapConfig and mapConfig:FindFirstChild("IsLobby") and mapConfig.IsLobby.Value

    if isLobby then
        matchStats.lastResult = "Lobby"
        matchStats.matchTime = "00:00"
        matchStats.countedCurrentMatch = false
        return
    end

    local pGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
    if not pGui then return end

    local resultsUI = pGui:FindFirstChild("ResultsUI")
    if resultsUI and resultsUI.Enabled then
        for _, label in ipairs(resultsUI:GetDescendants()) do
            if label:IsA("TextLabel") and label.Visible and label.Text ~= "" then
                local txt = label.Text:upper()
                if txt:find("VICTORY") or txt:find("WIN") then
                    matchStats.lastResult = "Victory"
                    if not matchStats.countedCurrentMatch then
                        matchStats.wins = matchStats.wins + 1
                        matchStats.countedCurrentMatch = true
                    end
                elseif txt:find("DEFEAT") or txt:find("FAILED") or txt:find("LOSE") then
                    matchStats.lastResult = "Defeat"
                    if not matchStats.countedCurrentMatch then
                        matchStats.losses = matchStats.losses + 1
                        matchStats.countedCurrentMatch = true
                    end
                end
                if txt:match("^%d%d?:%d%d$") then
                    matchStats.matchTime = txt
                end
            end
        end
        return
    else
        matchStats.lastResult = "Playing"
        matchStats.countedCurrentMatch = false
    end

    local foundTime = nil
    for _, label in ipairs(pGui:GetDescendants()) do
        if label:IsA("TextLabel") and label.Visible and label.Text:match("^%d%d?:%d%d$") then
            foundTime = label.Text
            break
        end
    end

    if foundTime then
        matchStats.matchTime = foundTime
    elseif Workspace:FindFirstChild("_wave_time") then
        matchStats.matchTime = formatSeconds(Workspace._wave_time.Value)
    end
end

local function getMapLocation()
    local mapConfig = Workspace:FindFirstChild("_MAP_CONFIG")
    if mapConfig then
        local isLobby = mapConfig:FindFirstChild("IsLobby") and mapConfig.IsLobby.Value
        if isLobby then return "Lobby" end

        local wave = Workspace:FindFirstChild("_wave_num") and Workspace._wave_num.Value or 0
        local mapName = nil

        for _, child in ipairs(mapConfig:GetChildren()) do
            if child:IsA("StringValue") and tostring(child.Value) ~= "" and tostring(child.Value) ~= "nil" then
                mapName = tostring(child.Value)
                break
            end
        end

        if not mapName then
            local attrs = mapConfig:GetAttributes()
            for _, v in pairs(attrs) do
                if type(v) == "string" and v ~= "" and v ~= "nil" then
                    mapName = v
                    break
                end
            end
        end

        if not mapName then
            local pGui = LocalPlayer and LocalPlayer:FindFirstChild("PlayerGui")
            if pGui then
                for _, label in ipairs(pGui:GetDescendants()) do
                    if label:IsA("TextLabel") and label.Visible and label.Text ~= "" then
                        local txt = label.Text:gsub("\n", " ")
                        if txt:find("Act ") or txt:find("Infinite") or txt:find("Raid") or txt:find("Normal") or txt:find("Nightmare") then
                            if #txt < 45 then
                                mapName = txt
                                break
                            end
                        end
                    end
                end
            end
        end

        return (mapName or "In-Game") .. " · Wave " .. tostring(wave)
    end
    return "Lobby"
end

local function refreshGcCache()
    local getGcFunc = env.getgc or getgc
    if type(getGcFunc) ~= "function" then return end

    for _, v in ipairs(getGcFunc(true)) do
        if type(v) == "table" then
            if not cachedPlayerTable and rawget(v, "gem_amount") ~= nil and type(rawget(v, "inventory")) == "table" then
                cachedPlayerTable = v
            end
            if not cachedUnitsTable and type(rawget(v, "owned_units")) == "table" and rawget(v, "capacity") ~= nil then
                cachedUnitsTable = v
            end
            if cachedPlayerTable and cachedUnitsTable then
                break
            end
        end
    end
end

local function collectGameData()
    LocalPlayer = Players.LocalPlayer
    if not LocalPlayer then return nil end

    updateMatchStatus()

    local stats = LocalPlayer:FindFirstChild("_stats")
    local currentXp = (stats and stats:FindFirstChild("player_xp") and tonumber(stats.player_xp.Value)) or 0
    local currentLv = getAccountLevel()

    local data = {
        username = LocalPlayer.Name,
        userId = LocalPlayer.UserId,
        machine = getMachineName(),
        gems = stats and stats:FindFirstChild("gem_amount") and stats.gem_amount.Value or 0,
        gold = stats and stats:FindFirstChild("gold_amount") and stats.gold_amount.Value or 0,
        xp = currentXp,
        lv = currentLv,
        summerPearls = stats and stats:FindFirstChild("_resourceSummerPearls") and stats._resourceSummerPearls.Value or 0,
        location = getMapLocation(),
        matchTime = matchStats.matchTime,
        matchResult = matchStats.lastResult,
        wins = matchStats.wins,
        losses = matchStats.losses,
        items = {},
        units = {}
    }

    if not cachedPlayerTable or not cachedUnitsTable then
        refreshGcCache()
    end

    if cachedPlayerTable and type(cachedPlayerTable.inventory) == "table" then
        local traitTokens = rawget(cachedPlayerTable, "trait_reroll_tokens") or 0
        if traitTokens > 0 then
            table.insert(data.items, { name = "Trait Reroll Token", count = traitTokens, category = "Token" })
        end

        local curseTokens = rawget(cachedPlayerTable, "curse_reroll_tokens") or 0
        if curseTokens > 0 then
            table.insert(data.items, { name = "Curse Reroll Token", count = curseTokens, category = "Token" })
        end

        local normalItems = cachedPlayerTable.inventory.normal_items
        if type(normalItems) == "table" then
            for itemName, itemVal in pairs(normalItems) do
                local count = type(itemVal) == "table" and (itemVal.amount or itemVal.count or 1) or itemVal
                if type(count) == "number" and count > 0 then
                    table.insert(data.items, { name = tostring(itemName), count = count, category = "Normal" })
                end
            end
        end

        local uniqueItems = cachedPlayerTable.inventory.unique_items
        if type(uniqueItems) == "table" then
            for uuid, itemInfo in pairs(uniqueItems) do
                if type(itemInfo) == "table" then
                    local itemName = tostring(itemInfo.item_id or itemInfo.id or itemInfo.name or uuid)
                    table.insert(data.items, { name = itemName, count = 1, category = "Unique" })
                end
            end
        end
    end

    if cachedUnitsTable and type(cachedUnitsTable.owned_units) == "table" then
        for uuid, unitInfo in pairs(cachedUnitsTable.owned_units) do
            if type(unitInfo) == "table" then
                table.insert(data.units, {
                    id = tostring(unitInfo.unit_id or unitInfo.name or "Unknown"),
                    level = unitInfo.level or 1,
                    trait = unitInfo.trait or "None"
                })
            end
        end
    end

    return data
end

-- Vòng lặp gửi dữ liệu lên Web Dashboard
task.spawn(function()
    task.wait(math.random(1, 15))
    print("[Tracker] Đã kết nối (" .. getMachineName() .. ") ->", API_URL)

    while true do
        local waitTime = UPDATE_INTERVAL
        local success, err = pcall(function()
            local payload = collectGameData()
            if payload then
                local res = httpRequest({
                    Url = API_URL,
                    Method = "POST",
                    Headers = {
                        ["Content-Type"] = "application/json"
                    },
                    Body = HttpService:JSONEncode(payload)
                })
                local code = res and res.StatusCode or 0
                if code == 429 then
                    waitTime = UPDATE_INTERVAL + 15
                end
            end
        end)

        if not success then
            warn("[Tracker] Lỗi đồng bộ:", err)
        end

        task.wait(waitTime)
    end
end)
