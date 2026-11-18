local ADDON = 'WritHelper'
local VERSION = '0.19.2'
local L = WritHelperTranslate
local data = WritHelperData or {}
local frame, output, status, progressFrame, auctionButton, windowBar, windowPercent, scanInfoButton, resultsScroll, stopButton
local state = {phase='idle', message=L('Откройте аукцион и нажмите «Сканировать».'), current=0, total=0}
local events
local startStandard
local sourceLabel
local showShoppingList
local function closeOnEscape(name)
  if type(UISpecialFrames)~='table' then return end
  for _,existing in ipairs(UISpecialFrames) do if existing==name then return end end
  table.insert(UISpecialFrames,name)
end
local function logEvent(message)
  if not WritHelperDB then return end
  WritHelperDB.log=WritHelperDB.log or {}
  local stamp=date and date('%H:%M:%S') or '--:--:--'
  WritHelperDB.log[#WritHelperDB.log+1]=stamp..' '..tostring(message):sub(1,512)
  while #WritHelperDB.log>1500 do table.remove(WritHelperDB.log,1) end
end
local function msg(s) print('|cff53d6ffWritHelper:|r '..s) end
local function idFromLink(link) return link and tonumber(link:match('item:(%d+)')) end
local function itemName(id)
  local get = C_Item and C_Item.GetItemInfo or GetItemInfo
  if not get then return nil end
  local name = get(id)
  if not name and C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
  return name
end
local function itemCount(id)
  local get = C_Item and C_Item.GetItemCount or GetItemCount
  return get and (get(id, false) or 0) or 0
end
local bankOpen=false
local function cachedBankCount(id)
  local bank=WritHelperDB and WritHelperDB.bank
  if not bank or not bank.counts then return nil end
  return bank.counts[id]
end
local function ownedCount(id)
  return itemCount(id)+(cachedBankCount(id) or 0)
end
local function captureBank()
  if not bankOpen or not WritHelperDB then return end
  local get=C_Item and C_Item.GetItemCount or GetItemCount
  if not get then return end
  local counts,ids={},{}
  for _,entry in ipairs(data) do ids[entry.writ]=true; ids[entry.item]=true end
  for _,recipe in pairs(WritHelperDB.recipes or {}) do
    for _,reagent in ipairs(recipe.reagents or {}) do ids[reagent.id]=true end
  end
  for id in pairs(ids) do
    local ok,total=pcall(get,id,true,false,false)
    local okBags,bags=pcall(get,id,false,false,false)
    if ok and okBags and type(total)=='number' and type(bags)=='number' then counts[id]=math.max(0,total-bags) end
  end
  WritHelperDB.bank={counts=counts,time=time()}
  logEvent(L('Банк обновлён для заказов, вещей и материалов известных рецептов'))
end
local function money(n,iconSize)
  if not n then return '?' end
  n=math.floor(n+0.5)
  local gold=math.floor(n/10000)
  local silver=math.floor(n/100)%100
  local copper=n%100
  local parts={}
  local size=tostring(iconSize or 16)
  if gold>0 then parts[#parts+1]=gold..' |TInterface\\MoneyFrame\\UI-GoldIcon:'..size..':'..size..':2:0|t' end
  if silver>0 then parts[#parts+1]=silver..' |TInterface\\MoneyFrame\\UI-SilverIcon:'..size..':'..size..':2:0|t' end
  if copper>0 or #parts==0 then parts[#parts+1]=copper..' |TInterface\\MoneyFrame\\UI-CopperIcon:'..size..':'..size..':2:0|t' end
  return table.concat(parts,'  ')
end
local function updateProgress(text, isError)
  state.message=text; state.error=isError
  if stopButton then if state.phase~='idle' then stopButton:Show() else stopButton:Hide() end end
  if status then status:SetText(text) end
  local total=math.max(state.total or 0,1)
  local current=math.min(state.current or 0,total)
  if windowBar then
    windowBar:SetMinMaxValues(0,total); windowBar:SetValue(current)
    if isError then windowBar:SetStatusBarColor(0.8,0.18,0.15) else windowBar:SetStatusBarColor(0.2,0.65,0.28) end
    if state.phase=='waiting' then windowPercent:SetText(L('Ожидание ответа'))
    elseif (state.total or 0)>0 then windowPercent:SetText(math.floor(current*100/total)..'%')
    else windowPercent:SetText('—') end
  end
  if scanInfoButton and scanInfoButton.label then
    local snapshot=WritHelperDB and WritHelperDB.snapshot
    local stamp=snapshot and snapshot.time and date and date('%d.%m %H:%M',snapshot.time) or '-'
    local icon
    if state.phase~='idle' then
      icon='|TInterface\\RaidFrame\\ReadyCheck-Waiting:16:16|t'
      if state.phase=='waiting' then icon=icon..L(' ожидание ')..tostring(state.waitPercent or 0)..'%'
      elseif (state.total or 0)>0 then icon=icon..' '..math.floor(current*100/total)..'%' end
    elseif state.error or not snapshot then icon='|TInterface\\RaidFrame\\ReadyCheck-NotReady:16:16|t'
    else icon='|TInterface\\RaidFrame\\ReadyCheck-Ready:16:16|t' end
    scanInfoButton.label:SetText(icon..'  '..stamp..(snapshot and (L('  - заказов: ')..tostring(state.foundCount or 0)) or ''))
  end
  if auctionButton and auctionButton.scanBadge then
    if auctionButton.icon then
      if state.phase~='idle' then auctionButton.icon:SetVertexColor(1,0.8,0.22)
      elseif state.error then auctionButton.icon:SetVertexColor(1,0.4,0.4)
      else auctionButton.icon:SetVertexColor(1,1,1) end
    end
    if state.error then auctionButton.scanBadge:SetText('|TInterface\\RaidFrame\\ReadyCheck-NotReady:16:16|t')
    elseif state.phase=='idle' and WritHelperDB and WritHelperDB.snapshot then auctionButton.scanBadge:SetText('|TInterface\\RaidFrame\\ReadyCheck-Ready:16:16|t')
    elseif state.phase=='idle' then auctionButton.scanBadge:SetText('|TInterface\\RaidFrame\\ReadyCheck-NotReady:16:16|t -')
    elseif state.phase=='waiting' then auctionButton.scanBadge:SetText('|cffffd54a'..tostring(state.waitPercent or 0)..'%|r')
    elseif (state.total or 0)>0 then auctionButton.scanBadge:SetText('|cffffd54a'..math.floor(current*100/total)..'%|r')
    else auctionButton.scanBadge:SetText('|cffffd54a...|r') end
  end
  if progressFrame then
    progressFrame.text:SetText(text)
    progressFrame.bar:SetMinMaxValues(0, math.max(state.total or 0, 1))
    progressFrame.bar:SetValue(math.min(state.current or 0, math.max(state.total or 0, 1)))
    if isError then progressFrame.bar:SetStatusBarColor(0.8,0.18,0.15) else progressFrame.bar:SetStatusBarColor(0.2,0.65,0.28) end
  end
end
local function fail(text)
  logEvent(L('Ошибка/остановка: ')..text)
  state.phase='idle'; state.token=(state.token or 0)+1
  updateProgress(text, true); msg(text)
end
local function stopScan()
  if state.phase=='idle' then return end
  state.phase='idle'; state.token=(state.token or 0)+1
  state.pending=nil; state.requests=nil; state.current=0; state.total=0
  local message=L('Сканирование остановлено. Предыдущие результаты сохранены.')
  logEvent(message); updateProgress(message,false); msg(message)
end
local function saveRecipe(product,recipe)
  local old=WritHelperDB.recipes[product]
  local same=old and old.profession==recipe.profession and old.makes==recipe.makes and type(old.reagents)=='table' and #old.reagents==#recipe.reagents
  if same then
    for i,reagent in ipairs(recipe.reagents) do
      local previous=old.reagents[i]
      if not previous or previous.id~=reagent.id or previous.count~=reagent.count then same=false; break end
    end
  end
  if same then return false end
  WritHelperDB.recipes[product]=recipe
  return true
end
local function captureModernTradeskill()
  local api=C_TradeSkillUI
  if not api or not api.GetAllRecipeIDs or not api.GetRecipeInfo or not api.GetRecipeSchematic then return false end
  local ids=api.GetAllRecipeIDs()
  if type(ids)~='table' or #ids==0 then return false end
  local relevant={}
  for _,entry in ipairs(data) do relevant[entry.item]=true end
  local changed, unsupported=0,0
  for _,recipeID in ipairs(ids) do
    local info=api.GetRecipeInfo(recipeID)
    if info and info.learned then
      local ok,schematic=pcall(api.GetRecipeSchematic,recipeID,false)
      if ok and type(schematic)=='table' and schematic.outputItemID and relevant[schematic.outputItemID] then
        local ingredients,valid={},true
        for _,slot in ipairs(schematic.reagentSlotSchematics or {}) do
          local isRequired=slot.required
          if isRequired==nil and Enum and Enum.CraftingReagentType then isRequired=slot.reagentType==Enum.CraftingReagentType.Basic end
          if isRequired==nil then isRequired=true end
          if isRequired then
            local choices=slot.reagents or {}
            local reagent=#choices==1 and choices[1] or nil
            local count=tonumber(slot.quantityRequired)
            if not reagent or not reagent.itemID or not count or count<=0 then valid=false
            else ingredients[#ingredients+1]={id=reagent.itemID,count=count} end
          end
        end
        if valid and #ingredients>0 then
          local profession=L('Профессия')
          if api.GetTradeSkillLineForRecipe then
            local success,_,name=pcall(api.GetTradeSkillLineForRecipe,recipeID)
            if success and type(name)=='string' and name~='' then profession=name end
          end
          if saveRecipe(schematic.outputItemID,{profession=profession,reagents=ingredients,makes=math.max(tonumber(schematic.quantityMin) or 1,1)}) then changed=changed+1 end
        else
          unsupported=unsupported+1
        end
      end
    end
  end
  if changed>0 then
    local report=L('Профессия: добавлено или обновлено рецептов ')..changed..L('; требуется проверка ')..unsupported
    logEvent(report); msg(report..L('. Для цен материалов обновите сканирование аукциона.'))
  end
  return true
end
local function captureTradeskill()
  if captureModernTradeskill() then return end
  if not GetNumTradeSkills or not GetTradeSkillItemLink or not GetTradeSkillNumReagents or not GetTradeSkillReagentItemLink or not GetTradeSkillReagentInfo then return end
  local profession=GetTradeSkillLine and GetTradeSkillLine()
  if not profession or profession=='UNKNOWN' then return end
  local num=GetNumTradeSkills()
  if not num or num==0 then return end
  local changed=0
  for i=1,num do
    local product=idFromLink(GetTradeSkillItemLink(i))
    if product then
      local ingredients, valid={},true
      for j=1,GetTradeSkillNumReagents(i) do
        local id=idFromLink(GetTradeSkillReagentItemLink(i,j))
        local _,_,count=GetTradeSkillReagentInfo(i,j)
        if not id or not count then valid=false else ingredients[#ingredients+1]={id=id,count=count} end
      end
      local makes=GetTradeSkillNumMade and GetTradeSkillNumMade(i) or 1
      if valid and #ingredients>0 then
        if saveRecipe(product,{profession=profession,reagents=ingredients,makes=math.max(tonumber(makes) or 1,1)}) then changed=changed+1 end
      end
    end
  end
  if changed>0 then msg(L('Рецепты: ')..profession..L(', добавлено или обновлено ')..changed..'.') end
end
-- Last recorded prices cannot establish current stock or exact stack costs.
local function auctionatorPrice(id)
  local api=Auctionator and Auctionator.API and Auctionator.API.v1
  if not api or not api.GetAuctionPriceByItemID then return nil end
  local ok,price=pcall(api.GetAuctionPriceByItemID,ADDON,id)
  if ok and type(price)=='number' and price>0 then return price end
end
local function externalPrice(id)
  local price=auctionatorPrice(id)
  if price then return price,'auctionator' end
  if TSM_API and type(TSM_API.GetCustomPriceValue)=='function' then
    for _,source in ipairs({'DBMinBuyout','DBMarket'}) do
      local ok,value=pcall(TSM_API.GetCustomPriceValue,source,'i:'..id)
      if ok and type(value)=='number' and value>0 then return value,source=='DBMarket' and 'tsm_market' or 'tsm' end
    end
  end
  local api=AucAdvanced and AucAdvanced.API
  if api and type(api.GetMarketValue)=='function' then
    local ok,value=pcall(api.GetMarketValue,id)
    if ok and type(value)=='number' and value>0 then return value,'auctioneer' end
  end
end
local sourceNames={auctionator='Auctionator',tsm='TSM',tsm_market=L('TSM (рыночная)'),auctioneer=L('Auctioneer (рыночная)')}
local function sourceText(used)
  if used and used.auctionator and not used.tsm and not used.tsm_market and not used.auctioneer then return L('Auctionator: цены использованы в текущем списке.') end
  local names={}
  for _,key in ipairs({'auctionator','tsm','tsm_market','auctioneer'}) do if used and used[key] then names[#names+1]=sourceNames[key] end end
  return #names>0 and (L('Использованы цены: ')..table.concat(names,', ')..'.') or L('Внешние цены в текущем списке не использованы.')
end
local function buyCost(snapshot,id,required)
  if required<=0 then return 0,false end
  local lots=snapshot and snapshot.lots and snapshot.lots[id]
  if lots then
    if snapshot.approximate then
      if lots[2] >= required then return lots[1]*required,true end
    else
      local dp={[0]=0}
      for _,lot in ipairs(lots) do
        local quantity,price=lot[1],lot[2]
        for n=required-1,0,-1 do
          local previous=dp[n]
          if previous then
            local target=math.min(required,n+quantity)
            local cost=previous+price
            if not dp[target] or cost<dp[target] then dp[target]=cost end
          end
        end
      end
      if dp[required] then return dp[required],false end
    end
    -- A current scan says too few were present; old prices do not prove stock.
    return nil,false
  end
  local quote=snapshot and snapshot.quotes and snapshot.quotes[id]
  if quote then
    if quote[2]>=required then return quote[1]*required,true end
    return nil,false
  end
  -- A current search or complete full snapshot without this item means it was absent then.
  if snapshot and snapshot.scanned and snapshot.scanned[id] then return nil,false end
  if snapshot and snapshot.quotes and (snapshot.unknown or 0)==0 then return nil,false end
  local price,source=externalPrice(id)
  if price then return price*required,true,source end
  return nil,false
end
local function availableCount(snapshot,id)
  if not snapshot or not snapshot.lots then return nil end
  local lots=snapshot.lots[id]
  if not lots then
    local quote=snapshot.quotes and snapshot.quotes[id]
    if quote then return tonumber(quote[2]) end
    if snapshot.scanned and snapshot.scanned[id] then return 0 end
    if not snapshot.quotes or (snapshot.unknown or 0)>0 then return nil end
    return 0
  end
  if snapshot.approximate then return tonumber(lots[2]) end
  local total=0
  for _,lot in ipairs(lots) do total=total+(tonumber(lot[1]) or 0) end
  return total
end
local function availability(snapshot,id)
  local count=availableCount(snapshot,id)
  return count and (count..L(' в продаже')) or L('наличие неизвестно')
end
local function craftInfo(snapshot,id,quantity)
  local recipe=WritHelperDB.recipes[id]
  if not recipe then return nil,L('неизвестно: откройте профессию'),false,nil end
  local crafts=math.ceil(quantity/(recipe.makes or 1))
  local total,valid,materials,estimated,usedSources=0,true,{},false,{}
  for _,reagent in ipairs(recipe.reagents) do
    local need=reagent.count*crafts
    local bags=itemCount(reagent.id)
    local bank=cachedBankCount(reagent.id)
    local missing=math.max(0,need-bags-(bank or 0))
    local price,isEstimate,source=buyCost(snapshot,reagent.id,missing)
    if not price then valid=false else total=total+price end
    if isEstimate then estimated=true end
    if source then usedSources[source]=true end
    materials[#materials+1]={id=reagent.id,need=need,bags=bags,bank=bank,missing=missing}
  end
  local bank=WritHelperDB.bank
  local bankNote=bank and bank.time and date and (L('; банк: ')..date('%d.%m %H:%M',bank.time)) or L('; банк: не проверен')
  local summary=recipe.profession..(valid and (L('; докупить ')..money(total)..(estimated and L(' (оценка)') or '')) or L('; цена или наличие материалов неизвестны'))..bankNote
  return valid and total or nil,summary,estimated,materials,valid and usedSources or nil
end
local cards, resultHeader = {}, nil
local function iconTexture(id)
  if C_Item and C_Item.GetItemIconByID then
    local icon=C_Item.GetItemIconByID(id)
    if icon then return icon end
  end
  if C_Item and C_Item.GetItemInfoInstant then
    local _,_,_,_,icon=C_Item.GetItemInfoInstant(id)
    if icon then return icon end
  end
  return 134400
end
local function textAt(parent,font,x,y,width)
  local text=parent:CreateFontString(nil,'OVERLAY',font)
  text:SetPoint('TOPLEFT',x,y); text:SetWidth(width); text:SetJustifyH('LEFT'); text:SetJustifyV('TOP')
  return text
end
local function shoppingVisible()
  return AuctionatorShoppingFrame and AuctionatorShoppingFrame.IsVisible and AuctionatorShoppingFrame:IsVisible()
end
local function putSearch(id, startSearch)
  if state.phase~='idle' then msg(L('Дождитесь завершения сканирования перед поиском.')) return end
  local name=itemName(id)
  if not name then msg(L('Название предмета ещё загружается, попробуйте снова.')) return end
  local options=shoppingVisible() and AuctionatorShoppingFrame.SearchOptions
  if options and options.SearchString and options.SearchString.SetText then
    options.SearchString:SetText(name)
    if startSearch then
      if not options.SearchButton or not options.SearchButton.Click then msg(L('Не удалось запустить поиск Auctionator.')) return end
      options.SearchButton:Click()
    elseif options.SearchString.SetFocus then options.SearchString:SetFocus() end
  else
    local ah=AuctionHouseFrame
    local bar=ah and ah.SearchBar
    local box=bar and bar.SearchBox
    if box and box.SetText then
      box:SetText(name)
      if startSearch then
        if not bar.StartSearch then msg(L('Не удалось запустить поиск аукциона.')) return end
        bar:StartSearch()
      elseif box.SetFocus then box:SetFocus() end
    elseif ah and ah.SetSearchText then
      ah:SetSearchText(name)
      if startSearch then msg(L('Название добавлено. Нажмите «Поиск» в аукционе.')) return end
    elseif _G.BrowseName and _G.BrowseName.SetText then
      _G.BrowseName:SetText(name)
      if startSearch and _G.BrowseSearchButton and _G.BrowseSearchButton.Click then _G.BrowseSearchButton:Click()
      elseif startSearch then msg(L('Название добавлено. Нажмите «Поиск» в аукционе.')) return end
    else
      msg(L('Не удалось найти строку поиска аукциона. Откройте аукцион и попробуйте снова.')) return
    end
  end
  msg((startSearch and L('Поиск: ') or L('В строку поиска добавлено: '))..name)
end
local function iconAt(parent,x)
  local button=CreateFrame('Button',nil,parent)
  button:SetSize(36,36); button:SetPoint('TOPLEFT',x,-13)
  local texture=button:CreateTexture(nil,'ARTWORK'); texture:SetAllPoints(); button.texture=texture
  button:SetScript('OnEnter',function(self)
    if self.itemID and GameTooltip then GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetItemByID(self.itemID); GameTooltip:Show() end
  end)
  button:SetScript('OnLeave',function() if GameTooltip then GameTooltip:Hide() end end)
  button:SetScript('OnClick',function(self) if IsShiftKeyDown and IsShiftKeyDown() then putSearch(self.itemID) end end)
  return button
end
local function writQuestID(writ)
  if writ<264011 or writ>264160 then return nil end
  return writ==264011 and 94004 or writ-169800
end
-- Wowhead guide and player reports, 2026-11-15: the coordinates are approximate.
local reportedTurnins={
  [264117]={1419,0.52,0.35,'npc:7363',"Kum'isha"}, [264153]={1419,0.52,0.35,'npc:7363',"Kum'isha"},
  [264146]={1430,0.47,0.75,'npc:257743','Hastings'}, [264155]={1430,0.47,0.75,'npc:257743','Hastings'},
}
local function turninLocation(writ)
  local questID=writQuestID(writ)
  if not questID then return nil end
  local mapID,x,y,key,name,community
  local db=LibQuestieDB
  if db and db.Quest and db.Npc and QuestieLoader and QuestieLoader.ImportModule then
    local ok,zoneDB=pcall(QuestieLoader.ImportModule,QuestieLoader,'ZoneDB')
    if ok and zoneDB and type(zoneDB.GetUiMapIdByAreaId)=='function' then
      local success,finishers=pcall(db.Quest.Get,questID,'finishedBy')
      local targets=success and type(finishers)=='table' and {{db.Npc,finishers[1],'npc:'},{db.Object,finishers[2],'object:'}} or {}
      for _,target in ipairs(targets) do
        local entity,ids=target[1],target[2]
        if entity and type(entity.Get)=='function' and type(ids)=='table' then
        for _,entityID in ipairs(ids) do
          local good,spawns=pcall(entity.Get,entityID,'spawns')
          if good and type(spawns)=='table' then
            local areas={}; for area in pairs(spawns) do if type(area)=='number' then areas[#areas+1]=area end end; table.sort(areas)
            for _,area in ipairs(areas) do
              local points=spawns[area]; local point=type(points)=='table' and points[1]
              local valid,id=pcall(zoneDB.GetUiMapIdByAreaId,zoneDB,area)
              if valid and type(id)=='number' and id>0 and type(point)=='table' and type(point[1])=='number' and type(point[2])=='number' and point[1]>=0 and point[1]<=100 and point[2]>=0 and point[2]<=100 then
                mapID,x,y,key=id,point[1]/100,point[2]/100,target[3]..entityID
                local named,npcName=pcall(entity.Get,entityID,'name')
                name=named and type(npcName)=='string' and npcName~='' and npcName or nil
                break
              end
            end
          end
          if mapID then break end
        end
        end
        if mapID then break end
      end
    end
  end
  if not mapID and reportedTurnins[writ] then local point=reportedTurnins[writ]; mapID,x,y,key,name,community=point[1],point[2],point[3],point[4],point[5],true end
  if not mapID then return nil end
  local zone
  if C_Map and C_Map.GetMapInfo then local ok,info=pcall(C_Map.GetMapInfo,mapID); if ok and type(info)=='table' then zone=info.name end end
  return {mapID=mapID,x=x,y=y,key=key,name=name,zone=zone,community=community}
end
local function showTurninMap(writ)
  if InCombatLockdown and InCombatLockdown() then msg(L('Карта недоступна во время боя.')); return end
  local questID=writQuestID(writ)
  if not questID then msg(L('Место сдачи неизвестно. Примите задание и проверьте игровую карту или обновите Questie.')); return end
  local location=turninLocation(writ)
  local mapID,x,y,route,community
  if location then mapID,x,y,community=location.mapID,location.x,location.y,location.community end
  if not mapID and C_QuestLog and C_QuestLog.GetNextWaypoint then
    local ok,id,px,py=pcall(C_QuestLog.GetNextWaypoint,questID)
    if ok and type(id)=='number' and id>0 and type(px)=='number' and type(py)=='number' and px>=0 and px<=1 and py>=0 and py<=1 then mapID,x,y,route=id,px,py,true end
  end
  if not mapID then msg(L('Место сдачи неизвестно. Примите задание и проверьте игровую карту или обновите Questie.')); return end
  if not C_Map or not C_Map.SetUserWaypoint or not UiMapPoint or not UiMapPoint.CreateFromCoordinates then msg(L('Не удалось открыть карту или поставить метку.')); return end
  local ok=pcall(function()
    if C_Map.CanSetUserWaypointOnMap and not C_Map.CanSetUserWaypointOnMap(mapID) then error('waypoint unavailable') end
    local point=UiMapPoint.CreateFromCoordinates(mapID,x,y)
    C_Map.SetUserWaypoint(point)
    if C_Map.OpenWorldMap then C_Map.OpenWorldMap(mapID)
    elseif WorldMapFrame then WorldMapFrame:Show(); WorldMapFrame:SetMapID(mapID)
    else error('map unavailable') end
  end)
  if not ok then msg(L('Не удалось открыть карту или поставить метку.')); return end
  if route then msg(L('Открыта следующая точка маршрута из игры; она может быть переходом, а не местом сдачи.')) end
  if community then msg(L('Метка приблизительная: координаты сообщены игроками Wowhead.')) end
end
local function locationOptions()
  local options={{key='all',name=L('Все локации')},{key='unknown',name=L('Локация неизвестна')}}
  local found={}
  for _,entry in ipairs(data) do
    local loc=turninLocation(entry.writ)
    if loc and loc.mapID then
      local key='map:'..loc.mapID
      if not found[key] then
        local place=loc.zone and loc.zone~='' and loc.zone or (L('Локация #')..loc.mapID)
        found[key]={key=key,name=place}
      end
    end
  end
  local sorted={}; for _,option in pairs(found) do sorted[#sorted+1]=option end
  table.sort(sorted,function(a,b) return a.name<b.name end)
  for _,option in ipairs(sorted) do options[#options+1]=option end
  return options
end
local function getCard(index)
  if cards[index] then return cards[index] end
  local card=CreateFrame('Frame',nil,output)
  card:SetSize(716,128)
  local bg=card:CreateTexture(nil,'BACKGROUND'); bg:SetAllPoints(); bg:SetColorTexture(0.12,0.12,0.13,0.9)
  local accent=card:CreateTexture(nil,'ARTWORK'); accent:SetPoint('TOPLEFT'); accent:SetSize(3,128); accent:SetColorTexture(0.75,0.55,0.24,1); card.accent=accent
  card.writIcon=iconAt(card,12); card.itemIcon=iconAt(card,357)
  card.writName=textAt(card,'GameFontHighlight',57,-12,288)
  card.itemName=textAt(card,'GameFontHighlight',402,-12,295)
  card.writPrice=textAt(card,'GameFontNormalSmall',57,-35,288)
  card.itemPrice=textAt(card,'GameFontNormalSmall',402,-35,295)
  card.levelWarning=textAt(card,'GameFontHighlightSmall',402,-56,295)
  card.choice=textAt(card,'GameFontNormalSmall',57,-56,335)
  card.completed=textAt(card,'GameFontHighlightSmall',14,-76,685)
  card.total=card:CreateFontString(nil,'OVERLAY','GameFontNormalLarge'); card.total:SetPoint('BOTTOMLEFT',14,12); card.total:SetWidth(190); card.total:SetJustifyH('LEFT')
  card.repPrice=card:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); card.repPrice:SetPoint('BOTTOMLEFT',220,13); card.repPrice:SetWidth(205); card.repPrice:SetJustifyH('LEFT'); card.repPrice:SetTextColor(0.65,0.65,0.65)
  card.materialLines={}
  local function nameClick(x,field)
    local b=CreateFrame('Button',nil,card); b:SetSize(285,25); b:SetPoint('TOPLEFT',x,-10)
    b:SetScript('OnClick',function() if IsShiftKeyDown and IsShiftKeyDown() then putSearch(card[field]) end end)
  end
  nameClick(57,'writID'); nameClick(402,'itemID')
  card.shop=CreateFrame('Button',nil,card,'UIPanelButtonTemplate'); card.shop:SetSize(152,24); card.shop:SetPoint('BOTTOMRIGHT',-8,7); card.shop:SetText(L('Список покупок'))
  card.shop:SetScript('OnClick',function() if card.entry then showShoppingList(card.entry) end end)
  card.map=CreateFrame('Button',nil,card,'UIPanelButtonTemplate'); card.map:SetSize(110,24); card.map:SetPoint('BOTTOMRIGHT',-165,7); card.map:SetText(L('На карте'))
  card.map:SetScript('OnClick',function() if card.entry then showTurninMap(card.entry.writ) end end)
  cards[index]=card
  return card
end
local function completedToday(writ)
  local questID=writQuestID(writ)
  if not questID then return false end
  local check=C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
  if type(check)~='function' then return false end
  local ok,completed=pcall(check,questID)
  return ok and completed==true
end
local function refresh()
  if not output then return end
  local snapshot=WritHelperDB.snapshot
  state.usedSources={}
  for _,card in ipairs(cards) do card:Hide() end
  local lines, rows={},{}
  if not snapshot then
    lines[#lines+1]=L('Своего сканирования нет. Цены других аддонов — оценка, наличие неизвестно.')
    lines[#lines+1]=L('Откройте свои профессии заранее, чтобы записать рецепты.')
  end
  do
    for _,e in ipairs(data) do
      local writCost,writEstimated,writSource=buyCost(snapshot,e.writ,1)
      local profs=WritHelperProfessions and WritHelperProfessions[e.writ]
      local profMatches=not WritHelperDB.profFilter or WritHelperDB.profFilter=='all' or (profs and profs[WritHelperDB.profFilter])
      local selectedLocation=WritHelperDB.locationFilter or 'all'
      local location=selectedLocation~='all' and turninLocation(e.writ) or nil
      local locationMatches=selectedLocation=='all' or (selectedLocation=='unknown' and not location) or (location and ('map:'..location.mapID)==selectedLocation)
      if writCost and profMatches and locationMatches and (WritHelperDB.hideCompleted==false or not completedToday(e.writ)) and (not WritHelperDB.repFilter or WritHelperDB.repFilter==0 or e.rep==WritHelperDB.repFilter) then
        local itemCost,itemEstimated,itemSource=buyCost(snapshot,e.item,e.count)
        local craft,detail,craftEstimated,materials,craftSources=craftInfo(snapshot,e.item,e.count)
        local best,bestEstimated=itemCost,itemEstimated
        if craft and (not best or craft<best) then best,bestEstimated=craft,craftEstimated end
        if not WritHelperDB.onlyCalculated or best then
          if writSource then state.usedSources[writSource]=true end
          if itemSource then state.usedSources[itemSource]=true end
          if craftSources then for source in pairs(craftSources) do state.usedSources[source]=true end end
          rows[#rows+1]={entry=e,writCost=writCost,writEstimated=writEstimated,writSource=writSource,itemCost=itemCost,itemEstimated=itemEstimated,itemSource=itemSource,craftCost=craft,craftEstimated=craftEstimated,detail=detail,materials=materials,totalEstimated=writEstimated or bestEstimated,total=best and writCost+best or nil}
        end
      end
    end
    table.sort(rows,function(a,b)
      if a.total and b.total then
        if WritHelperDB.sortBy=='efficiency' then
          local av,bv=a.total/a.entry.rep,b.total/b.entry.rep
          if av~=bv then return av<bv end
        end
        if a.total == b.total then return a.entry.writ < b.entry.writ end
        return a.total < b.total
      end
      if a.total then return true elseif b.total then return false end
      return a.entry.writ<b.entry.writ
    end)
    if #rows==0 then lines[#lines+1]=L('Заказы не найдены. Проверьте полноту сканирования и фильтр в настройках.') end
  end
  state.foundCount=#rows
  if sourceLabel then
    sourceLabel:SetText(sourceText(state.usedSources))
  end
  updateProgress(state.message,state.error)
  resultHeader:SetText(table.concat(lines,'\n'))
  local headerHeight=math.max(10,22*#lines)
  local offset=headerHeight
  for index,row in ipairs(rows) do
    local card=getCard(index); local e=row.entry
    card.entry=e; card.writID=e.writ; card.itemID=e.item
    local showMaterials=WritHelperDB.showMaterials~=false and row.materials~=nil
    local materialCount=showMaterials and #row.materials or 0
    local completed=completedToday(e.writ)
    local completedOffset=completed and 19 or 0
    local height=109+materialCount*19+completedOffset
    card:SetHeight(height); card.accent:SetHeight(height)
    card.completed:SetText(completed and L('|cffff5555Сегодня уже выполнено — повторно сдать нельзя.|r') or '')
    card:ClearAllPoints(); card:SetPoint('TOPLEFT',0,-offset)
    offset=offset+height+8
    for _,line in ipairs(card.materialLines) do line:Hide() end
    if showMaterials then
      for i,material in ipairs(row.materials) do
        local line=card.materialLines[i]
        if not line then line=textAt(card,'GameFontHighlightSmall',25,0,675); card.materialLines[i]=line end
        line:ClearAllPoints(); line:SetPoint('TOPLEFT',25,-77-completedOffset-(i-1)*19)
        local have=material.bags+(material.bank or 0)
        local icon
        if have>=material.need then icon='|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13|t'
        elseif material.bank==nil then icon='|TInterface\\RaidFrame\\ReadyCheck-Waiting:13:13|t'
        else icon='|TInterface\\RaidFrame\\ReadyCheck-NotReady:13:13|t' end
        local bankText=material.bank~=nil and tostring(material.bank) or L('не проверен')
        if material.bank and material.bank>0 then bankText='|cff55ee77'..bankText..'|r' end
        line:SetText(icon..'  '..(itemName(material.id) or ('#'..material.id))..L(' - нужно ')..material.need..L(', сумки ')..material.bags..L(', банк ')..bankText)
        line:Show()
      end
    end
    card.writIcon.itemID=e.writ; card.writIcon.texture:SetTexture(iconTexture(e.writ))
    card.itemIcon.itemID=e.item; card.itemIcon.texture:SetTexture(iconTexture(e.item))
    card.writName:SetText(index..'. '..(itemName(e.writ) or (L('Заказ #')..e.writ)))
    card.itemName:SetText((itemName(e.item) or (L('Предмет #')..e.item))..(e.count>1 and (' x'..e.count) or ''))
    card.writPrice:SetText(money(row.writCost)..'  •  '..availability(snapshot,e.writ)..'  •  '..e.rep..L(' реп.'))
    card.itemPrice:SetText((row.itemCost and money(row.itemCost) or L('не найдено / недостаточно'))..'  •  '..availability(snapshot,e.item))
    local info=C_Item and C_Item.GetItemInfo or GetItemInfo
    local required=info and select(5,info(e.writ))
    local playerLevel=UnitLevel and UnitLevel('player')
    if type(required)=='number' and required>0 and type(playerLevel)=='number' and playerLevel<required then
      card.levelWarning:SetText(L('|cffff5555Внимание: использовать заказ можно с ')..required..L(' уровня; у вас ')..playerLevel..'.|r')
    else
      card.levelWarning:SetText('')
    end
    local choice
    if row.itemCost and row.craftCost then
      if row.craftCost<row.itemCost then choice=L('Выгоднее изготовить')
      elseif row.itemCost<row.craftCost then choice=L('Выгоднее купить')
      else choice=L('Стоимость одинакова') end
    else choice='' end
    card.choice:SetText(choice)
    card.total:SetText(row.total and money(row.total) or L('Цена неизвестна'))
    card.repPrice:SetText(row.total and (L('за 100 реп.: ')..money(row.total*100/e.rep,12)) or '')
    card:Show()
  end
  output:SetHeight(math.max(430,offset+10))
  if status then status:SetText(state.message) end
end
local shoppingWindow, shoppingContent, shoppingTitle
local shoppingRows={}
local function shoppingEntries(entry)
  local buy={{id=entry.writ,count=1},{id=entry.item,count=entry.count}}
  local materials={}
  local recipe=WritHelperDB.recipes[entry.item]
  if recipe then
    local crafts=math.ceil(entry.count/(recipe.makes or 1))
    for _,reagent in ipairs(recipe.reagents) do materials[#materials+1]={id=reagent.id,count=reagent.count*crafts} end
  end
  return buy,materials,recipe
end
local function auctionatorList(entry)
  local api=Auctionator and Auctionator.API and Auctionator.API.v1
  local manager=Auctionator and Auctionator.Shopping and Auctionator.Shopping.ListManager
  if not api or not api.CreateShoppingList or not api.ConvertToSearchString or not manager then
    msg(L('Не удалось открыть список Auctionator. Проверьте, включён ли аддон.')) return
  end
  if state.phase~='idle' then msg(L('Дождитесь завершения сканирования перед созданием списка.')) return end
  local buy,materials,recipe=shoppingEntries(entry)
  local groups={}
  if recipe then
    local craft={{id=entry.writ,count=1}}
    for _,material in ipairs(materials) do
      local missing=math.max(0,material.count-ownedCount(material.id))
      if missing>0 then craft[#craft+1]={id=material.id,count=missing} end
    end
    groups[#groups+1]={name=L('Материалы'),entries=craft}
  end
  groups[#groups+1]={name=L('Готовое'),entries=buy}
  local baseName=itemName(entry.item)
  if not baseName then msg(L('Название предмета ещё загружается. Повторите попытку.')) return end
  for _,group in ipairs(groups) do
    group.terms={}
    for _,item in ipairs(group.entries) do
      local name=itemName(item.id)
      if not name then msg(L('Название предмета ещё загружается. Повторите попытку.')) return end
      local ok,term=pcall(api.ConvertToSearchString,ADDON,{searchString=name,isExact=true,quantity=item.count})
      if not ok or type(term)~='string' then msg(L('Не удалось подготовить позицию списка: ')..tostring(term)) return end
      group.terms[#group.terms+1]=term
    end
  end
  for _,group in ipairs(groups) do
    local base='WritHelper - '..group.name..': '..baseName
    local listName,n=base,2
    while manager:GetIndexForName(listName) do listName=base..' ('..n..')'; n=n+1 end
    local ok,err=pcall(api.CreateShoppingList,ADDON,listName,group.terms)
    if not ok then msg(L('Не удалось создать список Auctionator: ')..tostring(err)); return end
  end
  msg(L('Списки Auctionator созданы. Готовый предмет и изготовление — разные варианты.'))
end
showShoppingList=function(entry)
  if shoppingVisible() then auctionatorList(entry) end
  if not shoppingWindow then
    shoppingWindow=CreateFrame('Frame','WritHelperShoppingWindow',UIParent,'BasicFrameTemplateWithInset')
    closeOnEscape('WritHelperShoppingWindow')
    shoppingWindow:SetSize(550,420); shoppingWindow:SetPoint('CENTER',100,0); shoppingWindow:SetFrameStrata('DIALOG')
    shoppingWindow:SetMovable(true); shoppingWindow:EnableMouse(true); shoppingWindow:RegisterForDrag('LeftButton')
    shoppingWindow:SetScript('OnDragStart',shoppingWindow.StartMoving); shoppingWindow:SetScript('OnDragStop',shoppingWindow.StopMovingOrSizing)
    local title=shoppingWindow:CreateFontString(nil,'OVERLAY','GameFontHighlight'); title:SetPoint('TOP',0,-7); title:SetText(L('Список покупок'))
    shoppingTitle=textAt(shoppingWindow,'GameFontNormalSmall',18,-36,500)
    local scroll=CreateFrame('ScrollFrame','WritHelperShoppingScroll',shoppingWindow,'UIPanelScrollFrameTemplate'); scroll:SetPoint('TOPLEFT',18,-74); scroll:SetPoint('BOTTOMRIGHT',-35,20)
    shoppingContent=CreateFrame('Frame',nil,scroll); shoppingContent:SetSize(490,320); scroll:SetScrollChild(shoppingContent)
  end
  if frame then shoppingWindow:SetFrameLevel(frame:GetFrameLevel()+45) end
  shoppingTitle:SetText(L('Готовый предмет и ингредиенты — разные варианты выполнения.'))
  for _,row in ipairs(shoppingRows) do row:Hide() end
  local buy,materials,recipe=shoppingEntries(entry)
  local entries={{heading=L('Купить готовое')}}
  for _,item in ipairs(buy) do entries[#entries+1]=item end
  entries[#entries+1]={heading=L('Для изготовления')}
  if recipe then
    for _,item in ipairs(materials) do entries[#entries+1]=item end
  else
    entries[#entries+1]={heading=L('Рецепт не записан. Откройте окно профессии.')}
  end
  local offset=0
  for i,item in ipairs(entries) do
    local row=shoppingRows[i]
    if not row then
      row=CreateFrame('Frame',nil,shoppingContent); row:SetSize(480,60)
      local bg=row:CreateTexture(nil,'BACKGROUND'); bg:SetAllPoints(); bg:SetColorTexture(0.12,0.12,0.13,0.9); row.bg=bg
      row.icon=CreateFrame('Button',nil,row); row.icon:SetSize(32,32); row.icon:SetPoint('LEFT',8,0)
      row.icon.texture=row.icon:CreateTexture(nil,'ARTWORK'); row.icon.texture:SetAllPoints()
      row.icon:SetScript('OnEnter',function(self) if self.itemID then GameTooltip:SetOwner(self,'ANCHOR_RIGHT'); GameTooltip:SetItemByID(self.itemID); GameTooltip:Show() end end)
      row.icon:SetScript('OnLeave',function() GameTooltip:Hide() end)
      row.icon:SetScript('OnClick',function(self) if IsShiftKeyDown and IsShiftKeyDown() then putSearch(self.itemID) end end)
      row.text=textAt(row,'GameFontHighlightSmall',47,-6,330)
      row.details=textAt(row,'GameFontNormalSmall',47,-26,330)
      row.details:ClearAllPoints(); row.details:SetPoint('TOPLEFT',row,'LEFT',47,-2)
      row.find=CreateFrame('Button',nil,row,'UIPanelButtonTemplate'); row.find:SetSize(75,24); row.find:SetPoint('RIGHT',-6,0); row.find:SetText(L('Найти'))
      row.find:SetScript('OnClick',function() putSearch(row.itemID,true) end)
      shoppingRows[i]=row
    end
    row:ClearAllPoints(); row:SetPoint('TOPLEFT',0,-offset)
    if item.heading then
      row:SetHeight(25); row.bg:Hide(); row.icon:Hide(); row.find:Hide(); row.details:Hide()
      row.text:ClearAllPoints(); row.text:SetPoint('TOPLEFT',3,-5); row.text:SetWidth(470); row.text:SetText(item.heading); offset=offset+28
    else
      row:SetHeight(60); row.bg:Show(); row.icon:Show(); row.find:Show(); row.details:Show()
      row.text:ClearAllPoints(); row.text:SetPoint('BOTTOMLEFT',row,'LEFT',47,2); row.text:SetWidth(330)
      row.itemID=item.id; row.icon.itemID=item.id; row.icon.texture:SetTexture(iconTexture(item.id))
      row.text:SetText((itemName(item.id) or ('#'..item.id))..' x'..item.count)
      local bags=itemCount(item.id)
      local bank=cachedBankCount(item.id)
      local missing=math.max(0,item.count-bags-(bank or 0))
      local amount=missing>0 and missing or 1
      local price,approx=buyCost(WritHelperDB.snapshot,item.id,amount)
      local priceText=price and money(price) or L('нет данных о цене')
      local label=missing>0 and (L('цена за ')..amount..': ') or L('цена от: ')
      row.details:SetText(L('Сумки: ')..bags..L('  Банк: ')..(bank==nil and '?' or tostring(bank))..'  '..label..priceText)
      offset=offset+65
    end
    row:Show()
  end
  shoppingContent:SetHeight(math.max(320,offset))
  shoppingWindow:Show()
end
local function relevantItems()
  local ids={}
  for _,e in ipairs(data) do
    ids[e.writ]=true; ids[e.item]=true
    local recipe=WritHelperDB.recipes[e.item]
    if recipe then for _,r in ipairs(recipe.reagents) do ids[r.id]=true end end
  end
  return ids
end
local function completeScan()
  local pending=state.pending
  logEvent(L('Завершение: ')..(pending.approximate and L('обычный поиск') or L('полный запрос'))..L(', обработано=')..state.total..L(', пропущено=')..pending.unknown)
  WritHelperDB.snapshot={lots=pending.lots,quotes=pending.quotes,scanned=pending.scanned,count=state.total,unknown=pending.unknown,time=time(),updatedDuringRead=pending.updatedDuringRead,approximate=pending.approximate}
  state.phase='idle'; state.current=state.total
  local note=pending.unknown>0 and (L('; не распознано ')..pending.unknown..L(' лотов')) or ''
  if pending.updatedDuringRead then note=note..L('; повторное обновление при чтении') end
  updateProgress(L('Готово: ')..state.total..(pending.approximate and L(' запросов') or L(' лотов'))..note, pending.unknown>0)
  state.pending=nil
  msg(L('Сканирование завершено: ')..state.total..(pending.approximate and L(' запросов') or L(' лотов'))..note..'.')
  refresh()
end
local function processBatch(token)
  if state.phase~='processing' or state.token~=token then return end
  local last=math.min(state.index+249,state.total)
  for i=state.index,last do
    local info, link
    if state.backend=='replicate' then
      info={C_AuctionHouse.GetReplicateItemInfo(i-1)}
      if not tonumber(info[17]) and C_AuctionHouse.GetReplicateItemLink then link=C_AuctionHouse.GetReplicateItemLink(i-1) end
    else
      info={GetAuctionItemInfo('list',i)}
      if not tonumber(info[17]) and GetAuctionItemLink then link=GetAuctionItemLink('list',i) end
    end
    local id=tonumber(info[17]) or idFromLink(link)
    local quantity,price=tonumber(info[3]),tonumber(info[10])
    if not id or id==0 then
      state.pending.unknown=state.pending.unknown+1
    elseif quantity and quantity>0 and price and price>0 then
      local quotes=state.pending.quotes
      local unit=math.ceil(price/quantity)
      local quote=quotes[id]
      if quote then quote[1]=math.min(quote[1],unit); quote[2]=quote[2]+quantity
      else quotes[id]={unit,quantity} end
      if state.pending.ids[id] then
        local lots=state.pending.lots
        lots[id]=lots[id] or {}
        lots[id][#lots[id]+1]={quantity,price}
      end
    end
  end
  state.current=last; state.index=last+1
  local percent=state.total>0 and math.floor(last*100/state.total) or 100
  updateProgress(string.format(L('Обработка: %d%% (%d/%d лотов)'),percent,last,state.total))
  if state.index>state.total then completeScan() else C_Timer.After(0.01,function() local ok,err=pcall(processBatch,token); if not ok then fail(L('Ошибка обработки: ')..tostring(err)) end end) end
end
local function scanStandardNext(token, isPage)
  if state.token~=token or (state.phase~='standard' and state.phase~='standard_more') then return end
  local api=C_AuctionHouse
  if api.IsThrottledMessageSystemReady and not api.IsThrottledMessageSystemReady() then
    updateProgress(string.format(L('Ожидание сервера: %d/%d запросов'),state.current,state.total))
    C_Timer.After(0.5,function() scanStandardNext(token,isPage) end)
    return
  end
  local request=state.requests[state.index]
  if not request then completeScan(); return end
  local ok,err
  if isPage then
    state.phase='standard_wait_more'
    ok,err=pcall(api.RequestMoreBrowseResults)
  else
    state.phase='standard_wait_first'
    ok,err=pcall(api.SendBrowseQuery,{searchString=request.name,sorts={},filters={},itemClassFilters={}})
  end
  if not ok then fail(L('Ошибка обычного поиска: ')..tostring(err)); return end
  if not isPage and (state.current==0 or state.current%25==0) then
    logEvent(L('Обычный поиск: обработано ')..state.current..L(' из ')..state.total)
  end
  state.sequence=(state.sequence or 0)+1
  local seq=state.sequence
  updateProgress(string.format(L('Обычный поиск: %d%% (%d/%d), %s'),math.floor(state.current*100/state.total),state.current,state.total,request.name))
  C_Timer.After(30,function()
    if state.token==token and state.sequence==seq and (state.phase=='standard_wait_first' or state.phase=='standard_wait_more') then
      fail(L('Аукцион не ответил на обычный поиск. Результаты не сохранены; попробуйте снова.'))
    end
  end)
end
startStandard=function(reason)
  local api=C_AuctionHouse
  if not api or not api.SendBrowseQuery or not api.GetBrowseResults or not api.HasFullBrowseResults or not api.RequestMoreBrowseResults then
    fail(L('Обычный поиск недоступен в этом клиенте.')) return
  end
  state.token=(state.token or 0)+1
  local token=state.token
  state.phase='preparing'; state.current=0; state.total=0
  logEvent(L('Запуск обычного поиска: ')..tostring(reason))
  local ids=relevantItems()
  local count=0
  for id in pairs(ids) do count=count+1; itemName(id) end
  state.total=count
  local deadline=(GetTime and GetTime() or time())+20
  local function waitForNames()
    if state.token~=token or state.phase~='preparing' then return end
    local requests,missing={},0
    for id in pairs(ids) do
      local name=itemName(id)
      if name then requests[#requests+1]={id=id,name=name} else missing=missing+1 end
    end
    state.current=#requests
    updateProgress(string.format(L('Загрузка названий: %d%% (%d/%d)'),count>0 and math.floor(#requests*100/count) or 100,#requests,count))
    local now=GetTime and GetTime() or time()
    if missing>0 and now<deadline then C_Timer.After(1,waitForNames); return end
    table.sort(requests,function(a,b) return a.name<b.name end)
    if #requests==0 then fail(L('Названия предметов не загрузились. Подождите и повторите.')) return end
    state.requests=requests
    state.pending={ids=ids,lots={},scanned={},unknown=missing,approximate=true}
    state.total=#requests; state.current=0; state.index=1; state.phase='standard'
    logEvent(L('Подготовлено запросов: ')..state.total..L(', не загрузились названия: ')..missing)
    if missing>0 then msg(L('Не удалось загрузить названия: ')..missing..L('. Список может быть неполным.')) end
    scanStandardNext(token,false)
  end
  updateProgress((reason or L('Обычный поиск'))..L(': загрузка названий предметов...'))
  C_Timer.After(2,waitForNames)
end
local function startScan()
  if state.phase~='idle' then msg(L('Сканирование уже идёт. Дождитесь завершения.')) return end
  if not ((AuctionFrame and AuctionFrame:IsShown()) or (AuctionHouseFrame and AuctionHouseFrame:IsShown())) then fail(L('Откройте аукцион.')) return end
  if not C_Timer or not C_Timer.After then fail(L('В клиенте недоступен таймер сканирования.')) return end
  if WritHelperDB.scanMode=='standard' then startStandard(L('Обычное сканирование')); return end
  local modern=C_AuctionHouse and C_AuctionHouse.ReplicateItems and C_AuctionHouse.GetNumReplicateItems and C_AuctionHouse.GetReplicateItemInfo
  local legacy=CanSendAuctionQuery and QueryAuctionItems and GetNumAuctionItems and GetAuctionItemInfo
  if not modern and not legacy then startStandard(L('Полный запрос недоступен; переход к обычному')); return end
  if not modern then
    local ok,_,canAll=pcall(CanSendAuctionQuery)
    if not ok or not canAll then startStandard(L('Полный запрос недоступен; переход к обычному')); return end
  end
  state.backend=modern and 'replicate' or 'legacy'
  state.token=(state.token or 0)+1
  local token=state.token
  state.phase='waiting'; state.current=0; state.total=0; state.waitPercent=0
  logEvent(L('Запуск полного запроса: ')..state.backend)
  state.pending={ids=relevantItems(),lots={},quotes={},unknown=0}
  updateProgress(L('Ожидание ответа: 0% времени до перехода на обычный поиск. Прогресс сервера неизвестен.'))
  local sent,err
  if state.backend=='replicate' then sent,err=pcall(C_AuctionHouse.ReplicateItems)
  else sent,err=pcall(QueryAuctionItems,'',nil,nil,0,nil,nil,true,false,nil) end
  if not sent then startStandard(L('Ошибка полного запроса; переход к обычному')); return end
  msg(L('Полное сканирование началось. Не запускайте другие поиски до завершения.'))
  local started=GetTime and GetTime() or time()
  local function updateWait()
    if state.phase~='waiting' or state.token~=token then return end
    local now=GetTime and GetTime() or time()
    state.waitPercent=math.min(99,math.max(0,math.floor((now-started)*100/45)))
    updateProgress(L('Ожидание ответа: ')..state.waitPercent..L('% времени до перехода на обычный поиск. Прогресс сервера неизвестен.'))
    C_Timer.After(1,updateWait)
  end
  C_Timer.After(1,updateWait)
  C_Timer.After(45,function() if state.phase=='waiting' and state.token==token then logEvent(L('Полный запрос: нет ответа за 45 секунд, переход к обычному')); msg(L('Полный запрос не ответил: переходим к обычному поиску.')); startStandard(L('Полный запрос не ответил; переход к обычному')) end end)
end
local logWindow, logBox
local function showLog()
  if not logWindow then
    logWindow=CreateFrame('Frame','WritHelperLogWindow',UIParent,'BasicFrameTemplateWithInset')
    closeOnEscape('WritHelperLogWindow')
    logWindow:SetSize(690,470); logWindow:SetPoint('CENTER',50,20); logWindow:SetFrameStrata('DIALOG')
    logWindow:SetMovable(true); logWindow:EnableMouse(true); logWindow:RegisterForDrag('LeftButton')
    logWindow:SetScript('OnDragStart',logWindow.StartMoving); logWindow:SetScript('OnDragStop',logWindow.StopMovingOrSizing)
    local title=logWindow:CreateFontString(nil,'OVERLAY','GameFontHighlight'); title:SetPoint('TOP',0,-7); title:SetText(L('Журнал WritHelper'))
    local hint=logWindow:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); hint:SetPoint('TOPLEFT',18,-38)
    hint:SetText(L('Нажмите «Выделить для копирования», затем Ctrl+C.'))
    local copy=CreateFrame('Button',nil,logWindow,'UIPanelButtonTemplate'); copy:SetSize(205,25); copy:SetPoint('BOTTOMLEFT',18,16); copy:SetText(L('Выделить для копирования'))
    copy:SetScript('OnClick',function() logBox:SetFocus(); logBox:HighlightText() end)
    local scroll=CreateFrame('ScrollFrame','WritHelperLogScroll',logWindow,'UIPanelScrollFrameTemplate')
    scroll:SetPoint('TOPLEFT',18,-65); scroll:SetPoint('BOTTOMRIGHT',-38,55)
    logBox=CreateFrame('EditBox',nil,scroll); logBox:SetMultiLine(true); logBox:SetAutoFocus(false); logBox:SetFontObject(ChatFontNormal); logBox:SetWidth(630); logBox:SetMaxLetters(0)
    logBox:SetScript('OnEscapePressed',function(self) self:ClearFocus(); logWindow:Hide() end); scroll:SetScrollChild(logBox)
  end
  local lines={'WritHelper '..VERSION..L(' — последние 1500 событий'),''}
  for _,line in ipairs(WritHelperDB.log or {}) do lines[#lines+1]=line end
  if #lines==2 then lines[#lines+1]=L('Событий пока нет.') end
  logBox:SetText(table.concat(lines,'\n'))
  if frame then logWindow:SetFrameLevel(frame:GetFrameLevel()+50) end
  logWindow:Show()
end
local settingsWindow, settingsDraft, resetSettings
local function showSettings()
  if not settingsWindow then
    settingsWindow=CreateFrame('Frame','WritHelperSettingsWindow',UIParent,'BasicFrameTemplateWithInset')
    closeOnEscape('WritHelperSettingsWindow')
    settingsWindow:SetSize(500,455); settingsWindow:SetPoint('CENTER',80,0); settingsWindow:SetFrameStrata('DIALOG')
    settingsWindow:SetMovable(true); settingsWindow:EnableMouse(true); settingsWindow:RegisterForDrag('LeftButton')
    settingsWindow:SetScript('OnDragStart',settingsWindow.StartMoving); settingsWindow:SetScript('OnDragStop',settingsWindow.StopMovingOrSizing)
    local title=settingsWindow:CreateFontString(nil,'OVERLAY','GameFontHighlight'); title:SetPoint('TOP',0,-7); title:SetText(L('Настройки WritHelper'))
    local header=settingsWindow:CreateFontString(nil,'OVERLAY','GameFontNormal'); header:SetPoint('TOPLEFT',22,-42); header:SetText(L('Режим сканирования'))
    local full=CreateFrame('CheckButton',nil,settingsWindow,'UICheckButtonTemplate'); full:SetPoint('TOPLEFT',18,-65); full:SetSize(24,24)
    local ft=settingsWindow:CreateFontString(nil,'OVERLAY','GameFontHighlight'); ft:SetPoint('LEFT',full,'RIGHT',3,0); ft:SetText(L('Полный, с переходом на обычный'))
    local normal=CreateFrame('CheckButton',nil,settingsWindow,'UICheckButtonTemplate'); normal:SetPoint('TOPLEFT',18,-97); normal:SetSize(24,24)
    local nt=settingsWindow:CreateFontString(nil,'OVERLAY','GameFontHighlight'); nt:SetPoint('LEFT',normal,'RIGHT',3,0); nt:SetText(L('Обычный поиск'))
    local function setMode(mode)
      settingsDraft.scanMode=mode; full:SetChecked(mode~='standard'); normal:SetChecked(mode=='standard')
    end
    full:SetScript('OnClick',function() setMode('full') end); normal:SetScript('OnClick',function() setMode('standard') end)
    local only=CreateFrame('CheckButton',nil,settingsWindow,'UICheckButtonTemplate'); only:SetPoint('TOPLEFT',18,-145); only:SetSize(24,24)
    local ot=settingsWindow:CreateFontString(nil,'OVERLAY','GameFontHighlight'); ot:SetPoint('LEFT',only,'RIGHT',3,0); ot:SetText(L('Показывать только заказы с расчётом стоимости'))
    only:SetScript('OnClick',function(self) settingsDraft.onlyCalculated=self:GetChecked() and true or false end)
    local materials=CreateFrame('CheckButton',nil,settingsWindow,'UICheckButtonTemplate'); materials:SetPoint('TOPLEFT',18,-178); materials:SetSize(24,24)
    local mt=settingsWindow:CreateFontString(nil,'OVERLAY','GameFontHighlight'); mt:SetPoint('LEFT',materials,'RIGHT',3,0); mt:SetText(L('Показывать список материалов в карточках'))
    materials:SetScript('OnClick',function(self) settingsDraft.showMaterials=self:GetChecked() and true or false end)
    local hint=settingsWindow:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); hint:SetPoint('TOPLEFT',22,-215); hint:SetWidth(455); hint:SetJustifyH('LEFT'); hint:SetText(L('Полный запрос обычно доступен раз в 15 минут; ограничение задаёт игра. Режим действует со следующего сканирования.'))
    sourceLabel=settingsWindow:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); sourceLabel:SetPoint('TOPLEFT',22,-264); sourceLabel:SetWidth(455); sourceLabel:SetJustifyH('LEFT')
    local languageHeader=settingsWindow:CreateFontString(nil,'OVERLAY','GameFontNormal'); languageHeader:SetPoint('TOPLEFT',22,-300); languageHeader:SetText(L('Язык'))
    local choices={{'auto',L('Как в игре')},{'ru','Русский'},{'en','English'},{'zh','中文'}}
    local languageButtons={}
    local function updateLanguageButtons()
      for _,choice in ipairs(languageButtons) do choice.button:SetChecked(settingsDraft.language==choice.key) end
    end
    for i,choice in ipairs(choices) do
      local button=CreateFrame('CheckButton',nil,settingsWindow,'UICheckButtonTemplate'); button:SetSize(21,21); button:SetPoint('TOPLEFT',18+(i-1)*117,-323)
      local label=settingsWindow:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); label:SetPoint('LEFT',button,'RIGHT',1,0); label:SetText(choice[2])
      local key=choice[1]
      languageButtons[#languageButtons+1]={button=button,key=key}
      button:SetScript('OnClick',function()
        settingsDraft.language=key; updateLanguageButtons()
      end)
    end
    resetSettings=function()
      settingsDraft={scanMode=WritHelperDB.scanMode or 'full',onlyCalculated=WritHelperDB.onlyCalculated and true or false,showMaterials=WritHelperDB.showMaterials~=false,language=WritHelperDB.language or 'auto'}
      setMode(settingsDraft.scanMode); only:SetChecked(settingsDraft.onlyCalculated); materials:SetChecked(settingsDraft.showMaterials); updateLanguageButtons()
    end
    local languageHint=settingsWindow:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); languageHint:SetPoint('TOPLEFT',22,-352); languageHint:SetText(L('Смена языка после применения перезагрузит интерфейс.'))
    local thanks=CreateFrame('Button',nil,settingsWindow,'UIPanelButtonTemplate')
    thanks:SetSize(175,23)
    thanks:SetPoint('TOPLEFT',22,-374)
    thanks:SetText(L('Поблагодарить автора'))

    local boostyURL='https://boosty.to/rainrock/donate'
    local boostyLink=CreateFrame('EditBox',nil,settingsWindow,'InputBoxTemplate')
    boostyLink:SetSize(245,23)
    boostyLink:SetPoint('LEFT',thanks,'RIGHT',12,0)
    boostyLink:SetAutoFocus(false)
    boostyLink:SetText(boostyURL)
    boostyLink:SetScript('OnTextChanged',function(self,userInput)
      if userInput then self:SetText(boostyURL); self:HighlightText() end
    end)
    boostyLink:SetScript('OnEscapePressed',function(self) self:Hide() end)
    boostyLink:SetScript('OnEnterPressed',function(self) self:ClearFocus() end)
    boostyLink:Hide()
    thanks:SetScript('OnClick',function()
      boostyLink:Show()
      boostyLink:SetFocus()
      boostyLink:HighlightText()
    end)
    local journal=CreateFrame('Button',nil,settingsWindow,'UIPanelButtonTemplate'); journal:SetSize(105,23); journal:SetPoint('BOTTOMLEFT',22,15); journal:SetText(L('Журнал')); journal:SetScript('OnClick',showLog)
    local apply=CreateFrame('Button',nil,settingsWindow,'UIPanelButtonTemplate'); apply:SetSize(105,23); apply:SetPoint('BOTTOM',0,15); apply:SetText(L('Применить'))
    apply:SetScript('OnClick',function()
      local languageChanged=settingsDraft.language~=(WritHelperDB.language or 'auto')
      if languageChanged and state.phase~='idle' then msg(L('Дождитесь завершения сканирования перед сменой языка.')); return end
      WritHelperDB.scanMode=settingsDraft.scanMode; WritHelperDB.onlyCalculated=settingsDraft.onlyCalculated
      WritHelperDB.showMaterials=settingsDraft.showMaterials; WritHelperDB.language=settingsDraft.language
      if languageChanged and ReloadUI then ReloadUI() else refresh(); settingsWindow:Hide() end
    end)
    local version=settingsWindow:CreateFontString(nil,'OVERLAY','GameFontNormalSmall'); version:SetPoint('BOTTOMRIGHT',-22,20); version:SetText('WritHelper v'..VERSION)
  end
  resetSettings()
  if sourceLabel then sourceLabel:SetText(sourceText(state.usedSources)) end
  if frame then settingsWindow:SetFrameLevel(frame:GetFrameLevel()+30) end
  settingsWindow:Show()
end
local function makeButton(parent,label,x,width,callback)
  local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate')
  b:SetSize(width,25); b:SetPoint('TOPLEFT',x,-37); b:SetText(label)
  b:SetScript('OnClick',function(...) local ok,err=pcall(callback,...); if not ok then fail(L('Ошибка: ')..tostring(err)) end end)
end
local function createUI()
  if frame then return end
  frame=CreateFrame('Frame','WritHelperFrame',UIParent,'BasicFrameTemplateWithInset')
  closeOnEscape('WritHelperFrame')
  frame:SetFrameStrata('DIALOG'); frame:SetSize(780,600); frame:SetPoint('CENTER'); frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag('LeftButton'); frame:SetScript('OnDragStart',frame.StartMoving); frame:SetScript('OnDragStop',frame.StopMovingOrSizing)
  frame.title=frame:CreateFontString(nil,'OVERLAY','GameFontHighlight'); frame.title:SetPoint('TOP',0,-7); frame.title:SetText('WritHelper Forever')
  makeButton(frame,L('Сканировать аукцион'),15,200,startScan)
  makeButton(frame,L('Настройки'),220,120,showSettings)
  scanInfoButton=CreateFrame('Button',nil,frame)
  scanInfoButton:SetSize(190,25); scanInfoButton:SetPoint('TOPRIGHT',-76,-73)
  scanInfoButton.label=scanInfoButton:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall')
  scanInfoButton.label:SetPoint('RIGHT',0,0)
  scanInfoButton:SetScript('OnEnter',function(self)
    local snapshot=WritHelperDB and WritHelperDB.snapshot
    GameTooltip:SetOwner(self,'ANCHOR_LEFT'); GameTooltip:SetText(L('Сканирование WritHelper'))
    GameTooltip:AddLine(state.message or '',1,1,1,true)
    if snapshot then
      GameTooltip:AddLine(L('Последнее: ')..(snapshot.time and date and date('%d.%m.%Y %H:%M',snapshot.time) or '-'),0.8,0.8,0.8)
      GameTooltip:AddLine(L('Обработано: ')..tostring(snapshot.count or 0)..L('; пропущено: ')..tostring(snapshot.unknown or 0),0.8,0.8,0.8)
      GameTooltip:AddLine(L('Заказов с учётом фильтров: ')..tostring(state.foundCount or 0),0.8,0.8,0.8)
      GameTooltip:AddLine(L('«Оценка» обозначает ориентировочную или сохранённую цену; наличие проверьте на аукционе.'),1,0.82,0,true)
      if (snapshot.unknown or 0)>0 then GameTooltip:AddLine(L('Часть данных не распознана; результаты могут быть неполными.'),1,0.55,0,true) end
      if snapshot.updatedDuringRead then GameTooltip:AddLine(L('При чтении пришло обновление; данные могли смешаться.'),1,0.55,0,true) end
      GameTooltip:AddLine(L('Количество в продаже показано на момент сканирования.'),0.8,0.8,0.8,true)
    else GameTooltip:AddLine(L('Сканирование ещё не завершено.'),0.8,0.8,0.8) end
    GameTooltip:Show()
  end)
  scanInfoButton:SetScript('OnLeave',function() GameTooltip:Hide() end)
  stopButton=CreateFrame('Button',nil,frame,'UIPanelButtonTemplate')
  stopButton:SetSize(53,22); stopButton:SetPoint('TOPRIGHT',-18,-75); stopButton:SetText(L('Стоп'))
  stopButton:SetScript('OnClick',stopScan); stopButton:Hide()
  local function dropdown(x,width,optionList,field,default,labelPrefix,y)
    local button=CreateFrame('DropdownButton',nil,frame,'WowStyle1DropdownTemplate')
    button:SetSize(width,23); button:SetPoint('TOPLEFT',x,y or -74)
    local function options() return type(optionList)=='function' and optionList() or optionList end
    local function updateLabel()
      local selected=WritHelperDB[field]
      if selected==nil then selected=default end
      local list=options()
      local name=list[1].name
      local found=false
      for _,option in ipairs(list) do if selected==option.key then name=option.name; found=true end end
      if not found then WritHelperDB[field]=default end
      button:OverrideText(labelPrefix..name)
    end
    button:SetupMenu(function(_,root)
      for _,option in ipairs(options()) do
        local selectedKey=option.key
        root:CreateRadio(option.name,function() return (WritHelperDB[field] or default)==selectedKey end,function()
        WritHelperDB[field]=selectedKey
        updateLabel()
        logEvent(L('Фильтр/сортировка: ')..field..'='..tostring(selectedKey))
        local ok,err=pcall(refresh)
        if not ok then fail(L('Не удалось обновить список: ')..tostring(err)); return end
        if resultsScroll then
          if resultsScroll.UpdateScrollChildRect then resultsScroll:UpdateScrollChildRect() end
          resultsScroll:SetVerticalScroll(0)
        end
        logEvent(L('Список обновлён: заказов=')..tostring(state.foundCount or 0))
        end)
      end
    end)
    updateLabel()
    return button
  end
  dropdown(15,145,{{key=0,name=L('Все')},{key=75,name='75'},{key=125,name='125'},{key=200,name='200'}},'repFilter',0,L('Реп.: '))
  dropdown(165,160,{{key='price',name=L('Общая цена')},{key='efficiency',name=L('Цена / репутация')}},'sortBy','price','')
  dropdown(330,185,{{key='all',name=L('Все профессии')},{key='alchemy',name=L('Алхимия')},{key='blacksmith',name=L('Кузнечное дело')},{key='engineering',name=L('Инженерное дело')},{key='leatherworking',name=L('Кожевничество')},{key='tailoring',name=L('Портняжное дело')}},'profFilter','all','')
  local locationFilter=dropdown(15,360,locationOptions,'locationFilter','all','',-103)
  local hideCompleted=CreateFrame('CheckButton',nil,frame,'UICheckButtonTemplate')
  hideCompleted:SetSize(22,22); hideCompleted:SetPoint('LEFT',locationFilter,'RIGHT',10,0); hideCompleted:SetChecked(WritHelperDB.hideCompleted~=false)
  local hideLabel=frame:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall'); hideLabel:SetPoint('LEFT',hideCompleted,'RIGHT',2,0); hideLabel:SetText(L('Не показывать выполненные'))
  hideCompleted:SetScript('OnClick',function(self)
    WritHelperDB.hideCompleted=self:GetChecked() and true or false
    refresh()
    if resultsScroll then if resultsScroll.UpdateScrollChildRect then resultsScroll:UpdateScrollChildRect() end; resultsScroll:SetVerticalScroll(0) end
  end)
  updateProgress(state.message,state.error)
  local scroll=CreateFrame('ScrollFrame','WritHelperScroll',frame,'UIPanelScrollFrameTemplate'); resultsScroll=scroll; scroll:SetPoint('TOPLEFT',18,-137); scroll:SetPoint('BOTTOMRIGHT',-35,29)
  output=CreateFrame('Frame',nil,scroll); output:SetSize(720,430); scroll:SetScrollChild(output)
  resultHeader=textAt(output,'GameFontHighlightSmall',0,0,710)
  frame:Hide()
end
local function toggleUI()
  createUI()
  if frame:IsShown() then frame:Hide() else frame:Show(); refresh() end
end
local function createMinimapButton()
  if not Minimap then return end
  local button = CreateFrame('Button', 'WritHelperMinimapButton', Minimap)
  button:SetSize(32, 32)
  button:SetFrameStrata('MEDIUM')
  button:SetFrameLevel(Minimap:GetFrameLevel() + 8)
  button:SetHighlightTexture('Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight')
  local icon = button:CreateTexture(nil, 'BACKGROUND')
  icon:SetSize(20, 20)
  icon:SetPoint('CENTER')
  icon:SetTexture('Interface\\AddOns\\WritHelper\\Icon')
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
  local border = button:CreateTexture(nil, 'OVERLAY')
  border:SetSize(54, 54)
  border:SetPoint('TOPLEFT', 0, 0)
  border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
  local function position()
    local angle = WritHelperDB.minimapAngle or 225
    button:ClearAllPoints()
    button:SetPoint('CENTER', Minimap, 'CENTER', math.cos(math.rad(angle)) * 80, math.sin(math.rad(angle)) * 80)
  end
  position()
  button:RegisterForClicks('LeftButtonUp')
  button:RegisterForDrag('LeftButton')
  button:SetScript('OnClick', toggleUI)
  button:SetScript('OnEnter', function(self)
    GameTooltip:SetOwner(self, 'ANCHOR_LEFT')
    GameTooltip:SetText('WritHelper Forever')
    GameTooltip:AddLine(L('Нажмите, чтобы открыть заказы.'), 1, 1, 1)
    GameTooltip:AddLine(L('Перетащите, чтобы переместить кнопку.'), 0.8, 0.8, 0.8)
    GameTooltip:Show()
  end)
  button:SetScript('OnLeave', function() GameTooltip:Hide() end)
  button:SetScript('OnDragStart', function(self)
    self:SetScript('OnUpdate', function()
      local x, y = GetCursorPosition()
      local scale = Minimap:GetEffectiveScale()
      local cx, cy = Minimap:GetCenter()
      if cx and cy and scale and scale > 0 then
        WritHelperDB.minimapAngle = math.deg(math.atan2(y / scale - cy, x / scale - cx))
        position()
      end
    end)
  end)
  button:SetScript('OnDragStop', function(self) self:SetScript('OnUpdate', nil) end)
end
local function setupAuctionButton()
  local parent
  if AuctionFrame and AuctionFrame:IsShown() then parent = AuctionFrame
  elseif AuctionHouseFrame and AuctionHouseFrame:IsShown() then parent = AuctionHouseFrame end
  if not parent then return end
  if not auctionButton then
    auctionButton = CreateFrame('Button', 'WritHelperAuctionButton', parent)
    auctionButton:SetSize(36,36)
    local icon=auctionButton:CreateTexture(nil,'ARTWORK'); icon:SetAllPoints(); icon:SetTexture('Interface\\AddOns\\WritHelper\\Icon'); auctionButton.icon=icon
    auctionButton.scanBadge=auctionButton:CreateFontString(nil,'OVERLAY','GameFontNormalSmall')
    auctionButton.scanBadge:SetPoint('BOTTOM',auctionButton,'BOTTOM',0,-12)
    auctionButton:SetScript('OnClick', toggleUI)
    auctionButton:SetScript('OnEnter', function(self)
      GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
      GameTooltip:SetText('WritHelper Forever')
      GameTooltip:AddLine(L('Открыть WritHelper'), 1, 1, 1)
      GameTooltip:AddLine(state.message or '', 0.8, 0.8, 0.8)
      GameTooltip:Show()
    end)
    auctionButton:SetScript('OnLeave', function() GameTooltip:Hide() end)
  elseif auctionButton:GetParent() ~= parent then
    auctionButton:SetParent(parent)
  end
  auctionButton:ClearAllPoints()
  auctionButton:SetPoint('TOPLEFT', parent, 'TOPRIGHT', 3, -35)
  auctionButton:SetFrameStrata(parent:GetFrameStrata())
  auctionButton:SetFrameLevel(parent:GetFrameLevel() + 10)
  auctionButton:Show()
  updateProgress(state.message, state.error)
end
events=CreateFrame('Frame')
local initialized=false
local function initialize()
  if initialized then return end
  initialized=true
  WritHelperDB=WritHelperDB or {}; WritHelperDB.recipes=WritHelperDB.recipes or {}; WritHelperDB.log=WritHelperDB.log or {}
  logEvent(L('Загружена версия ')..VERSION)
  SLASH_WRITHELPER1='/writ'; SlashCmdList.WRITHELPER=toggleUI
  local ok,err=pcall(createMinimapButton)
  if not ok then msg(L('Кнопка миникарты недоступна: ')..tostring(err)) end
  msg(L('Загружен. Команда: /writ'))
end
events:SetScript('OnEvent',function(_,event,arg)
  if event=='ADDON_LOADED' and arg==ADDON then initialize()
  elseif event=='PLAYER_LOGIN' then initialize()
  elseif event=='QUEST_TURNED_IN' or event=='QUEST_LOG_UPDATE' or event=='QUEST_QUERY_COMPLETE' then
    if frame and frame:IsShown() and WritHelperDB then refresh() end
  elseif event=='BANKFRAME_OPENED' then
    bankOpen=true
    if C_Timer and C_Timer.After then C_Timer.After(0.5,function() if bankOpen then captureBank(); if frame and frame:IsShown() then refresh() end end end) else captureBank() end
  elseif event=='BANKFRAME_CLOSED' then
    bankOpen=false
  elseif event=='BAG_UPDATE_DELAYED' or event=='PLAYERBANKSLOTS_CHANGED' then
    if bankOpen then
      if C_Timer and C_Timer.After then C_Timer.After(0.2,function() if bankOpen then captureBank(); if frame and frame:IsShown() then refresh() end end end) else captureBank(); if frame and frame:IsShown() then refresh() end end
    elseif event=='BAG_UPDATE_DELAYED' and frame and frame:IsShown() then refresh() end
  elseif event=='AUCTION_HOUSE_SHOW' then
    if C_Timer and C_Timer.After then C_Timer.After(0.2,setupAuctionButton) else setupAuctionButton() end
  elseif event=='AUCTION_HOUSE_CLOSED' then
    if state.phase~='idle' then fail(L('Сканирование прервано: аукцион закрыт.')) end
    if frame then frame:Hide() end
  elseif event=='AUCTION_HOUSE_BROWSE_FAILURE' and (state.phase=='standard_wait_first' or state.phase=='standard_wait_more') then
    fail(L('Обычный поиск отклонён аукционом. Попробуйте снова.'))
  elseif (event=='AUCTION_HOUSE_BROWSE_RESULTS_UPDATED' and state.phase=='standard_wait_first') or (event=='AUCTION_HOUSE_BROWSE_RESULTS_ADDED' and state.phase=='standard_wait_more') then
    local token=state.token
    local ok,full=pcall(C_AuctionHouse.HasFullBrowseResults)
    if not ok then fail(L('Не удалось проверить результаты поиска: ')..tostring(full)); return end
    if not full then
      state.phase='standard_more'
      C_Timer.After(0,function() scanStandardNext(token,true) end)
    else
      local got,results=pcall(C_AuctionHouse.GetBrowseResults)
      if not got or type(results)~='table' then fail(L('Не удалось прочитать результаты обычного поиска.')); return end
      local request=state.requests[state.index]
      local best,quantity=nil,0
      for _,row in ipairs(results) do
        if row.itemKey and row.itemKey.itemID==request.id then
          local price,count=tonumber(row.minPrice),tonumber(row.totalQuantity)
          if price and price>0 and count and count>0 then
            best=not best and price or math.min(best,price); quantity=quantity+count
          end
        end
      end
      if best then state.pending.lots[request.id]={best,quantity} end
      state.pending.scanned[request.id]=true
      state.current=state.current+1; state.index=state.index+1
      state.phase='standard'
      updateProgress(string.format(L('Обычный поиск: %d%% (%d/%d)'),math.floor(state.current*100/state.total),state.current,state.total))
      if state.index>state.total then completeScan()
      else C_Timer.After(0,function() scanStandardNext(token,false) end) end
    end
  elseif ((event=='AUCTION_ITEM_LIST_UPDATE' and state.backend=='legacy') or (event=='REPLICATE_ITEM_LIST_UPDATE' and state.backend=='replicate')) and state.phase=='processing' then
    if state.pending then state.pending.updatedDuringRead=true end
  elseif ((event=='AUCTION_ITEM_LIST_UPDATE' and state.backend=='legacy') or (event=='REPLICATE_ITEM_LIST_UPDATE' and state.backend=='replicate')) and state.phase=='waiting' then
    logEvent(L('Получено событие полного списка: ')..event)
    local ok,num
    if state.backend=='replicate' then ok,num=pcall(C_AuctionHouse.GetNumReplicateItems) else ok,num=pcall(GetNumAuctionItems,'list') end
    if not ok or type(num)~='number' then fail(L('Не удалось получить список лотов.')) return end
    logEvent(L('Полный список: ')..num..L(' лотов'))
    state.phase='processing'; state.total=num; state.current=0; state.index=1
    updateProgress(L('Получено лотов: ')..num..L('. Обработка…'))
    if num==0 then completeScan() else
      local token=state.token
      C_Timer.After(0,function() local success,err=pcall(processBatch,token); if not success then fail(L('Ошибка обработки: ')..tostring(err)) end end)
    end
  elseif (event=='TRADE_SKILL_SHOW' or event=='TRADE_SKILL_LIST_UPDATE' or event=='TRADE_SKILL_UPDATE') and WritHelperDB then
    local ok,err=pcall(captureTradeskill); if ok and bankOpen then captureBank() end; if not ok then logEvent(L('Ошибка профессии: ')..tostring(err)); msg(L('Не удалось прочитать профессию: ')..tostring(err)) elseif frame and frame:IsShown() then refresh() end
    if event=='TRADE_SKILL_SHOW' and C_Timer and C_Timer.After then
      C_Timer.After(1,function()
        local success,problem=pcall(captureTradeskill)
        if success and bankOpen then captureBank() end
        if not success then logEvent(L('Ошибка профессии: ')..tostring(problem)); msg(L('Не удалось прочитать профессию: ')..tostring(problem)) elseif frame and frame:IsShown() then refresh() end
      end)
    end
  end
end)
events:RegisterEvent('ADDON_LOADED'); events:RegisterEvent('PLAYER_LOGIN')
for _,event in ipairs({'QUEST_TURNED_IN','QUEST_LOG_UPDATE','QUEST_QUERY_COMPLETE','BANKFRAME_OPENED','BANKFRAME_CLOSED','BAG_UPDATE_DELAYED','PLAYERBANKSLOTS_CHANGED','AUCTION_HOUSE_SHOW','AUCTION_HOUSE_CLOSED','AUCTION_ITEM_LIST_UPDATE','REPLICATE_ITEM_LIST_UPDATE','AUCTION_HOUSE_BROWSE_RESULTS_UPDATED','AUCTION_HOUSE_BROWSE_RESULTS_ADDED','AUCTION_HOUSE_BROWSE_FAILURE','TRADE_SKILL_SHOW','TRADE_SKILL_LIST_UPDATE','TRADE_SKILL_UPDATE'}) do pcall(events.RegisterEvent,events,event) end
