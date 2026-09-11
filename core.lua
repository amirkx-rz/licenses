script_name("Private Assistant - Cloud Core")
script_author("Diagnostic")
script_version("120.0.FULL")

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

-- لینک فرم گوگل
local GOOGLE_FORM_URL = "https://docs.google.com/forms/d/e/1FAIpQLSckd95-_wZKdXN9p0N-AS5c5wj_8H0pf1JZ4wAPrhVxOvSx6Q/formResponse?entry.401900459=%s&entry.713901036=%s&entry.1717034231=%d&entry.219007459=%d"

-- =================================================================
-- تابع اصلی (Main)
-- =================================================================
function main()
    while not isSampAvailable() do wait(100) end
    while not sampIsLocalPlayerSpawned() do wait(200) end

    sampRegisterChatCommand("bot", function()
        autoPilot = not autoPilot
        sampAddChatMessage(autoPilot and "{00FF00}[Bot] ROSHAN" or "{FF0000}[Bot] KHAMOSH", -1)
        if autoPilot then
            startJobCycle()
        else
            sendStatsToGoogle(config.settings.jobMode:upper())
        end
    end)

    sampAddChatMessage("{00FF00}[Private Core] {FFFFFF}Loaded! Cmd: {00FFFF}/bot", -1)

    -- ترِد نظارت خودکار و ارسال مختصات به /atp
    lua_thread.create(function()
        while true do
            wait(250)
            if autoPilot and currentPoleCoords and not hasTeleported then
                local mx, my, mz = getCharCoordinates(PLAYER_PED)
                if getDistanceBetweenCoords3d(mx, my, mz, currentPoleCoords.x, currentPoleCoords.y, currentPoleCoords.z) > 3.0 then
                    local cmd = string.format("/atp %.2f %.2f %.2f", currentPoleCoords.x, currentPoleCoords.y, currentPoleCoords.z)
                    sampProcessChatInput(cmd)
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
-- ثبت چک‌پوینت‌ها
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

-- =================================================================
-- محاسبه درآمد و ارسال به فرم گوگل
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
            sendStatsToGoogle(prevMode:upper())
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
-- دیالوگ‌ها و حل مینی‌گیم سیم‌ها
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
function sampev.onSendClickTextDraw(id)
    if not autoPilot then return end
    if config.wires["RED_ID"] == -1 then config.wires["RED_ID"]=id; config.wires["RED_IS_PLAYER"]=false; pcall(inicfg.save, config, iniFile) end
end
function sampev.onSendClickPlayerTextDraw(id)
    if not autoPilot then return end
    if config.wires["RED_ID"] == -1 then config.wires["RED_ID"]=id; config.wires["RED_IS_PLAYER"]=true; pcall(inicfg.save, config, iniFile) end
end

-- استارت در اجرای ابری
main()
