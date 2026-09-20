/* GAMELAND server admin helpers */

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <reapi>
#include <fakemeta>

#define PLUGIN  "GAMELAND Admin Tools"
#define VERSION "1.4.1"
#define AUTHOR  "GAMELAND"

#define MAX_MAPS 128
#define TASK_BLACK_SCREEN 19001
#define TASK_SPECTATOR_FINALIZE 19100
#define TASK_INITIAL_JOIN_MENU 19200
#define TASK_SPEC_GUARD 19300
#define TASK_SPEC_CONFIRM 19400
#define SPEC_IDLE_SECONDS 120.0
#define SPEC_GRACE_SECONDS 300.0
#define SPEC_CONFIRM_SECONDS 20.0
#define JOIN_MENU_ID "GAMELAND_Join_Menu"
#define SPEC_CONFIRM_MENU_ID "GAMELAND_Spec_Confirm"
#define BAN_PLAYERS_MENU_ID "GAMELAND_Ban_Players"
#define BAN_OPTIONS_MENU_ID "GAMELAND_Ban_Options"
#define MAX_BAN_ENTRIES 128
#define TASK_MAP_VOTE 19500
#define MAP_VOTE_DURATION 20.0
#define MAX_VOTE_MAPS 7

new Array:g_aMaps
new g_pAlltalk
new g_pFriendlyFire
new g_pAllowSpectators
new g_pForceCamera
new g_pForceChaseCam
new g_pFadeToBlack
new g_pJoinMode
new g_iJoinMode = 1
new g_iMapCategory[33]
new bool:g_bInternalTeamChange[33]
new Float:g_flSpecEnteredAt[33]
new Float:g_flLastActivity[33]
new Float:g_flLastViewAngles[33][3]
new bool:g_bSpecConfirmOpen[33]
new g_iBanTargetUserId[33]
new g_szBannedIps[MAX_BAN_ENTRIES][32]
new g_iBannedIpCount
new bool:g_bVoteMapSelected[33][MAX_MAPS]
new g_iVoteMapPage[33]
new bool:g_bMapVoteActive
new g_iVoteMapCount
new g_iVoteMapIndex[MAX_VOTE_MAPS]
new g_iVoteCount[MAX_VOTE_MAPS]
new g_iPlayerVote[MAX_PLAYERS + 1]

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	register_clcmd("say /map", "CmdMapMenu", ADMIN_MAP)
	register_clcmd("say_team /map", "CmdMapMenu", ADMIN_MAP)
	register_clcmd("map", "CmdMapMenu", ADMIN_MAP)
	register_clcmd("say /k", "CmdKickMenu", ADMIN_KICK)
	register_clcmd("say_team /k", "CmdKickMenu", ADMIN_KICK)
	register_clcmd("k", "CmdKickMenu", ADMIN_KICK)
	register_clcmd("say /b", "CmdBanMenu", ADMIN_BAN)
	register_clcmd("say_team /b", "CmdBanMenu", ADMIN_BAN)
	register_clcmd("b", "CmdBanMenu", ADMIN_BAN)
	register_clcmd("say /ub", "CmdUnban", ADMIN_BAN)
	register_clcmd("say_team /ub", "CmdUnban", ADMIN_BAN)
	register_clcmd("ub", "CmdUnban", ADMIN_BAN)
	register_clcmd("say /vm", "CmdVoteMapMenu", ADMIN_MAP)
	register_clcmd("say_team /vm", "CmdVoteMapMenu", ADMIN_MAP)
	register_clcmd("vm", "CmdVoteMapMenu", ADMIN_MAP)

	register_clcmd("say /spec", "CmdMoveAllToSpec", ADMIN_CVAR)
	register_clcmd("say_team /spec", "CmdMoveAllToSpec", ADMIN_CVAR)
	register_clcmd("spec", "CmdMoveAllToSpec", ADMIN_CVAR)
	register_clcmd("say /st", "CmdSwapTeams", ADMIN_CVAR)
	register_clcmd("say_team /st", "CmdSwapTeams", ADMIN_CVAR)
	register_clcmd("st", "CmdSwapTeams", ADMIN_CVAR)
	register_clcmd("say /rr", "CmdRestartRound", ADMIN_CVAR)
	register_clcmd("say_team /rr", "CmdRestartRound", ADMIN_CVAR)
	register_clcmd("rr", "CmdRestartRound", ADMIN_CVAR)
	register_clcmd("say /restart", "CmdRestartRound", ADMIN_CVAR)
	register_clcmd("say_team /restart", "CmdRestartRound", ADMIN_CVAR)
	register_clcmd("restart", "CmdRestartRound", ADMIN_CVAR)
	register_clcmd("say /kspec", "CmdKickSpecs", ADMIN_KICK)
	register_clcmd("say_team /kspec", "CmdKickSpecs", ADMIN_KICK)
	register_clcmd("kspec", "CmdKickSpecs", ADMIN_KICK)

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
	register_forward(FM_CmdStart, "HookCmdStart", 1)
	register_message(get_user_msgid("ShowMenu"), "MessageShowMenu")
	RegisterHookChain(RG_HandleMenu_ChooseTeam, "HookChooseTeam_Pre")
	register_menucmd(register_menuid("Team_Select", 1), 1023, "HookTeamSelectMenu")
	register_menucmd(register_menuid(JOIN_MENU_ID, 1), MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_0, "HandleJoinMenu")
	register_menucmd(register_menuid("GAMELAND_Open_Team_Menu", 1), MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_6 | MENU_KEY_0, "HandleOpenTeamMenu")
	register_menucmd(register_menuid("GAMELAND_Map_Categories", 1), MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_3 | MENU_KEY_0, "HandleMapCategoryMenu")
	register_menucmd(register_menuid("GAMELAND_VoteMap_Select", 1), 1023, "HandleVoteMapSelect")
	register_menucmd(register_menuid(SPEC_CONFIRM_MENU_ID, 1), MENU_KEY_1 | MENU_KEY_2, "HandleSpecConfirmMenu")

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
	set_task(5.0, "TaskSpecGuard", TASK_SPEC_GUARD, _, _, "b")
}

public client_putinserver(id)
{
	g_flLastActivity[id] = get_gametime()
	g_flSpecEnteredAt[id] = 0.0
	g_bSpecConfirmOpen[id] = false
	set_task(0.4, "ShowInitialJoinMenu", TASK_INITIAL_JOIN_MENU + id)
}

public MessageShowMenu(msgId, msgDest, id)
{
	if(!is_user_connected(id) || !IsJoinMenuPlayer(id))
	{
		return PLUGIN_CONTINUE
	}

	new menuText[128]
	get_msg_arg_string(4, menuText, charsmax(menuText))
	if(contain(menuText, "Team_Select") == -1 && contain(menuText, "#Team_Select") == -1)
	{
		return PLUGIN_CONTINUE
	}

	ShowInitialJoinMenu(TASK_INITIAL_JOIN_MENU + id)
	return PLUGIN_HANDLED
}

stock bool:IsJoinMenuPlayer(id)
{
	new CsTeams:team = cs_get_user_team(id)
	return team == CS_TEAM_UNASSIGNED || team == CS_TEAM_SPECTATOR
}

public client_disconnected(id)
{
	remove_task(TASK_INITIAL_JOIN_MENU + id)
	remove_task(TASK_SPECTATOR_FINALIZE + id)
	remove_task(TASK_SPEC_CONFIRM + id)
	g_iMapCategory[id] = 0
	g_bInternalTeamChange[id] = false
	g_flSpecEnteredAt[id] = 0.0
	g_flLastActivity[id] = get_gametime()
	g_flLastViewAngles[id][0] = 0.0
	g_flLastViewAngles[id][1] = 0.0
	g_flLastViewAngles[id][2] = 0.0
	g_bSpecConfirmOpen[id] = false
	g_iBanTargetUserId[id] = 0
	g_iPlayerVote[id] = -1
	arrayset(g_bVoteMapSelected[id], false, MAX_MAPS)
	g_iVoteMapPage[id] = 0
	g_iPlayerVote[id] = -1
}

public ShowInitialJoinMenu(taskId)
{
	new id = taskId - TASK_INITIAL_JOIN_MENU
	if(!is_user_connected(id))
	{
		return
	}

	new CsTeams:team = cs_get_user_team(id)
	if(team != CS_TEAM_UNASSIGNED && team != CS_TEAM_SPECTATOR)
	{
		return
	}

	if(g_iJoinMode == 1)
	{
		ShowOpenTeamMenu(id)
	}
	else
	{
		ShowRestrictedJoinMenu(id)
	}
}

public TaskSpecGuard()
{
	new Float:now = get_gametime()

	for(new id = 1; id <= get_maxplayers(); id++)
	{
		if(!is_user_connected(id) || is_user_hltv(id) || IsAdminExempt(id))
		{
			ResetSpecGuard(id)
			continue
		}

		new CsTeams:team = cs_get_user_team(id)
		if((team == CS_TEAM_T || team == CS_TEAM_CT)
		&& g_flLastActivity[id] > 0.0
		&& now - g_flLastActivity[id] >= SPEC_IDLE_SECONDS)
		{
			client_print_color(id, print_team_default, "^4[GAMELAND] ^1You were moved to Spectator after 2 minutes of inactivity.")
			MoveToFreeSpectator(id)
			continue
		}

		if(team != CS_TEAM_SPECTATOR)
		{
			ResetSpecGuard(id)
			continue
		}

		if(g_flSpecEnteredAt[id] <= 0.0)
		{
			g_flSpecEnteredAt[id] = now
			continue
		}

		if(!g_bSpecConfirmOpen[id] && now - g_flSpecEnteredAt[id] >= SPEC_GRACE_SECONDS)
		{
			ShowSpecConfirmMenu(id)
		}
	}
}

stock ResetSpecGuard(id)
{
	if(!(1 <= id <= 32))
	{
		return
	}

	remove_task(TASK_SPEC_CONFIRM + id)
	g_flSpecEnteredAt[id] = 0.0
	g_bSpecConfirmOpen[id] = false
}

public HookCmdStart(id, ucHandle, seed)
{
	if(!is_user_connected(id) || is_user_hltv(id) || IsAdminExempt(id))
	{
		return FMRES_IGNORED
	}

	new CsTeams:team = cs_get_user_team(id)
	if(team != CS_TEAM_T && team != CS_TEAM_CT)
	{
		return FMRES_IGNORED
	}

	new buttons = get_uc(ucHandle, UC_Buttons)
	new Float:angles[3]
	get_uc(ucHandle, UC_ViewAngles, angles)

	if(buttons != 0
	|| floatabs(angles[0] - g_flLastViewAngles[id][0]) > 0.25
	|| floatabs(angles[1] - g_flLastViewAngles[id][1]) > 0.25
	|| floatabs(angles[2] - g_flLastViewAngles[id][2]) > 0.25)
	{
		g_flLastActivity[id] = get_gametime()
	}

	g_flLastViewAngles[id][0] = angles[0]
	g_flLastViewAngles[id][1] = angles[1]
	g_flLastViewAngles[id][2] = angles[2]
	return FMRES_IGNORED
}

stock bool:IsAdminExempt(id)
{
	return (get_user_flags(id) & (ADMIN_KICK | ADMIN_CVAR | ADMIN_MAP | ADMIN_RCON)) != 0
}

stock ShowSpecConfirmMenu(id)
{
	if(!is_user_connected(id) || is_user_hltv(id) || IsAdminExempt(id)
	|| cs_get_user_team(id) != CS_TEAM_SPECTATOR)
	{
		ResetSpecGuard(id)
		return
	}

	g_bSpecConfirmOpen[id] = true
	show_menu(id, MENU_KEY_1,
		"\y[GAMELAND]\w Are you still present?^n^n\y1.\w Yes, keep watching^n^n\rYou have 20 seconds to answer.",
		floatround(SPEC_CONFIRM_SECONDS), SPEC_CONFIRM_MENU_ID)

	remove_task(TASK_SPEC_CONFIRM + id)
	set_task(SPEC_CONFIRM_SECONDS, "TaskSpecConfirmTimeout", TASK_SPEC_CONFIRM + id)
	client_print_color(id, print_team_default, "^4[GAMELAND] ^1Spectator timeout check: press ^41 ^1within 20 seconds to stay.")
}

public HandleSpecConfirmMenu(id, key)
{
	if(!is_user_connected(id))
	{
		return PLUGIN_HANDLED
	}

	remove_task(TASK_SPEC_CONFIRM + id)
	g_bSpecConfirmOpen[id] = false

	if(IsAdminExempt(id) || cs_get_user_team(id) != CS_TEAM_SPECTATOR)
	{
		ResetSpecGuard(id)
		return PLUGIN_HANDLED
	}

	if(key == 0)
	{
		g_flSpecEnteredAt[id] = get_gametime()
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1Presence confirmed. You may continue watching.")
	}

	return PLUGIN_HANDLED
}

public TaskSpecConfirmTimeout(taskId)
{
	new id = taskId - TASK_SPEC_CONFIRM
	if(!is_user_connected(id))
	{
		return
	}

	g_bSpecConfirmOpen[id] = false

	if(!IsAdminExempt(id) && cs_get_user_team(id) == CS_TEAM_SPECTATOR)
	{
		KickSpectatorTimeout(id)
	}
	else
	{
		ResetSpecGuard(id)
	}
}

stock KickSpectatorTimeout(id)
{
	if(!is_user_connected(id))
	{
		return
	}

	new userid = get_user_userid(id)
	server_cmd("kick #%d ^"GAMELAND: spectator timeout.^"", userid)
	server_exec()
	ResetSpecGuard(id)
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

	ShowMapBrowser(id)
	return PLUGIN_HANDLED
}

public CmdVoteMapMenu(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	if(g_bMapVoteActive)
	{
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1A map vote is already active.")
		return PLUGIN_HANDLED
	}

	if(GetDeMapCount() < 2)
	{
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1At least two de_ maps are required.")
		return PLUGIN_HANDLED
	}

	g_iVoteMapPage[id] = 0
	arrayset(g_bVoteMapSelected[id], false, MAX_MAPS)
	ShowVoteMapSelectMenu(id)
	return PLUGIN_HANDLED
}

stock ShowVoteMapSelectMenu(id)
{
	if(!is_user_connected(id) || !(get_user_flags(id) & ADMIN_MAP))
	{
		return
	}

	new page = g_iVoteMapPage[id]
	new start = page * MAX_VOTE_MAPS
	new total = GetDeMapCount()
	if(start >= total)
	{
		g_iVoteMapPage[id] = 0
		page = 0
		start = 0
	}

	new text[512], line[96], map[32], actualIndex
	formatex(text, charsmax(text), "\y[GAMELAND]\w Vote maps \r(Page %d)^n^n", page + 1)

	for(new slot = 0; slot < MAX_VOTE_MAPS; slot++)
	{
		actualIndex = GetDeMapIndexByPosition(start + slot)
		if(actualIndex < 0)
		{
			break
		}

		ArrayGetString(g_aMaps, actualIndex, map, charsmax(map))
		formatex(line, charsmax(line), "\y%d.\w %s%s^n", slot + 1,
			g_bVoteMapSelected[id][actualIndex] ? "\r*\w " : "", map)
		add(text, charsmax(text), line)
	}

	add(text, charsmax(text), "^n\y8.\w Start vote")
	if(start + MAX_VOTE_MAPS < total)
	{
		add(text, charsmax(text), "^n\y9.\w Next page")
	}
	add(text, charsmax(text), "^n\y0.\w Cancel")

	show_menu(id, MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_3 | MENU_KEY_4 | MENU_KEY_5 | MENU_KEY_6 | MENU_KEY_7 | MENU_KEY_8 | MENU_KEY_9 | MENU_KEY_0, text, -1, "GAMELAND_VoteMap_Select")
}

public HandleVoteMapSelect(id, key)
{
	if(!is_user_connected(id) || !(get_user_flags(id) & ADMIN_MAP) || g_bMapVoteActive)
	{
		return PLUGIN_HANDLED
	}

	new total = GetDeMapCount()
	new page = g_iVoteMapPage[id]
	new start = page * MAX_VOTE_MAPS

	if(key >= 0 && key < MAX_VOTE_MAPS)
	{
		new actualIndex = GetDeMapIndexByPosition(start + key)
		if(actualIndex >= 0)
		{
			g_bVoteMapSelected[id][actualIndex] = !g_bVoteMapSelected[id][actualIndex]
		}
		ShowVoteMapSelectMenu(id)
		return PLUGIN_HANDLED
	}

	if(key == 7)
	{
		StartSelectedMapVote(id)
		return PLUGIN_HANDLED
	}

	if(key == 8 && start + MAX_VOTE_MAPS < total)
	{
		g_iVoteMapPage[id]++
		ShowVoteMapSelectMenu(id)
		return PLUGIN_HANDLED
	}

	return PLUGIN_HANDLED
}

stock StartSelectedMapVote(admin)
{
	new count
	for(new i = 0; i < ArraySize(g_aMaps) && count < MAX_VOTE_MAPS; i++)
	{
		new candidate[32]
		ArrayGetString(g_aMaps, i, candidate, charsmax(candidate))
		if(MapMatchesCategory(candidate, 1) && g_bVoteMapSelected[admin][i])
		{
			g_iVoteMapIndex[count] = i
			g_iVoteCount[count] = 0
			count++
		}
	}

	if(count < 2)
	{
		client_print_color(admin, print_team_default, "^4[GAMELAND] ^1Select at least two maps before starting the vote.")
		ShowVoteMapSelectMenu(admin)
		return
	}

	g_bMapVoteActive = true
	g_iVoteMapCount = count
	for(new id = 1; id <= MAX_PLAYERS; id++)
	{
		g_iPlayerVote[id] = -1
	}

	new menu = menu_create("\y[GAMELAND]\w Choose the next map", "MapVoteMenuHandler")
	new map[32], info[8]
	for(new i = 0; i < count; i++)
	{
		ArrayGetString(g_aMaps, g_iVoteMapIndex[i], map, charsmax(map))
		num_to_str(i, info, charsmax(info))
		menu_additem(menu, map, info)
	}
	menu_setprop(menu, MPROP_EXIT, MEXIT_NEVER)
	for(new player = 1; player <= MAX_PLAYERS; player++)
	{
		if(player != admin && is_user_connected(player) && !is_user_hltv(player))
		{
			menu_display(player, menu)
		}
	}
	if(is_user_connected(admin) && !is_user_hltv(admin))
	{
		menu_display(admin, menu)
	}
	client_print_color(0, print_team_default, "^4[GAMELAND] ^1Map vote started. You have ^420 seconds^1 to vote.")
	set_task(MAP_VOTE_DURATION, "FinishMapVote", TASK_MAP_VOTE)
}

public MapVoteMenuHandler(id, menu, item)
{
	if(!g_bMapVoteActive || item == MENU_EXIT || !is_user_connected(id))
	{
		return PLUGIN_HANDLED
	}

	if(g_iPlayerVote[id] >= 0 && g_iPlayerVote[id] < g_iVoteMapCount)
	{
		g_iVoteCount[g_iPlayerVote[id]]--
	}

	g_iPlayerVote[id] = item
	g_iVoteCount[item]++
	client_print_color(id, print_team_default, "^4[GAMELAND] ^1Your vote was recorded.")
	menu_display(id, menu)
	return PLUGIN_HANDLED
}

public FinishMapVote()
{
	if(!g_bMapVoteActive)
	{
		return
	}

	new winner = 0
	for(new i = 1; i < g_iVoteMapCount; i++)
	{
		if(g_iVoteCount[i] > g_iVoteCount[winner])
		{
			winner = i
		}
	}

	new map[32]
	ArrayGetString(g_aMaps, g_iVoteMapIndex[winner], map, charsmax(map))
	g_bMapVoteActive = false
	client_print_color(0, print_team_default, "^4[GAMELAND] ^1Vote finished: ^4%s^1 won with ^3%d^1 votes.", map, g_iVoteCount[winner])
	set_task(2.0, "ChangeToVotedMap", TASK_MAP_VOTE + 1, map, sizeof map)
}

public ChangeToVotedMap(map[])
{
	if(is_map_valid(map))
	{
		engine_changelevel(map)
	}
}

stock GetDeMapCount()
{
	new count
	for(new i = 0; i < ArraySize(g_aMaps); i++)
	{
		new map[32]
		ArrayGetString(g_aMaps, i, map, charsmax(map))
		if(MapMatchesCategory(map, 1))
		{
			count++
		}
	}
	return count
}

stock GetDeMapIndexByPosition(position)
{
	new current
	for(new i = 0; i < ArraySize(g_aMaps); i++)
	{
		new map[32]
		ArrayGetString(g_aMaps, i, map, charsmax(map))
		if(MapMatchesCategory(map, 1))
		{
			if(current == position)
			{
				return i
			}
			current++
		}
	}
	return -1
}

public ShowMapBrowser(id)
{
	if(!is_user_connected(id) || !(get_user_flags(id) & ADMIN_MAP))
	{
		return
	}

	show_menu(id, MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_3 | MENU_KEY_0,
		"\y[GAMELAND]\w Map browser^n^n\y1.\w Competitive DE maps^n\y2.\w Shooting SK / AWP^n\y3.\w CS maps^n^n\y0.\w Cancel",
		-1, "GAMELAND_Map_Categories")
}

public HandleMapCategoryMenu(id, key)
{
	if(!is_user_connected(id) || !(get_user_flags(id) & ADMIN_MAP))
	{
		return PLUGIN_HANDLED
	}

	if(key == 0)
	{
		ShowMapCategory(id, 1)
	}
	else if(key == 1)
	{
		ShowMapCategory(id, 2)
	}
	else if(key == 2)
	{
		ShowMapCategory(id, 3)
	}
	return PLUGIN_HANDLED
}

public ShowMapCategory(id, category)
{
	if(!is_user_connected(id) || !(get_user_flags(id) & ADMIN_MAP))
	{
		return
	}

	new title[64]
	switch(category)
	{
		case 1: copy(title, charsmax(title), "\y[GAMELAND]\w Competitive DE")
		case 2: copy(title, charsmax(title), "\y[GAMELAND]\w Shooting SK / AWP")
		case 3: copy(title, charsmax(title), "\y[GAMELAND]\w CS maps")
		default: return
	}
	g_iMapCategory[id] = category

	new mapMenu = menu_create(title, "MapMenuHandler")
	new map[32]

	for(new i = 0; i < ArraySize(g_aMaps); i++)
	{
		ArrayGetString(g_aMaps, i, map, charsmax(map))
		if(MapMatchesCategory(map, category))
		{
			menu_additem(mapMenu, map, map)
		}
	}

	menu_setprop(mapMenu, MPROP_EXIT, MEXIT_ALL)
	menu_display(id, mapMenu)
}

stock bool:MapMatchesCategory(const map[], category)
{
	if(category == 1)
	{
		return containi(map, "de_") == 0
	}
	if(category == 2)
	{
		return containi(map, "awp_") == 0 || containi(map, "aim_sk_") == 0
	}
	if(category == 3)
	{
		return containi(map, "cs_") == 0
	}
	return false
}

public CmdKickMenu(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	new menu = menu_create("\y[GAMELAND]\w Kick player", "KickMenuHandler")
	new players[32], count, target
	get_players(players, count, "ch")

	for(new i = 0; i < count; i++)
	{
		target = players[i]
		new name[MAX_NAME_LENGTH], userid[16], itemText[64]
		get_user_name(target, name, charsmax(name))
		num_to_str(get_user_userid(target), userid, charsmax(userid))
		formatex(itemText, charsmax(itemText), "%s \y[%d]", name, target)
		menu_additem(menu, itemText, userid)
	}

	if(count == 0)
	{
		menu_destroy(menu)
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1No players are available to kick.")
		return PLUGIN_HANDLED
	}

	menu_setprop(menu, MPROP_EXIT, MEXIT_ALL)
	menu_display(id, menu)
	return PLUGIN_HANDLED
}

public CmdBanMenu(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	new menu = menu_create("\y[GAMELAND]\w Ban player", "BanPlayerMenuHandler")
	new players[32], count, target
	get_players(players, count, "ch")

	for(new i = 0; i < count; i++)
	{
		target = players[i]
		if(is_user_hltv(target) || (get_user_flags(target) & ADMIN_IMMUNITY))
		{
			continue
		}

		new name[MAX_NAME_LENGTH], userid[16], itemText[64]
		get_user_name(target, name, charsmax(name))
		num_to_str(get_user_userid(target), userid, charsmax(userid))
		formatex(itemText, charsmax(itemText), "%s \y[#%d]", name, get_user_userid(target))
		menu_additem(menu, itemText, userid)
	}

	if(menu_items(menu) <= 0)
	{
		menu_destroy(menu)
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1No eligible players are available to ban.")
		return PLUGIN_HANDLED
	}

	menu_setprop(menu, MPROP_EXIT, MEXIT_ALL)
	menu_display(id, menu)
	return PLUGIN_HANDLED
}

public BanPlayerMenuHandler(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}

	if(!is_user_connected(id) || !(get_user_flags(id) & ADMIN_BAN))
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}

	new itemName[64], useridText[16], access, callback
	menu_item_getinfo(menu, item, access, useridText, charsmax(useridText),
		itemName, charsmax(itemName), callback)
	menu_destroy(menu)

	new target = find_player("k", str_to_num(useridText))
	if(!target || is_user_hltv(target) || (get_user_flags(target) & ADMIN_IMMUNITY))
	{
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1That player cannot be banned.")
		return PLUGIN_HANDLED
	}

	g_iBanTargetUserId[id] = get_user_userid(target)
	ShowBanOptions(id, target)
	return PLUGIN_HANDLED
}

stock ShowBanOptions(id, target)
{
	new name[MAX_NAME_LENGTH]
	get_user_name(target, name, charsmax(name))

	new menu = menu_create(fmt("\y[GAMELAND]\w Ban \r%s", name), "BanOptionsMenuHandler")
	menu_additem(menu, "5 minutes \y[IP]", "5")
	menu_additem(menu, "15 minutes \y[IP]", "15")
	menu_additem(menu, "30 minutes \y[IP]", "30")
	menu_additem(menu, "2 hours \y[IP]", "120")
	menu_additem(menu, "1 day \y[IP]", "1440")
	menu_additem(menu, "7 days \y[IP]", "10080")
	menu_additem(menu, "Permanent \y[IP]", "0")
	menu_setprop(menu, MPROP_EXIT, MEXIT_ALL)
	menu_display(id, menu)
}

public BanOptionsMenuHandler(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}

	if(!is_user_connected(id) || !(get_user_flags(id) & ADMIN_BAN))
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}

	new itemName[64], option[32], access, callback
	menu_item_getinfo(menu, item, access, option, charsmax(option),
		itemName, charsmax(itemName), callback)
	menu_destroy(menu)

	new target = find_player("k", g_iBanTargetUserId[id])
	if(!target || is_user_hltv(target) || (get_user_flags(target) & ADMIN_IMMUNITY))
	{
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1That player is no longer eligible for banning.")
		return PLUGIN_HANDLED
	}

	new minutes = str_to_num(option)
	ExecuteBan(id, target, minutes)
	return PLUGIN_HANDLED
}

stock ExecuteBan(admin, target, minutes)
{
	new userid = get_user_userid(target)
	new targetName[MAX_NAME_LENGTH], adminName[MAX_NAME_LENGTH]
	get_user_name(target, targetName, charsmax(targetName))
	GetAdminName(admin, adminName, charsmax(adminName))

	new minutesText[16]
	num_to_str(minutes, minutesText, charsmax(minutesText))

	new ip[32]
	get_user_ip(target, ip, charsmax(ip), 1)
	server_cmd("addip ^"%s^" ^"%s^";wait;writeip;kick #%d ^"GAMELAND: IP banned by admin.^"", minutesText, ip, userid)
	server_exec()
	if(!IsCachedBanIp(ip) && g_iBannedIpCount < MAX_BAN_ENTRIES)
	{
		copy(g_szBannedIps[g_iBannedIpCount], charsmax(g_szBannedIps[]), ip)
		g_iBannedIpCount++
	}

	client_print_color(0, print_team_default, "^4[GAMELAND] ^3%s ^1IP-banned ^3%s ^1for ^4%s minutes^1.",
		adminName, targetName, minutesText)
	log_amx("Cmd: ^"%s^" IP-banned ^"%s^" (%s minutes)", adminName, targetName, minutesText)
	g_iBanTargetUserId[admin] = 0
}

public CmdUnban(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	ShowUnbanMenu(id)
	return PLUGIN_HANDLED
}

public ShowUnbanMenu(id)
{
	if(!is_user_connected(id) || !(get_user_flags(id) & ADMIN_BAN))
	{
		return
	}

	new menu = menu_create("\y[GAMELAND]\w Unban list", "UnbanMenuHandler")
	new value[64], display[96], info[80], count
	for(new i = 0; i < g_iBannedIpCount && menu_items(menu) < 7; i++)
	{
		formatex(display, charsmax(display), "%s \y[IP]", g_szBannedIps[i])
		formatex(info, charsmax(info), "1|%s", g_szBannedIps[i])
		menu_additem(menu, display, info)
		count++
	}
	new filePath[192]
	GetBanFilePath(1, filePath, charsmax(filePath))
	new file = fopen(filePath, "rt")
	if(file)
	{
		while(count < MAX_BAN_ENTRIES && ReadBanEntry(file, 1, value, charsmax(value)))
		{
			if(menu_items(menu) < 7 && !IsCachedBanIp(value))
			{
				formatex(display, charsmax(display), "%s \y[IP]", value)
				formatex(info, charsmax(info), "1|%s", value)
				menu_additem(menu, display, info)
			}
			if(!IsCachedBanIp(value))
			{
				count++
			}
		}
		fclose(file)
	}

	if(count > 0)
	{
		menu_additem(menu, "Unban all entries", "ALL")
	}
	else
	{
		menu_additem(menu, "\dNo active bans found", "NONE")
	}

	menu_setprop(menu, MPROP_EXIT, MEXIT_ALL)
	menu_display(id, menu)
}

public UnbanMenuHandler(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}

	if(!is_user_connected(id) || !(get_user_flags(id) & ADMIN_BAN))
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}

	new itemName[96], info[80], access, callback
	menu_item_getinfo(menu, item, access, info, charsmax(info),
		itemName, charsmax(itemName), callback)
	menu_destroy(menu)

	if(equal(info, "NONE"))
	{
		return PLUGIN_HANDLED
	}

	if(equal(info, "ALL"))
	{
		UnbanAllEntries(id)
		return PLUGIN_HANDLED
	}

	new typeText[8], value[64]
	strtok(info, typeText, charsmax(typeText), value, charsmax(value), '|')
	trim(value)
	UnbanEntry(id, value)
	return PLUGIN_HANDLED
}

stock UnbanEntry(id, const value[])
{
	if(!value[0])
	{
		return
	}

	server_cmd("removeip ^"%s^";wait;writeip", value)
	server_exec()
	RemoveCachedBanIp(value)

	new adminName[MAX_NAME_LENGTH]
	GetAdminName(id, adminName, charsmax(adminName))
	client_print_color(0, print_team_default, "^4[GAMELAND] ^3%s ^1unbanned ^4%s^1.", adminName, value)
	log_amx("Cmd: ^"%s^" unbanned IP ^"%s^"", adminName, value)
}

stock UnbanAllEntries(id)
{
	new value[64], count, filePath[192]
	GetBanFilePath(1, filePath, charsmax(filePath))
	new file = fopen(filePath, "rt")
	if(file)
	{
		while(count < MAX_BAN_ENTRIES && ReadBanEntry(file, 1, value, charsmax(value)))
		{
			server_cmd("removeip ^"%s^"", value)
			count++
		}
		fclose(file)
	}
	server_cmd("writeip")
	server_exec()
	g_iBannedIpCount = 0

	new adminName[MAX_NAME_LENGTH]
	GetAdminName(id, adminName, charsmax(adminName))
	client_print_color(0, print_team_default, "^4[GAMELAND] ^3%s ^1unbanned all listed entries (^4%d^1).", adminName, count)
	log_amx("Cmd: ^"%s^" unbanned all listed entries (%d)", adminName, count)
}

stock GetBanFilePath(type, output[], outputLen)
{
	new configsDir[128]
	get_configsdir(configsDir, charsmax(configsDir))
	formatex(output, outputLen, "%s/../../../%s", configsDir, type ? "listip.cfg" : "banned.cfg")
}

stock bool:ReadBanEntry(file, type, output[], outputLen)
{
	new line[256], command[16], minutes[16]
	while(!feof(file))
	{
		fgets(file, line, charsmax(line))
		trim(line)
		if(!line[0] || line[0] == ';' || line[0] == '/' || line[0] == '#')
		{
			continue
		}

		command[0] = 0
		minutes[0] = 0
		output[0] = 0
		parse(line, command, charsmax(command), minutes, charsmax(minutes), output, outputLen - 1)
		if(type == 0 && equali(command, "banid") && output[0])
		{
			return true
		}
		if(type == 1 && equali(command, "addip") && output[0])
		{
			return true
		}
	}
	return false
}

stock bool:IsCachedBanIp(const value[])
{
	for(new i = 0; i < g_iBannedIpCount; i++)
	{
		if(equal(g_szBannedIps[i], value))
		{
			return true
		}
	}
	return false
}

stock RemoveCachedBanIp(const value[])
{
	for(new i = 0; i < g_iBannedIpCount; i++)
	{
		if(equal(g_szBannedIps[i], value))
		{
			for(new j = i; j < g_iBannedIpCount - 1; j++)
			{
				copy(g_szBannedIps[j], charsmax(g_szBannedIps[]), g_szBannedIps[j + 1])
			}
			g_iBannedIpCount--
			return
		}
	}
}

public CmdMoveAllToSpec(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	new moved
	for(new player = 1; player <= get_maxplayers(); player++)
	{
		if(!is_user_connected(player) || is_user_hltv(player))
		{
			continue
		}

		new CsTeams:team = cs_get_user_team(player)
		if(team != CS_TEAM_T && team != CS_TEAM_CT)
		{
			continue
		}

		if(is_user_alive(player))
		{
			user_silentkill(player)
		}

		g_bInternalTeamChange[player] = true
		rg_join_team(player, TEAM_SPECTATOR)
		g_bInternalTeamChange[player] = false
		moved++
	}

	new adminName[MAX_NAME_LENGTH]
	GetAdminName(id, adminName, charsmax(adminName))
	client_print_color(0, print_team_default, "^4[GAMELAND] ^3%s ^1moved ^4%d ^1players to Spectator.", adminName, moved)
	log_amx("Cmd: ^"%s^" moved %d players to Spectator", adminName, moved)
	return PLUGIN_HANDLED
}

public CmdSwapTeams(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	rg_swap_all_players()
	// ReGameDLL performs the proper round reset and respawns through the
	// normal game flow; do not manually respawn players before it.
	server_cmd("sv_restart 1")
	server_exec()

	new adminName[MAX_NAME_LENGTH]
	GetAdminName(id, adminName, charsmax(adminName))
	client_print_color(0, print_team_default, "^4[GAMELAND] ^3%s ^1swapped the CT and Terrorist teams and restarted the round.", adminName)
	log_amx("Cmd: ^"%s^" swapped CT and Terrorist teams and restarted the round", adminName)
	return PLUGIN_HANDLED
}

public CmdRestartRound(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	server_cmd("sv_restart 1")
	server_exec()

	new adminName[MAX_NAME_LENGTH]
	GetAdminName(id, adminName, charsmax(adminName))
	client_print_color(0, print_team_default, "^4[GAMELAND] ^3%s ^1restarted the round.", adminName)
	log_amx("Cmd: ^"%s^" restarted the round", adminName)
	return PLUGIN_HANDLED
}

public CmdKickSpecs(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	new kicked
	for(new player = 1; player <= get_maxplayers(); player++)
	{
		if(!is_user_connected(player) || is_user_hltv(player)
		|| cs_get_user_team(player) != CS_TEAM_SPECTATOR)
		{
			continue
		}

		new userid = get_user_userid(player)
		server_cmd("kick #%d ^"GAMELAND: spectators removed by admin.^"", userid)
		kicked++
	}
	server_exec()

	new adminName[MAX_NAME_LENGTH]
	GetAdminName(id, adminName, charsmax(adminName))
	client_print_color(0, print_team_default, "^4[GAMELAND] ^3%s ^1kicked ^4%d ^1spectators.", adminName, kicked)
	log_amx("Cmd: ^"%s^" kicked %d spectators", adminName, kicked)
	return PLUGIN_HANDLED
}

stock GetAdminName(id, output[], outputLen)
{
	if(id > 0 && is_user_connected(id))
	{
		get_user_name(id, output, outputLen)
	}
	else
	{
		copy(output, outputLen, "Console")
	}
}

public KickMenuHandler(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu)
		ShowMapBrowser(id)
		return PLUGIN_HANDLED
	}

	if(!is_user_connected(id) || !(get_user_flags(id) & ADMIN_KICK))
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}

	new itemName[64], useridText[16], access, callback
	menu_item_getinfo(menu, item, access, useridText, charsmax(useridText),
		itemName, charsmax(itemName), callback)
	menu_destroy(menu)

	new userid = str_to_num(useridText)
	new target = find_player("k", userid)
	if(!target)
	{
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1That player is no longer connected.")
		return PLUGIN_HANDLED
	}

	new adminName[MAX_NAME_LENGTH], targetName[MAX_NAME_LENGTH]
	get_user_name(id, adminName, charsmax(adminName))
	get_user_name(target, targetName, charsmax(targetName))
	log_amx("Cmd: ^"%s^" kicked ^"%s^" (userid %d)", adminName, targetName, userid)
	client_print_color(0, print_team_default, "^4[GAMELAND] ^3%s ^1kicked ^3%s^1.", adminName, targetName)
	server_cmd("kick #%d ^"Kicked by GameLand admin.^"", userid)
	server_exec()
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
		show_menu(id, MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_6,
			"\y[GAMELAND]\w Choose your team^n^n\y1.\w Terrorist^n\y2.\w Counter-Terrorist^n^n\y6.\w Spectator",
			-1, "GAMELAND_Open_Team_Menu")
	}
}

public HandleOpenTeamMenu(id, key)
{
	if(!is_user_connected(id) || g_iJoinMode != 1)
	{
		return PLUGIN_HANDLED
	}

	// On first connection, the open-join menu exposes only 1, 2 and 6:
	// Terrorist, Counter-Terrorist and Spectator.
	if(cs_get_user_team(id) == CS_TEAM_UNASSIGNED)
	{
		if(key == 5)
		{
			MoveToFreeSpectator(id)
		}
		else if(key == 0)
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
	if(!is_user_connected(id) || g_iJoinMode == 1)
	{
		return PLUGIN_HANDLED
	}

	if(key == 9)
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
		else if(key != 9 && showMenu)
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
	g_flSpecEnteredAt[id] = get_gametime()
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
		// Keep dead CT/T players able to spectate teammates. The custom
		// ScreenFade below is reserved for actual spectators only.
		SetCvar(g_pFadeToBlack, 0)
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
		if(!is_user_connected(id) || is_user_hltv(id))
		{
			continue
		}

		new CsTeams:team = cs_get_user_team(id)
		if(team == CS_TEAM_SPECTATOR || team == CS_TEAM_UNASSIGNED)
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

stock ClearBlackScreen(id)
{
	if(!is_user_connected(id))
	{
		return
	}

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
	SortMapsByPriority()
}

stock SortMapsByPriority()
{
	new Array:ordered = ArrayCreate(32)
	new map[32]
	new priorityMap[32]

	for(new p = 0; p < 9; p++)
	{
		GetPriorityMap(p, priorityMap, charsmax(priorityMap))
		if(is_map_valid(priorityMap) && MapExists(priorityMap))
		{
			ArrayPushString(ordered, priorityMap)
		}
	}

	for(new i = 0; i < ArraySize(g_aMaps); i++)
	{
		ArrayGetString(g_aMaps, i, map, charsmax(map))
		if(!IsPriorityMap(map))
		{
			ArrayPushString(ordered, map)
		}
	}

	ArrayClear(g_aMaps)
	for(new i = 0; i < ArraySize(ordered); i++)
	{
		ArrayGetString(ordered, i, map, charsmax(map))
		ArrayPushString(g_aMaps, map)
	}
	ArrayDestroy(ordered)
}

stock GetPriorityMap(index, output[], outputLen)
{
	switch(index)
	{
		// Core competitive rotation: always keep the three primary maps first.
		case 0: copy(output, outputLen, "de_dust2")
		case 1: copy(output, outputLen, "de_inferno")
		case 2: copy(output, outputLen, "de_nuke")
		case 3: copy(output, outputLen, "de_train")
		case 4: copy(output, outputLen, "de_mirage")
		case 5: copy(output, outputLen, "de_cache")
		case 6: copy(output, outputLen, "de_cbble")
		case 7: copy(output, outputLen, "de_overpass")
		case 8: copy(output, outputLen, "de_tuscan")
		default: output[0] = 0
	}
}

stock bool:IsPriorityMap(const map[])
{
	return equali(map, "de_dust2")
		|| equali(map, "de_inferno")
		|| equali(map, "de_nuke")
		|| equali(map, "de_train")
		|| equali(map, "de_mirage")
		|| equali(map, "de_cache")
		|| equali(map, "de_cbble")
		|| equali(map, "de_overpass")
		|| equali(map, "de_tuscan")
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
