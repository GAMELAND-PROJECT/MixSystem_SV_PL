/* GAMELAND server admin helpers */

#include <amxmodx>
#include <amxmisc>

#define PLUGIN  "GAMELAND Admin Tools"
#define VERSION "1.0.0"
#define AUTHOR  "GAMELAND"

#define MAX_MAPS 128

new Array:g_aMaps
new g_pAlltalk

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
