--!strict
-- The story of the Wellmouth, told only through what previous expeditions
-- left behind. Entries are placed either at fixed story anchors (`Anchor`) or
-- scattered through matching zones each run (`Zones`).
--
-- The mystery is revealed in layers (`Layer`):
--   1  People have been here before.
--   2  Several expeditions never came back.
--   3  Some of them went deeper on purpose.
--   4  Something lives below.
--   5  The cave does not keep its shape.
--   6  The figures in the dark were explorers.
--   7  The Lamplighter came from the deep cave, and from them.
--   8  Every expedition repeats the one before it.
-- Nothing here explains everything. That is deliberate.

export type LoreEntry = {
	Id: string,
	Title: string,
	-- Journal | Note | Recording | Photograph | Carving | Remains | Device
	Kind: string,
	Expedition: string,
	Layer: number,
	Text: string,
	Anchor: string?,
	Zones: { string }?,
	-- Only appears in hidden rooms.
	Hidden: boolean?,
}

local Expeditions = {
	Ardent = "Ardent Survey, 1911",
	Lindqvist = "Lindqvist Society, 1958",
	Strata = "Deep Strata Project, 1994",
	BelowLine = "Below the Line, 2019",
	Builders = "Unknown",
	Current = "Expedition Five",
}

local Entries: { LoreEntry } = {
	-- Surface / Upper cave -----------------------------------------------
	{
		Id = "permit",
		Title = "Laminated Permit",
		Kind = "Note",
		Expedition = Expeditions.Current,
		Layer = 1,
		Anchor = "SurfaceCamp",
		Text = "WELLMOUTH CAVE SYSTEM — SURVEY ACCESS\nParty: 4. Duration: 2 days.\nNotes from the ranger, handwritten on the back:\n\"Fifth group to ask this decade. The others signed the same form. Rope's still hanging in the big shaft from the last lot — don't trust it, bring your own.\"",
	},
	{
		Id = "carved_initials",
		Title = "Initials in the Rock",
		Kind = "Carving",
		Expedition = "Several",
		Layer = 1,
		Anchor = "UpperHall",
		Text = "Names scratched into the wall at shoulder height, layered over each other.\nE.M. 1911.  K.L. '58.  A.O. + P.R. + J.K. 1994.  DANNY WAS HERE 2019 lol.\nBelow them, fresher than the rest, a fifth set of initials has been started and abandoned after the first letter.",
	},
	{
		Id = "belowline_phone1",
		Title = "Cracked Phone — Notes App",
		Kind = "Device",
		Expedition = Expeditions.BelowLine,
		Layer = 1,
		Zones = { "UpperCave", "Shaft" },
		Text = "ep 14 cave thing - shot list\n- entrance wide (golden hour!!)\n- shay on the rope, slow mo\n- marcus 'scared' reaction lol\n- find the old rope from the 90s ppl\n- find the OLDER rope?? ranger said there's 3\n\nedit: there are 4",
	},
	-- Shaft / Wet cave ---------------------------------------------------
	{
		Id = "ardent_fieldbook1",
		Title = "Field Book of E. Marrow, p.3",
		Kind = "Journal",
		Expedition = Expeditions.Ardent,
		Layer = 1,
		Anchor = "ShaftBottom",
		Text = "Descended the great shaft by rope, 812 feet by the line. Pryce swears it was nearer 900; he counted the knots twice and each count came out different. The air below is still and smells of rain that has not fallen.\nMen in good spirits. We have found no seam, but the Company wants a survey of the whole, and a survey of the whole they shall have.",
	},
	{
		Id = "lindqvist_photo1",
		Title = "Photograph: The Rope",
		Kind = "Photograph",
		Expedition = Expeditions.Lindqvist,
		Layer = 2,
		Zones = { "WetCave", "Shaft" },
		Text = "A flash photograph of the shaft bottom. Three ropes hang down into frame: one tarred hemp, rotten; one modern nylon; one the photographer must have just used.\nOn the back, in pencil: 'Marrow's rope. Whose is the second? Nobody has been down since 1911. — K.L.'",
	},
	{
		Id = "strata_tape1",
		Title = "Cassette: 'Day 1, Cistern'",
		Kind = "Recording",
		Expedition = Expeditions.Strata,
		Layer = 2,
		Anchor = "Cistern",
		Text = "[water, close] — Osei here. Day one. The cistern is exactly where the Lindqvist survey puts it, which is a relief, honestly. Paul's mapping the east passages.\n[pause]\nWe found their camp stove. And a stove older than theirs, under it. Joanna asked if we should be keeping count of these. I said that's literally the job.\n[long pause]\nJoanna, was that you?",
	},
	{
		Id = "wet_note_boots",
		Title = "Note Under a Pair of Boots",
		Kind = "Note",
		Expedition = Expeditions.Lindqvist,
		Layer = 2,
		Zones = { "WetCave" },
		Text = "Tomas's boots. He walked off in his socks around three this morning. We followed the wet prints for an hour.\nThey went in a circle. We went around twice before Ruth noticed the prints were only going one way — and they were ours.",
	},
	{
		Id = "ring_scratches",
		Title = "Tally Marks",
		Kind = "Carving",
		Expedition = "Unknown",
		Layer = 5,
		Anchor = "Ring",
		Text = "Tally marks scratched beside the skeleton, hundreds of them, in groups of five.\nThe last group is unfinished: four strokes and a long gouge trailing toward the floor.\nWhoever counted the laps stopped counting here.",
	},
	-- Deep cave ----------------------------------------------------------
	{
		Id = "ardent_fieldbook2",
		Title = "Field Book of E. Marrow, p.19",
		Kind = "Journal",
		Expedition = Expeditions.Ardent,
		Layer = 4,
		Anchor = "DeepHall",
		Text = "Something walks below us. Not a man — too heavy, too slow. You feel it in the soles before you hear it.\nThe men call it the Lamplighter, because Hask swore he saw lamps moving down the long passage after ours were out. Several lamps, all together, at a height no man carries a lamp.\nI have told them it is water in the rock. It is not water in the rock.",
	},
	{
		Id = "strata_tape2",
		Title = "Cassette: 'The Corridor'",
		Kind = "Recording",
		Expedition = Expeditions.Strata,
		Layer = 5,
		Zones = { "DeepCave" },
		Text = "Reyes, mapping log. The passage south of the deep hall is one hundred and ninety-two metres on the Lindqvist survey. Straight. Level. You can see the far end with a good lamp.\nI have been walking it for forty minutes.\n[footsteps]\nSame rock. Same crack in the ceiling shaped like a seven. Same— I put a chalk mark on the wall. I'm looking at my chalk mark.\nI haven't turned around.",
	},
	{
		Id = "deep_remains1",
		Title = "Remains with a Lantern",
		Kind = "Remains",
		Expedition = Expeditions.Ardent,
		Layer = 2,
		Zones = { "DeepCave" },
		Text = "A skeleton in a wool coat, sitting upright against the wall as if resting. Its lantern is still clutched in one hand, glass intact, the wick burnt to nothing.\nIn the coat pocket: a Company pay slip and a note in pencil. 'Not lost. Waiting for the others to come back up for me. They said they would come back up.'",
	},
	{
		Id = "belowline_phone2",
		Title = "Phone — Livestream Chat Export",
		Kind = "Device",
		Expedition = Expeditions.BelowLine,
		Layer = 6,
		Zones = { "DeepCave", "WetCave" },
		Text = "[chat log, 02:14:33]\nxXvoidXx: who's the 4th guy\nmilk_tea: ??\nxXvoidXx: theres 4 lights. danny shay marcus and who\nnotabot22: yo someone's standing behind marcus\nmilk_tea: thats a rock\nnotabot22: rocks dont turn their head\n[stream ended]",
	},
	{
		Id = "deep_footprints",
		Title = "Prints in the Silt",
		Kind = "Note",
		Expedition = Expeditions.Current,
		Layer = 4,
		Zones = { "DeepCave" },
		Hidden = true,
		Text = "Your own note, scribbled on the back of the permit map:\nFootprints in the silt. Bare. Long — longer than my forearm. Two toes dragging.\nThe stride is wrong. Each print is a full body length from the last.\nThey go down. They come back up. The ones coming back are deeper in the mud.",
	},
	-- Explorer camp ------------------------------------------------------
	{
		Id = "lindqvist_journal",
		Title = "K. Lindqvist, Expedition Journal",
		Kind = "Journal",
		Expedition = Expeditions.Lindqvist,
		Layer = 3,
		Anchor = "Camp",
		Text = "We have made camp where Marrow's men made theirs. Their tins are stacked as neatly as ours. Ruth says that is a sign of discipline. I think it's a sign that they, too, believed they'd be coming back for them.\nTomas wants to turn around. Berg and I want to go on. Marrow's last page says the bottom is 'full of people'. I need to know what he meant.\nWe vote in the morning. I already know how it will go. I think I knew before we came.",
	},
	{
		Id = "strata_tape3",
		Title = "Cassette: 'Camp Two'",
		Kind = "Recording",
		Expedition = Expeditions.Strata,
		Layer = 3,
		Anchor = "Camp",
		Text = "Osei. We've found the Lindqvist camp — and it's laid out exactly like ours. Exactly. Their tent's on the left, stove in the middle, ropes coiled on the right.\nNobody planned that. We just... unpacked.\nPaul and Joanna want to go back up. I've told them we're going down. We're going to find out where everyone went.\n[quietly] I don't remember deciding that.",
	},
	{
		Id = "camp_photo_group",
		Title = "Photograph: Group Portrait",
		Kind = "Photograph",
		Expedition = Expeditions.Lindqvist,
		Layer = 6,
		Zones = { "ExplorerCamp" },
		Text = "Four people in caving suits, smiling, lamps on. Lindqvist, Berg, Aldane, Holm, written underneath.\nBehind them, at the edge of the flash, a fifth figure stands in the passage, perfectly dark, the shape of a person in a caving suit.\nSomeone has circled it in pen and written: 'Tomas?? He was taking the photo.'",
	},
	{
		Id = "belowline_gopro",
		Title = "GoPro, Battery Dead",
		Kind = "Device",
		Expedition = Expeditions.BelowLine,
		Layer = 6,
		Zones = { "ExplorerCamp", "DeepCave" },
		Text = "The camera's case is scratched with a message, as if with a key:\nDONT FOLLOW THE TALL ONE WITH THE LIGHTS\nDONT FOLLOW SHAY. SHAY IS AT THE TOP. SHAY WAS ALWAYS AT THE TOP.\nWHO IS DOWN HERE WITH US",
	},
	{
		Id = "camp_supplylist",
		Title = "Supply Inventory",
		Kind = "Note",
		Expedition = Expeditions.Strata,
		Layer = 8,
		Zones = { "ExplorerCamp" },
		Hidden = true,
		Text = "Inventory, Camp 2:\n4 sleeping bags (ours)\n4 sleeping bags (Lindqvist)\n4 bedrolls (Ardent)\n4 sleeping bags — new, unopened, packaging dated next year.\nWho brought these? We are only three.",
	},
	-- The monster ---------------------------------------------------------
	{
		Id = "lair_lamps",
		Title = "Pile of Dead Lamps",
		Kind = "Remains",
		Expedition = "Several",
		Layer = 7,
		Anchor = "Hollow",
		Text = "Headlamps. Dozens. Carbide lamps, brass lanterns, plastic LED strips, a phone with its torch-glass smashed — all heaped in the hollow like a nest.\nEvery strap has been torn, not cut.\nSome of the older lamps are fused to scraps of something pale and smooth, as though they had been grown into rather than worn.",
	},
	{
		Id = "ardent_fieldbook3",
		Title = "Field Book of E. Marrow, p.31",
		Kind = "Journal",
		Expedition = Expeditions.Ardent,
		Layer = 7,
		Zones = { "DeepCave", "ExplorerCamp" },
		Text = "Hask went down alone to bring back the lamps he saw. He did not return. Last night we heard him above us, calling for the rope.\nThis morning the Lamplighter passed the camp. I lay still and counted its steps. Before it went, it stopped and turned its head toward us, and one of the lights on its head was Hask's lamp. I'd know the dent in that reflector anywhere. I made it.",
	},
	-- The Old Works -------------------------------------------------------
	{
		Id = "builders_mural1",
		Title = "Relief: The Line",
		Kind = "Carving",
		Expedition = Expeditions.Builders,
		Layer = 3,
		Anchor = "Threshold",
		Text = "A relief carved across the arch, older than any tool mark in the upper cave.\nFigures descend a single vertical line, each holding a small flame. At the bottom they stand together in a great round space.\nOn the right side of the arch the same figures climb back up the line.\nThere are fewer of them. They hold no flames. Their faces have been chiselled away.",
	},
	{
		Id = "builders_mural2",
		Title = "Relief: The Tall One",
		Kind = "Carving",
		Expedition = Expeditions.Builders,
		Layer = 7,
		Anchor = "Colonnade",
		Text = "A pillar carved on every side with the same tall figure: long arms, bowed head, and a crown of small flames.\nAt its feet, little people kneel and offer up their flames one by one.\nThe figure is shown at the bottom of the pillar small, like the others. Halfway up it is taller. At the top it has many flames, and no face.",
	},
	{
		Id = "strata_tape4",
		Title = "Cassette: 'Osei, alone'",
		Kind = "Recording",
		Expedition = Expeditions.Strata,
		Layer = 6,
		Zones = { "Ancient" },
		Text = "[breathing] Paul's gone back for Joanna. She was standing in the side passage for an hour. Not moving. When he got close she wasn't— it wasn't her, it was the shape of her. Like a shadow that forgot the person.\nShe's also at camp. Paul radioed. She's at camp and she's asleep.\nI think the people who stand in the dark are the parts of us that the cave keeps. I think it keeps a copy of everyone who goes past.",
	},
	{
		Id = "ancient_hidden_eye",
		Title = "Carving: The Open Eye",
		Kind = "Carving",
		Expedition = Expeditions.Builders,
		Layer = 5,
		Zones = { "Ancient" },
		Hidden = true,
		Text = "Hidden behind the fallen slab: a single carved eye, wide open, ringed by concentric passages like the rings of a tree.\nThe passages are a map. You recognise the shaft, the cistern, the ring.\nIn the carving the passages are drawn in a different arrangement — and in the margin someone has carved it again, and again, each version different, as if keeping up with it.",
	},
	-- Final chamber -------------------------------------------------------
	{
		Id = "final_marrow",
		Title = "Field Book of E. Marrow, Last Page",
		Kind = "Journal",
		Expedition = Expeditions.Ardent,
		Layer = 8,
		Anchor = "FinalChamber",
		Text = "The bottom is full of people.\nNot bodies — I mean that too, there are bodies — but people. Standing between the old camps. They do not move while you look at them. They are all of us. Pryce is here twice.\nI understand now why the stoves were stacked. We do not come back up. We come back down. Again and again, with new rope and new names, and we set our things down where we set them last time.\nIf you are reading this, you have already read it before.",
	},
	{
		Id = "final_lindqvist",
		Title = "Photograph: Ourselves",
		Kind = "Photograph",
		Expedition = Expeditions.Lindqvist,
		Layer = 8,
		Anchor = "FinalChamber",
		Text = "A photograph of the great chamber. In the middle of it, Lindqvist's team, lamps lit, looking up at the camera.\nThe photograph was found in Lindqvist's own camera, at the top of the chamber, where she was standing.\nOn the back: 'Taken at 11:40. We arrived at 12:15.'",
	},
	{
		Id = "final_strata",
		Title = "Cassette: 'Last'",
		Kind = "Recording",
		Expedition = Expeditions.Strata,
		Layer = 7,
		Anchor = "FinalChamber",
		Text = "[very close, whispering] It's here. It's standing in the middle of all of them like it's — guarding them. Or keeping them.\nIt has Paul's lamp. It has Lindqvist's. It has a carbide lamp from before any of us.\nI think it was the first one to come down. I think it was the first one who wouldn't leave. I think it's been collecting lights ever since, so it's never in the dark.\n[steps, enormous, close] — oh God it's—",
	},
	{
		Id = "final_belowline",
		Title = "Phone — Draft Message",
		Kind = "Device",
		Expedition = Expeditions.BelowLine,
		Layer = 6,
		Anchor = "FinalChamber",
		Text = "Draft, never sent:\n'mum i found the way out, theres a chimney past the big room, you climb and you can feel wind. i'm going up. if i come home and i seem different please don't'\n\nThe message ends there. The phone's last location ping, in its settings, is the trailhead car park.",
	},
	{
		Id = "final_current",
		Title = "Journal — Expedition Five",
		Kind = "Journal",
		Expedition = Expeditions.Current,
		Layer = 8,
		Anchor = "FinalChamber",
		Text = "A new notebook, the kind your expedition bought. The handwriting is yours.\nDay 1. Entrance. Rope still hanging from the last lot.\nDay 1. Shaft. Further than it looked.\nDay 1. Walked the loop twice before I noticed.\nDay 1. The corridor.\nDay 1. The camp is set up like ours.\nThe last line is written over and over, down the whole final page:\nI should not be down here.",
	},
	{
		Id = "final_hidden_tent",
		Title = "Photograph: Surface Camp",
		Kind = "Photograph",
		Expedition = Expeditions.Current,
		Layer = 8,
		Zones = { "FinalChamber" },
		Hidden = true,
		Text = "A photograph of your own camp on the surface, at dusk. Your tent, your truck, your gear laid out on the tarp.\nSomeone is standing beside the tent, facing the cave, lamp on.\nYou weren't there when this was taken. You know, because it's you.",
	},
	-- Escape --------------------------------------------------------------
	{
		Id = "escape_marks",
		Title = "Chalk Arrows",
		Kind = "Carving",
		Expedition = "Several",
		Layer = 3,
		Anchor = "ChimneyBase",
		Text = "Arrows chalked on the rock, pointing up the chimney. Dozens of them, in different hands, different decades.\nSomeone has crossed out every one of them except the newest.\nBeside it, in the same hand that crossed out the others: 'IT LETS YOU GO. THAT'S THE WORST PART.'",
	},
}

local ById: { [string]: LoreEntry } = {}
for _, entry in Entries do
	ById[entry.Id] = entry
end

return {
	Entries = Entries,
	ById = ById,
	Expeditions = Expeditions,
	LayerNames = {
		"People have been here before.",
		"Not everyone came back.",
		"Some went deeper on purpose.",
		"Something lives below.",
		"The cave does not keep its shape.",
		"The figures in the dark were explorers.",
		"The Lamplighter.",
		"Again.",
	},
}
