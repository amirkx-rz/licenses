script_name("Private Assistant - Cloud Core")
script_author("Diagnostic")
script_version("108.0.FINAL")

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
local isTeleporting = false
local TeleportSync = false

-- لینک گوگل فرم آماده با آیدی‌های استخراج‌شده
local FORM_URL = "https://docs.google.com/forms/d/e/1FAIpQLSckd95-_wZKdXN9p0N-AS5c5wj_8H0pf1JZ4wAPrhVxOvSx6Q/formResponse?entry.401900459=%s&entry.713901036=%s&entry.1717034231=%d&entry.219007459=%d"

local ADMINS = {"Admin1", "Admin2", "Admin3"}
local font = renderCreateFont("Arial", 10, 5)
local spectatingMe = "None"

function startJobCycle()
    if not autoPilot then return end
    lua_thread.create(function() wait(500); sampSendChat("/pl") end)
end

-- ارسال داده به گوگل فرم
function sendStatsToGoogle(modeName)
    if totalPoles > 0 then
        lua_thread.create(function()
            local req = require 'requests'
            local myName = "Player"
            pcall(function() myName = sampGetPlayerNickname(select(2, sampGetPlayerIdByCharHandle(PLAYER_PED))) end)
            local encodedName = myName:gsub(" ", "%%20")
            local targetUrl = string.format(FORM_URL, encodedName, modeName, totalPoles, sessionMoney)
            pcall(req.get, targetUrl)
            
            -- بازنشانی مقادیر پس از ارسال موفق
            totalPoles = 0
            sessionMoney = 0
            config.stats.savedPoles = 0
            config.stats.savedMoney = 0
            pcall(inicfg.save, config, iniFile)
        end)
    end
end

-- رندر وضعیت اسپکت و ادمین‌های آنلاین
lua_thread.create(function()
    while true do
        wait(0)
        local sw, sh = getScreenResolution()
        renderFontDrawText(font, "Spectator: " .. spectatingMe, 10, sh / 2, 0xFF00FFFF)
        
        local yOffset = sh / 3
        renderFontDrawText(font, "--- Admins Online ---", sw - 160, yOffset, 0xFFFFAA00)
        yOffset = yOffset + 15
        local found = false
        for i = 0, sampGetMaxPlayerId(true) do
            if sampIsPlayerConnected(i) then
                local name = sampGetPlayerNickname(i)
                for _, admin in ipairs(ADMINS) do
                    if name:find(admin) then
                        renderFontDrawText(font, name .. " ["..i.."]", sw - 160, yOffset, 0xFFFF0000)
                        yOffset = yOffset + 15
                        found = true
                    end
                end
            end
        end
        if not found then renderFontDrawText(font, "Safe", sw - 160, yOffset, 0xFF00FF00) end
    end
end)

-- ترِد نظارت و جابه‌جایی
lua_thread.create(function()
    while true do
        wait(250)
        if autoPilot and currentPoleCoords and not isTeleporting then
            local mx, my, mz = getCharCoordinates(PLAYER_PED)
            if getDistanceBetweenCoords3d(mx, my, mz, currentPoleCoords.x, currentPoleCoords.y, currentPoleCoords.z) > 3.0 then
                isTeleporting = true
                TeleportSync = true
                local tx, ty, tz = currentPoleCoords.x, currentPoleCoords.y, currentPoleCoords.z
                local targetZ = (tz and tz > 0.0) and tz or 15.0

                if isCharInAnyCar(PLAYER_PED) then
                    local car = storeCarCharIsInNoSave(PLAYER_PED)
                    freezeCarPosition(car, false)
                    setCarForwardSpeed(car, 0.0)
                    setCarCoordinates(car, tx, ty, targetZ + 0.15)
                    setCarForwardSpeed(car, 0.0)
                    wait(500)
                    freezeCarPosition(car, true) -- فریز پایدار روی دکل
                else
                    setCharCoordinates(PLAYER_PED, tx, ty, targetZ + 0.3)
                end
                wait(800)
                TeleportSync = false
                isTeleporting = false
            end
        end
    end
end)

function sampev.onReceiveRpc(id, bitStream)
    if TeleportSync or isTeleporting then
        if id == 12 or id == 159 or id == 71 then return false end
    end
end

function sampev.onSetCheckpoint(pos, rad) currentPoleCoords = pos end
function sampev.onSetRaceCheckpoint(t, pos, np, r) currentPoleCoords = pos end
function sampev.onDisableCheckpoint() currentPoleCoords = nil end
function sampev.onDisableRaceCheckpoint() currentPoleCoords = nil end

function sampev.onPlayerSync(playerId, data)
    if sampIsPlayerConnected(playerId) then
        local mx, my, mz = getCharCoordinates(PLAYER_PED)
        if getDistanceBetweenCoords3d(mx, my, mz, data.position.x, data.position.y, data.position.z) < 1.5 then
            if not isCharOnScreen(getCharPlayerIsTargeting(PLAYER_HANDLE)) then
                spectatingMe = sampGetPlayerNickname(playerId)
                return
            end
        end
    end
    spectatingMe = "None"
end

-- دریافت پیام‌های سرور و پردازش درآمد
function sampev.onServerMessage(color, text)
    if not autoPilot then return end

    -- ۱. به‌روزرسانی مقدار دقیق درآمد در صورت چاپ رقم توسط سرور
    local earned = text:match("Earned: %$(%d+)")
    if earned then
        sessionMoney = tonumber(earned)
    end

    -- ۲. تایید پایان کار روی دکل
    if text:find("All wires got fixed successfully") or text:find("You successfully stole the metal") then
        completedJobs = completedJobs + 1
        totalPoles = totalPoles + 1
        
        -- محاسبه ریاضی درآمد در صورتی که سرور رقم را چاپ نکرده باشد
        if not earned then
            local isRob = (config.settings.jobMode == "rob")
            if config.settings.isVIP then
                sessionMoney = sessionMoney + (isRob and 21600 or 23400)
            else
                sessionMoney = sessionMoney + (isRob and 10800 or 11700)
            end
        end

        -- ذخیره آنی در حافظه محلی برای حفظ داده‌ها در صورت کرش
        config.stats.savedPoles = totalPoles
        config.stats.savedMoney = sessionMoney
        pcall(inicfg.save, config, iniFile)

        currentPoleCoords = nil
        if isCharInAnyCar(PLAYER_PED) then freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false) end
        sampAddChatMessage("[Bot] Dakal sabt shod! (" .. completedJobs .. "/4)", 0x00FF00)

        -- تغییر مود پس از ۴ دکل و ارسال داده‌ها به فرم
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
        lua_thread.create(function() wait(2000); startJobCycle() end)
    end
end

sampRegisterChatCommand("bot", function()
    autoPilot = not autoPilot
    sampAddChatMessage(autoPilot and "{00FF00}Bot ROSHAN" or "{FF0000}Bot KHAMOSH", -1)
    if autoPilot then
        startJobCycle()
    else
        if isCharInAnyCar(PLAYER_PED) then freezeCarPosition(storeCarCharIsInNoSave(PLAYER_PED), false) end
        sendStatsToGoogle(config.settings.jobMode:upper())
    end
end)

sampRegisterChatCommand("atp", function()
    local ok, x, y, z = getTargetBlipCoordinates()
    if ok then
        TeleportSync = true
        if isCharInAnyCar(PLAYER_PED) then
            setCarCoordinates(storeCarCharIsInNoSave(PLAYER_PED), x, y, z + 0.5)
        else
            setCharCoordinates(PLAYER_PED, x, y, z + 0.5)
        end
        lua_thread.create(function() wait(1000); TeleportSync = false end)
    end
end)

-- پاسخ‌دهی به دیالوگ‌ها
function sampev.onShowDialog(id, style, title, b1, b2, text)
    if not autoPilot then return end
    local t = (title or ""):lower()
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

-- حل مینی‌گیم سیم‌ها
function triggerClick(color)
    local wireID = config.wires[color .. "_ID"]
    if not wireID or wireID == -1 then return end
    local isPlayer = config.wires[color .. "_IS_PLAYER"]
    lua_thread.create(function()
        wait(config.settings.clickDelay)
        if isPlayer then sampSendClickPlayerTextDraw(wireID) else sampSendClickTextdraw(wireID) end
    end)
end

function handleColorCheck(text)
    local col = (text or ""):gsub("{.-}", ""):upper()
    local c = col:find("GREEN") and "GREEN" or col:find("RED") and "RED" or col:find("BLUE") and "BLUE" or col:find("YELLOW") and "YELLOW"
    if c then triggerClick(c) end
end

function sampev.onShowTextDraw(id, data) handleColorCheck(data.text)
    if config.wires["RED_ID"] == -1 then config.wires["RED_ID"]=id; config.wires["RED_IS_PLAYER"]=false; pcall(inicfg.save, config, iniFile) end
end
function sampev.onShowPlayerTextDraw(id, data) handleColorCheck(data.text) end
function sampev.onTextDrawSetString(id, text) handleColorCheck(text) end
function sampev.onPlayerTextDrawSetString(id, text) handleColorCheck(text) end
