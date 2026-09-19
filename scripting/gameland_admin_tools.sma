/* GAMELAND server admin helpers */

#include <amxmodx>
#include <amxmisc>
#include <cstrike>

#define PLUGIN  "GAMELAND Admin Tools"
#define VERSION "1.0.0"
#define AUTHOR  "GAMELAND"

#define MAX_MAPS 128

new Array:g_aMaps
new g_pAlltalk
new g_pFriendlyFire
new g_pAllowSpectators
new g_pForceCamera
new g_pForceChaseCam
new g_pFadeToBlack
new g_iJoinMode = 1

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	register_clcmd("say /map", "CmdMapMenu", ADMIN_MAP)
	register_clcmd("say_team /map", "CmdMapMenu", ADMIN_MAP)
	register_clcmd("map", "CmdMapMenu", ADMIN_MAP)

	register_clcmd("say /t1", "CmdAlltalk1", ADMIN_CVAR)
	register_clcmd("say_team /t1", "CmdAlltalk1", ADMIN_CVAR)
	register_clcmd("t1", "CmdAlltalk1", ADMIN_CVAR)

	register_clcmd("say /t2", "CmdAlltalk2", ADMIN_CVAR)
	register_clcmd("say_team /t2", "CmdAlltalk2", ADMIN_CVAR)
	register_clcmd("t2", "CmdAlltalk2", ADMIN_CVAR)

	register_clcmd("say /t3", "CmdAlltalk3", ADMIN_CVAR)
	register_clcmd("say_team /t3", "CmdAlltalk3", ADMIN_CVAR)
	register_clcmd("t3", "CmdAlltalk3", ADMIN_CVAR)

	g_pAlltalk = get_cvar_pointer("sv_alltalk")
	g_pFriendlyFire = get_cvar_pointer("mp_friendlyfire")

	register_clcmd("say /ff1", "CmdFriendlyFireOn", ADMIN_CVAR)
	register_clcmd("say_team /ff1", "CmdFriendlyFireOn", ADMIN_CVAR)
	register_clcmd("ff1", "CmdFriendlyFireOn", ADMIN_CVAR)

	register_clcmd("say /ff0", "CmdFriendlyFireOff", ADMIN_CVAR)
	register_clcmd("say_team /ff0", "CmdFriendlyFireOff", ADMIN_CVAR)
	register_clcmd("ff0", "CmdFriendlyFireOff", ADMIN_CVAR)

	register_clcmd("say /j1", "CmdJoinOpen", ADMIN_CVAR)
	register_clcmd("say_team /j1", "CmdJoinOpen", ADMIN_CVAR)
	register_clcmd("j1", "CmdJoinOpen", ADMIN_CVAR)
	register_clcmd("say /j0", "CmdJoinClosed", ADMIN_CVAR)
	register_clcmd("say_team /j0", "CmdJoinClosed", ADMIN_CVAR)
	register_clcmd("j0", "CmdJoinClosed", ADMIN_CVAR)
	register_clcmd("say /j2", "CmdJoinBlack", ADMIN_CVAR)
	register_clcmd("say_team /j2", "CmdJoinBlack", ADMIN_CVAR)
	register_clcmd("j2", "CmdJoinBlack", ADMIN_CVAR)
	register_clcmd("jointeam", "CmdJoinTeam")

	g_pAllowSpectators = get_cvar_pointer("allow_spectators")
	g_pForceCamera = get_cvar_pointer("mp_forcecamera")
	g_pForceChaseCam = get_cvar_pointer("mp_forcechasecam")
	g_pFadeToBlack = get_cvar_pointer("mp_fadetoblack")

	g_aMaps = ArrayCreate(32)
	LoadMaps()
}

public plugin_end()
{
	if(g_aMaps != Invalid_Array)
	{
		ArrayDestroy(g_aMaps)
	}
}

public CmdMapMenu(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	if(ArraySize(g_aMaps) <= 0)
	{
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1No valid maps found in maps.ini or mapcycle.txt.")
		return PLUGIN_HANDLED
	}

	new menu = menu_create("\y[GAMELAND]\w Change Map", "MapMenuHandler")
	new map[32]

	for(new i = 0; i < ArraySize(g_aMaps); i++)
	{
		ArrayGetString(g_aMaps, i, map, charsmax(map))
		menu_additem(menu, map, map)
	}

	menu_setprop(menu, MPROP_EXIT, MEXIT_ALL)
	menu_display(id, menu)
	return PLUGIN_HANDLED
}

public MapMenuHandler(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}

	if(!is_user_connected(id) || !(get_user_flags(id) & ADMIN_MAP))
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}

	new map[32], itemName[32], access, callback
	menu_item_getinfo(menu, item, access, map, charsmax(map), itemName, charsmax(itemName), callback)
	menu_destroy(menu)

	if(!is_map_valid(map))
	{
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1Map ^3%s ^1is not installed or is invalid.", map)
		return PLUGIN_HANDLED
	}

	new name[MAX_NAME_LENGTH], authid[32]
	get_user_name(id, name, charsmax(name))
	get_user_authid(id, authid, charsmax(authid))

	log_amx("Cmd: ^"%s<%d><%s><>^" changelevel ^"%s^"", name, get_user_userid(id), authid, map)
	client_print_color(0, print_team_default, "^4[GAMELAND] ^3%s ^1changed map to ^4%s^1.", name, map)
	engine_changelevel(map)

	return PLUGIN_HANDLED
}

public CmdAlltalk1(id, level, cid)
{
	return SetAlltalkMode(id, level, cid, 1)
}

public CmdAlltalk2(id, level, cid)
{
	return SetAlltalkMode(id, level, cid, 2)
}

public CmdAlltalk3(id, level, cid)
{
	return SetAlltalkMode(id, level, cid, 3)
}

public CmdFriendlyFireOn(id, level, cid)
{
	return SetFriendlyFire(id, level, cid, 1)
}

public CmdFriendlyFireOff(id, level, cid)
{
	return SetFriendlyFire(id, level, cid, 0)
}

public CmdJoinOpen(id, level, cid)
{
	return SetJoinMode(id, level, cid, 1)
}

public CmdJoinClosed(id, level, cid)
{
	return SetJoinMode(id, level, cid, 0)
}

public CmdJoinBlack(id, level, cid)
{
	return SetJoinMode(id, level, cid, 2)
}

public CmdJoinTeam(id)
{
	if(g_iJoinMode != 0 || !is_user_connected(id) || cs_get_user_team(id) != CS_TEAM_SPECTATOR)
	{
		return PLUGIN_CONTINUE
	}

	new requested[8]
	read_argv(1, requested, charsmax(requested))
	if(equali(requested, "2") || equali(requested, "3") || equali(requested, "5"))
	{
		client_print(id, print_center, "Joining a team is currently disabled.")
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1Spectators cannot join a team right now.")
		return PLUGIN_HANDLED
	}

	return PLUGIN_CONTINUE
}

stock SetJoinMode(id, level, cid, mode)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	g_iJoinMode = mode
	SetCvar(g_pAllowSpectators, 1)

	if(mode == 2)
	{
		SetCvar(g_pForceCamera, 2)
		SetCvar(g_pForceChaseCam, 2)
		SetCvar(g_pFadeToBlack, 1)
	}
	else
	{
		SetCvar(g_pForceCamera, 0)
		SetCvar(g_pForceChaseCam, 0)
		SetCvar(g_pFadeToBlack, 0)
	}

	new name[MAX_NAME_LENGTH]
	if(id)
	{
		get_user_name(id, name, charsmax(name))
	}
	else
	{
		copy(name, charsmax(name), "Console")
	}

	client_print_color(0, print_team_default, "^4[GAMELAND] ^3%s ^1set join mode to ^4/j%d^1.", name, mode)
	log_amx("Cmd: ^"%s^" set join mode to ^"j%d^"", name, mode)
	return PLUGIN_HANDLED
}

stock SetCvar(pcvar, value)
{
	if(pcvar)
	{
		set_pcvar_num(pcvar, value)
	}
}

stock SetFriendlyFire(id, level, cid, mode)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	if(g_pFriendlyFire)
	{
		set_pcvar_num(g_pFriendlyFire, mode)
	}
	else
	{
		server_cmd("mp_friendlyfire %d", mode)
		server_exec()
	}

	new name[MAX_NAME_LENGTH]
	if(id)
	{
		get_user_name(id, name, charsmax(name))
	}
	else
	{
		copy(name, charsmax(name), "Console")
	}

	client_print_color(0, print_team_default, "^4[GAMELAND] ^3%s ^1set ^4mp_friendlyfire ^1to ^4%d^1.", name, mode)
	log_amx("Cmd: ^"%s^" set mp_friendlyfire to ^"%d^"", name, mode)

	return PLUGIN_HANDLED
}

stock SetAlltalkMode(id, level, cid, mode)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	if(g_pAlltalk)
	{
		set_pcvar_num(g_pAlltalk, mode)
	}
	else
	{
		server_cmd("sv_alltalk %d", mode)
	}

	new name[MAX_NAME_LENGTH]
	if(id)
	{
		get_user_name(id, name, charsmax(name))
	}
	else
	{
		copy(name, charsmax(name), "Console")
	}

	client_print_color(0, print_team_default, "^4[GAMELAND] ^3%s ^1set ^4sv_alltalk ^1to ^4%d^1.", name, mode)
	log_amx("Cmd: ^"%s^" set sv_alltalk to ^"%d^"", name, mode)

	return PLUGIN_HANDLED
}

stock LoadMaps()
{
	ArrayClear(g_aMaps)

	new configsDir[64], path[128]
	get_configsdir(configsDir, charsmax(configsDir))
	formatex(path, charsmax(path), "%s/maps.ini", configsDir)

	if(!file_exists(path))
	{
		get_localinfo("amxx_basedir", configsDir, charsmax(configsDir))
		formatex(path, charsmax(path), "mapcycle.txt")
	}

	ReadMapList(path)
}

stock ReadMapList(const path[])
{
	new file = fopen(path, "rt")
	if(!file)
	{
		return
	}

	new line[128], map[32]
	while(!feof(file) && ArraySize(g_aMaps) < MAX_MAPS)
	{
		fgets(file, line, charsmax(line))
		trim(line)

		if(!line[0] || line[0] == ';' || line[0] == '#')
		{
			continue
		}

		parse(line, map, charsmax(map))
		if(map[0] && is_map_valid(map) && !MapExists(map))
		{
			ArrayPushString(g_aMaps, map)
		}
	}

	fclose(file)
}

stock bool:MapExists(const map[])
{
	new current[32]
	for(new i = 0; i < ArraySize(g_aMaps); i++)
	{
		ArrayGetString(g_aMaps, i, current, charsmax(current))
		if(equali(current, map))
		{
			return true
		}
	}

	return false
}
