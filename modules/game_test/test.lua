Test = {}

local window
local monsterList
local collecting = false
local buffer = {}
local fullMonsterList = {}
local characterMarkers = {} -- Armazena marcadores por personagem: characterMarkers[charName] = {monster=true}
local currentSort = "name_asc"

------------------------------------------------------------
-- Helper: Retorna tabela de marcadores do personagem atual
------------------------------------------------------------
local function getCurrentMarkers()
    local player = g_game.getLocalPlayer()
    if not player then return {} end
    
    local name = player:getName()
    if not characterMarkers[name] then
        characterMarkers[name] = {}
    end
    return characterMarkers[name]
end

function init()
    print("[TEST] Loaded!")

    g_ui.importStyle("bestiary_card_block.otui")

    window = g_ui.displayUI("test")
    window:hide()

    -- Botão Close
    local closeButton = window:getChildById("closeButton")
    if closeButton then
        closeButton.onClick = function() window:hide() end
    end

    -- Área onde aparecem os cards
    monsterList = window:getChildById("monsterScroll")
    
    -- Configurar ComboBox de ordenação
    local sortBox = window:getChildById("sortComboBox")
    if sortBox then
        sortBox:addOption("Nome (A-Z)", "name_asc")
        sortBox:addOption("Nome (Z-A)", "name_desc")
        sortBox:addOption("Ciclos (Maior)", "cycle_desc")
        sortBox:addOption("Ciclos (Menor)", "cycle_asc")
        sortBox:addOption("Mortes (Maior)", "progress_desc")
        sortBox:addOption("Mortes (Menor)", "progress_asc")
        sortBox:addOption("Progresso % (Maior)", "percent_desc")
        sortBox:addOption("Progresso % (Menor)", "percent_asc")
        
        sortBox.onOptionChange = function(widget, option, data)
            currentSort = data
            Test.sortAndDisplay()
        end
    end

    modules.client_topmenu.addRightGameToggleButton(
        "testButton",
        "Bestiary",
        "/images/options/test",
        function() Test.toggle() end
    )

    connect(g_game, {
        onGameEnd = Test.onGameEnd,
        onTextMessage = Test.onTextMessage
    })
end

function terminate()
    disconnect(g_game, {
        onGameEnd = Test.onGameEnd,
        onTextMessage = Test.onTextMessage
    })
    
    if window then
        window:destroy()
    end
end

------------------------------------------------------------
-- Abre / fecha janela
------------------------------------------------------------
function Test.toggle()
    if window:isVisible() then
        window:hide()
    else
        window:show()
        window:raise()
        window:focus()

        if g_game.isOnline() then
            g_game.talk("/bestiary_request")
        end
    end
end

function Test.onGameEnd()
    if window and window:isVisible() then
        window:hide()
    end
end

------------------------------------------------------------
-- Processa mensagens do chat (JSON chunks)
------------------------------------------------------------
function Test.onTextMessage(mode, text)
    if not g_game.isOnline() then return end
    
    if text == "[BESTIARY_START]" then
        collecting = true
        buffer = {}
        return
    elseif text == "[BESTIARY_END]" then
        collecting = false
        local fullJson = table.concat(buffer)
        
        -- Tentar decodificar
        local status, list = pcall(function() return json.decode(fullJson) end)
        if status and list then
            fullMonsterList = list
            Test.sortAndDisplay()
        else
            print("[TEST] Erro JSON: " .. fullJson)
        end
        return
    end
    
    if collecting then
        table.insert(buffer, text)
    end
end

------------------------------------------------------------
-- Alterna marcador (max 4)
------------------------------------------------------------
function Test.toggleMarker(name)
    if not name then return end

    local markers = getCurrentMarkers()

    if markers[name] then
        markers[name] = nil
    else
        -- Contar quantos já estão marcados
        local count = 0
        for _ in pairs(markers) do count = count + 1 end
        
        if count >= 4 then
            -- Feedback visual ou log
            return
        end
        markers[name] = true
    end
    
    -- Reordenar e atualizar a lista
    Test.sortAndDisplay()
end

------------------------------------------------------------
-- Ordena e atualiza a lista
------------------------------------------------------------
function Test.sortAndDisplay()
    if not fullMonsterList or #fullMonsterList == 0 then
        Test.updateList({})
        return
    end

    table.sort(fullMonsterList, function(a, b)
        local markers = getCurrentMarkers()
        -- 1. Marcados primeiro
        local markedA = markers[a.name] and 1 or 0
        local markedB = markers[b.name] and 1 or 0
        if markedA ~= markedB then
            return markedA > markedB
        end

        -- 2. Ordenação normal
        if currentSort == "name_asc" then
            return (a.name or "") < (b.name or "")
        elseif currentSort == "name_desc" then
            return (a.name or "") > (b.name or "")
        elseif currentSort == "cycle_desc" then
            if (a.cycle or 0) == (b.cycle or 0) then return (a.name or "") < (b.name or "") end
            return (a.cycle or 0) > (b.cycle or 0)
        elseif currentSort == "cycle_asc" then
            if (a.cycle or 0) == (b.cycle or 0) then return (a.name or "") < (b.name or "") end
            return (a.cycle or 0) < (b.cycle or 0)
        elseif currentSort == "progress_desc" then
            if (a.progress or 0) == (b.progress or 0) then return (a.name or "") < (b.name or "") end
            return (a.progress or 0) > (b.progress or 0)
        elseif currentSort == "progress_asc" then
            if (a.progress or 0) == (b.progress or 0) then return (a.name or "") < (b.name or "") end
            return (a.progress or 0) < (b.progress or 0)
        elseif currentSort == "percent_desc" then
            if (a.percent or 0) == (b.percent or 0) then return (a.name or "") < (b.name or "") end
            return (a.percent or 0) > (b.percent or 0)
        elseif currentSort == "percent_asc" then
            if (a.percent or 0) == (b.percent or 0) then return (a.name or "") < (b.name or "") end
            return (a.percent or 0) < (b.percent or 0)
        else
            return (a.name or "") < (b.name or "")
        end
    end)

    Test.updateList(fullMonsterList)
end

------------------------------------------------------------
-- Cria e exibe os cards
------------------------------------------------------------
function Test.updateList(list)
    if not monsterList then return end

    monsterList:destroyChildren()

    if #list == 0 then
        local lbl = g_ui.createWidget("UILabel", monsterList)
        lbl:setFont("Verdana Bold-11px-wheel")
        lbl:setText("Nenhum Bestiary iniciado.")
        lbl:setColor("#FFD700")
        return
    end

    for _, m in ipairs(list) do
        -- Criar card usando o estilo BestiaryCardBlock
        local block = g_ui.createWidget("BestiaryCardBlock", monsterList)

        if block then
            -- Pegar widgets internos
            local icon      = block:getChildById("icon")
            local name      = block:getChildById("nameLabel")
            local cycle     = block:getChildById("cycleLabel")
            local pbBg      = block:getChildById("progressBarBg")
            local pbFill    = pbBg and pbBg:getChildById("progressBarFill")
            local pbText    = pbBg and pbBg:getChildById("progressText")
            local markerBtn = block:getChildById("markerButton")

            -- Configurar botão de marcador
            if markerBtn then
                local markers = getCurrentMarkers()
                local isMarked = markers[m.name]
                if isMarked then
                    markerBtn:setBackgroundColor("#FFFF00") -- Amarelo se marcado
                else
                    markerBtn:setBackgroundColor("#333333") -- Padrão
                end
                
                markerBtn.onClick = function()
                    Test.toggleMarker(m.name)
                end
            end

            -- Preencher dados
            if icon then
                local lookType = m.lookType
                if not lookType then lookType = 21 end -- Fallback

                local creatureWidget = g_ui.createWidget("UICreature", icon)
                creatureWidget:setSize("64 64")
                creatureWidget:setCreatureSize(64)
                creatureWidget:setCenter(true)
                creatureWidget:setOutfit({
                    type = lookType,
                    head = m.lookHead or 0,
                    body = m.lookBody or 0,
                    legs = m.lookLegs or 0,
                    feet = m.lookFeet or 0,
                    addons = m.lookAddons or 0
                })
                local c = creatureWidget:getCreature()
                if c then c:setDirection(2) end
            end

            if name then
                name:setText(m.name or "Unknown")
            end

            if cycle then
                cycle:setText(string.format("Ciclo: %d / %d", m.cycle or 0, m.maxCycles or 0))
            end

            if pbFill and pbText then
                local percent = m.percent or 0
                if percent > 100 then percent = 100 end
                if percent < 0 then percent = 0 end
                
                -- Max width is 128 (130 - 2 margin)
                local maxWidth = 128 
                local w = math.floor((percent / 100) * maxWidth)
                if w < 1 then w = 1 end 
                if percent == 0 then w = 0 end

                pbFill:setWidth(w)
                pbText:setText(percent .. "%")
                
                -- Color logic
                if percent >= 100 then
                    pbFill:setBackgroundColor("#00FF00") -- Green
                elseif percent >= 50 then
                    pbFill:setBackgroundColor("#FFAA00") -- Orange
                else
                    pbFill:setBackgroundColor("#FF4444") -- Red
                end
            end
        end
    end
end
