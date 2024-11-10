Config = {}

---------------------------------
-- safe deposit box
---------------------------------
Config.StorageMaxWeight = 500000
Config.StorageMaxSlots = 5

---------------------------------
-- settings
---------------------------------
Config.Keybind    = 'J'
Config.OpenTime   = 9 -- hrs : 24hour clock
Config.CloseTime  = 17 -- hrs : 24hour clock
Config.AlwaysOpen = true -- sets bank always open if set to true
Config.UseTarget  = false
Config.OneBank = false -- turn to true to use one banking in the server.

---------------------------------
-- bank locations
---------------------------------
Config.BankLocations = {
    {
        name = 'Valentine Bank',
        bankid = 'valbank',
        coords = vector3(-308.4189, 775.8842, 118.7017),
	    npcmodel = 'S_M_M_BankClerk_01',
	    npccoords = vector4(-308.14, 773.98, 118.7, 4.75),
        showblip = true,
        blipsprite = 'blip_proc_bank',
        blipscale = 0.2
    },
    {
        name = 'Rhodes Bank',
        bankid = 'rhobank',
        coords = vector3(1292.307, -1301.539, 77.04012),
	    npcmodel = 'S_M_M_BankClerk_01',
	    npccoords = vector4(1291.22, -1303.28, 77.04, 316.53),
        showblip = true,
        blipsprite = 'blip_proc_bank',
        blipscale = 0.2
    },
    {
        name = 'Saint Denis Bank',
        bankid = 'bank',
        coords = vector3(2644.579, -1292.313, 52.24956),
	npcmodel = 'S_M_M_BankClerk_01',
	npccoords = vector4(2644.75, -1294.15, 52.25, 17.11),
        showblip = true,
        blipsprite = 'blip_proc_bank', 
        blipscale = 0.2
    },
    {
        name = 'Blackwater Bank',
        bankid = 'blkbank',
        coords = vector3(-813.1633, -1277.486, 43.63771),
	npcmodel = 'S_M_M_BankClerk_01',
	npccoords = vector4(-813.2, -1275.38, 43.64, 173.1),
        showblip = true,
        blipsprite = 'blip_proc_bank', 
        blipscale = 0.2
    },
    {
        name = 'Armadillo Bank',
        bankid = 'armbank',
        coords = vector3(-3666.25, -2626.57, -13.59),
	npcmodel = 'S_M_M_BankClerk_01',
	npccoords = vector4(-3666.28, -2628.69, -13.59, 359.78),
        showblip = true,
        blipsprite = 'blip_proc_bank', 
        blipscale = 0.2
    },
}

---------------------------------
-- bank doors
---------------------------------
Config.BankDoors = {

    -- valentine ( open = 0 / locked = 1)
    { door = 2642457609, state = 0 }, -- main door
    { door = 3886827663, state = 0 }, -- main door
    { door = 1340831050, state = 1 }, -- bared right
    { door = 2343746133, state = 1 }, -- bared left
    { door = 334467483,  state = 1 }, -- inner door1
    { door = 3718620420, state = 1 }, -- inner door2
    { door = 576950805,  state = 1 }, -- valut

    -- rhodes  ( open = 0 / locked = 1)
    { door = 3317756151, state = 0 }, -- main door
    { door = 3088209306, state = 0 }, -- main door
    { door = 2058564250, state = 1 }, -- inner door1
    { door = 3142122679, state = 1 }, -- inner door2
    { door = 1634148892, state = 1 }, -- inner door3
    { door = 3483244267, state = 1 }, -- valut

    -- saint denis ( open = 0 / locked = 1)
    { door = 2158285782, state = 0 }, -- main door
    { door = 1733501235, state = 0 }, -- main door
    { door = 2089945615, state = 0 }, -- main door
    { door = 2817024187, state = 0 }, -- main door
    { door = 1830999060, state = 1 }, -- inner private door
    { door = 965922748,  state = 1 }, -- manager door
    { door = 1634115439, state = 1 }, -- manager door
    { door = 1751238140, state = 1 }, -- vault

    -- blackwater
    { door = 531022111,  state = 0 }, -- main door
    { door = 2117902999, state = 1 }, -- inner door
    { door = 2817192481, state = 1 }, -- manager door
    { door = 1462330364, state = 1 }, -- vault door
    
    -- armadillo
    { door = 3101287960, state = 0 }, -- main door
    { door = 3550475905, state = 1 }, -- inner door
    { door = 1329318347, state = 1 }, -- inner door
    { door = 1366165179, state = 1 }, -- back door

}
