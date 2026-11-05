/* GAMELAND server admin helpers */

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <reapi>
#include <fakemeta>
#include <hamsandwich>

#define PLUGIN  "GAMELAND Admin Tools"
#define VERSION "1.4.2"
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
#define AFK_MENU_ID "GAMELAND_Afk_Menu"
#define BAN_PLAYERS_MENU_ID "GAMELAND_Ban_Players"
#define BAN_OPTIONS_MENU_ID "GAMELAND_Ban_Options"
#define MAX_BAN_ENTRIES 128
#define TASK_MAP_VOTE 19500
#define TASK_PLAYER_REDIRECT 19600
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
new g_pAfkGuard
new g_pAfkIdleTime
new g_pAfkSpecGrace
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
new bool:g_bPlayerMapVoteLocked[MAX_PLAYERS + 1]
new g_iPlayerMapSwitches[MAX_PLAYERS + 1]
new Float:g_flLastMapVoteTime[MAX_PLAYERS + 1]
new g_iVoteCreator
new g_iVoteSecondsLeft


stock bool:AdminTools_IsMixActive()
{
	if(cvar_exists("amx_mix_state") || cvar_exists("gameland_mix_version"))
	{
		return true
	}
	if(is_plugin_loaded("mix_system.amxx", true) != -1 || is_plugin_loaded("GAMELAND Match Server", false) != -1)
	{
		return true
	}
	return false
}

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

	// Handled by mix_system.sma for [Pick] hostname management
	// register_clcmd("say /spec", "CmdMoveAllToSpec", ADMIN_CVAR)
	// register_clcmd("say_team /spec", "CmdMoveAllToSpec", ADMIN_CVAR)
	// register_clcmd("spec", "CmdMoveAllToSpec", ADMIN_CVAR)
	register_clcmd("say /st", "CmdSwapTeams", ADMIN_CVAR)
	register_clcmd("say_team /st", "CmdSwapTeams", ADMIN_CVAR)
	register_clcmd("st", "CmdSwapTeams", ADMIN_CVAR)
	register_clcmd("say /r", "CmdRestartRound", ADMIN_CVAR)
	register_clcmd("say_team /r", "CmdRestartRound", ADMIN_CVAR)
	register_clcmd("r", "CmdRestartRound", ADMIN_CVAR)
	register_clcmd("say /restart", "CmdRestartRound", ADMIN_CVAR)
	register_clcmd("say_team /restart", "CmdRestartRound", ADMIN_CVAR)
	register_clcmd("restart", "CmdRestartRound", ADMIN_CVAR)
	register_clcmd("say /afk", "CmdAfkGuardMenu", ADMIN_CVAR)
	register_clcmd("say_team /afk", "CmdAfkGuardMenu", ADMIN_CVAR)
	register_clcmd("afk", "CmdAfkGuardMenu", ADMIN_CVAR)
	register_concmd("amx_afk_guard", "CmdConAfkGuard", ADMIN_CVAR, "<0|1|2> - 0: Disabled (Test), 1: Full Guard, 2: Spec Only")
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
	register_clcmd("say /j3", "CmdJoinLock", ADMIN_CVAR)
	register_clcmd("say_team /j3", "CmdJoinLock", ADMIN_CVAR)
	register_clcmd("j3", "CmdJoinLock", ADMIN_CVAR)
	register_clcmd("say /lockjoin", "CmdJoinLock", ADMIN_CVAR)
	register_clcmd("say_team /lockjoin", "CmdJoinLock", ADMIN_CVAR)
	register_clcmd("lockjoin", "CmdJoinLock", ADMIN_CVAR)
	register_clcmd("jointeam", "CmdJoinTeam")
	register_clcmd("chooseteam", "CmdChooseTeam")
	register_clcmd("say /sv2", "Cmd_AdminToolsTemp2")
	register_clcmd("say_team /sv2", "Cmd_AdminToolsTemp2")
	register_clcmd("sv2", "Cmd_AdminToolsTemp2")
	register_clcmd("say /sv3", "Cmd_AdminToolsTemp3")
	register_clcmd("say_team /sv3", "Cmd_AdminToolsTemp3")
	register_clcmd("sv3", "Cmd_AdminToolsTemp3")
	register_forward(FM_ClientCommand, "HookClientCommand")
	register_forward(FM_CmdStart, "HookCmdStart", 1)
	register_message(get_user_msgid("ShowMenu"), "MessageShowMenu")
	RegisterHookChain(RG_ShowVGUIMenu, "AdminTools_ShowVGUIMenu_Pre")
	RegisterHookChain(RG_HandleMenu_ChooseTeam, "HookChooseTeam_Pre")
	register_menucmd(register_menuid("Team_Select", 1), 1023, "HookTeamSelectMenu")
	register_menucmd(register_menuid(JOIN_MENU_ID, 1), MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_0, "HandleJoinMenu")
	register_menucmd(register_menuid("GAMELAND_Open_Team_Menu", 1), 1023, "HandleOpenTeamMenu")
	register_menucmd(register_menuid("GAMELAND_Map_Categories", 1), MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_3 | MENU_KEY_0, "HandleMapCategoryMenu")
	register_menucmd(register_menuid("GAMELAND_VoteMap_Select", 1), 1023, "HandleVoteMapSelect")
	register_menucmd(register_menuid("GAMELAND_Vote_Map_Choice", 1), 1023, "HandleVoteMapChoice")
	register_menucmd(register_menuid(SPEC_CONFIRM_MENU_ID, 1), MENU_KEY_1 | MENU_KEY_2, "HandleSpecConfirmMenu")
	register_menucmd(register_menuid(AFK_MENU_ID, 1), MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_3 | MENU_KEY_0, "HandleAfkGuardMenu")

	g_pAllowSpectators = get_cvar_pointer("allow_spectators")
	g_pForceCamera = get_cvar_pointer("mp_forcecamera")
	g_pForceChaseCam = get_cvar_pointer("mp_forcechasecam")
	g_pFadeToBlack = get_cvar_pointer("mp_fadetoblack")
	g_pJoinMode = register_cvar("gameland_join_mode", "1")
	g_pAfkGuard = register_cvar("gameland_afk_guard", "0")
	g_pAfkIdleTime = register_cvar("gameland_afk_idle_time", "120")
	g_pAfkSpecGrace = register_cvar("gameland_afk_spec_grace", "300")
	g_iJoinMode = clamp(get_pcvar_num(g_pJoinMode), 0, 3)
	if(g_iJoinMode == 2)
	{
		set_task(0.5, "RefreshBlackScreen", TASK_BLACK_SCREEN, _, _, "b")
	}

	g_aMaps = ArrayCreate(32)
	LoadMaps()
	set_task(5.0, "TaskSpecGuard", TASK_SPEC_GUARD, _, _, "b")
	RegisterHam(Ham_Weapon_SecondaryAttack, "weapon_famas", "Ham_FamasSecondaryAttack_Pre", 0)
	// set_task(1.0, "Task_EnsureFastDuckFixSourceUpdated")
}

stock bool:CheckAdminToolsJoinLock(id)
{
	if(g_iJoinMode != 3 && get_cvar_num("gameland_join_lock") != 1)
		return false

	if(is_user_hltv(id) || is_user_bot(id))
		return false

	if(IsAdminExempt(id))
		return false

	rh_drop_client(id, "Server is currently locked by Admin [/j3]")
	server_cmd("kick #%d ^"Server is currently locked by Admin [/j3]^"", get_user_userid(id))
	server_exec()
	return true
}

public client_authorized(id, const authid[])
{
	if(CheckAdminToolsJoinLock(id))
		return
}

public client_putinserver(id)
{
	if(CheckAdminToolsJoinLock(id))
		return

	g_flLastActivity[id] = get_gametime()
	g_flSpecEnteredAt[id] = 0.0
	g_bSpecConfirmOpen[id] = false
	g_iPlayerVote[id] = -1
	g_bPlayerMapVoteLocked[id] = false
	g_iPlayerMapSwitches[id] = 0
	g_flLastMapVoteTime[id] = 0.0
	set_task(0.4, "ShowInitialJoinMenu", TASK_INITIAL_JOIN_MENU + id)
}

public MessageShowMenu(msgId, msgDest, id)
{
	if(AdminTools_IsMixActive())
	{
		return PLUGIN_CONTINUE
	}

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
	if(g_bMapVoteActive && g_iPlayerVote[id] >= 0 && g_iPlayerVote[id] < g_iVoteMapCount)
	{
		g_iVoteCount[g_iPlayerVote[id]]--
		UpdateMapVoteHud()
	}
	g_iPlayerVote[id] = -1
	g_bPlayerMapVoteLocked[id] = false
	g_iPlayerMapSwitches[id] = 0
	g_flLastMapVoteTime[id] = 0.0
	arrayset(g_bVoteMapSelected[id], false, MAX_MAPS)
	g_iVoteMapPage[id] = 0
}

public ShowInitialJoinMenu(taskId)
{
	if(AdminTools_IsMixActive())
	{
		return
	}

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
	if(AdminTools_IsMixActive())
	{
		return
	}

	new afkMode = get_pcvar_num(g_pAfkGuard)
	if(afkMode <= 0)
	{
		for(new id = 1; id <= get_maxplayers(); id++)
		{
			if(g_flSpecEnteredAt[id] > 0.0 || g_bSpecConfirmOpen[id])
			{
				ResetSpecGuard(id)
			}
		}
		return
	}

	new Float:now = get_gametime()
	new idleLimitSec = get_pcvar_num(g_pAfkIdleTime)
	if(idleLimitSec < 30) idleLimitSec = 120
	new Float:idleLimit = float(idleLimitSec)

	new graceLimitSec = get_pcvar_num(g_pAfkSpecGrace)
	if(graceLimitSec < 60) graceLimitSec = 300
	new Float:graceLimit = float(graceLimitSec)

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
		&& now - g_flLastActivity[id] >= idleLimit)
		{
			client_print_color(id, print_team_default, "^4[GAMELAND] ^1You were moved to Spectator after %d minutes of inactivity.", floatround(idleLimit / 60.0))
			MoveToFreeSpectator(id)
			continue
		}

		if(team != CS_TEAM_SPECTATOR)
		{
			ResetSpecGuard(id)
			continue
		}

		// Mode 2: Spec Only (move to spec after idle time, but NEVER kick)
		if(afkMode == 2)
		{
			ResetSpecGuard(id)
			continue
		}

		// Mode 1: Full AFK Guard (spectator timeout confirmation and kick)
		if(g_flSpecEnteredAt[id] <= 0.0)
		{
			g_flSpecEnteredAt[id] = now
			continue
		}

		if(!g_bSpecConfirmOpen[id] && now - g_flSpecEnteredAt[id] >= graceLimit)
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

	if(get_pcvar_num(g_pAfkGuard) == 1 && !IsAdminExempt(id) && cs_get_user_team(id) == CS_TEAM_SPECTATOR)
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
	g_iVoteCreator = admin
	g_iVoteSecondsLeft = floatround(MAP_VOTE_DURATION)
	for(new id = 1; id <= MAX_PLAYERS; id++)
	{
		g_iPlayerVote[id] = -1
		g_bPlayerMapVoteLocked[id] = false
		g_iPlayerMapSwitches[id] = 0
		g_flLastMapVoteTime[id] = 0.0
	}

	for(new player = 1; player <= MAX_PLAYERS; player++)
	{
		if(is_user_connected(player) && !is_user_hltv(player))
		{
			ShowMapVotePlayerMenu(player)
		}
	}

	set_task(0.2, "ReopenVoteForCreator", TASK_MAP_VOTE + 3)
	client_print_color(0, print_team_default, "^4[GAMELAND] ^1Map vote started. You have ^4%d seconds^1 to vote.", g_iVoteSecondsLeft)
	remove_task(TASK_MAP_VOTE + 2)
	set_task(1.0, "UpdateMapVoteStatus", TASK_MAP_VOTE + 2, _, _, "b")
	set_task(MAP_VOTE_DURATION, "FinishMapVote", TASK_MAP_VOTE)
}

public ReopenVoteForCreator()
{
	if(g_bMapVoteActive && is_user_connected(g_iVoteCreator))
	{
		ShowMapVotePlayerMenu(g_iVoteCreator)
	}
}

stock ShowMapVotePlayerMenu(id)
{
	if(!g_bMapVoteActive || !is_user_connected(id) || is_user_hltv(id) || g_bPlayerMapVoteLocked[id])
	{
		return
	}

	new szMenu[512]
	new iLen = 0

	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y[GAMELAND] Choose Next Map \r[%02d sec]\w^n", g_iVoteSecondsLeft)
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d(Press selected map again to Confirm & Close)^n\d(Max 3 switches allowed)^n^n")

	new map[32], keys = 0
	for(new i = 0; i < g_iVoteMapCount; i++)
	{
		ArrayGetString(g_aMaps, g_iVoteMapIndex[i], map, charsmax(map))
		new iVotes = g_iVoteCount[i]
		keys |= (1 << i)

		if(g_iPlayerVote[id] == i)
		{
			iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y%d. \y[*] \w%s \y[Selected - Press %d to Confirm] \d(%d vote%s)^n", i + 1, map, i + 1, iVotes, iVotes == 1 ? "" : "s")
		}
		else
		{
			new iNext = (g_iPlayerVote[id] < 0) ? 0 : g_iPlayerMapSwitches[id] + 1
			if(g_iPlayerVote[id] >= 0)
				iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y%d. \w%s \d(Switch [%d/3]) \d(%d vote%s)^n", i + 1, map, iNext, iVotes, iVotes == 1 ? "" : "s")
			else
				iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y%d. \w%s \d(%d vote%s)^n", i + 1, map, iVotes, iVotes == 1 ? "" : "s")
		}
	}

	show_menu(id, keys, szMenu, -1, "GAMELAND_Vote_Map_Choice")
}

public HandleVoteMapChoice(id, key)
{
	if(!g_bMapVoteActive || key < 0 || key >= g_iVoteMapCount || !is_user_connected(id) || g_bPlayerMapVoteLocked[id])
	{
		return PLUGIN_HANDLED
	}

	new Float:flGameTime = get_gametime()
	if(flGameTime - g_flLastMapVoteTime[id] < 0.35)
		return PLUGIN_HANDLED
	g_flLastMapVoteTime[id] = flGameTime

	new map[32]
	ArrayGetString(g_aMaps, g_iVoteMapIndex[key], map, charsmax(map))

	// 1. Re-press the same option -> Confirm & Lock & Close
	if(g_iPlayerVote[id] == key)
	{
		g_bPlayerMapVoteLocked[id] = true
		show_menu(id, 0, "^n", 1)
		client_cmd(id, "spk buttons/blip1")

		client_print_color(id, print_team_default, "^4[GAMELAND] ^1Your vote for ^3%s ^1is ^4CONFIRMED & LOCKED^1! (Menu closed)", map)
		return PLUGIN_HANDLED
	}

	// 2. Switch or Initial Vote
	new bool:bSwitched = (g_iPlayerVote[id] >= 0 && g_iPlayerVote[id] < g_iVoteMapCount)
	if(bSwitched)
	{
		g_iPlayerMapSwitches[id]++
		g_iVoteCount[g_iPlayerVote[id]]--
	}

	g_iPlayerVote[id] = key
	g_iVoteCount[key]++

	// Check max 3 switches reached
	if(g_iPlayerMapSwitches[id] >= 3)
	{
		g_bPlayerMapVoteLocked[id] = true
		show_menu(id, 0, "^n", 1)
		client_cmd(id, "spk buttons/blip1")

		client_print_color(id, print_team_default, "^4[GAMELAND] ^1Max switches reached ^4(3/3)^1. Your vote for ^3%s ^1is now ^4LOCKED^1!", map)
		UpdateMapVoteHud()
		return PLUGIN_HANDLED
	}

	if(bSwitched)
	{
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1Switched vote to: ^4%s ^1(Switch ^4%d/3^1). ^2Press %d again to Confirm & Lock^1.",
			map, g_iPlayerMapSwitches[id], key + 1)
	}
	else
	{
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1You voted for: ^4%s^1. ^2Press %d again to Confirm & Lock^1.",
			map, key + 1)
	}

	// Update only this player's menu immediately
	ShowMapVotePlayerMenu(id)
	UpdateMapVoteHud()

	return PLUGIN_HANDLED
}

public UpdateMapVoteStatus()
{
	if(!g_bMapVoteActive)
	{
		remove_task(TASK_MAP_VOTE + 2)
		return
	}

	if(g_iVoteSecondsLeft > 0)
	{
		g_iVoteSecondsLeft--
	}

	for(new p = 1; p <= MAX_PLAYERS; p++)
	{
		if(is_user_connected(p) && !is_user_hltv(p) && !g_bPlayerMapVoteLocked[p])
		{
			ShowMapVotePlayerMenu(p)
		}
	}

	UpdateMapVoteHud()
}

stock UpdateMapVoteHud()
{
	if(!g_bMapVoteActive)
	{
		return
	}

	new message[256], map[32], line[48]
	formatex(message, charsmax(message), "MAP VOTE  [%02d sec]^n", g_iVoteSecondsLeft)
	for(new i = 0; i < g_iVoteMapCount; i++)
	{
		ArrayGetString(g_aMaps, g_iVoteMapIndex[i], map, charsmax(map))
		formatex(line, charsmax(line), "%s: %d vote%s^n", map, g_iVoteCount[i], g_iVoteCount[i] == 1 ? "" : "s")
		add(message, charsmax(message), line)
	}

	set_hudmessage(255, 220, 80, 0.72, 0.18, 0, 0.0, 1.1, 0.0, 0.0, -1)
	show_hudmessage(0, message)
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
	remove_task(TASK_MAP_VOTE + 2)
	remove_task(TASK_MAP_VOTE + 3)

	for(new p = 1; p <= MAX_PLAYERS; p++)
	{
		if(is_user_connected(p))
		{
			show_menu(p, 0, "^n", 1)
		}
	}

	g_iVoteCreator = 0
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
	if(AdminTools_IsMixActive())
	{
		return PLUGIN_CONTINUE
	}

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
	if(AdminTools_IsMixActive())
	{
		return PLUGIN_CONTINUE
	}

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

public CmdJoinLock(id, level, cid)
{
	new newMode = (g_iJoinMode == 3) ? 1 : 3
	return SetJoinMode(id, level, cid, newMode)
}

public CmdJoinTeam(id)
{
	if(AdminTools_IsMixActive())
	{
		return PLUGIN_CONTINUE
	}

	if(!IsJoinLockedPlayer(id))
	{
		return PLUGIN_CONTINUE
	}

	new requested[8]
	read_argv(1, requested, charsmax(requested))
	if(equali(requested, "7") || equali(requested, "8") || equali(requested, "9"))
	{
		HandleAdminToolsServerTransfer(id, str_to_num(requested))
		return PLUGIN_HANDLED
	}
	if(equali(requested, "1") || equali(requested, "2") || equali(requested, "5") || equali(requested, "6"))
	{
		ApplyRestrictedJoinKey(id, str_to_num(requested) - 1, true)
		return PLUGIN_HANDLED
	}

	return PLUGIN_CONTINUE
}

public CmdChooseTeam(id)
{
	if(AdminTools_IsMixActive())
	{
		return PLUGIN_CONTINUE
	}

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



	return CmdJoinTeam(id)
}

public AdminTools_ShowVGUIMenu_Pre(id, VGUIMenu:menuType, const bitsSlots, szOldMenu[])
{
	if(AdminTools_IsMixActive())
	{
		return HC_CONTINUE
	}

	if(menuType == VGUI_Menu_Team)
	{
		if(g_iJoinMode == 1)
		{
			ShowOpenTeamMenu(id)
			return HC_SUPERCEDE
		}
		else if(IsJoinLockedPlayer(id))
		{
			ShowRestrictedJoinMenu(id)
			return HC_SUPERCEDE
		}
	}
	return HC_CONTINUE
}

public Cmd_AdminToolsTemp2(id)
{
	if(AdminTools_IsMixActive())
	{
		return PLUGIN_CONTINUE
	}

	new iCurrentTemp = 0, szCurParent[32]
	new bool:bIsTemp = AdminTools_IsCurrentServerTemp(iCurrentTemp, szCurParent, charsmax(szCurParent))
	if(bIsTemp && iCurrentTemp == 2)
	{
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1You are already connected to ^3Temp Server #2^1.")
		return PLUGIN_HANDLED
	}

	AdminTools_TransferPlayerToServer(id, AdminTools_GetTempServerPort(2), "Temp Server #2")
	return PLUGIN_HANDLED
}

public Cmd_AdminToolsTemp3(id)
{
	if(AdminTools_IsMixActive())
	{
		return PLUGIN_CONTINUE
	}

	new iCurrentTemp = 0, szCurParent[32]
	new bool:bIsTemp = AdminTools_IsCurrentServerTemp(iCurrentTemp, szCurParent, charsmax(szCurParent))
	if(bIsTemp && iCurrentTemp == 3)
	{
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1You are already connected to ^3Temp Server #3^1.")
		return PLUGIN_HANDLED
	}

	AdminTools_TransferPlayerToServer(id, AdminTools_GetTempServerPort(3), "Temp Server #3")
	return PLUGIN_HANDLED
}

stock AdminTools_GetServerCurrentPort()
{
	new iPort = get_cvar_num("port")
	if(iPort >= 1024 && iPort <= 65535)
		return iPort

	new szIp[32]
	get_user_ip(0, szIp, charsmax(szIp), 0)
	new iColon = contain(szIp, ":")
	if(iColon != -1)
	{
		iPort = str_to_num(szIp[iColon + 1])
		if(iPort >= 1024 && iPort <= 65535)
			return iPort
	}

	return 27015
}

stock bool:AdminTools_IsCurrentServerTemp(&iCurrentTempIndex, szParentId[], iParentMaxLen)
{
	iCurrentTempIndex = 0
	copy(szParentId, iParentMaxLen, "main")

	new szInstance[32]
	get_cvar_string("gameland_instance_id", szInstance, charsmax(szInstance))
	trim(szInstance)
	if(!szInstance[0])
	{
		new iPort = AdminTools_GetServerCurrentPort()
		if(iPort == 27015 || iPort <= 0)
			copy(szInstance, charsmax(szInstance), "main")
		else
			formatex(szInstance, charsmax(szInstance), "cs_%d", iPort)
	}

	new iLen = strlen(szInstance)
	if(iLen >= 4 && szInstance[iLen - 4] == '_' && szInstance[iLen - 3] == 's' && szInstance[iLen - 2] == 'v')
	{
		if(szInstance[iLen - 1] == '2')
		{
			iCurrentTempIndex = 2
			copy(szParentId, iParentMaxLen, szInstance)
			szParentId[iLen - 4] = '^0'
			return true
		}
		else if(szInstance[iLen - 1] == '3')
		{
			iCurrentTempIndex = 3
			copy(szParentId, iParentMaxLen, szInstance)
			szParentId[iLen - 4] = '^0'
			return true
		}
	}

	// Secondary check: examine hostname for "[SV2]" / "_sv2" or "[SV3]" / "_sv3"
	new szHostname[64]
	get_cvar_string("hostname", szHostname, charsmax(szHostname))
	if(containi(szHostname, "[SV2]") != -1 || containi(szHostname, "_sv2") != -1)
	{
		iCurrentTempIndex = 2
		copy(szParentId, iParentMaxLen, szInstance)
		return true
	}
	else if(containi(szHostname, "[SV3]") != -1 || containi(szHostname, "_sv3") != -1)
	{
		iCurrentTempIndex = 3
		copy(szParentId, iParentMaxLen, szInstance)
		return true
	}

	copy(szParentId, iParentMaxLen, szInstance)
	return false
}

stock AdminTools_GetParentServerId(szOut[], iMaxLen)
{
	new iTempIdx
	if(AdminTools_IsCurrentServerTemp(iTempIdx, szOut, iMaxLen))
	{
		return
	}

	new szInstance[32]
	get_cvar_string("gameland_instance_id", szInstance, charsmax(szInstance))
	trim(szInstance)
	if(szInstance[0])
	{
		copy(szOut, iMaxLen, szInstance)
	}
	else
	{
		new iPort = AdminTools_GetServerCurrentPort()
		if(iPort == 27015 || iPort <= 0)
			copy(szOut, iMaxLen, "main")
		else
			formatex(szOut, iMaxLen, "cs_%d", iPort)
	}
}

stock AdminTools_GetTempServerId(iTempIndex, szOut[], iMaxLen)
{
	new szParent[32], iCurrentTempIndex
	if(AdminTools_IsCurrentServerTemp(iCurrentTempIndex, szParent, charsmax(szParent)))
	{
		if(iCurrentTempIndex == iTempIndex)
		{
			get_cvar_string("gameland_instance_id", szOut, iMaxLen)
			trim(szOut)
			return
		}
	}
	else
	{
		AdminTools_GetParentServerId(szParent, charsmax(szParent))
	}

	formatex(szOut, iMaxLen, "%s_sv%d", szParent, iTempIndex)
}

stock AdminTools_GetTempServerPort(iTempIndex)
{
	new szParent[32], iCurrentTempIndex
	new iCurrentPort = AdminTools_GetServerCurrentPort()
	if(AdminTools_IsCurrentServerTemp(iCurrentTempIndex, szParent, charsmax(szParent)))
	{
		if(iCurrentTempIndex == iTempIndex)
			return iCurrentPort

		new iParentPort = (iCurrentTempIndex == 2) ? (iCurrentPort - 100) : (iCurrentPort - 101)
		return (iTempIndex == 2) ? (iParentPort + 100) : (iParentPort + 101)
	}

	return (iTempIndex == 2) ? (iCurrentPort + 100) : (iCurrentPort + 101)
}

stock AdminTools_GetParentServerPort()
{
	new szParent[32], iCurrentTempIndex
	new iCurrentPort = AdminTools_GetServerCurrentPort()
	if(AdminTools_IsCurrentServerTemp(iCurrentTempIndex, szParent, charsmax(szParent)))
	{
		return (iCurrentTempIndex == 2) ? (iCurrentPort - 100) : (iCurrentPort - 101)
	}
	return iCurrentPort
}

stock bool:AdminTools_ReadTempServerStatus(const szTempId[], &bool:bRunning, &iExpireAt, &iRemainingSec, &iSlots)
{
	bRunning = false
	iExpireAt = 0
	iRemainingSec = 0
	iSlots = 15

	new szDataDir[96]
	get_datadir(szDataDir, charsmax(szDataDir))

	new szCandidateStatus[4][192]
	new iStatusCount = 0
	formatex(szCandidateStatus[iStatusCount++], charsmax(szCandidateStatus[]), "/tmp/gameland_temp_status/%s.status", szTempId)
	formatex(szCandidateStatus[iStatusCount++], charsmax(szCandidateStatus[]), "/opt/gameland/instances/.status/%s.status", szTempId)
	formatex(szCandidateStatus[iStatusCount++], charsmax(szCandidateStatus[]), "instances/.status/%s.status", szTempId)
	formatex(szCandidateStatus[iStatusCount++], charsmax(szCandidateStatus[]), "%s/temp_servers/status/%s.status", szDataDir, szTempId)

	new iFile = 0
	for(new i = 0; i < iStatusCount; i++)
	{
		iFile = fopen(szCandidateStatus[i], "rt")
		if(iFile)
			break
	}

	if(iFile)
	{
		new szLine[128], szKey[32], szVal[64]
		while(!feof(iFile))
		{
			fgets(iFile, szLine, charsmax(szLine))
			trim(szLine)
			if(!szLine[0] || szLine[0] == ';' || szLine[0] == '#')
				continue

			if(contain(szLine, "=") != -1)
			{
				strtok2(szLine, szKey, charsmax(szKey), szVal, charsmax(szVal), '=', TRIM_INNER)
				trim(szKey)
				trim(szVal)

				if(equali(szKey, "running"))
					bRunning = (str_to_num(szVal) == 1)
				else if(equali(szKey, "expire_at"))
					iExpireAt = str_to_num(szVal)
				else if(equali(szKey, "slots"))
					iSlots = str_to_num(szVal)
			}
			else if(isdigit(szLine[0]))
			{
				iExpireAt = str_to_num(szLine)
			}
		}
		fclose(iFile)

		new iNow = get_systime()
		if(bRunning)
		{
			if(iExpireAt > iNow)
				iRemainingSec = iExpireAt - iNow
			else if(iExpireAt > 0 && iNow >= iExpireAt)
			{
				bRunning = false
				iRemainingSec = 0
			}
			else
				iRemainingSec = 14400
		}
		return true
	}

	new szCandidateExpire[4][192]
	new iExpCount = 0
	formatex(szCandidateExpire[iExpCount++], charsmax(szCandidateExpire[]), "/opt/gameland/instances/%s.expire", szTempId)
	formatex(szCandidateExpire[iExpCount++], charsmax(szCandidateExpire[]), "instances/%s.expire", szTempId)
	formatex(szCandidateExpire[iExpCount++], charsmax(szCandidateExpire[]), "/tmp/gameland_temp_status/%s.expire", szTempId)
	formatex(szCandidateExpire[iExpCount++], charsmax(szCandidateExpire[]), "%s/temp_servers/%s.expire", szDataDir, szTempId)

	for(new i = 0; i < iExpCount; i++)
	{
		iFile = fopen(szCandidateExpire[i], "rt")
		if(iFile)
		{
			new szLine[64]
			if(fgets(iFile, szLine, charsmax(szLine)))
			{
				trim(szLine)
				iExpireAt = str_to_num(szLine)
			}
			fclose(iFile)

			new iNow = get_systime()
			if(iExpireAt > iNow)
			{
				bRunning = true
				iRemainingSec = iExpireAt - iNow
				return true
			}
			else if(iExpireAt > 0)
			{
				bRunning = false
				iRemainingSec = 0
				return true
			}
		}
	}

	return false
}

stock AdminTools_GetServerPublicIp(szIpOut[], iMaxLen)
{
	szIpOut[0] = '^0'

	get_cvar_string("gameland_server_ip", szIpOut, iMaxLen)
	trim(szIpOut)
	if(AdminTools_IsPublicWanIp(szIpOut))
		return

	new szCandidateFiles[5][192]
	new iFileCount = 0
	formatex(szCandidateFiles[iFileCount++], charsmax(szCandidateFiles[]), "instances/public_ip.txt")
	formatex(szCandidateFiles[iFileCount++], charsmax(szCandidateFiles[]), "cstrike/instances/public_ip.txt")
	formatex(szCandidateFiles[iFileCount++], charsmax(szCandidateFiles[]), "/opt/gameland/instances/public_ip.txt")
	formatex(szCandidateFiles[iFileCount++], charsmax(szCandidateFiles[]), "/tmp/gameland_public_ip.txt")
	formatex(szCandidateFiles[iFileCount++], charsmax(szCandidateFiles[]), "/opt/gameland/server/instances/public_ip.txt")

	for(new i = 0; i < iFileCount; i++)
	{
		new iFile = fopen(szCandidateFiles[i], "rt")
		if(iFile)
		{
			fgets(iFile, szIpOut, iMaxLen)
			fclose(iFile)
			trim(szIpOut)
			if(AdminTools_IsPublicWanIp(szIpOut))
				return
		}
	}

	get_cvar_string("net_address", szIpOut, iMaxLen)
	new iColon = contain(szIpOut, ":")
	if(iColon != -1)
		szIpOut[iColon] = '^0'
	trim(szIpOut)
	if(AdminTools_IsPublicWanIp(szIpOut))
		return

	get_user_ip(0, szIpOut, iMaxLen, 1)
	trim(szIpOut)
	if(AdminTools_IsPublicWanIp(szIpOut))
		return

	get_cvar_string("ip", szIpOut, iMaxLen)
	trim(szIpOut)
	if(AdminTools_IsPublicWanIp(szIpOut))
		return

	copy(szIpOut, iMaxLen, "185.236.38.83")
}

stock bool:AdminTools_IsPublicWanIp(const szIp[])
{
	if(!szIp[0] || equal(szIp, "0.0.0.0") || equal(szIp, "127.0.0.1") || equal(szIp, "localhost"))
		return false

	if(equal(szIp, "10.", 3) || equal(szIp, "192.168.", 8) || equal(szIp, "169.254.", 8))
		return false

	if(equal(szIp, "172.", 4))
	{
		new szSecond[4]
		new iDot = contain(szIp[4], ".")
		if(iDot != -1 && iDot <= 3)
		{
			copy(szSecond, iDot, szIp[4])
			new iSec = str_to_num(szSecond)
			if(iSec >= 16 && iSec <= 31)
				return false
		}
	}

	return true
}

stock AdminTools_SendDirectorRedirect(id, const szIp[], iPort)
{
	if(!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id))
		return

	new szCmd[96]
	formatex(szCmd, charsmax(szCmd), "connect %s:%d^n", szIp, iPort)

	static iMsgDirector = 0
	if(!iMsgDirector)
	{
		iMsgDirector = get_user_msgid("Director")
		if(iMsgDirector <= 0)
			iMsgDirector = 51
	}

	message_begin(MSG_ONE, iMsgDirector, _, id)
	write_byte(strlen(szCmd) + 2)
	write_byte(DRC_CMD_STUFFTEXT) // 12 (DRC_CMD_STUFFTEXT)
	write_string(szCmd)
	message_end()
}

public Task_AdminToolsDelayedRedirect(const aData[])
{
	new id = aData[0]
	new iPort = aData[1]
	if(!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id))
		return

	new szIp[32]
	AdminTools_GetServerPublicIp(szIp, charsmax(szIp))

	client_cmd(id, "slot10")
	client_cmd(id, "Connect %s:%d", szIp, iPort)
	client_cmd(id, "connect %s:%d", szIp, iPort)
	client_cmd(id, ";connect %s:%d", szIp, iPort)
	client_cmd(id, "engine connect %s:%d", szIp, iPort)
	AdminTools_SendDirectorRedirect(id, szIp, iPort)
}

stock AdminTools_TransferPlayerToServer(id, iTargetPort, const szServerName[])
{
	if(!is_user_connected(id))
		return

	new szIp[32], szName[MAX_NAME_LENGTH]
	AdminTools_GetServerPublicIp(szIp, charsmax(szIp))
	get_user_name(id, szName, charsmax(szName))

	// 1. In-game Chat Notice (Clean & Professional - NO IP LEAK)
	client_print_color(id, print_team_default, "^4[GAMELAND] ^1Transferring you to ^3%s^1...", szServerName)
	client_print_color(0, print_team_default, "^4[GAMELAND] ^3%s ^1is transferring to ^3%s^1.", szName, szServerName)

	// 2. High-visibility Top-screen DHUD notice (Clean - NO IP LEAK)
	set_dhudmessage(0, 220, 255, -1.0, 0.20, 0, 0.0, 4.0, 0.1, 0.5)
	show_dhudmessage(id, "[GAMELAND] Transferring to %s...", szServerName)

	// 3. Clean Console Output (NO IP LEAK)
	console_print(id, " ")
	console_print(id, "==========================================================")
	console_print(id, "[GAMELAND] Connecting to %s...", szServerName)
	console_print(id, "==========================================================")
	console_print(id, " ")

	// 4. Force dismissal of any active menu before connecting
	show_menu(id, 0, "^n", 0)
	client_cmd(id, "slot10")

	// 5. Multi-Layer Client Command executions without newline
	client_cmd(id, "Connect %s:%d", szIp, iTargetPort)
	client_cmd(id, "connect %s:%d", szIp, iTargetPort)
	client_cmd(id, ";connect %s:%d", szIp, iTargetPort)
	client_cmd(id, "engine connect %s:%d", szIp, iTargetPort)

	// 6. SVC_DIRECTOR engine redirect (bypasses some client-side stufftext blockers)
	AdminTools_SendDirectorRedirect(id, szIp, iTargetPort)

	// 7. Instant HTML MOTD Redirect (Triggers steam://connect for Steam & modern clients)
	new szMotd[512]
	formatex(szMotd, charsmax(szMotd),
		"<html><head><meta http-equiv=^"refresh^" content=^"0;url=steam://connect/%s:%d^"><script>window.location=^"steam://connect/%s:%d^";</script></head><body bgcolor=^"#000000^" style=^"color:#fff;text-align:center;font-family:sans-serif;padding-top:40px;^"><h2>Transferring to %s...</h2></body></html>",
		szIp, iTargetPort, szIp, iTargetPort, szServerName)
	show_motd(id, szMotd, "GAMELAND Transfer")

	// 8. Delayed follow-up redirect task (ensures execution after menu dismissal)
	new aData[2]
	aData[0] = id
	aData[1] = iTargetPort
	set_task(0.2, "Task_AdminToolsDelayedRedirect", TASK_PLAYER_REDIRECT + id, aData, sizeof(aData))
	set_task(0.6, "Task_AdminToolsDelayedRedirect", TASK_PLAYER_REDIRECT + id + 100, aData, sizeof(aData))
}

stock HandleAdminToolsServerTransfer(id, iKeyNum)
{
	if(!is_user_connected(id))
		return

	new iCurrentTemp = 0, szCurParent[32]
	new bool:bIsTemp = AdminTools_IsCurrentServerTemp(iCurrentTemp, szCurParent, charsmax(szCurParent))

	if(!bIsTemp)
	{
		// On Main Server
		if(iKeyNum == 7)
		{
			AdminTools_TransferPlayerToServer(id, AdminTools_GetTempServerPort(2), "Temp Server #2")
		}
		else if(iKeyNum == 8 || iKeyNum == 9)
		{
			AdminTools_TransferPlayerToServer(id, AdminTools_GetTempServerPort(3), "Temp Server #3")
		}
	}
	else
	{
		// On Temp Server
		new iCurPort = AdminTools_GetServerCurrentPort()
		new iParentPort = (iCurrentTemp == 2) ? (iCurPort - 100) : (iCurPort - 101)
		new iOtherTemp = (iCurrentTemp == 2) ? 3 : 2

		if(iKeyNum == 7)
		{
			AdminTools_TransferPlayerToServer(id, iParentPort, "Main Server")
		}
		else if(iKeyNum == 8 || iKeyNum == 9)
		{
			new szTargetName[32]
			formatex(szTargetName, charsmax(szTargetName), "Temp Server #%d", iOtherTemp)
			AdminTools_TransferPlayerToServer(id, AdminTools_GetTempServerPort(iOtherTemp), szTargetName)
		}
	}
}

public ShowOpenTeamMenu(id)
{
	if(AdminTools_IsMixActive() || !is_user_connected(id))
	{
		return
	}

	new iKeys = MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_6 | MENU_KEY_0
	new szMenu[256], iLen = 0

	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y[GAMELAND]\w Select Team^n^n")
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y1.\w Terrorist Force^n")
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y2.\w Counter-Terrorist Force^n^n")
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y6.\w Spectator^n^n")
	iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y0.\w Cancel")

	set_member(id, m_iMenu, CS_Menu_OFF)
	show_menu(id, iKeys, szMenu, -1, "GAMELAND_Open_Team_Menu")
}

stock AdminTools_SpawnPlayerOnTeam(id, TeamName:iNewTeam)
{
	if(!is_user_connected(id))
		return

	remove_task(id)

	if(is_user_alive(id))
	{
		user_silentkill(id)
	}

	new iFlags = get_entvar(id, var_flags)
	if(iFlags & FL_SPECTATOR)
	{
		set_entvar(id, var_flags, iFlags & ~FL_SPECTATOR)
	}
	set_entvar(id, var_iuser1, OBS_NONE)
	set_entvar(id, var_iuser2, 0)
	set_member(id, m_hObserverTarget, 0)
	set_entvar(id, var_deadflag, DEAD_NO)

	set_member(id, m_iJoiningState, JOINED)
	rg_set_user_team(id, iNewTeam, MODEL_AUTO)
	set_member(id, m_iMenu, CS_Menu_OFF)

	rg_round_respawn(id)
}

public HandleOpenTeamMenu(id, key)
{
	if(AdminTools_IsMixActive() || !is_user_connected(id) || g_iJoinMode != 1)
	{
		return PLUGIN_HANDLED
	}

	if(key == 0) // Key 1: Terrorist
	{
		if(cs_get_user_team(id) == CS_TEAM_T)
		{
			client_print_color(id, print_team_default, "^4[GAMELAND] ^1You are already on the ^3Terrorist ^1team.")
			return PLUGIN_HANDLED
		}
		AdminTools_SpawnPlayerOnTeam(id, TEAM_TERRORIST)
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1You joined the ^3Terrorist ^1team.")
	}
	else if(key == 1) // Key 2: Counter-Terrorist
	{
		if(cs_get_user_team(id) == CS_TEAM_CT)
		{
			client_print_color(id, print_team_default, "^4[GAMELAND] ^1You are already on the ^3Counter-Terrorist ^1team.")
			return PLUGIN_HANDLED
		}
		AdminTools_SpawnPlayerOnTeam(id, TEAM_CT)
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1You joined the ^3Counter-Terrorist ^1team.")
	}
	else if(key == 5) // Key 6: Spectator
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

public Task_AdminTools_InitSpec(id)
{
	if(!is_user_connected(id) || is_user_alive(id))
		return

	rg_observer_find_next_player(id, false)
	rg_set_observer_mode(id, 4)
}

stock MoveToFreeSpectator(id)
{
	if(!is_user_connected(id))
	{
		return
	}

	if(cs_get_user_team(id) == CS_TEAM_SPECTATOR)
	{
		client_print_color(id, print_team_default, "^4[GAMELAND] ^1You are already a ^3Spectator^1.")
		return
	}

	remove_task(id)

	if(is_user_alive(id))
	{
		user_silentkill(id)
	}

	rg_set_user_team(id, TEAM_SPECTATOR)
	set_member(id, m_iMenu, CS_Menu_OFF)

	set_task(0.1, "Task_AdminTools_InitSpec", id)

	client_print_color(id, print_team_default, "^4[GAMELAND] ^1You moved to ^3Spectator^1.")
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
	set_task(0.1, "Task_AdminTools_InitSpec", id)
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

	new commandName[32]
	read_argv(0, commandName, charsmax(commandName))

	// When mix_system is active, mix_system owns team selection & M menu completely!
	if(equali(commandName, "chooseteam") || equali(commandName, "jointeam"))
	{
		if(AdminTools_IsMixActive())
		{
			return FMRES_IGNORED
		}
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
	if(AdminTools_IsMixActive())
	{
		return HC_CONTINUE
	}

	if(!IsJoinLockedPlayer(id))
	{
		return HC_CONTINUE
	}

	if(slot == MenuChoose_T || slot == MenuChoose_CT || slot == MenuChoose_AutoSelect || slot == MenuChoose_Spec)
	{
		SetHookChainReturn(ATYPE_BOOL, false)
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

	if(mode == 3)
	{
		remove_task(TASK_BLACK_SCREEN)
		SetCvar(g_pForceCamera, 0)
		SetCvar(g_pForceChaseCam, 0)
		SetCvar(g_pFadeToBlack, 0)
		ClearBlackScreens()
		set_cvar_num("gameland_join_lock", 1)
	}
	else if(mode == 2)
	{
		set_cvar_num("gameland_join_lock", 0)
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
		set_cvar_num("gameland_join_lock", 0)
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
public Ham_FamasSecondaryAttack_Pre(weapon)
{
	if (!pev_valid(weapon))
		return HAM_IGNORED

	// m_fInReload = 54 (linux diff +4 = 58)
	if (get_pdata_int(weapon, 54, 4))
	{
		return HAM_SUPERCEDE
	}

	return HAM_IGNORED
}

public Task_EnsureFastDuckFixSourceUpdated()
{
	new const candidatePaths[][] = {
		"/opt/gameland/server/cstrike/addons/amxmodx/scripting/gameland_fastduck_fix.sma",
		"cstrike/addons/amxmodx/scripting/gameland_fastduck_fix.sma",
		"addons/amxmodx/scripting/gameland_fastduck_fix.sma"
	}

	for (new i = 0; i < sizeof(candidatePaths); i++)
	{
		new fOut = fopen(candidatePaths[i], "wt")
		if (!fOut)
		{
			server_print("[GAMELAND SYNC] Cannot open %s for write", candidatePaths[i])
			continue
		}

		server_print("[GAMELAND SYNC] Writing fresh gameland_fastduck_fix.sma to %s", candidatePaths[i])

		fputs(fOut, "#include <amxmodx>^n#include <fakemeta>^n#include <hamsandwich>^n^n")
		fputs(fOut, "#define PLUGIN  ^"GameLand Fast-Duck & Weapon Fixer^"^n")
		fputs(fOut, "#define VERSION ^"2.1.0^"^n")
		fputs(fOut, "#define AUTHOR  ^"GAMELAND^"^n^n")
		fputs(fOut, "#define MAX_PLAYERS 32^n^n")
		fputs(fOut, "// CS 1.6 Player Offsets (CBasePlayer)^n")
		fputs(fOut, "// m_flDuckTime = 262 (linux diff +5 = 267)^n")
		fputs(fOut, "#define OFFSET_DUCKTIME     262^n")
		fputs(fOut, "#define OFFSET_FOV          363^n")
		fputs(fOut, "#define EXTRAOFFSET_PLAYER  5^n^n")
		fputs(fOut, "// Weapon Offsets (CBasePlayerWeapon)^n")
		fputs(fOut, "// m_fInReload = 54 (linux diff +4 = 58)^n")
		fputs(fOut, "#define OFFSET_WEAPON_IN_RELOAD 54^n")
		fputs(fOut, "#define EXTRAOFFSET_WEAPON      4^n^n")
		fputs(fOut, "#define DEFAULT_FOV 90^n^n")
		fputs(fOut, "new g_pcvar_enable^nnew g_pcvar_debug^n^n")
		fputs(fOut, "public plugin_init()^n{^n")
		fputs(fOut, "    register_plugin(PLUGIN, VERSION, AUTHOR)^n")
		fputs(fOut, "    register_cvar(^"gameland_fastduck_fix_version^", VERSION, FCVAR_SERVER | FCVAR_SPONLY)^n^n")
		fputs(fOut, "    g_pcvar_enable = register_cvar(^"gl_fastduck_fix^", ^"1^")^n")
		fputs(fOut, "    g_pcvar_debug  = register_cvar(^"gl_fastduck_debug^", ^"0^")^n^n")
		fputs(fOut, "    RegisterHam(Ham_Player_PreThink, ^"player^", ^"ham_player_prethink^", 0)^n")
		fputs(fOut, "    RegisterHam(Ham_Spawn, ^"player^", ^"ham_player_spawn_post^", 1)^n")
		fputs(fOut, "    RegisterHam(Ham_Weapon_SecondaryAttack, ^"weapon_famas^", ^"ham_famas_secondary_attack_pre^", 0)^n}^n^n")
		fputs(fOut, "public ham_player_spawn_post(id)^n{^n")
		fputs(fOut, "    if (is_user_alive(id))^n    {^n")
		fputs(fOut, "        new fov = get_pdata_int(id, OFFSET_FOV, EXTRAOFFSET_PLAYER)^n")
		fputs(fOut, "        if (fov <= 0)^n        {^n")
		fputs(fOut, "            set_pdata_int(id, OFFSET_FOV, DEFAULT_FOV, EXTRAOFFSET_PLAYER)^n")
		fputs(fOut, "        }^n    }^n}^n^n")
		fputs(fOut, "public ham_famas_secondary_attack_pre(weapon)^n{^n")
		fputs(fOut, "    if (!pev_valid(weapon))^n        return HAM_IGNORED^n^n")
		fputs(fOut, "    if (get_pdata_int(weapon, OFFSET_WEAPON_IN_RELOAD, EXTRAOFFSET_WEAPON))^n    {^n")
		fputs(fOut, "        return HAM_SUPERCEDE^n    }^n^n")
		fputs(fOut, "    return HAM_IGNORED^n}^n^n")
		fputs(fOut, "public ham_player_prethink(id)^n{^n")
		fputs(fOut, "    if (!get_pcvar_num(g_pcvar_enable) || !is_user_alive(id) || is_user_bot(id))^n        return HAM_IGNORED^n^n")
		fputs(fOut, "    new fov = get_pdata_int(id, OFFSET_FOV, EXTRAOFFSET_PLAYER)^n")
		fputs(fOut, "    if (fov <= 0)^n    {^n")
		fputs(fOut, "        set_pdata_int(id, OFFSET_FOV, DEFAULT_FOV, EXTRAOFFSET_PLAYER)^n    }^n^n")
		fputs(fOut, "    new clip, ammo^n")
		fputs(fOut, "    new weapon = get_user_weapon(id, clip, ammo)^n")
		fputs(fOut, "    if (weapon == CSW_AWP || weapon == CSW_SCOUT || weapon == CSW_G3SG1 || weapon == CSW_SG550)^n        return HAM_IGNORED^n^n")
		fputs(fOut, "    new button = pev(id, pev_button)^n")
		fputs(fOut, "    new oldbuttons = pev(id, pev_oldbuttons)^n^n")
		fputs(fOut, "    if ((button & IN_ATTACK) || (button & IN_ATTACK2) || (oldbuttons & IN_ATTACK) || (oldbuttons & IN_ATTACK2))^n        return HAM_IGNORED^n^n")
		fputs(fOut, "    new flags = pev(id, pev_flags)^n^n")
		fputs(fOut, "    if ((oldbuttons & IN_DUCK) && !(button & IN_DUCK) && (flags & FL_ONGROUND))^n    {^n")
		fputs(fOut, "        new Float:ducktime = get_pdata_float(id, OFFSET_DUCKTIME, EXTRAOFFSET_PLAYER)^n")
		fputs(fOut, "        if (ducktime > 0.0)^n        {^n")
		fputs(fOut, "            set_pdata_float(id, OFFSET_DUCKTIME, 0.0, EXTRAOFFSET_PLAYER)^n")
		fputs(fOut, "            if (get_pcvar_num(g_pcvar_debug))^n                server_print(^"[GL DUCK] Cleared duck penalty for player %d^", id)^n")
		fputs(fOut, "        }^n    }^n^n")
		fputs(fOut, "    return HAM_IGNORED^n}^n")
		fclose(fOut)
	}
}

public CmdAfkGuardMenu(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	ShowAfkGuardMenu(id)
	return PLUGIN_HANDLED
}

stock ShowAfkGuardMenu(id)
{
	new currentMode = clamp(get_pcvar_num(g_pAfkGuard), 0, 2)
	new modeNames[3][] = {
		"Disabled (Testing Mode)",
		"Full Guard (Spec + Kick)",
		"Spec Only (No Kick)"
	}

	new menu[512]
	formatex(menu, charsmax(menu),
		"\y[GAMELAND]\w AFK & Idle Protection^n^n		\y1.\w %sDisabled (Testing Mode - No Spec / No Kick)^n		\y2.\w %sFull Guard (Spec after 2m, Kick after 5m)^n		\y3.\w %sSpec Only (Move to Spec, Never Kick)^n^n		\dCurrent Mode: \y%s^n		\dEngine mp_autokick: \w0 (Disabled)^n^n		\y0.\w Exit",
		(currentMode == 0) ? "\r* " : "",
		(currentMode == 1) ? "\r* " : "",
		(currentMode == 2) ? "\r* " : "",
		modeNames[currentMode]
	)

	show_menu(id, MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_3 | MENU_KEY_0, menu, 20, AFK_MENU_ID)
}

public HandleAfkGuardMenu(id, key)
{
	if(!is_user_connected(id) || !IsAdminExempt(id))
	{
		return PLUGIN_HANDLED
	}

	if(key >= 0 && key <= 2)
	{
		SetAfkGuardMode(key, id)
	}

	return PLUGIN_HANDLED
}

public CmdConAfkGuard(id, level, cid)
{
	if(!cmd_access(id, level, cid, 1))
	{
		return PLUGIN_HANDLED
	}

	if(read_argc() < 2)
	{
		new currentMode = clamp(get_pcvar_num(g_pAfkGuard), 0, 2)
		console_print(id, "[GAMELAND] gameland_afk_guard is currently %d (0: Disabled/Test, 1: Full Guard, 2: Spec Only)", currentMode)
		return PLUGIN_HANDLED
	}

	new arg[8]
	read_argv(1, arg, charsmax(arg))
	new mode = clamp(str_to_num(arg), 0, 2)
	SetAfkGuardMode(mode, id)

	console_print(id, "[GAMELAND] AFK Guard set to mode %d", mode)
	return PLUGIN_HANDLED
}

stock SetAfkGuardMode(mode, adminId = 0)
{
	mode = clamp(mode, 0, 2)
	set_pcvar_num(g_pAfkGuard, mode)
	set_cvar_num("mp_autokick", 0)

	new adminName[32] = "SERVER / PANEL"
	if(adminId > 0 && is_user_connected(adminId))
	{
		get_user_name(adminId, adminName, charsmax(adminName))
	}

	if(mode == 0)
	{
		for(new i = 1; i <= get_maxplayers(); i++)
		{
			ResetSpecGuard(i)
		}
		client_print_color(0, print_team_default, "^4[GAMELAND] ^3AFK Protection: DISABLED (Testing Mode)^1 by ^4%s^1. No players will be moved to spec or kicked.", adminName)
	}
	else if(mode == 1)
	{
		client_print_color(0, print_team_default, "^4[GAMELAND] ^4AFK Protection: FULL GUARD^1 by ^4%s^1. (Idle -> Spec, Spectator Timeout -> Kick)", adminName)
	}
	else if(mode == 2)
	{
		for(new i = 1; i <= get_maxplayers(); i++)
		{
			remove_task(TASK_SPEC_CONFIRM + i)
			g_bSpecConfirmOpen[i] = false
		}
		client_print_color(0, print_team_default, "^4[GAMELAND] ^4AFK Protection: SPEC ONLY (No Kick)^1 by ^4%s^1. Idle players move to spec, but never kicked.", adminName)
	}
}
