local OPCODE_CUSTOM_STORE = 217
local BACKEND_URL = "http://localhost:5000"

local storeWindow = nil
local authToken = nil
local playerId = nil

local categories = {}
local products = {}
local featuredProducts = {}

local currentCategory = nil
local selectedProduct = nil

function init()
    g_ui.importStyle('customstore')
    ProtocolGame.registerExtendedOpcode(OPCODE_CUSTOM_STORE, onExtendedOpcode)
    connect(g_game, { onGameEnd = onGameEnd })
end

function terminate()
    disconnect(g_game, { onGameEnd = onGameEnd })
    ProtocolGame.unregisterExtendedOpcode(OPCODE_CUSTOM_STORE)
    
    if storeWindow then
        storeWindow:destroy()
        storeWindow = nil
    end
end

function onGameEnd()
    if storeWindow then
        storeWindow:destroy()
        storeWindow = nil
    end
    authToken = nil
    playerId = nil
    categories = {}
    products = {}
end

function toggle()
    if not storeWindow then
        storeWindow = g_ui.createWidget('CustomStoreWindow', rootWidget)
        storeWindow:hide()
    end
    
    if storeWindow:isVisible() then
        storeWindow:hide()
    else
        storeWindow:show()
        storeWindow:raise()
        storeWindow:focus()
        
        -- Initialize Player ID and Load Data directly
        local player = g_game.getLocalPlayer()
        if player then
            playerId = player:getId()
            loadCatalog()
            -- loadBalance is called inside loadCatalog, but we can call it here too to be sure
        end
    end
end

function onExtendedOpcode(protocol, opcode, buffer)
    if opcode ~= OPCODE_CUSTOM_STORE then return end
    local status, data = pcall(json.decode, buffer)
    if not status then return end
    
    -- Optional: Update balance if server pushes notification
    if data.action == 'update_balance' then
        loadBalance()
    end
end

function loadCatalog()
    HTTP.get(BACKEND_URL .. "/store/catalog", function(data, err)
        if err then return displayError("Network Error", err) end
        
        local status, json_data = pcall(json.decode, data)
        if not status then return displayError("Parse Error", "Invalid JSON") end
        
        categories = json_data.categories
        products = json_data.products
        
        -- Filter Featured Products
        featuredProducts = {}
        for _, prod in ipairs(products) do
            if prod.is_featured == 1 or prod.is_featured == true then
                table.insert(featuredProducts, prod)
            end
        end
        
        -- Organize products by category for easier access
        for _, cat in ipairs(categories) do
            cat.products = {}
            for _, prod in ipairs(products) do
                if prod.category_id == cat.id then
                    table.insert(cat.products, prod)
                end
            end
        end
        
        buildUI()
        loadBalance()
    end)
end

function loadBalance()
    local player = g_game.getLocalPlayer()
    if not player then return end
    local pid = player:getId()
    
    HTTP.get(BACKEND_URL .. "/store/balance?player_id=" .. pid, function(data, err)
        if err then return end
        local status, json_data = pcall(json.decode, data)
        if status and json_data.coins then
            if storeWindow then
                local lbl = storeWindow:recursiveGetChildById('balanceLabel')
                if lbl then lbl:setText("Coins: " .. json_data.coins) end
            end
        end
    end)
end

function buildUI()
    if not storeWindow then return end
    
    local catList = storeWindow:recursiveGetChildById('categoriesList')
    catList:destroyChildren()
    
    -- 1. Setup Home Button
    local homeBtn = storeWindow:recursiveGetChildById('homeButton')
    homeBtn.onClick = function() showHome() end
    
    -- 2. Setup Categories
    for _, cat in ipairs(categories) do
        local btn = g_ui.createWidget('CategoryButton', catList)
        btn:getChildById('text'):setText(cat.name)
        
        if cat.icon and tonumber(cat.icon) then
            btn:getChildById('icon'):setItemId(tonumber(cat.icon))
        end
        
        btn.onClick = function() showCategory(cat) end
        btn.categoryId = cat.id
    end
    
    -- 3. Search Setup
    local searchInput = storeWindow:recursiveGetChildById('searchInput')
    if searchInput then
        searchInput.onTextChange = function(widget, text)
            filterProducts(text)
        end
    end
    
    -- 4. Default View
    showHome()
end

function updateCategorySelection(catId)
    if not storeWindow then return end
    
    -- Handle Home Button selection
    local homeBtn = storeWindow:recursiveGetChildById('homeButton')
    if catId == nil then -- Home
        homeBtn:setOn(true) -- Assuming setOn triggers checked style or use setChecked
        homeBtn:setChecked(true)
    else
        homeBtn:setOn(false)
        homeBtn:setChecked(false)
    end
    
    -- Handle other categories
    local catList = storeWindow:recursiveGetChildById('categoriesList')
    for _, child in ipairs(catList:getChildren()) do
        if child.categoryId == catId then
            child:setChecked(true)
            if child.setOn then child:setOn(true) end
        else
            child:setChecked(false)
            if child.setOn then child:setOn(false) end
        end
    end
end

function showHome()
    if not storeWindow then return end
    currentCategory = nil
    updateCategorySelection(nil)
    
    local homeView = storeWindow:recursiveGetChildById('homeView')
    local shopView = storeWindow:recursiveGetChildById('shopView')
    
    homeView:setVisible(true)
    shopView:setVisible(false)
    
    -- Populate Featured
    local featuredList = storeWindow:recursiveGetChildById('featuredList')
    featuredList:destroyChildren()
    
    for _, prod in ipairs(featuredProducts) do
        local widget = g_ui.createWidget('HomeOfferWidget', featuredList)
        setupHomeOfferWidget(widget, prod)
    end
end

function showCategory(cat)
    if not storeWindow then return end
    currentCategory = cat
    updateCategorySelection(cat.id)
    
    local homeView = storeWindow:recursiveGetChildById('homeView')
    local shopView = storeWindow:recursiveGetChildById('shopView')
    
    homeView:setVisible(false)
    shopView:setVisible(true)
    
    local productList = storeWindow:recursiveGetChildById('productList')
    productList:destroyChildren()
    
    for _, prod in ipairs(cat.products) do
        local widget = g_ui.createWidget('OfferButton', productList)
        setupOfferWidget(widget, prod)
    end
    
    clearDetails()
end

function filterProducts(text)
    if not storeWindow then return end
    
    -- If text is empty, restore current view
    if text == "" then
        if currentCategory then
            showCategory(currentCategory)
        else
            showHome()
        end
        return
    end
    
    -- Search in ALL products and show in Shop View
    local homeView = storeWindow:recursiveGetChildById('homeView')
    local shopView = storeWindow:recursiveGetChildById('shopView')
    local productList = storeWindow:recursiveGetChildById('productList')
    
    homeView:setVisible(false)
    shopView:setVisible(true)
    productList:destroyChildren()
    
    text = text:lower()
    
    for _, cat in ipairs(categories) do
        for _, prod in ipairs(cat.products) do
            if prod.name:lower():find(text) then
                local widget = g_ui.createWidget('OfferButton', productList)
                setupOfferWidget(widget, prod)
            end
        end
    end
    
    clearDetails()
end

function setupOfferWidget(widget, prod)
    local item = widget:getChildById('item')
    local name = widget:getChildById('name')
    local price = widget:getChildById('price')
    
    item:setItemId(prod.image_id)
    name:setText(prod.name)
    price:setText(prod.price .. " coins")
    
    widget.onClick = function() selectProduct(prod) end
end

function setupHomeOfferWidget(widget, prod)
    local item = widget:getChildById('item')
    local name = widget:getChildById('name')
    local price = widget:getChildById('price')
    
    item:setItemId(prod.image_id)
    name:setText(prod.name)
    price:setText(prod.price) -- Coin icon is separate
    
    -- On Home, clicking might open details in a modal or switch to category view
    -- For now, let's switch to category view and select it, or just buy directly?
    -- User said "ao clicar... mostrará os detalhes".
    -- Let's just find the category and switch to it? Or just show a modal?
    -- Easiest: Select it in the background and show details panel? No, details panel is in ShopView.
    -- Let's switch to ShopView -> Category -> Select Product
    widget.onClick = function() 
        -- Find category
        local cat = nil
        for _, c in ipairs(categories) do
            if c.id == prod.category_id then
                cat = c
                break
            end
        end
        
        if cat then
            showCategory(cat)
            selectProduct(prod)
        end
    end
end

function openBuyCoins()
    g_platform.openUrl("http://localhost:5000/buy-coins") -- Replace with real URL
end

function showHistory()
    if not authToken then return end
    
    HTTP.addCustomHeader("Authorization", authToken)
    HTTP.get(BACKEND_URL .. "/store/history", function(data, err)
        if err then return displayError("Error", err) end
        
        local status, json_data = pcall(json.decode, data)
        if not status then return displayError("Error", "Invalid JSON") end
        
        local msg = "Purchase History:\n\n"
        for _, entry in ipairs(json_data.history or {}) do
            msg = msg .. entry.timestamp .. " - " .. entry.product_name .. " (" .. entry.price .. " coins)\n"
        end
        
        if #json_data.history == 0 then
            msg = msg .. "No purchases yet."
        end
        
        displayInfo("History", msg)
    end)
end

function selectProduct(prod)
    if not storeWindow then return end
    selectedProduct = prod
    
    local detailsPanel = storeWindow:recursiveGetChildById('detailsPanel')
    local detailItem = detailsPanel:getChildById('detailItem')
    local detailName = detailsPanel:getChildById('detailName')
    local detailPrice = detailsPanel:getChildById('detailPrice')
    local detailDescription = detailsPanel:getChildById('detailDescription')
    local buyButton = detailsPanel:getChildById('buyButton')
    
    detailItem:setItemId(prod.image_id)
    detailName:setText(prod.name)
    detailPrice:setText(prod.price .. " coins")
    detailDescription:setText(prod.description)
    
    buyButton:setEnabled(true)
    buyButton.onClick = function() buySelected(prod) end
end

function clearDetails()
    if not storeWindow then return end
    selectedProduct = nil
    
    local detailsPanel = storeWindow:recursiveGetChildById('detailsPanel')
    local detailItem = detailsPanel:getChildById('detailItem')
    local detailName = detailsPanel:getChildById('detailName')
    local detailPrice = detailsPanel:getChildById('detailPrice')
    local detailDescription = detailsPanel:getChildById('detailDescription')
    local buyButton = detailsPanel:getChildById('buyButton')
    
    detailItem:setItemId(0)
    detailName:setText("")
    detailPrice:setText("")
    detailDescription:setText("")
    buyButton:setEnabled(false)
end

function buySelected(prod)
    if not prod then return end
    
    -- Optimistic UI update or lock button
    local buyButton = storeWindow:recursiveGetChildById('buyButton')
    buyButton:setEnabled(false)
    buyButton:setText("Buying...")
    
    local payload = {
        player_id = playerId,
        product_id = prod.id
    }
    
    HTTP.addCustomHeader("Content-Type", "application/json")
    HTTP.postJSON(BACKEND_URL .. "/store/buy", json.encode(payload), function(data, err)
        if storeWindow then
            local btn = storeWindow:recursiveGetChildById('buyButton')
            if btn then
                btn:setText(tr('Buy'))
                btn:setEnabled(true)
            end
        end
        
        if err then return displayError("Error", err) end
        
        local status, json_data = pcall(json.decode, data)
        if not status then return displayError("Error", "Invalid response") end
        
        if json_data.error then
            displayError("Purchase Failed", json_data.error)
        else
            displayInfo("Success", json_data.message)
            loadBalance() -- Update balance
        end
    end)
end