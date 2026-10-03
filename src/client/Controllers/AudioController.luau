--!strict
-- Every sound the player hears goes through here.
--
--  * Logical names resolve through SoundLibrary (real asset -> fallback).
--  * Sound groups per category; deep zones muffle everything slightly.
--  * Zone ambience: looped beds crossfade on zone change, and a scheduler
--    places randomized one-shots in 3D around the listener with weights,
--    cooldowns, a global gap, volume/pitch jitter and a bias for sounds that
--    come from behind.
--  * Silence(): the Horror Director can make the cave go quiet.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local AudioConfig = require(Shared.Config.AudioConfig)
local SoundLibrary = require(Shared.Config.SoundLibrary)
local ZoneConfig = require(Shared.Config.ZoneConfig)
local Weighted = require(Shared.Utility.Weighted)

local LocalPlayer = Players.LocalPlayer

export type PlayOptions = {
	Volume: number?,
	Pitch: number?,
	Group: string?,
	MinDistance: number?,
	MaxDistance: number?,
	-- Apply the default random jitter (on by default).
	Jitter: boolean?,
	Looped: boolean?,
	Delay: number?,
	-- Extra effect instances to clone into the sound (echo, reverb, ...).
	Effects: { Instance }?,
}

type Resolved = { Id: string, Volume: number, Pitch: number, Looped: boolean }

local AudioController = {}
AudioController.__index = AudioController

type State = {
	Groups: { [string]: SoundGroup },
	_rng: Random,
	_warned: { [string]: boolean },
	_beds: { [string]: Sound },
	_zone: string,
	_nextAmbient: number,
	_cooldowns: { [string]: number },
	_active: number,
	_silencedUntil: number,
	_muffle: { EqualizerSoundEffect },
	_folder: Folder?,
	_zoneChangedAt: number,
}
export type AudioController = typeof(setmetatable({} :: State, AudioController))

local function cleanupWhenDone(sound: Sound, holder: Instance?)
	local function finish()
		if holder then
			holder:Destroy()
		else
			sound:Destroy()
		end
	end
	sound.Ended:Once(finish)
	-- Safety net for sounds that never load.
	task.delay(30, function()
		if sound.Parent and not sound.Looped then
			finish()
		end
	end)
end

local function listenerCFrame(): CFrame
	local camera = Workspace.CurrentCamera
	return if camera then camera.CFrame else CFrame.identity
end

function AudioController.Init(self: AudioController)
	local folder = Instance.new("Folder")
	folder.Name = "ClientSounds"
	folder.Parent = SoundService
	self._folder = folder
	for name, volume in AudioConfig.Groups do
		local group = Instance.new("SoundGroup")
		group.Name = name
		group.Volume = volume
		group.Parent = SoundService
		self.Groups[name] = group
		if name == "Ambient" or name == "Footsteps" or name == "Effects" then
			local eq = Instance.new("EqualizerSoundEffect")
			eq.LowGain = 0
			eq.MidGain = 0
			eq.HighGain = 0
			eq.Parent = group
			table.insert(self._muffle, eq)
		end
	end
end

function AudioController.Start(self: AudioController)
	local function onZone()
		local zone = LocalPlayer:GetAttribute(Constants.Attributes.Zone)
		if type(zone) == "string" and zone ~= self._zone then
			self:_setZone(zone)
		end
	end
	LocalPlayer:GetAttributeChangedSignal(Constants.Attributes.Zone):Connect(onZone)
	onZone()
	if self._zone == "" then
		self:_setZone("Surface")
	end
	RunService.Heartbeat:Connect(function()
		self:_updateMuffle()
		self:_tickAmbient()
	end)
end

-- Resolution ----------------------------------------------------------------------

function AudioController.Resolve(self: AudioController, name: string): Resolved?
	local spec = SoundLibrary[name]
	if not spec then
		if not self._warned[name] then
			self._warned[name] = true
			warn(`[Audio] Unknown sound '{name}'`)
		end
		return nil
	end
	if spec.Id and spec.Id ~= "" then
		return { Id = spec.Id, Volume = spec.Volume or 1, Pitch = spec.Pitch or 1, Looped = spec.Looped == true }
	end
	local fallback = spec.Fallback
	if fallback then
		return { Id = fallback.Id, Volume = fallback.Volume or 1, Pitch = fallback.Pitch or 1, Looped = spec.Looped == true }
	end
	if RunService:IsStudio() and not self._warned[name] then
		self._warned[name] = true
		print(`[Audio] '{name}' has no asset assigned (SoundLibrary); it will be silent.`)
	end
	return nil
end

function AudioController.HasSound(self: AudioController, name: string): boolean
	local spec = SoundLibrary[name]
	return spec ~= nil and ((spec.Id ~= nil and spec.Id ~= "") or spec.Fallback ~= nil)
end

function AudioController._makeSound(self: AudioController, name: string, opts: PlayOptions?): Sound?
	local resolved = self:Resolve(name)
	if not resolved then
		return nil
	end
	local o: PlayOptions = opts or {}
	local rng = self._rng
	local jitter = o.Jitter ~= false
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = resolved.Id
	local volume = resolved.Volume * (o.Volume or 1)
	local pitch = resolved.Pitch * (o.Pitch or 1)
	if jitter then
		volume *= rng:NextNumber(AudioConfig.DefaultVolumeJitter.Min, AudioConfig.DefaultVolumeJitter.Max)
		pitch *= rng:NextNumber(AudioConfig.DefaultPitchJitter.Min, AudioConfig.DefaultPitchJitter.Max)
	end
	sound.Volume = volume
	sound.PlaybackSpeed = pitch
	sound.Looped = o.Looped or resolved.Looped
	sound.SoundGroup = self.Groups[o.Group or "Effects"]
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = o.MinDistance or 8
	sound.RollOffMaxDistance = o.MaxDistance or 160
	if o.Effects then
		for _, effect in o.Effects do
			effect:Clone().Parent = sound
		end
	end
	return sound
end


-- Playback ------------------------------------------------------------------------

-- Non-positional (heard "in the head"): UI, own breathing, own footsteps.
function AudioController.Play2D(self: AudioController, name: string, opts: PlayOptions?): Sound?
	local sound = self:_makeSound(name, opts)
	if not sound then
		return nil
	end
	sound.Parent = self._folder
	local delay = opts and opts.Delay
	if delay then
		task.delay(delay, function()
			if sound.Parent then
				sound:Play()
			end
		end)
	else
		sound:Play()
	end
	if not sound.Looped then
		cleanupWhenDone(sound)
	end
	return sound
end

-- Positional one-shot at a world position.
function AudioController.PlayAt(self: AudioController, name: string, position: Vector3, opts: PlayOptions?): Sound?
	local sound = self:_makeSound(name, opts)
	if not sound then
		return nil
	end
	local holder = Instance.new("Attachment")
	holder.Name = "Sound_" .. name
	holder.WorldPosition = position
	holder.Parent = Workspace.Terrain
	sound.Parent = holder
	local delay = opts and opts.Delay
	if delay then
		task.delay(delay, function()
			if sound.Parent then
				sound:Play()
			end
		end)
	else
		sound:Play()
	end
	if not sound.Looped then
		cleanupWhenDone(sound, holder)
	end
	return sound
end

-- Sound that follows an instance (a part or attachment).
function AudioController.PlayAttached(self: AudioController, name: string, parent: Instance, opts: PlayOptions?): Sound?
	local sound = self:_makeSound(name, opts)
	if not sound then
		return nil
	end
	sound.Parent = parent
	sound:Play()
	if not sound.Looped then
		cleanupWhenDone(sound)
	end
	return sound
end

-- Plays the sound several times with small gaps (e.g. a run of footsteps).
function AudioController.Burst(self: AudioController, name: string, position: Vector3, count: number, gap: NumberRange, opts: PlayOptions?, drift: Vector3?)
	task.spawn(function()
		local p = position
		for _ = 1, count do
			self:PlayAt(name, p, opts)
			if drift then
				p += drift
			end
			task.wait(self._rng:NextNumber(gap.Min, gap.Max))
		end
	end)
end

-- Zone ambience ---------------------------------------------------------------------

function AudioController._setZone(self: AudioController, zone: string)
	self._zone = zone
	self._zoneChangedAt = os.clock()
	local zoneDef = ZoneConfig.Get(zone)
	SoundService.AmbientReverb = zoneDef.Reverb
	local ambience = AudioConfig.Zones[zone]
	local wanted: { [string]: number } = {}
	if ambience then
		for _, bed in ambience.Beds do
			wanted[bed.Sound] = bed.Volume
		end
	end
	local fade = TweenInfo.new(AudioConfig.BedFade, Enum.EasingStyle.Sine)
	-- Fade out beds that are no longer wanted.
	for name, sound in self._beds do
		if not wanted[name] then
			self._beds[name] = nil
			local tween = TweenService:Create(sound, fade, { Volume = 0 })
			tween.Completed:Once(function()
				sound:Destroy()
			end)
			tween:Play()
		end
	end
	-- Fade in new beds / retarget existing ones.
	for name, volume in wanted do
		local sound = self._beds[name]
		if not sound then
			local created = self:_makeSound(name, { Group = "Ambient", Looped = true, Jitter = false })
			if created then
				created.Volume = 0
				created.Parent = self._folder
				created:Play()
				self._beds[name] = created
				sound = created
			end
		end
		if sound then
			local resolved = self:Resolve(name)
			local target = volume * (if resolved then resolved.Volume else 1)
			TweenService:Create(sound, fade, { Volume = target }):Play()
		end
	end
	self._nextAmbient = os.clock() + self._rng:NextNumber(3, 8)
end

function AudioController._updateDepthBeds(self: AudioController, depth: number)
	local blend = AudioConfig.DepthBeds[self._zone]
	-- Let the zone crossfade finish before taking over the bed volumes.
	if not blend or os.clock() - self._zoneChangedAt < AudioConfig.BedFade then
		return
	end
	local t = math.clamp((depth - blend.Depth.Min) / (blend.Depth.Max - blend.Depth.Min), 0, 1)
	for name, range in blend.Beds do
		local sound = self._beds[name]
		if sound then
			local resolved = self:Resolve(name)
			local target = (range.Shallow + (range.Deep - range.Shallow) * t) * (if resolved then resolved.Volume else 1)
			sound.Volume += (target - sound.Volume) * 0.05
		end
	end
end

function AudioController._updateMuffle(self: AudioController)
	local depth = (LocalPlayer:GetAttribute(Constants.Attributes.Depth) :: number?) or 0
	self:_updateDepthBeds(depth)
	local cfg = AudioConfig.DepthMuffle
	local t = math.clamp((depth - cfg.StartDepth) / (cfg.FullDepth - cfg.StartDepth), 0, 1)
	for _, eq in self._muffle do
		eq.HighGain = cfg.HighGainAtFull * t
	end
end


-- Picks a world position for an ambient one-shot around the listener.
function AudioController.AmbientPosition(self: AudioController, distance: NumberRange, behindBias: number?, above: boolean?): Vector3
	local rng = self._rng
	local cf = listenerCFrame()
	if above then
		return cf.Position + Vector3.new(rng:NextNumber(-6, 6), rng:NextNumber(4, 10), rng:NextNumber(-6, 6))
	end
	local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
	if look.Magnitude < 0.01 then
		look = Vector3.zAxis
	end
	look = look.Unit
	local angle: number
	if behindBias and rng:NextNumber() < behindBias then
		-- Somewhere behind: 180 deg +/- 60 deg.
		angle = math.pi + rng:NextNumber(-math.pi / 3, math.pi / 3)
	else
		angle = rng:NextNumber(-math.pi, math.pi)
	end
	local rotated = CFrame.Angles(0, angle, 0):VectorToWorldSpace(look)
	local d = rng:NextNumber(distance.Min, distance.Max)
	return cf.Position + rotated * d + Vector3.new(0, rng:NextNumber(-3, 4), 0)
end

function AudioController._tickAmbient(self: AudioController)
	local now = os.clock()
	if now < self._nextAmbient or now < self._silencedUntil then
		return
	end
	local ambience = AudioConfig.Zones[self._zone]
	if not ambience then
		return
	end
	local rng = self._rng
	self._nextAmbient = now + rng:NextNumber(ambience.Gap.Min, ambience.Gap.Max)
	if self._active >= AudioConfig.MaxConcurrent then
		return
	end
	local eligible = {}
	for _, entry in ambience.Pool do
		if now >= (self._cooldowns[entry.Sound] or 0) and self:HasSound(entry.Sound) then
			table.insert(eligible, entry)
		end
	end
	local entry = Weighted.pick(eligible, function(e)
		return e.Weight
	end, rng)
	if not entry then
		return
	end
	self._cooldowns[entry.Sound] = now + entry.Cooldown
	local position = self:AmbientPosition(entry.Distance, entry.BehindBias, entry.Above)
	local volume = if entry.Volume then rng:NextNumber(entry.Volume.Min, entry.Volume.Max) else 1
	local pitch = if entry.Pitch then rng:NextNumber(entry.Pitch.Min, entry.Pitch.Max) else 1
	local opts: PlayOptions = {
		Group = "Ambient",
		Volume = volume,
		Pitch = pitch,
		MinDistance = 10,
		MaxDistance = entry.Distance.Max * 1.6 + 20,
	}
	self._active += 1
	task.delay(4, function()
		self._active -= 1
	end)
	if entry.Burst then
		local drift = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * 2.4
		self:Burst(entry.Sound, position, entry.Burst, NumberRange.new(0.45, 0.65), opts, drift)
	else
		self:PlayAt(entry.Sound, position, opts)
	end
end

-- Cuts ambience for a while. Silence is a horror event in its own right.
function AudioController.Silence(self: AudioController, seconds: number)
	self._silencedUntil = os.clock() + seconds
	local fadeOut = TweenInfo.new(AudioConfig.BedFadeOutWhileSilenced, Enum.EasingStyle.Sine)
	local group = self.Groups.Ambient
	if group then
		TweenService:Create(group, fadeOut, { Volume = AudioConfig.Groups.Ambient * 0.08 }):Play()
		task.delay(seconds, function()
			TweenService:Create(group, TweenInfo.new(6, Enum.EasingStyle.Sine), { Volume = AudioConfig.Groups.Ambient }):Play()
		end)
	end
end

function AudioController.SetGroupVolume(self: AudioController, group: string, volume: number, time: number?)
	local g = self.Groups[group]
	if g then
		TweenService:Create(g, TweenInfo.new(time or 1), { Volume = volume }):Play()
	end
end

function AudioController.GetZone(self: AudioController): string
	return self._zone
end


local instance: AudioController = setmetatable({
	Groups = {},
	_rng = Random.new(),
	_warned = {},
	_beds = {},
	_zone = "",
	_nextAmbient = 0,
	_cooldowns = {},
	_active = 0,
	_silencedUntil = 0,
	_muffle = {},
	_folder = nil,
	_zoneChangedAt = 0,
} :: State, AudioController)

return instance
