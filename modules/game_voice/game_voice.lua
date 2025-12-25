local voiceWindow = nil
local statusLabel = nil
local volumeBar = nil
local volumeBg = nil
local loopbackBox = nil
local isRecording = false
local sendEvent = nil

function init()
  -- Bind keys
  g_keyboard.bindKeyDown('V', startRecording)
  g_keyboard.bindKeyUp('V', stopRecording)
  
  -- Load UI
  voiceWindow = g_ui.loadUI('game_voice', modules.game_interface.getRightPanel())
  voiceWindow:setup()
  
  statusLabel = voiceWindow:recursiveGetChildById('statusLabel')
  volumeBg = voiceWindow:recursiveGetChildById('volumeBg')
  volumeBar = voiceWindow:recursiveGetChildById('volumeBar')
  loopbackBox = voiceWindow:recursiveGetChildById('loopbackBox')
  
  -- Initialize capture device
  if g_sounds and g_sounds.initCapture then
      g_sounds.initCapture()
  end
  
  connect(g_game, {
    onGameEnd = stopRecording
  })
end

function terminate()
  g_keyboard.unbindKeyDown('V')
  g_keyboard.unbindKeyUp('V')
  stopRecording()
  
  disconnect(g_game, {
    onGameEnd = stopRecording
  })
  
  if voiceWindow then
    voiceWindow:destroy()
    voiceWindow = nil
  end
end

function startRecording()
  g_logger.info("Voice: startRecording triggered")
  if not g_game.isOnline() then 
    g_logger.warning("Voice: Cannot record, game not online")
    return 
  end
  if isRecording then return end
  
  isRecording = true
  
  statusLabel:setText('Transmitting...')
  statusLabel:setColor('#ff0000')
  
  if g_sounds and g_sounds.startCapture then
      g_logger.info("Voice: Calling g_sounds.startCapture()")
      g_sounds.startCapture()
  else
      g_logger.error("Voice: g_sounds.startCapture not available")
  end
  
  sendVoiceLoop()
end

function stopRecording()
  if not isRecording then return end
  
  isRecording = false
  
  statusLabel:setText('Connected')
  statusLabel:setColor('#00ff00')
  if volumeBar then
      volumeBar:setHeight(0)
  end
  
  if g_sounds and g_sounds.stopCapture then
      g_sounds.stopCapture()
  end
  
  if sendEvent then
      sendEvent:cancel()
      sendEvent = nil
  end
end

function getAudioLevel(data)
    if not data or #data == 0 then return 0 end
    
    local maxVal = 0
    -- Sample every 2 bytes (16-bit mono)
    -- Optimization: Sample every 20th sample to save CPU
    local step = 40 -- 20 samples * 2 bytes
    
    for i = 1, #data - 1, step do
        local low = string.byte(data, i)
        local high = string.byte(data, i+1)
        local val = low + high * 256
        if val > 32767 then val = val - 65536 end
        
        local absVal = math.abs(val)
        if absVal > maxVal then maxVal = absVal end
    end
    
    -- Normalize to 0-100 (assuming 16-bit max is 32768)
    -- Use a non-linear scale for better visual feedback
    local percent = (maxVal / 32768) * 100
    return math.min(100, math.max(0, percent * 3)) -- Boost the visual a bit
end

function sendVoiceLoop()
  if not isRecording then return end
  
  if g_sounds and g_sounds.getCapturedData and g_game.sendVoiceAudio then
      local data = g_sounds.getCapturedData()
      if data and #data > 0 then
          -- Update visualizer
          if volumeBar and volumeBg then
            local level = getAudioLevel(data)
            local maxHeight = volumeBg:getHeight()
            local height = math.floor((level / 100) * maxHeight)
            volumeBar:setHeight(height)
          end
          
          -- Loopback check
          if loopbackBox and loopbackBox:isChecked() then
             if g_sounds.playVoice then
                 g_sounds.playVoice(data)
             end
          end
          
          -- Send data
          g_logger.info("Voice: Sending " .. #data .. " bytes")
          g_game.sendVoiceAudio(data)
      else
          if volumeBar then volumeBar:setHeight(0) end
      end
  end
  
  sendEvent = scheduleEvent(sendVoiceLoop, 100)
end
