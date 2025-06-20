include("shared.lua")

function ENT:Initialize()
    self.LightColor = self:GetColor()
    self.LightProperties = {
        r = self.LightColor.r,
        g = self.LightColor.g,
        b = self.LightColor.b,
        brightness = 3,
        Decay = 512,
        Size = 128
    }
end

function ENT:OnColorChanged(color)
    self.LightProperties = {
        r = color.r,
        g = color.g,
        b = color.b,
        brightness = 3,
        Decay = 512,
        Size = 128
    }
end

function ENT:Draw()
    if self:GetNWBool("FullyClosed") then
        // Dont draw anything at all if the door is closed
        return
    end

    if halo.RenderedEntity() == self then
        self:DrawModel()
        return
    end

    -- reusing screeneffect texture, no need to create a new rendertarget
    local blur_texture = render.GetScreenEffectTexture(1)
    render.UpdateScreenEffectTexture(1) -- update current screen data

    -- blur rt
    local cache = render.GetRenderTarget()
    render.BlurRenderTarget(blur_texture, 5, 5, 1)
    render.SetRenderTarget(cache)  -- blurrendertarget is fucked, gotta do this

    -- massive block of stencil setup
    render.ClearStencil()
    render.SetStencilWriteMask(255)
    render.SetStencilTestMask(255)
    render.SetStencilReferenceValue(0)
    render.SetStencilCompareFunction(STENCIL_ALWAYS)
    render.SetStencilPassOperation(STENCIL_KEEP)
    render.SetStencilFailOperation(STENCIL_KEEP)
    render.SetStencilZFailOperation(STENCIL_KEEP)
    render.SetStencilEnable(true)

    -- k time to do the shits
    -- task: replace behind of model with a blurred version of the background

    -- first, we need to setup the area in the stencil buffer
    -- where our texture will be rendered
    render.SetStencilPassOperation(STENCIL_REPLACE)
    render.SetStencilReferenceValue(1)

    -- draw our model
    -- before, you IGNORED z when drawing, but we dont actually want to do that
    -- in this situation we still want to obey the depth buffer, but not write to it
    -- othherwise that will make it draw through walls
    render.OverrideDepthEnable(true, false)
    self:DrawModel()
    render.OverrideDepthEnable(false, false)

    -- now, render our image in screenspace only on top of where our model was
    render.SetStencilCompareFunction(STENCIL_EQUAL)
    render.SetStencilPassOperation(STENCIL_KEEP)

    render.DrawTextureToScreen(blur_texture)

    render.SetStencilEnable(false)

    -- Finally draw the actual door model
    self:DrawModel()
end

function ENT:Think()
    self:FrameAdvance()

    if self._IsPlayingOpenAnim then
        local cycle = self:GetCycle()
        print("Timedoor open anim cycle:", cycle)  -- debug output

        if cycle >= 1 then
            local idleSeq = self:LookupSequence("idle")
            print("Idle seq index:", idleSeq)
            if idleSeq and idleSeq >= 0 then
                self:ResetSequence(idleSeq)
                self:SetCycle(0)
                self:SetPlaybackRate(1)
                self.AutomaticFrameAdvance = false -- stop advancing frames on idle
            else
                print("Timedoor: idle animation missing!")
            end
            self._IsPlayingOpenAnim = false
        end
    end

    local curColor = self:GetColor()
    if curColor ~= self._lastColor then
        self._lastColor = curColor
        self:OnColorChanged(curColor)
    end

    local dlight = DynamicLight(self:EntIndex())

    if dlight and self:GetNWBool("Open") then
        dlight.pos = self:GetPos() + self:GetUp() * 35
        dlight.r = self.LightProperties.r
        dlight.g = self.LightProperties.g
        dlight.b = self.LightProperties.b
        dlight.brightness = self.LightProperties.brightness
        dlight.Decay = self.LightProperties.Decay
        dlight.Size = self.LightProperties.Size
        dlight.dietime = CurTime()+0.1
    end

    self:NextThink(CurTime())
    return true
end

net.Receive("Timedoor_PlayOpenAnim", function()
    local ent = net.ReadEntity()
    if not IsValid(ent) then return end

    ent:SetNoDraw(false) -- show the door

    local seq = ent:LookupSequence("open")
    if IsValid(seq) then
        ent:ResetSequence(seq)
        ent:SetCycle(0)
        ent:SetPlaybackRate(1)
        ent._IsPlayingOpenAnim = true -- flag for tracking
    else
        print("Timedoor: 'open' animation not found on client!")
    end
end)
