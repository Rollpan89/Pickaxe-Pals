-- Shared type definitions. Plain types only, so this module loads outside Studio too.
-- PlayerData is the shape the saving milestone will store with ProfileStore.

export type OreId = string
export type UpgradeKind = "pickaxe" | "backpack"

-- What a placeable object can be. Properties owns the matching attribute names, the values each
-- one accepts, and the reader that turns them into one of these.
export type PlaceableKind = "ore" | "sellPad"

-- One ore node as WorldBuilder found it: the object that carries the kind, which is a BasePart or
-- a Model, and the ore it names. MiningService owns its health from there on.
export type OreNode = {
	id: string,
	oreId: OreId,
	instance: any,
	unlimited: boolean,
}

export type Ore = {
	id: OreId,
	name: string,
	health: number,
	value: number,
	respawnSeconds: number,
}

export type Layer = {
	id: string,
	name: string,
	unlockRebirth: number,
	ores: { Ore },
}

export type PickaxeTier = {
	tier: number,
	name: string,
	damage: number,
	cooldown: number,
	cost: number,
	unlockRebirth: number,
}

export type BackpackLevel = {
	level: number,
	name: string,
	capacity: number,
	cost: number,
}

-- Ore items currently carried, keyed by ore id. This lives in the session only: the
-- architecture document saves progress, and a backpack is one trip to the Sell Pad.
export type Backpack = { [OreId]: number }

export type PetCounts = { normal: number, shiny: number }

-- The saved profile. The keys match the architecture document's PlayerData exactly, because
-- the store fills missing keys in by name. Schema owns the matching runtime template.
export type PlayerData = {
	version: number,
	coins: number,
	gems: number,
	rebirths: number,
	pickaxeTier: number,
	backpackLevel: number,
	pets: { [string]: PetCounts },
	equipped: { string },
	pity: { [string]: number },
	daily: { lastLoginDay: number, streak: number, quests: { [string]: number } },
	lastSeen: number,
	receipts: { string },
	flags: { [string]: boolean },
}

-- The session half of a player: the saved profile above plus what is not saved.
export type Session = {
	data: PlayerData,
	backpack: Backpack,
}

-- What the server sends the client after a change. The client never edits these numbers.
export type StateSnapshot = {
	coins: number,
	gems: number,
	rebirths: number,
	pickaxeTier: number,
	backpackLevel: number,
	backpack: Backpack,
	capacity: number,
}

return {}
