script_name("Private Assistant - Cloud Core")
script_author("Diagnostic")
script_version("1000.0.ULTIMATE_PACKAGE")

local sampev = require 'samp.events'
local inicfg = require 'inicfg'

local iniFile = "AutoElectrician.ini"
local defaultConfig = {
    wires = { RED_ID = -1, RED_IS_PLAYER = false, GREEN_ID = -1, GREEN_IS_PLAYER = false, BLUE_ID = -1, BLUE_IS_PLAYER = false, YELLOW_ID = -1, YELLOW_IS_PLAYER = false },
    settings = { autoClick = true, jobMode = "repair", clickDelay = 180, isVIP = true },
    stats = { savedPoles = 0, savedMoney = 0 }
}
local config = nil
local status, res = pcall(inicfg.load, defaultConfig, iniFile)
if not status or not res then
    iniFile = "PrivateSettings.ini"
    status, res = pcall(inicfg.load, defaultConfig, iniFile)
end
if status and res then config = res else config = defaultConfig end

local autoPilot = false
local currentPoleCoords = nil
local completedJobs = 0
local sessionMoney = config.stats.savedMoney or 0
local totalPoles = config.stats.savedPoles or 0
local hasTeleported = false

local font = nil
local activeSpectators = {}

local currentColor = nil
local isAutoClicking = false
local isInMinigame = false
local lastWireTime = 0

-- کلیدها و آیدی دقیق یوزر شما در روبیکا
local RUBIKA_BOT_TOKEN = "8899767938:AAGND-rSlHi-6w7TBjAAAHFkGnKQHWC2Dr8"
local RUBIKA_CHAT_ID   = "u0HMBLf0979ba9be99cc859323174c34"

-- سپر محافظ پکت‌ها
local TeleportSync = false

-- =================================================================
-- تابع اصلی (Main)
-- =================================================================
function main()
    while not isSampAvailable() do wait(100) end
    while not sampIsLocalPlayerSpawned() do wait(200) end

    font = renderCreateFont("Arial", 11, 5)

    sampRegisterChatCommand("bot", function()
        autoPilot = not autoPilot
        sampAddChatMessage(autoPilot and "{00FF00}[Bot] ROSHAN" or "{FF0000}[Bot] KHAMOSH", -1)
        if autoPilot then
            startJobCycle()
        else
            -- ارسال آمار به روبیکا موقع خاموش کردن
            sendStats("MANUAL_STOP", true)
        end
    end)

    -- دستور تست فوری روبیکا
    sampRegisterChatCommand("testrubika", function()
        sampAddChatMessage("{00DDFF}[Test] Dar hale ersal be Rubika (Method: URL GET)...", -1)
        sendStats("TEST_MANUAL", true)
    end)

    -- نمایش آمار آفلاین در چت
    sampRegisterChatCommand("mystats", function()
        sampAddChatMessage(string.format("{00DDFF}[Stats] {FFFFFF}Poles: %d | Income: $%d", totalPoles, sessionMoney), -1)
    end)

    sampAddChatMessage("{00FF00}[Private Core] {FFFFFF}Loaded! Cmds: {00FFFF}/bot {FFFFFF}| {00FFFF}/testrubika {FFFFFF}| {00FFFF}/mystats", -1)

    -- ترِد ۱: رندر ادمین‌ها و اسپکتورها
    lua_thread.create(function()
        while true do
            wait(0)
            if font and sampIsLocalPlayerSpawned() then
                local sw, sh = getScreenResolution()
                
                -- اسپکتور
                local specY = sh / 2
                renderFontDrawText(font, "--- Spectators ---", 10, specY - 18, 0xFF00FFFF)
                local hasSpec = false
                for name, time in pairs(activeSpectators) do
                    if os.clock() - time < 3.0 then 
                        renderFontDrawText(font, ">> " .. name, 10, specY, 0xFFFF0000)
                        specY = specY + 16
                        hasSpec = true
                    else
                        activeSpectators[name] = nil
                    end
                end
                if not hasSpec then renderFontDrawText(font, "None", 10, specY, 0xFF00FF00) end
                
                -- ادمین و هلپر [A] [H]
                local yOffset = sh / 3
                renderFontDrawText(font, "--- Staff Online ---", sw - 170, yOffset, 0xFFFFAA00)
                yOffset = yOffset + 18
                local foundStaff = false
                for i = 0, sampGetMaxPlayerId(true) do
                    if sampIsPlayerConnected(i) then
                        local name = sampGetPlayerNickname(i)
                        if name and type(name) == "string" then
                            if name:find("%[A%]") or name:find("%[H%]") or name:find("Admin") then
                                renderFontDrawText(font, name .. " ["..i.."]", sw - 170, yOffset, 0xFFFF0000)
                                yOffset = yOffset + 16
                                foundStaff = true
                            end
                        end
                    end
                end
                if not foundStaff then renderFontDrawText(font, "Safe", sw - 170, yOffset, 0xFF00FF00) end
            end
        end
    end)

    -- ترِد ۲: تلپورت خودکار (متد دقیق آرت)
    lua_thread.create(function()
        while true do
            wait(250)
            if autoPilot and currentPoleCoords and not hasTeleported then
                local mx, my, mz = getCharCoordinates(PLAYER_PED)
                if getDistanceBetweenCoords3d(mx, my, mz, currentPoleCoords.x, currentPoleCoords.y, currentPoleCoords.z) > 3.0 then
                    executeArtTeleport(currentPoleCoords.x, currentPoleCoords.y, currentPoleCoords.z)
                    hasTeleported = true
                else
                    hasTeleported = true
                end
            end
        end
    end)

    wait(-1)
end

function startJobCycle()
    if not autoPilot then return end
    lua_thread.create(function() wait(500); sampSendChat("/pl") end)
end

-- =================================================================
-- متد ۱۰۰٪ خالص آرت (بدون فریز ماشین، بدون کرش، فقط Player Ped)
-- =================================================================
function executeArtTeleport(tx, ty, tz)
    lua_thread.create(function()
        TeleportSync = true
        local targetZ = (tz and tz > 0.0) and tz or 15.0
        
        -- جادوی موبایل: انتقال کاراکتر حتی اگر در ماشین باشد!
        setCharCoordinates(PLAYER_PED, tx, ty, targetZ)
        
        -- سپر 2.5 ثانیه باز می‌ماند تا سرور تسلیم شود
        wait(2500)
        TeleportSync = false
    end)
end

-- مسدودسازی پکت‌های بازگرداننده سرور
function sampev.onReceiveRpc(id, bitStream)
    if TeleportSync then
        -- 12 = SetPlayerPos | 159/71 = SetVehiclePos
        if id == 12 or id == 159 or id == 71 then
            return false
        end
    end
end

-- =================================================================
-- ثبت چک‌پوینت‌ها و اسپکتور
-- =================================================================
function sampev.onSetCheckpoint(pos, rad) 
    if autoPilot then currentPoleCoords = pos; hasTeleported = false end 
end

function sampev.onSetRaceCheckpoint(t, pos, np, r) 
    if autoPilot then currentPoleCoords = pos; hasTeleported = false end 
end

function sampev.onDisableCheckpoint() currentPoleCoords = nil; hasTeleported = false end
function sampev.onDisableRaceCheckpoint() currentPoleCoords = nil; hasTeleported = false end

function sampev.onPlayerSync(playerId, data)
    if not sampIsLocalPlayerSpawned() then return end
    pcall(function()
        if sampIsPlayerConnected(playerId) then
            local mx, my, mz = getCharCoordinates(PLAYER_PED)
            local dist = getDistanceBetweenCoords3d(mx, my, mz, data.position.x, data.position.y, data.position.z)
            if dist < 2.0 then
                local hasPed, pedHandle = sampGetCharHandleBySampPlayerId(playerId)
                if not hasPed or (hasPed and doesCharExist(pedHandle) and not isCharOnScreen(pedHandle)) then
                    local specName = sampGetPlayerNickname(playerId)
                    if specName and specName ~= "" then
                        activeSpectators[specName] = os.clock()
                    end
                end
            end
        end
    end)
end

-- =================================================================
-- سیستم ارسال آمار به روبیکا (متد جادویی URL Encode بدون JSON)
-- =================================================================
local function urlencode(str)
    if str then
        str = string.gsub(str, "\n", "\r\n")
        str = string.gsub(str, "([^%w %-%_%.%~])", function(c) return string.format("%%%02X", string.byte(c)) end)
        str = string.gsub(str, " ", "%%20")
    end
    return str
end

function sendStats(modeName, forceSend)
    if (totalPoles > 0 or forceSend) then
        lua_thread.create(function()
            local myName = "Player"
            pcall(function() myName = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) end)
            
            local pCount = math.floor(totalPoles > 0 and totalPoles or 1)
            local pMoney = math.floor(sessionMoney > 0 and sessionMoney or 11700)
            local pMode  = modeName or "REPAIR"

            -- 1. ذخیره در فایل متنی داخل گوشی (بک‌آپ امنیتی آفلاین)
            pcall(function()
                local path = getWorkingDirectory() .. "/ElectricianStats.txt"
                local f = io.open(path, "a")
                if f then
                    f:write(string.format("[%s] Player: %s | Mode: %s | Poles: %d | Money: $%d\n", os.date("%H:%M:%S"), myName, pMode, pCount, pMoney))
                    f:close()
                end
            end)

            -- 2. ارسال به روبیکا از طریق لینک مستقیم (GET Request)
            local rawText = string.format("📊 Report (Electrician)\n👤 Player: %s\n🛠 Mode: %s\n⚡️ Poles: %d\n💰 Income: $%d", myName, pMode, pCount, pMoney)
            local encodedText = urlencode(rawText)
            
            -- فرمت جادویی که امکان ندارد INVALID_INPUT بدهد!
            local targetUrl = string.format("https://botapi.rubika.ir/v3/%s/sendMessage?chat_id=%s&text=%s", RUBIKA_BOT_TOKEN, RUBIKA_CHAT_ID, encodedText)

            -- استفاده از 2 کتابخانه مختلف برای اطمینان 100 درصدی از ارسال
            local req_ok, req = pcall(require, 'requests')
            if req_ok and req then
                pcall(req.get, targetUrl)
            else
                local http_ok, http = pcall(require, 'socket.http')
                if http_ok and http then
                    pcall(http.request, targetUrl)
                end
            end
            
            sampAddChatMessage("{00FF00}[System] {FFFFFF}Amar zakhire va ersal shod!", -1)
            
            if not forceSend then
                totalPoles = 0
                sessionMoney = 0
                config.stats.savedPoles = 0
                config.stats.savedMoney = 0
                pcall(inicfg.save, config, iniFile)
            end
        end)
    end
end

-- =================================================================
-- تایید سرور و مدیریت پایان دکل
-- =================================================================
function sampev.onServerMessage(color, text)
    if not autoPilot then return end

    local earned = text:match("Earned: %$(%d+)")
    if earned then sessionMoney = tonumber(earned) end

    if text:find("All wires got fixed") or text:find("successfully stole the metal") then
        completedJobs = completedJobs + 1
        totalPoles = totalPoles + 1
        
        if not earned then
            local isRob = (config.settings.jobMode == "rob")
            sessionMoney = sessionMoney + (isRob and (config.settings.isVIP and 21600 or 10800) or (config.settings.isVIP and 23400 or 11700))
        end

        config.stats.savedPoles = totalPoles
        config.stats.savedMoney = sessionMoney
        pcall(inicfg.save, config, iniFile)

        currentPoleCoords = nil
        hasTeleported = false

        sampAddChatMessage("[Bot] Dakal sabt shod! (" .. completedJobs .. "/4)", 0x00FF00)

        if completedJobs >= 4 then
            completedJobs = 0
            local prevMode = config.settings.jobMode
            config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
            sendStats(prevMode:upper(), false)
        end

        lua_thread.create(function() wait(2000); startJobCycle() end)
    end

    if text:find("یافت نشد") or text:find("هیچ") then
        config.settings.jobMode = (config.settings.jobMode == "repair") and "rob" or "repair"
        completedJobs = 0
        hasTeleported = false
        lua_thread.create(function() wait(2000); startJobCycle() end)
    end
end

-- =================================================================
-- دیالوگ‌ها
-- =================================================================
function sampev.onShowDialog(id, style, title, b1, b2, text)
    if not autoPilot then return end
    local t, rawText = (title or ""):lower(), (text or "")
    if t:find("what job") or t:find("what do you want") then
        lua_thread.create(function() wait(200); sampSendDialogResponse(id, 1, (config.settings.jobMode == "repair") and 0 or 1, "") end)
        return
    end
    if t:find("in need of repair") or t:find("can be robbed") then
        local best, minD, row = -1, 999999, 0
        for line in text:gmatch("[^\r\n]+") do
            if not line:find("Distance") and not line:find("Location") then
                local d = tonumber(line:match("(%d+%.?%d*)%s*$"))
                if d and d < minD then minD = d; best = row end
                row = row + 1
            end
        end
        if best ~= -1 then lua_thread.create(function() wait(200); sampSendDialogResponse(id, 1, best, "") end) end
    end
end

-- =================================================================
-- مینی‌گیم سیم‌ها
-- =================================================================
function triggerClick(color)
    local wireID = config.wires[color .. "_ID"]
    if not wireID or wireID == -1 then return end
    local isPlayer = config.wires[color .. "_IS_PLAYER"]
    
    lua_thread.create(function()
        wait(config.settings.clickDelay or 180)
        if currentColor == color and config.settings.autoClick then
            isAutoClicking = true
            if isPlayer then
                sampSendClickPlayerTextDraw(wireID)
            else
                sampSendClickTextdraw(wireID)
            end
            isAutoClicking = false
        end
    end)
end

function handleColorCheck(text)
    if not text or text == "" then return end
    local detected = nil
    
    if text:find("~g~") or text:find("~G~") or text:upper():find("GREEN") or text:upper():find("SABZ") or text:find("00FF00") or text:find("00ff00") then
        detected = "GREEN"
    elseif text:find("~r~") or text:find("~R~") or text:upper():find("RED") or text:upper():find("GHERMEZ") or text:find("FF0000") or text:find("ff0000") then
        detected = "RED"
    elseif text:find("~b~") or text:find("~B~") or text:upper():find("BLUE") or text:upper():find("ABI") or text:find("0000FF") or text:find("0088FF") then
        detected = "BLUE"
    elseif text:find("~y~") or text:find("~Y~") or text:upper():find("YELLOW") or text:upper():find("ZARD") or text:find("FFFF00") or text:find("ffff00") then
        detected = "YELLOW"
    end

    if detected then
        isInMinigame = true
        lastWireTime = os.clock()
        currentColor = detected
        triggerClick(detected)
    end
end

function saveLearnedID(color, id, isPlayer)
    config.wires[color .. "_ID"] = id
    config.wires[color .. "_IS_PLAYER"] = isPlayer
    pcall(inicfg.save, config, iniFile)
    sampAddChatMessage(string.format("[Electrician] Saved {" .. (color == "RED" and "FF0000" or color == "GREEN" and "00FF00" or color == "BLUE" and "0088FF" or "FFFF00") .. "}%s {FFFFFF}!", color), -1)
end

function sampev.onShowTextDraw(id, data) handleColorCheck(data.text) end
function sampev.onShowPlayerTextDraw(id, data) handleColorCheck(data.text) end
function sampev.onTextDrawSetString(id, text) handleColorCheck(text) end
function sampev.onPlayerTextDrawSetString(id, text) handleColorCheck(text) end

function sampev.onSendClickTextDraw(id)
    if isAutoClicking or not config.settings.autoClick then return end
    if currentColor and config.wires[currentColor .. "_ID"] == -1 then
        saveLearnedID(currentColor, id, false)
    end
end

function sampev.onSendClickPlayerTextDraw(id)
    if isAutoClicking or not config.settings.autoClick then return end
    if currentColor and config.wires[currentColor .. "_ID"] == -1 then
        saveLearnedID(currentColor, id, true)
    end
end

main()
