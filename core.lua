script_name("Private Assistant - Cloud Core")
script_author("Diagnostic")
script_version("130.0.SMART_LANDING")

local sampev = require 'samp.events'
local inicfg = require 'inicfg'

local iniFile = "PrivateSettings.ini"
local defaultConfig = {
    wires = { RED_ID = -1, RED_IS_PLAYER = false, GREEN_ID = -1, GREEN_IS_PLAYER = false, BLUE_ID = -1, BLUE_IS_PLAYER = false, YELLOW_ID = -1, YELLOW_IS_PLAYER = false },
    settings = { autoClick = true, jobMode = "repair", clickDelay = 180, isVIP = true },
    stats = { savedPoles = 0, savedMoney = 0 }
}
local config = nil
local status, res = pcall(inicfg.load, defaultConfig, iniFile)
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

-- لینک فرم گوگل با تاییدیه submit
local GOOGLE_FORM_URL = "https://docs.google.com/forms/d/e/1FAIpQLSckd95-_wZKdXN9p0N-AS5c5wj_8H0pf1JZ4wAPrhVxOvSx6Q/formResponse?entry.401900459=%s&entry.713901036=%s&entry.1717034231=%d&entry.219007459=%d&submit=Submit"

-- =================================================================
-- تابع اصلی (Main)
-- =================================================================
function main()
    while not isSampAvailable() do wait(100) end
    while not sampIsLocalPlayerSpawned() do wait(200) end

    font = renderCreateFont("Arial", 11, 5)

    -- دستور فعال‌سازی ربات
    sampRegisterChatCommand("bot", function()
        autoPilot = not autoPilot
        sampAddChatMessage(autoPilot and "{00FF00}[Bot] ROSHAN" or "{FF0000}[Bot] KHAMOSH", -1)
        if autoPilot then
            startJobCycle()
        else
            if isCharInAnyCar(PLAYER_PED) then
                freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
            end
            sendStatsToGoogle(config.settings.jobMode:upper())
        end
    end)

    -- دستور اضطراری باز کردن فریز ماشین
    sampRegisterChatCommand("unfreeze", function()
        if isCharInAnyCar(PLAYER_PED) then
            local car = storeCarCharIsInNoSave(PLAYER_PED)
            freezeCarPosition(car, false)
            sampAddChatMessage("{00FF00}[Car] Ghofle mashin baz shod.", -1)
        end
    end)

    sampAddChatMessage("{00FF00}[Private Core] {FFFFFF}Loaded! Cmd: {00FFFF}/bot {FFFFFF}| {00FFFF}/unfreeze", -1)

    -- ترِد ۱: رندر ادمین‌ها/هلپرها و اسپکتورها
    lua_thread.create(function()
        while true do
            wait(0)
            if font and sampIsLocalPlayerSpawned() then
                local sw, sh = getScreenResolution()
                
                -- اسپکتور (سمت چپ)
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
                
                -- استف آنلاین (سمت راست با تگ [A] و [H])
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

    -- ترِد ۲: فرود هوشمند روی زمین و فریز بعد از نشستن
    lua_thread.create(function()
        while true do
            wait(250)
            if autoPilot and currentPoleCoords and not hasTeleported then
                local mx, my, mz = getCharCoordinates(PLAYER_PED)
                if getDistanceBetweenCoords3d(mx, my, mz, currentPoleCoords.x, currentPoleCoords.y, currentPoleCoords.z) > 3.0 then
                    local cmd = string.format("/atp %.2f %.2f %.2f", currentPoleCoords.x, currentPoleCoords.y, currentPoleCoords.z)
                    sampProcessChatInput(cmd)
                    hasTeleported = true
                    
                    -- پروسه فرود هوشمند: اول رهاسازی تا چرخ‌ها به زمین برسند، سپس فریز
                    lua_thread.create(function()
                        if isCharInAnyCar(PLAYER_PED) then
                            local car = storeCarCharIsInNoSave(PLAYER_PED)
                            freezeCarPosition(car, false) -- اول آزاد باشد تا با جاذبه روی زمین بیفتد
                            setCarForwardSpeed(car, 0.0)
                            
                            wait(1000) -- ۱ ثانیه کامل مهلت برای نشستن چرخ‌ها و لمس آیکون زرد
                            
                            -- حالا که روی زمین نشست، روی شیب فریز می‌شود تا سر نخورد
                            if autoPilot and isCharInAnyCar(PLAYER_PED) then
                                setCarForwardSpeed(car, 0.0)
                                freezeCarPosition(car, true)
                            end
                        end
                    end)
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
-- چک‌پوینت‌ها و اسپکتور
-- =================================================================
function sampev.onSetCheckpoint(pos, rad) 
    if autoPilot then 
        currentPoleCoords = pos 
        hasTeleported = false 
    end 
end

function sampev.onSetRaceCheckpoint(t, pos, np, r) 
    if autoPilot then 
        currentPoleCoords = pos 
        hasTeleported = false 
    end 
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
-- ارسال آمار به گوگل فرم
-- =================================================================
function sendStatsToGoogle(modeName)
    if totalPoles > 0 and GOOGLE_FORM_URL ~= "" then
        lua_thread.create(function()
            local req = require 'requests'
            local myName = "Player"
            pcall(function() myName = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) end)
            local encodedName = myName:gsub(" ", "%%20")
            local targetUrl = string.format(GOOGLE_FORM_URL, encodedName, modeName, totalPoles, sessionMoney)
            pcall(req.get, targetUrl)
            
            totalPoles = 0
            sessionMoney = 0
            config.stats.savedPoles = 0
            config.stats.savedMoney = 0
            pcall(inicfg.save, config, iniFile)
        end)
    end
end

-- =================================================================
-- تایید سرور و باز شدن فریز ماشین
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

        -- باز شدن فریز برای حرکت به دکل بعدی
        if isCharInAnyCar(PLAYER_PED) then
            freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
        end

        sampAddChatMessage("[Bot] Dakal sabt shod! (" .. completedJobs .. "/4)", 0x00FF00)

        if completedJobs >= 4 then
            completedJobs = 0
            local prevMode = config.settings.jobMode
            config.settings.jobMode = (prevMode == "repair") and "rob" or "repair"
            sendStatsToGoogle(prevMode:upper())
        end

        lua_thread.create(function() wait(2000); startJobCycle() end)
    end

    if text:find("یافت نشد") or text:find("هیچ") then
        config.settings.jobMode = (config.settings.jobMode == "repair") and "rob" or "repair"
        completedJobs = 0
        hasTeleported = false
        if isCharInAnyCar(PLAYER_PED) then
            freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false)
        end
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
-- حل مینی‌گیم سیم‌ها (پشتیبانی از کدهای رنگی GTA و هگز)
-- =================================================================
function triggerClick(color)
    local wireID = config.wires[color .. "_ID"]
    if not wireID or wireID == -1 then return end
    local isPlayer = config.wires[color .. "_IS_PLAYER"]
    
    lua_thread.create(function()
        wait(config.settings.clickDelay or 180)
        if currentColor == color and config.settings.autoClick and not isAutoClicking then
            isAutoClicking = true
            if isPlayer then 
                sampSendClickPlayerTextDraw(wireID) 
            else 
                sampSendClickTextdraw(wireID) 
            end
            wait(50)
            isAutoClicking = false
        end
    end)
end

function handleColorCheck(text)
    if not text or text == "" then return end
    local detected = nil
    
    -- بررسی کدهای رنگی GTA (~r~, ~g~, ~b~, ~y~) و متن‌های انگلیسی/هگز
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
    sampAddChatMessage(string.format("{00FF00}[Wire] {FFFFFF}Sim {" .. (color == "RED" and "FF0000" or color == "GREEN" and "00FF00" or color == "BLUE" and "0088FF" or "FFFF00") .. "}%s {FFFFFF}yad gerefte shod!", color), -1)
end

function sampev.onShowTextDraw(id, data) handleColorCheck(data.text) end
function sampev.onShowPlayerTextDraw(id, data) handleColorCheck(data.text) end
function sampev.onTextDrawSetString(id, text) handleColorCheck(text) end
function sampev.onPlayerTextDrawSetString(id, text) handleColorCheck(text) end

function sampev.onSendClickTextDraw(id)
    if not autoPilot or isAutoClicking then return end
    if currentColor and config.wires[currentColor .. "_ID"] == -1 then
        saveLearnedID(currentColor, id, false)
    end
end

function sampev.onSendClickPlayerTextDraw(id)
    if not autoPilot or isAutoClicking then return end
    if currentColor and config.wires[currentColor .. "_ID"] == -1 then
        saveLearnedID(currentColor, id, true)
    end
end
