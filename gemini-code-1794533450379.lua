-- ========================================================
-- SCRIPT AUTO CHECK XP (>= 9200) & AUTO SWITCH ACCOUNT
-- Game: Anime Adventures + Discord Webhook Notification
-- ========================================================

-- Chờ game load hoàn tất trước khi lấy dịch vụ
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")

-- Chờ cho đến khi LocalPlayer được khởi tạo (Fix lỗi nil)
local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait(0.5)
    LocalPlayer = Players.LocalPlayer
end

local TARGET_XP = 9200
local FILE_CONTENT = "yummytool"
local DISCORD_WEBHOOK_URL = "https://discord.com/api/webhooks/1569617417947324427/NSsvGYLnIMFxV7msb5cCToo-DfIVHsvR-ckqoM7doYn4S1szvFe0obwqN2ZYXbtSw9r8"

-- Hàm gửi thông báo qua Discord Webhook
local function sendDiscordWebhook(username, xpValue)
    if DISCORD_WEBHOOK_URL == "" then
        warn("[AUTO-SWITCH] Chưa cấu hình Discord Webhook URL!")
        return
    end

    local requestFunc = (syn and syn.request) or (http and http.request) or http_request or (fluxus and fluxus.request) or request
    if not requestFunc then
        warn("[AUTO-SWITCH] Executor không hỗ trợ hàm HTTP Request để gửi Webhook!")
        return
    end

    local payload = HttpService:JSONEncode({
        content = "🚀 **[AUTO CHANGE ACCOUNT]**",
        embeds = {{
            title = "Tài khoản đã hoàn thành mốc XP!",
            color = 65280, -- Màu xanh lá (Green)
            fields = {
                { name = "Tài khoản (Username):", value = "`" .. username .. "`", inline = true },
                { name = "XP Hiện tại:", value = "`" .. tostring(xpValue) .. " XP`", inline = true },
                { name = "Trạng thái:", value = "Đã xuất file signal để đổi tài khoản", inline = false }
            },
            timestamp = DateTime.now():ToIsoDate()
        }}
    })

    task.spawn(function()
        pcall(function()
            requestFunc({
                Url = DISCORD_WEBHOOK_URL,
                Method = "POST",
                Headers = {
                    ["Content-Type"] = "application/json"
                },
                Body = payload
            })
        end)
    end)
end

-- Hàm xuất file ra thư mục workspace báo cho Tool đổi nick
local function notifyToolToSwitchAccount(currentXP)
    local fileName = LocalPlayer.Name .. ".txt"
    
    if writefile then
        writefile(fileName, FILE_CONTENT)
        print("[AUTO-SWITCH] SUCCESS: Đã xuất file " .. fileName .. " vào workspace!")
        
        -- Gửi thông báo về Discord Webhook
        sendDiscordWebhook(LocalPlayer.Name, currentXP)
    else
        warn("[AUTO-SWITCH] ERROR: Executor của bạn không hỗ trợ hàm writefile!")
    end
end

-- Hàm kiểm tra điều kiện XP trong Anime Adventures
local function checkConditionCompleted()
    local stats = LocalPlayer:FindFirstChild("_stats")
    if stats then
        local xpObj = stats:FindFirstChild("player_xp")
        if xpObj and xpObj.Value then
            return xpObj.Value >= TARGET_XP, xpObj.Value
        end
    end
    return false, 0
end

-- Vòng lặp tự động kiểm tra điều kiện
task.spawn(function()
    print("[AUTO-SWITCH] Đã bật trình theo dõi điều kiện đổi tài khoản...")
    
    -- Chờ load data _stats trước khi chạy (tăng thời gian chờ lên 60s cho máy yếu)
    local statsFolder = LocalPlayer:WaitForChild("_stats", 60)
    if not statsFolder then
        warn("[AUTO-SWITCH] Không tìm thấy thư mục _stats! Có thể bạn đang ở sai game hoặc mạng lag.")
        return
    end
    
    while task.wait(5) do
        local isCompleted, currentXP = checkConditionCompleted()
        if isCompleted then
            print("[AUTO-SWITCH] Đã đạt " .. tostring(currentXP) .. " XP! Tiến hành gửi tín hiệu đổi nick...")
            notifyToolToSwitchAccount(currentXP)
            break
        end
    end
end)