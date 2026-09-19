/* GAMELAND server admin helpers */

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <reapi>
#include <fakemeta>

#define PLUGIN  "GAMELAND Admin Tools"
#define VERSION "1.1.3"
#define AUTHOR  "GAMELAND"

#define MAX_MAPS 128
#define TASK_BLACK_SCREEN 19001
#define TASK_SPECTATOR_FINALIZE 19100
#define JOIN_MENU_ID "GAMELAND_Join_Menu"

new Array:g_aMaps
new g_pAlltalk
new g_pFriendlyFire
new g_pAllowSpectators
new g_pForceCamera
new g_pForceChaseCam
new g_pFadeToBlack
new g_pJoinMode
new g_iJoinMode = 1
new bool:g_bInternalTeamChange[33]

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
	register_clcmd("chooseteam", "CmdChooseTeam")
	register_forward(FM_ClientCommand, "HookClientCommand")
	RegisterHookChain(RG_HandleMenu_ChooseTeam, "HookChooseTeam_Pre")
	register_menucmd(register_menuid("Team_Select", 1), 1023, "HookTeamSelectMenu")
	register_menucmd(register_menuid(JOIN_MENU_ID, 1), MENU_KEY_1 | MENU_KEY_2, "HandleJoinMenu")
	register_menucmd(register_menuid("GAMELAND_Open_Team_Menu", 1), MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_6 | MENU_KEY_0, "HandleOpenTeamMenu")

	g_pAllowSpectators = get_cvar_pointer("allow_spectators")
	g_pForceCamera = get_cvar_pointer("mp_forcecamera")
	g_pForceChaseCam = get_cvar_pointer("mp_forcechasecam")
	g_pFadeToBlack = get_cvar_pointer("mp_fadetoblack")
	g_pJoinMode = register_cvar("gameland_join_mode", "1")
	g_iJoinMode = clamp(get_pcvar_num(g_pJoinMode), 0, 2)
	if(g_iJoinMode == 2)
	{
		set_task(0.5, "RefreshBlackScreen", TASK_BLACK_SCREEN, _, _, "b")
	}

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
	if(!IsJoinLockedPlayer(id))
	{
		return PLUGIN_CONTINUE
	}

	new requested[8]
	read_argv(1, requested, charsmax(requested))
	if(equali(requested, "1") || equali(requested, "2") || equali(requested, "5") || equali(requested, "6"))
	{
		ApplyRestrictedJoinKey(id, str_to_num(requested) - 1, true)
		return PLUGIN_HANDLED
	}

	return PLUGIN_CONTINUE
}

public CmdChooseTeam(id)
{
	if(g_iJoinMode == 1 && is_user_connected(id))
	{
		ShowOpenTeamMenu(id)
		return PLUGIN_HANDLED
	}

	if(g_iJoinMode != 1 && IsJoinLockedPlayer(id))
	{
		ShowRestrictedJoinMenu(id)
		return PLUGIN_HANDLED
	}

	if(g_iJoinMode != 1 && is_user_connected(id)
	&& (cs_get_user_team(id) == CS_TEAM_T || cs_get_user_team(id) == CS_TEAM_CT))
	{
		return PLUGIN_HANDLED
	}

	return CmdJoinTeam(id)
}

public ShowOpenTeamMenu(id)
{
	if(!is_user_connected(id))
	{
		return
	}

	if(cs_get_user_team(id) == CS_TEAM_T || cs_get_user_team(id) == CS_TEAM_CT)
	{
		show_menu(id, MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_6 | MENU_KEY_0,
			"\y[GAMELAND]\w Team options^n^n\y1.\w Terrorist^n\y2.\w Counter-Terrorist^n^n\y6.\w Spectator^n^n\y0.\w Cancel",
			-1, "GAMELAND_Open_Team_Menu")
	}
	else
	{
		show_menu(id, MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_0,
			"\y[GAMELAND]\w Team options^n^n\y1.\w Terrorist^n\y2.\w Counter-Terrorist^n^n\y0.\w Cancel",
			-1, "GAMELAND_Open_Team_Menu")
	}
}

public HandleOpenTeamMenu(id, key)
{
	if(!is_user_connected(id) || g_iJoinMode != 1)
	{
		return PLUGIN_HANDLED
	}

	if(key == 9)
	{
		return PLUGIN_HANDLED
	}

	if(key == 0)
	{
		g_bInternalTeamChange[id] = true
		engclient_cmd(id, "jointeam", "1")
		g_bInternalTeamChange[id] = false
	}
	else if(key == 1)
	{
		g_bInternalTeamChange[id] = true
		engclient_cmd(id, "jointeam", "2")
		g_bInternalTeamChange[id] = false
	}
	else if(key == 5)
	{
		MoveToFreeSpectator(id)
	}

	return PLUGIN_HANDLED
}

public ShowRestrictedJoinMenu(id)
{
	if(!is_user_connected(id))
	{
		return
	}

	new menuText[256]
	if(g_iJoinMode == 2)
	{
		formatex(menuText, charsmax(menuText),
			"\y[GAMELAND]\w Spectator access is restricted^n^n\y1.\w Disconnect from server^n^n\y0.\w Cancel")
		show_menu(id, MENU_KEY_1 | MENU_KEY_0, menuText, -1, JOIN_MENU_ID)
	}
	else
	{
		formatex(menuText, charsmax(menuText),
			"\y[GAMELAND]\w Join options^n^n\y1.\w Move to Spectator^n\y2.\w Disconnect from server^n^n\y0.\w Cancel")
		show_menu(id, MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_0, menuText, -1, JOIN_MENU_ID)
	}
}

public HandleJoinMenu(id, key)
{
	if(!is_user_connected(id) || g_iJoinMode == 1 || key == 9)
	{
		return PLUGIN_HANDLED
	}

	return ApplyRestrictedJoinKey(id, key, false)
}

stock ApplyRestrictedJoinKey(id, key, bool:showMenu)
{
	if(!is_user_connected(id) || g_iJoinMode == 1)
	{
		return PLUGIN_HANDLED
	}

	if(g_iJoinMode == 2)
	{
		if(key == 0)
		{
			KickRestrictedClient(id)
		}
		else if(showMenu)
		{
			ShowRestrictedJoinMenu(id)
		}
		return PLUGIN_HANDLED
	}

	if(key == 0)
	{
		MoveToFreeSpectator(id)
		SetCvar(g_pForceCamera, 0)
		SetCvar(g_pForceChaseCam, 0)
		SetCvar(g_pFadeToBlack, 0)
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1You were moved to Spectator.")
	}
	else if(key == 1)
	{
		KickRestrictedClient(id)
	}
	else if(showMenu)
	{
		ShowRestrictedJoinMenu(id)
	}
	return PLUGIN_HANDLED
}

stock MoveToFreeSpectator(id)
{
	if(!is_user_connected(id))
	{
		return
	}

	if(is_user_alive(id))
	{
		user_silentkill(id)
	}

	g_bInternalTeamChange[id] = true
	engclient_cmd(id, "jointeam", "6")
	cs_set_user_team(id, CS_TEAM_SPECTATOR)
	g_bInternalTeamChange[id] = false
	set_task(0.1, "FinalizeSpectator", TASK_SPECTATOR_FINALIZE + id)
}

public FinalizeSpectator(taskId)
{
	new id = taskId - TASK_SPECTATOR_FINALIZE
	if(!is_user_connected(id))
	{
		return
	}

	if(is_user_alive(id))
	{
		user_silentkill(id)
	}

	cs_set_user_team(id, CS_TEAM_SPECTATOR)
}

stock KickRestrictedClient(id)
{
	if(!is_user_connected(id))
	{
		return
	}

	new userid = get_user_userid(id)
	server_cmd("kick #%d ^"GAMELAND: server join is currently restricted.^"", userid)
	server_exec()
}

public HookClientCommand(id)
{
	if(g_bInternalTeamChange[id])
	{
		return FMRES_IGNORED
	}

	// While j0 is active, players already in a team must not reopen
	// the default team menu with M/chooseteam. Spectators still get
	// the restricted menu handled below.
	new commandName[32]
	read_argv(0, commandName, charsmax(commandName))
	if(g_iJoinMode == 0 && is_user_connected(id)
	&& (equali(commandName, "chooseteam") || equali(commandName, "jointeam"))
	&& (cs_get_user_team(id) == CS_TEAM_T || cs_get_user_team(id) == CS_TEAM_CT))
	{
		return FMRES_SUPERCEDE
	}

	if(!IsJoinLockedPlayer(id))
	{
		return FMRES_IGNORED
	}

	new command[32], args[16]
	read_argv(0, command, charsmax(command))
	read_args(args, charsmax(args))
	remove_quotes(args)
	trim(args)

	if(equali(command, "jointeam") || equali(command, "chooseteam"))
	{
		ShowRestrictedJoinMenu(id)
		return FMRES_SUPERCEDE
	}

	if(equali(command, "menuselect")
	&& get_member(id, m_iMenu) == CS_Menu_ChooseTeam
	&& (equali(args, "1") || equali(args, "2") || equali(args, "5") || equali(args, "6")))
	{
		ApplyRestrictedJoinKey(id, str_to_num(args) - 1, true)
		return FMRES_SUPERCEDE
	}

	return FMRES_IGNORED
}

public HookTeamSelectMenu(id, key)
{
	if(g_bInternalTeamChange[id])
	{
		return PLUGIN_CONTINUE
	}

	if(!IsJoinLockedPlayer(id))
	{
		return PLUGIN_CONTINUE
	}

	// Team_Select keys: 1=T (0), 2=CT (1), 5=Auto (4), 6=Spec (5).
	if(key == 0 || key == 1 || key == 4 || key == 5)
	{
		ApplyRestrictedJoinKey(id, key, true)
		return PLUGIN_HANDLED
	}

	return PLUGIN_CONTINUE
}

public HookChooseTeam_Pre(id, MenuChooseTeam:slot)
{
	if(!IsJoinLockedPlayer(id))
	{
		return HC_CONTINUE
	}

	if(slot == MenuChoose_T || slot == MenuChoose_CT || slot == MenuChoose_AutoSelect || slot == MenuChoose_Spec)
	{
		SetHookChainReturn(ATYPE_INTEGER, 0)
		if(slot == MenuChoose_T)
		{
			ApplyRestrictedJoinKey(id, 0, true)
		}
		else if(slot == MenuChoose_CT)
		{
			ApplyRestrictedJoinKey(id, 1, true)
		}
		else if(slot == MenuChoose_AutoSelect)
		{
			ApplyRestrictedJoinKey(id, 4, true)
		}
		else
		{
			ApplyRestrictedJoinKey(id, 5, true)
		}
		return HC_SUPERCEDE
	}

	return HC_CONTINUE
}

stock bool:IsJoinLockedPlayer(id)
{
	// j1 is the only mode that allows spectators to join.
	// j0 blocks joining; j2 blocks joining and hides spectator view.
	if(g_iJoinMode == 1 || g_bInternalTeamChange[id] || !is_user_connected(id))
	{
		return false
	}

	new CsTeams:team = cs_get_user_team(id)
	return team == CS_TEAM_UNASSIGNED || team == CS_TEAM_SPECTATOR
}

stock SetJoinMode(id, level, cid, mode)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	g_iJoinMode = mode
	if(g_pJoinMode)
	{
		set_pcvar_num(g_pJoinMode, mode)
	}
	SetCvar(g_pAllowSpectators, 1)

	if(mode == 2)
	{
		SetCvar(g_pForceCamera, 2)
		SetCvar(g_pForceChaseCam, 2)
		SetCvar(g_pFadeToBlack, 1)
		remove_task(TASK_BLACK_SCREEN)
		set_task(0.5, "RefreshBlackScreen", TASK_BLACK_SCREEN, _, _, "b")
	}
	else
	{
		remove_task(TASK_BLACK_SCREEN)
		SetCvar(g_pForceCamera, 0)
		SetCvar(g_pForceChaseCam, 0)
		SetCvar(g_pFadeToBlack, 0)
		ClearBlackScreens()
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

public RefreshBlackScreen()
{
	if(g_iJoinMode != 2)
	{
		remove_task(TASK_BLACK_SCREEN)
		return
	}

	for(new id = 1; id <= get_maxplayers(); id++)
	{
		if(is_user_connected(id)
		&& (cs_get_user_team(id) == CS_TEAM_SPECTATOR || cs_get_user_team(id) == CS_TEAM_UNASSIGNED))
		{
			SendBlackScreen(id)
		}
	}
}

stock SendBlackScreen(id)
{
	message_begin(MSG_ONE_UNRELIABLE, get_user_msgid("ScreenFade"), _, id)
	write_short(1 << 10)
	write_short(1 << 12)
	write_short(0x0004)
	write_byte(0)
	write_byte(0)
	write_byte(0)
	write_byte(255)
	message_end()
}

stock ClearBlackScreens()
{
	for(new id = 1; id <= get_maxplayers(); id++)
	{
		if(is_user_connected(id))
		{
			message_begin(MSG_ONE_UNRELIABLE, get_user_msgid("ScreenFade"), _, id)
			write_short(1)
			write_short(1)
			write_short(0)
			write_byte(0)
			write_byte(0)
			write_byte(0)
			write_byte(0)
			message_end()
		}
	}
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
