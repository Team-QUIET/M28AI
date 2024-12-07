---
--- Generated by EmmyLua(https://github.com/EmmyLua)
--- Created by maudlin27.
--- DateTime: 04/12/2024 22:44
---
function AIChat(group, text, sender)
    AISendChatMessage({group}, {to = group, Chat = true, text = text, aisender = sender})

    --[[if false and text then
        if import("/lua/ui/game/taunt.lua").CheckForAndHandleTaunt(text, sender) then
            return
        end
        ChatTo:Set(group)
        msg = { to = ChatTo(), Chat = true }
        msg.text = text
        msg.aisender = sender
        local armynumber = GetArmyData(sender)
        if ChatTo() == 'allies' then
            AISendChatMessage(FindAllies(armynumber), msg)
        elseif ChatTo() == 'enemies' then
            AISendChatMessage(FindEnemies(armynumber), msg)
        elseif type(ChatTo()) == 'number' then
            AISendChatMessage({ChatTo()}, msg)
        else
            AISendChatMessage(nil, msg)
        end
    end--]]
end