/* Sublime AMXX Editor v4.2 */

/* 	Activare sistem de puncte 
	Activate Points system 
*/
//#define POINTS_SYS

/* 	Mod Fastcup ( /start, runda de cutite automata, alegere a echipei de catre echipa castigatoare ) 
	Fastcup Mode ( /start, automatic knife round, choose start side by winning team )
*/
#define FASTCUP_MODE
 
/* 	Modificarea indicilor kickback ale armelor care suporta acest lucru 
	Modifying supported weapons kickback angles
*/
//#define PUNCH_ANGLE

/* 	Optiuni pentru debugging, nu recomand a se porni daca nu se testeaza 
	Debugging messages, uncomment only if you're testing
*/
//#define DEBUG

/* 	Overtime-ul este doar de o runda, setarile din overtime.cfg se aplica 
   	Only one round of overtime, settings from overtime.cfg applies
*/
//#define OVERTIME_ONE_ROUND

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fun>
#include <reapi>
#include <regex>
#include <mix_system>

#define PLUGIN  "Mix System"
#if defined FASTCUP_MODE
#undef PLUGIN
#define PLUGIN  "Mix System ~ Fastcup Mode"
#endif

#define VERSION "2.19.11"
#define AUTHOR  "Shadows Adi"

#define SHOOTING_END_SCORE 10

#define IsPlayer(%1)				((1 <= %1 <= MAX_PLAYERS) && is_user_connected(%1))
#define NATIVE_ERROR				-1

enum (+=1200)
{
	TASK_WARM = 8200,
	TASK_SET_MONEY,
	TASK_GIVE_WEAPON,
	TASK_SWAP,
	TASK_REVIVE,
	TASK_CHANGE_BOOL,
	#if defined FASTCUP_MODE
	TASK_ASK,
	TASK_CHECKVOTES,
	#endif
	TASK_SPECALL,
	TASK_LOAD,
	TASK_COUNT_DURATION,
	TASK_GIVE_EQUIPMENT
}

enum MatchState
{
	MATCHSTATE_WARM = 0,
	MATCHSTATE_IN_MATCH,
	MATCHSTATE_KNIFE_ROUND,
	MATCHSTATE_OVERTIME
}

new const CHAT_PREFIX[]			=		"CHAT_PREFIX"
new const OVERTIME_ROUNDS[]		=		"OVERTIME_ROUNDS"
new const OVERTIME_SCORE[]		=		"OVERTIME_SCORE"
new const MIX_END_ROUND[]		=		"MIX_END_ROUND"
new const ADMIN_CHAT_FLAGS[]	=		"ADMIN_CHAT_FLAGS"
new const ADMIN_ACCESS[]		=		"ADMIN_LEVEL_ACCESS"
new const FREEZETIME_SWAP[]		=		"FREEZE_TIME_SWAP"
new const AUTO_OVERTIME[]		=		"AUTOMATIC_OVERTIME"
new const START_CFG[]			=		"START_CONFIG"
new const STOP_CFG[]			=		"STOP_CONFIG"
new const OVERTIME_CFG[]		=		"OVERTIME_CONFIG"
new const FREEZETIME[]			=		"FREEZETIME"
new const PAUSE_TIME[]			=		"PAUSE_DURATION"
new const TEN_REQUIRED[]		=		"START_TEN_REQUIRED"
new const KNIFE_ROUND_DELAY[]	=		"KNIFE_ROUND_START_DELAY"
new const DEFAULT_POINTS[]		=		"DEFAULT_START_POINTS"
new const FORCE_WARMUP[]		=		"FORCE_WARMUP"
new const SHOW_COMMANDS[]		=		"SHOW_COMMANDS"
new const START_COMMANDS[]		=		"START_MIX_COMMANDS"
new const STOP_COMMANDS[]		=		"STOP_MIX_COMMANDS"
new const WARM_COMMANDS[]		=		"WARM_COMMANDS"
new const KNIFE_COMMANDS[]		=		"KNIFE_COMMANDS"
new const CHAT_ON_COMMANDS[]	=		"CHAT_ON_COMMANDS"
new const CHAT_OFF_COMMANDS[]	=		"CHAT_OFF_COMMANDS"
new const OVERTIME_COMMANDS[]	=		"OVERTIME_COMMANDS"
new const PASSON_COMMANDS[]		=		"PASSWORD_ON_COMMANDS"
new const PASSOFF_COMMANDS[]	=		"PASSWORD_OFF_COMMANDS"
new const SPECALL_COMMANDS[]	=		"SPECALL_COMMANDS"
new const RESTART_COMMANDS[]	=		"RESTART_COMMANDS"
new const SCORE_COMMANDS[]		=		"SCORE_COMMANDS"
new const CT_COMMANDS[]			=		"MOVE_CT_COMMANDS"
new const T_COMMANDS[]			=		"MOVE_TERO_COMMANDS"
new const SPEC_COMMANDS[]		=		"MOVE_SPEC_COMMANDS"
new const STARTDEMO_COMMANDS[]	=		"START_DEMO_COMMANDS"
new const STOPDEMO_COMMANDS[]	=		"STOPDEMO_COMMANDS"
new const PAUSE_COMMANDS[]		=		"PAUSE_COMMANDS"
new const WARM_TYPE[]			=		"WARMUP_TYPE"
new const WARM_SPAWN_MONEY[]	=		"WARMUP_SPAWN_MONEY"
new const WARM_WEAPON_CT[]		=		"WARMUP_WEAPON_CT"
new const WARM_WEAPON_TERO[]	=		"WARMUP_WEAPON_TERO"
new const WARM_PISTOL[]			=		"WARMUP_PISTOL"
new const WARM_BP_AMMO[]		=		"WARMUP_BP_AMMO"
new const HUD_COLORS[]			=		"HUD_COLOR"
new const HUD_POSITION[]		=		"HUD_POSITION"
new const DEMO_AUTO[]			=		"AUTO_DEMO"
new const DEMO_TYPE[]			= 		"DEMO_TYPE"
new const DEMO_NAME[]			=		"DEMO_NAME"


enum
{
	SETTINGS_SECTION = 1,
	COMMANDS_SECTION,
	WARM_SETTINGS,
	HUD_SETTINGS,
	DEMO_SETTINGS,
	POINTS_SYSTEM,
	RANK_SYSTEM
}

enum _:Settings
{
	szPrefix[64],
	iRoundOvertime,
	iMixEndRound,
	iOvertimeScore[5],
	szAdminFlags[22],
	szAdminAccess[4],
	iFreezetimeSwap,
	iAutoOvertime,
	szStartCfg[32],
	szOvertimeCfg[32],
	iPauseTime,
	bool:bRequireTen,
	iKnifeStartDelay,
	iStartPoints,
	bool:bForceWarmup,
	szStopCfg[32],
	}

enum _:WarmSettings
{
	bool:bWarmType,
	iWarmMoney[6],
	szWeaponCT[16],
	szWeaponT[16],
	szPistol[16],
	iBpAmmo
}

enum _:DemoSettings
{
	iDemoAuto,
	iDemoType,
	szDemoName[32],
}

enum
{
	DEMO_MAPNAME,
	DEMO_CUSTOM_NAME,
	DEMO_CIN_NAME
}

enum _:Score
{
	CT_SCORE,
	TERO_SCORE,
	CT_OVER_SCORE,
	TERO_OVER_SCORE,
	DRAW // Unusable, only for equal case in OverTime
}

enum
{
	CT_LAST = 1,
	T_LAST
}

enum _:Infos
{
	MIX_STARTER[MAX_NAME_LENGTH],
	MIX_STOPER[MAX_NAME_LENGTH],
	CHAT[MAX_NAME_LENGTH],
	WARM_CALLER[MAX_NAME_LENGTH],
	KNIFE_STRATER[MAX_NAME_LENGTH],
	OVERTIME_STARTER[MAX_NAME_LENGTH],
	PASSON_CALLER[MAX_NAME_LENGTH],
	PASSOFF_CALLER[MAX_NAME_LENGTH],
	SPECALL_CALLER[MAX_NAME_LENGTH],
	ACE[MAX_NAME_LENGTH],
	SEMI_ACE[MAX_NAME_LENGTH]
}

enum _:Bools
{
	#if defined FASTCUP_MODE
	bool:bWasKnife,
	#endif
	bool:bCanChat[MAX_PLAYERS + 1],
	bool:bIsMixOn,
	bool:bIsShooting,
	bool:bShouldRecordMix,
	bool:bIsKnife,
	bool:bIsWarm,
	bool:bTeamSwap,
	bool:bOvertime,
	bool:bIsStoppingMix,
	bool:bCanShowStats
}

enum _:HudSettings
{
	Float:fHudPosX,
	Float:fHudPosY,
	iHudColorR,
	iHudColorG,
	iHudColorB
}

enum _:OVERTIME
{
	bool:FirstOvertime,
	bool:SecondOvertime
}

enum 
{
	SPEC,
	CT,
	TERO
}

enum _:Pdata
{
	STEAMID[32],
	KILLS,
	DEATHS,
	MONEY
}

#if defined FASTCUP_MODE
new g_iPlayers

enum _:TeamAnswers
{
	SWITCH = 0,
	STAY
}
#endif

enum _:PlayerScore
{
	iKILLS,
	iDEATHS
}

enum _:Teams
{
	CT_PAUSE,
	TERO_PAUSE
}

enum _:PlayerStats
{
	DamageGiven,
	HitsGiven,
	PlayerHealth
}

enum _:Forwards
{
	Kill,
	GameOver,
	GameBeginPre,
	GameBeginPost,
	GameStopped,
	NewRound,
	DatabaseConnected,
	Winners,
	Save,
	MaxFwds
}

new Array:g_aStartCmds
new Array:g_aStopCmds
new Array:g_aWarmCmds
new Array:g_aKnifeCmds
new Array:g_aChatOnCmds
new Array:g_aChatOffCmds
new Array:g_aOvertimeCmds
new Array:g_aPassOnCmds
new Array:g_aPassOffCmds
new Array:g_aSpecAllCmds
new Array:g_aCTCmds
new Array:g_aTCmds
new Array:g_aSpecCmds
new Array:g_aStartDemoCmds
new Array:g_aStopDemoCmds

new g_ePluginSettings[Settings]
new g_eHudSettings[HudSettings]
new g_eWarmSettings[WarmSettings]
new g_eInformations[Infos]
new g_eDemoSettings[DemoSettings]

new g_eOvertime[OVERTIME]
new g_iOvertimeScore[Score]

new g_iScore[Score]
new g_iRoundNum
new g_iKnifes
new g_iStart

new g_szName[MAX_PLAYERS + 1][MAX_NAME_LENGTH]
new g_szAuthID[MAX_PLAYERS][32]
new Array:g_aPlayerData

new g_eBooleans[Bools]

new g_cFreezeTime
new g_iFreezeTime
new bool:g_bShootingOpening

new g_szHltvDemoName[64]


new g_iPlayerKills[MAX_PLAYERS + 1]
new g_szWeapon[MAX_PLAYERS + 1][32]

new g_ePlayerScore[MAX_PLAYERS + 1][PlayerScore]

new g_eTeamPause[Teams]
new bool:g_bPaused
new g_iTimer

#if defined FASTCUP_MODE
new bool:g_bVoted
new g_iVote
new g_iAnswer[TeamAnswers]
#endif

new g_ePlayerStats[MAX_PLAYERS + 1][MAX_PLAYERS + 1][PlayerStats]

new g_eForwards[Forwards]
new g_iDuration

new g_iRet


new g_szConfigsDir[48]
new g_iGaveC4

new g_iMsgScreenFade

public plugin_init()
{
	register_plugin(PLUGIN, VERSION, AUTHOR)

	register_cvar("mix_sys", VERSION, FCVAR_SERVER|FCVAR_EXTDLL|FCVAR_UNLOGGED|FCVAR_SPONLY)

	register_dictionary("mix_system.txt")

	g_iMsgScreenFade = get_user_msgid("ScreenFade")

	register_clcmd("say", "hook_say")

	register_clcmd("fullupdate", "clcmd_fullupdate")

	RegisterHookChain(RG_RoundEnd, "RG_EndRound")
	RegisterHookChain(RG_RoundEnd, "RG_EndRound_Pre", 0)
	RegisterHookChain(RG_CSGameRules_CheckWinConditions, "RG_CheckWinConditions_Pre")
	RegisterHookChain(RG_CSGameRules_PlayerKilled, "RG_Player_Killed_Post", 1)
	RegisterHookChain(RG_CWeaponBox_SetModel, "RG_Weapon_Remove")
	RegisterHookChain(RG_HandleMenu_ChooseTeam, "RG_ChooseTeam_Pre")
	RegisterHookChain(RG_HandleMenu_ChooseAppearance, "ShootingAppearance_Pre")
	RegisterHookChain(RG_CBasePlayer_Spawn, "ShootingSpawn_Post", 1)
	RegisterHookChain(RG_CSGameRules_OnRoundFreezeEnd, "ShootingFreezeEnd_Post", 1)
	RegisterHookChain(RG_CSGameRules_RestartRound, "ShootingRestart_Pre")
	RegisterHookChain(RG_CSGameRules_RestartRound, "ShootingRestart_Post", 1)
	RegisterHookChain(RG_HandleMenu_ChooseTeam, "RG_ChooseTeam_Post", 1)
	RegisterHookChain(RG_CSGameRules_CanHavePlayerItem, "RG_CSGameRules_CanHavePlayerItem_Pre")

		RegisterHookChain(RG_CBasePlayer_TakeDamage, "RG_PlayerTakeDamage_Pre")
	RegisterHookChain(RG_CBasePlayer_TakeDamage, "RG_PlayerTakeDamage_Post", 1)
	#if defined PUNCH_ANGLE
	RegisterHookChain(RG_CBasePlayerWeapon_KickBack, "RG_KickBack_Pre")
	#endif

	register_message(get_user_msgid("SayText"), "HookSay")
	register_event("HLTV", "ev_NewRound", "a", "1=0", "2=0");
	register_event("TextMsg", "ev_GameRestart", "a", "2=#Game_will_restart_in")
	g_cFreezeTime = get_cvar_pointer("mp_freezetime")

	#if defined DEBUG
	register_clcmd("say /test_over", "clcmd_say_test_over")
	register_clcmd("say /test_score", "clcmd_say_test_score")
	register_clcmd("say /test", "clcmd_say_test")
	#endif 

	register_clcmd("hs1", "clcmd_hs1")
	register_clcmd("say hs1", "clcmd_hs1")
	register_clcmd("say /hs1", "clcmd_hs1")
	register_clcmd("say .hs1", "clcmd_hs1")
	register_clcmd("say_team hs1", "clcmd_hs1")
	register_clcmd("say_team /hs1", "clcmd_hs1")

	register_clcmd("hs0", "clcmd_hs0")
	register_clcmd("say hs0", "clcmd_hs0")
	register_clcmd("say /hs0", "clcmd_hs0")
	register_clcmd("say .hs0", "clcmd_hs0")
	register_clcmd("say_team hs0", "clcmd_hs0")
	register_clcmd("say_team /hs0", "clcmd_hs0")
 

	g_eForwards[Kill] = CreateMultiForward("mix_player_killed", ET_IGNORE, FP_CELL, FP_CELL, FP_CELL, FP_STRING, FP_STRING)
	g_eForwards[GameBeginPre] = CreateMultiForward("mix_game_begin_pre", ET_IGNORE)
		g_eForwards[NewRound] = CreateMultiForward("mix_game_new_round", ET_IGNORE, FP_CELL, FP_CELL, FP_CELL)
	
	new pcvar = get_cvar_pointer("amx_mode")
	if(pcvar != 0)
	{
		hook_cvar_change(pcvar, "OnCvarChange")
	}


	set_task(0.1, "task_read_config")
}

public task_read_config()
{
	ReadConfig()
}

public plugin_natives()
{
	g_aStartCmds = ArrayCreate(32)
	g_aStopCmds = ArrayCreate(32)
	g_aWarmCmds = ArrayCreate(32)
	g_aKnifeCmds = ArrayCreate(32)
	g_aChatOnCmds = ArrayCreate(32)
	g_aChatOffCmds = ArrayCreate(32)
	g_aOvertimeCmds = ArrayCreate(32)
	g_aPassOnCmds = ArrayCreate(32)
	g_aPassOffCmds = ArrayCreate(32)
	g_aSpecAllCmds = ArrayCreate(32)
	g_aCTCmds = ArrayCreate(32)
	g_aTCmds = ArrayCreate(32)
	g_aSpecCmds = ArrayCreate(32)
	g_aStartDemoCmds = ArrayCreate(32)
	g_aStopDemoCmds = ArrayCreate(32)
	g_aPlayerData = ArrayCreate(Pdata)

	
	register_library("mix_system")

	register_native("Mix_IsHalf", "native_is_half")
	register_native("Mix_IsLastRound", "native_is_last_round")
	register_native("Mix_IsPreLastRound", "native_is_prelast_round")
	register_native("Mix_CanOvertime", "native_can_overtime")
	register_native("Mix_IsStarted", "native_is_started")
	register_native("Mix_IsWarm", "native_is_warm")
	register_native("Mix_GetPrefix", "native_get_prefix")
	register_native("Mix_GetUserName", "native_get_username")
		register_native("Mix_HasPointsSys", "native_has_points_sys")
}

public plugin_end()
{
	ArrayDestroy(g_aStartCmds)
	ArrayDestroy(g_aStopCmds)
	ArrayDestroy(g_aWarmCmds)
	ArrayDestroy(g_aKnifeCmds)
	ArrayDestroy(g_aChatOnCmds)
	ArrayDestroy(g_aChatOffCmds)
	ArrayDestroy(g_aOvertimeCmds)
	ArrayDestroy(g_aPassOnCmds)
	ArrayDestroy(g_aPassOffCmds)
	ArrayDestroy(g_aSpecAllCmds)
	ArrayDestroy(g_aCTCmds)
	ArrayDestroy(g_aTCmds)
	ArrayDestroy(g_aSpecCmds)
	ArrayDestroy(g_aStartDemoCmds)
	ArrayDestroy(g_aStopDemoCmds)
	ArrayDestroy(g_aPlayerData)
	
	for(new i; i < MaxFwds; i++)
	{
		DestroyForward(g_eForwards[i])
	}

	}

public OnCvarChange(pcvar, const old_value[], const new_value[])
{
	if(get_pcvar_num(pcvar) != 1)
	{
		set_pcvar_num(pcvar, 1)
	}

	server_cmd("amx_reloadadmins")
	server_exec()
}

#if defined DEBUG
public clcmd_say_test_score(id)
{
	g_iScore[CT_SCORE] += 1
	g_iScore[TERO_SCORE] += 12

	g_iRoundNum += 13
}

public clcmd_say_test_over(id)
{
	g_iScore[CT_SCORE] += 0
	g_iScore[TERO_SCORE] += 14
	g_iRoundNum += 14
}

public clcmd_say_test(id)
{
	console_print(id, "Can chat: %s", g_eBooleans[bCanChat] ? "YES" : "NO")
	console_print(id, "Mix started: %s", g_eBooleans[bIsMixOn] ? "YES" : "NO")
	console_print(id, "Knife started: %s", g_eBooleans[bIsKnife] ? "YES" : "NO")
	console_print(id, "Warm started: %s", g_eBooleans[bIsWarm] ? "YES" : "NO")
	console_print(id, "Team swap: %s", g_eBooleans[bTeamSwap] ? "YES" : "NO")
	console_print(id, "Overtime: %s", g_eBooleans[bOvertime] ? "YES" : "NO")
	console_print(id, "First Overtime: %s", g_eOvertime[FirstOvertime] ? "YES" : "NO")
	console_print(id, "Second Overtime: %s", g_eOvertime[SecondOvertime] ? "YES" : "NO")
	console_print(id, "Admin Flags: %s", g_ePluginSettings[szAdminAccess])
	console_print(id, "Score T: %i", g_iScore[TERO_SCORE])
	console_print(id, "Score CT: %i", g_iScore[CT_SCORE])
	console_print(id, "Score Over T: %i", g_iOvertimeScore[TERO_OVER_SCORE])
	console_print(id, "Score Over CT: %i", g_iOvertimeScore[CT_OVER_SCORE])
	console_print(id, "Warmup Type: %s", g_eWarmSettings[bWarmType] ? "True" : "False")
	console_print(id, "Weapon Tero: %s", g_eWarmSettings[szWeaponT])
	console_print(id, "Weapon CT: %s", g_eWarmSettings[szWeaponCT])
	}
#endif

ReadConfig()
{
	new szConfigsDir[128], szFileDir[64]
	get_configsdir(szConfigsDir, charsmax(szConfigsDir))

	formatex(szFileDir, charsmax(szFileDir), "%s/MixSettings.ini", szConfigsDir)

	new iFile = fopen(szFileDir, "rt")

	if(iFile)
	{
		new szData[128], iSection, szString[64], szValue[64]

		
		while(!feof(iFile))
		{
			fgets(iFile, szData, charsmax(szData))
			trim(szData)

			if(szData[0] == '#' || szData[0] == EOS || szData[0] == ';')
				continue

			if(szData[0] == '[')
			{
				iSection += 1
			}
			switch(iSection)
			{
				case SETTINGS_SECTION:
				{
					if(szData[0] != '[')
					{
						strtok2(szData, szString, charsmax(szString), szValue, charsmax(szValue), '=', TRIM_INNER)

						if(szValue[0] == EOS || !szValue[0])
							continue

						if(equal(szString, CHAT_PREFIX))
						{
							copy(g_ePluginSettings[szPrefix], charsmax(g_ePluginSettings[szPrefix]), szValue)
						}
						else if(equal(szString, OVERTIME_ROUNDS))
						{
							g_ePluginSettings[iRoundOvertime] = str_to_num(szValue)
						}
						else if(equal(szString, OVERTIME_SCORE))
						{
							g_ePluginSettings[iOvertimeScore] = str_to_num(szValue)
						}
						else if(equal(szString, MIX_END_ROUND))
						{
							g_ePluginSettings[iMixEndRound] = str_to_num(szValue)
						}
						else if(equal(szString, ADMIN_CHAT_FLAGS))
						{
							copy(g_ePluginSettings[szAdminFlags], charsmax(g_ePluginSettings[szAdminFlags]), szValue)
						}
						else if(equal(szString, ADMIN_ACCESS))
						{
							copy(g_ePluginSettings[szAdminAccess], charsmax(g_ePluginSettings[szAdminAccess]), szValue)
						}
						else if(equal(szString, FREEZETIME_SWAP))
						{
							g_ePluginSettings[iFreezetimeSwap] = str_to_num(szValue)
						}
						else if(equal(szString, AUTO_OVERTIME))
						{
							g_ePluginSettings[iAutoOvertime] = str_to_num(szValue)
						}
						else if(equal(szString, START_CFG))
						{
							copy(g_ePluginSettings[szStartCfg], charsmax(g_ePluginSettings[szStartCfg]), szValue)
						}
						else if(equal(szString, STOP_CFG))
						{
							copy(g_ePluginSettings[szStopCfg], charsmax(g_ePluginSettings[szStopCfg]), szValue)
						}
						else if(equal(szString, OVERTIME_CFG))
						{
							copy(g_ePluginSettings[szOvertimeCfg], charsmax(g_ePluginSettings[szOvertimeCfg]), szValue)
						}
						else if(equal(szString, FREEZETIME))
						{
							g_iFreezeTime = str_to_num(szValue)
						}
						else if(equal(szString, PAUSE_TIME))
						{
							g_ePluginSettings[iPauseTime] = str_to_num(szValue)
						}
						else if (equal(szString, TEN_REQUIRED))
						{
							g_ePluginSettings[bRequireTen] = bool:clamp(str_to_num(szValue), 0, 1) 
						}
						else if (equal(szString, KNIFE_ROUND_DELAY))
						{
							g_ePluginSettings[iKnifeStartDelay] = str_to_num(szValue)
						}
						else if (equal(szString, DEFAULT_POINTS))
						{
							g_ePluginSettings[iStartPoints] = str_to_num(szValue)
						}
						else if (equal(szString, FORCE_WARMUP))
						{
							g_ePluginSettings[bForceWarmup] = bool:clamp(str_to_num(szValue), 0, 1) 
						}
					}
				}
				case COMMANDS_SECTION:
				{
					if(szData[0] != '[')
					{
						strtok2(szData, szString, charsmax(szString), szValue, charsmax(szValue), '=', TRIM_INNER)

						if(szValue[0] == EOS || !szValue[0])
							continue

						if(equal(szString, SHOW_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_showcmds")
							}
						}
						else if(equal(szString, START_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_startmix")
								ArrayPushString(g_aStartCmds, szString)
							}
						}
						else if(equal(szString, STOP_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_stopmix")
								ArrayPushString(g_aStopCmds, szString)
							}
						}
						else if(equal(szString, WARM_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_warm")
								ArrayPushString(g_aWarmCmds, szString)
							}
						}
						else if(equal(szString, KNIFE_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_knife")
								ArrayPushString(g_aKnifeCmds, szString)
							}
						}
						else if(equal(szString, CHAT_ON_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_chat_on")
								ArrayPushString(g_aChatOnCmds, szString)
							}
						}
						else if(equal(szString, CHAT_OFF_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_chat_off")
								ArrayPushString(g_aChatOffCmds, szString)
							}
						}
						else if(equal(szString, OVERTIME_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_overtime")
								ArrayPushString(g_aOvertimeCmds, szString)
							}
						}
						else if(equal(szString, PASSON_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_passon")
								ArrayPushString(g_aPassOnCmds, szString)
							}
						}
						else if(equal(szString, PASSOFF_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_passoff")
								ArrayPushString(g_aPassOffCmds, szString)
							}
						}
						else if(equal(szString, SPECALL_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_specall")
								ArrayPushString(g_aSpecAllCmds, szString)
							}
						}
						else if(equal(szString, RESTART_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_restart")
							}
						}
						else if(equal(szString, SCORE_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_score")
							}
						}
						else if(equal(szString, CT_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_ct")
								ArrayPushString(g_aCTCmds, szString)
							}
						}
						else if(equal(szString, T_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_t")
								ArrayPushString(g_aTCmds, szString)
							}
						}
						else if(equal(szString, SPEC_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_spec")
								ArrayPushString(g_aSpecCmds, szString)
							}
						}
						else if(equal(szString, STARTDEMO_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_start_demo")
								ArrayPushString(g_aStartDemoCmds, szString)
							}
						}
						else if(equal(szString, STOPDEMO_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_stop_demo")
								ArrayPushString(g_aStopDemoCmds, szString)
							}
						}
												else if(equal(szString, PAUSE_COMMANDS))
						{
							while(szValue[0] != EOS && strtok2(szValue, szString, charsmax(szString), szValue, charsmax(szValue), ',', TRIM_INNER))
							{
								register_clcmd(szString, "clcmd_say_pause")
							}
						}
					}
				}
				case WARM_SETTINGS:
				{
					if(szData[0] == '[')
						continue

					strtok2(szData, szString, charsmax(szString), szValue, charsmax(szValue), '=', TRIM_INNER)

					if(equal(szString, WARM_TYPE))
					{
						g_eWarmSettings[bWarmType] = (str_to_num(szValue) == 1 ? true : false)
					}
					else if(equal(szString, WARM_SPAWN_MONEY))
					{
						g_eWarmSettings[iWarmMoney] = str_to_num(szValue)
					}
					else if(equal(szString, WARM_WEAPON_CT))
					{
						copy(g_eWarmSettings[szWeaponCT], charsmax(g_eWarmSettings[szWeaponCT]), szValue)
					}
					else if(equal(szString, WARM_WEAPON_TERO))
					{
						copy(g_eWarmSettings[szWeaponT], charsmax(g_eWarmSettings[szWeaponT]), szValue)
					}
					else if(equal(szString, WARM_PISTOL))
					{
						copy(g_eWarmSettings[szPistol], charsmax(g_eWarmSettings[szPistol]), szValue)
					}
					else if(equal(szString, WARM_BP_AMMO))
					{
						g_eWarmSettings[iBpAmmo] = str_to_num(szValue)
					}
				}
				case HUD_SETTINGS:
				{
					if(szData[0] == '[')
						continue

					strtok2(szData, szString, charsmax(szString), szValue, charsmax(szValue), '=', TRIM_INNER)

					if(equal(szString, HUD_COLORS))
					{
						new szHudColorR[4], szHudColorG[4], szHudColorB[4]

						parse(szValue, szHudColorR, charsmax(szHudColorR), szHudColorG, charsmax(szHudColorG), szHudColorB, charsmax(szHudColorB))

						g_eHudSettings[iHudColorR] = str_to_num(szHudColorR)
						g_eHudSettings[iHudColorG] = str_to_num(szHudColorG)
						g_eHudSettings[iHudColorB] = str_to_num(szHudColorB)
					}
					else if(equal(szString, HUD_POSITION))
					{
						new szHudPosX[5], szHudPosY[5]
						parse(szValue, szHudPosX, charsmax(szHudPosX), szHudPosY, charsmax(szHudPosY))

						g_eHudSettings[fHudPosX] = str_to_float(szHudPosX)
						g_eHudSettings[fHudPosY] = str_to_float(szHudPosY)

						#if defined DEBUG
						server_print("HudPostX : %f", g_eHudSettings[fHudPosX])
						server_print("HudPostY : %f", g_eHudSettings[fHudPosY])
						server_print("szHudX: %s", szHudPosX)
						server_print("szHudY: %s", szHudPosY)
						server_print("szValue: %s", szValue)
						#endif
					}
				}
				case DEMO_SETTINGS:
				{
					if(szData[0] == '[')
						continue

					strtok2(szData, szString, charsmax(szString), szValue, charsmax(szValue), '=', TRIM_INNER)

					if(equal(szString, DEMO_AUTO))
					{
						g_eDemoSettings[iDemoAuto] = str_to_num(szValue)
					}
					else if(equal(szString, DEMO_TYPE))
					{
						g_eDemoSettings[iDemoType] = str_to_num(szValue)
					}
					else if(equal(szString, DEMO_NAME))
					{
						copy(g_eDemoSettings[szDemoName], charsmax(g_eDemoSettings[szDemoName]), szValue)
					}
				}
							}
		}
	}

	
	g_iTimer = g_ePluginSettings[iPauseTime] - 1
}


public client_putinserver(id)
{
	get_user_authid(id, g_szAuthID[id], charsmax(g_szAuthID[]))
	get_user_name(id, g_szName[id], charsmax(g_szName[]))

		g_iPlayerKills[id] = 0

	g_eBooleans[bCanChat][id] = true

	if(g_eBooleans[bIsMixOn])
	{
		if(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminFlags]))
		{
			g_eBooleans[bCanChat][id] = true
		}
		else 
		{
			g_eBooleans[bCanChat][id] = false
		}
	}
}

public client_disconnected(id)
{
	if(is_bot(id))
		return

	if(g_eBooleans[bIsMixOn] && !is_nullent(id))
	{
		new iData[Pdata]
		iData[STEAMID] = g_szAuthID[id]
		iData[DEATHS] = get_user_deaths(id)
		iData[KILLS] = get_user_frags(id)
		iData[MONEY] = get_member(id, m_iAccount)
		ArrayPushArray(g_aPlayerData, iData)

		g_ePlayerScore[id][iKILLS] = 0
		g_ePlayerScore[id][iDEATHS] = 0
	}

	}

#if defined PUNCH_ANGLE
public RG_KickBack_Pre(const index, Float:up_base, Float:lateral_base, Float:up_modifier, Float:lateral_modifier, Float:up_max, Float:lateral_max, direction_change)
{
	/* De modificat doar daca stiti ce se intampla aici*/
	SetHookChainArg(4, ATYPE_FLOAT, up_modifier * 0.90)
	SetHookChainArg(5, ATYPE_FLOAT, lateral_modifier * 0.90)
}
#endif

public RG_Weapon_Remove(iEnt, const szModelName[])
{
	if(g_eBooleans[bIsWarm] || g_eBooleans[bIsKnife])
	{
		static szClass[32]
		get_entvar(iEnt, var_classname, szClass, charsmax(szClass))

		if(!equal(szClass, "weaponbox"))
			return HC_CONTINUE

		set_entvar(iEnt, var_nextthink, get_gametime() + 1)
	}

	return HC_CONTINUE
}

public RG_CSGameRules_CanHavePlayerItem_Pre(id, item)
{
	// Shooting maps receive their loadout through rg_give_item.  Do not let
	// knife-round/buy-lock restrictions reject those weapons.
	if(!(g_eBooleans[bIsShooting] || (g_eBooleans[bIsWarm] && IsShootingMap())) && (g_eBooleans[bIsKnife] || get_member_game(m_bCTCantBuy) || get_member_game(m_bTCantBuy)))
	{
		if(get_member(item, m_iId) == WEAPON_KNIFE)
			return

		SetHookChainReturn(ATYPE_INTEGER, 0)
	}

	if(g_eBooleans[bIsWarm])
	{
		if(get_member(item, m_iId) == WEAPON_C4)
			SetHookChainReturn(ATYPE_INTEGER, 0)
	}
}

public ShootingAppearance_Pre(id, slot)
{
	if(g_eBooleans[bIsShooting] && g_eBooleans[bIsMixOn])
		SetHookChainArg(2, ATYPE_INTEGER, 1)
	return HC_CONTINUE
}

public ShootingSpawn_Post(id)
{
	if(!is_user_alive(id) || !g_eBooleans[bIsShooting] || !g_eBooleans[bIsMixOn])
		return
	new CsTeams:team = cs_get_user_team(id)
	if(team == CS_TEAM_CT)
		cs_set_user_model(id, "urban")
	else if(team == CS_TEAM_T)
		cs_set_user_model(id, "terror")
}

public ShootingFreezeEnd_Post()
{
	if(g_eBooleans[bIsShooting] && g_eBooleans[bIsMixOn])
	{
		if(g_bShootingOpening)
		{
			g_bShootingOpening = false
			ShowShootingLive()
			client_print_color(0, print_team_default, "^4[GAMELAND] ^1LIVE!")
		}
		set_pcvar_num(g_cFreezeTime, 0)
	}
}

public ShootingRestart_Pre()
{
	if(g_eBooleans[bIsShooting] && g_eBooleans[bIsMixOn])
		set_pcvar_num(g_cFreezeTime, g_bShootingOpening ? 5 : 0)
}

public ShootingRestart_Post()
{
	if(g_eBooleans[bIsShooting] && g_eBooleans[bIsMixOn] && g_bShootingOpening)
		ShowShootingLive()
}

stock ShowShootingLive()
{
	set_hudmessage(0, 255, 0, -1.0, 0.25, 0, 0.0, 5.0, 0.0, 0.2, -1)
	show_hudmessage(0, "=== LIVE LIVE LIVE ===")
}

public RG_ChooseTeam_Pre(id, MenuChooseTeam:slot)
{
	if(g_eBooleans[bIsMixOn])
	{
		new iCT = get_playersnum_ex(GetPlayers_MatchTeam, "CT")
		new iTero = get_playersnum_ex(GetPlayers_MatchTeam, "TERRORIST")

		if(slot == MenuChoose_T && iTero == 5)
		{
			SetHookChainReturn(ATYPE_INTEGER, 0)
			return HC_SUPERCEDE
		}
		else if(slot == MenuChoose_CT && iCT == 5)
		{
			SetHookChainReturn(ATYPE_INTEGER, 0)
			return HC_SUPERCEDE
		}
		else if(slot == MenuChoose_AutoSelect)
		{
			SetHookChainReturn(ATYPE_INTEGER, 0)
			return HC_SUPERCEDE
		}
	}
	return HC_CONTINUE
}

public RG_ChooseTeam_Post(id, MenuChooseTeam:slot)
{
	if(g_eBooleans[bIsWarm])
	{
		set_task(1.0, "task_revive", id + TASK_REVIVE)
	}

	if(g_eBooleans[bIsMixOn])
	{
		new iData[Pdata]
		new pID = ArrayFindString(g_aPlayerData, g_szAuthID[id])

		if(pID != -1)
		{
			ArrayGetArray(g_aPlayerData, pID, iData)
			set_user_frags(id, iData[KILLS])
			cs_set_user_deaths(id, iData[DEATHS], true)
			set_member(id, m_iAccount, iData[MONEY])

			ArrayDeleteItem(g_aPlayerData, pID)
		}
	}
}

public clcmd_fullupdate(id)
{
	return PLUGIN_HANDLED_MAIN
}

public StartCount()
{
	g_iDuration += 1
}

public ev_DeathMsg()
{
	new killer = read_data(1)
	if(!is_user_connected(killer))
	{
		return PLUGIN_HANDLED
	}
	read_data(4, g_szWeapon[killer], charsmax(g_szWeapon[]))

	return PLUGIN_HANDLED
}

public RG_PlayerTakeDamage_Pre(iVictim, pevInflictor, iAttacker, Float:flDamage, bitsDamageType)
{
	if(!g_eBooleans[bIsMixOn])
		return

	g_ePlayerStats[iAttacker][iVictim][PlayerHealth] = get_user_health(iVictim)
}

public RG_PlayerTakeDamage_Post(iVictim, pevInflictor, iAttacker, Float:flDamage, bitsDamageType)
{
	if(!g_eBooleans[bIsMixOn])
		return

	new iAfter = g_ePlayerStats[iAttacker][iVictim][PlayerHealth] - get_user_health( iVictim )

	new iCalculation = (iAfter) < 0 ? g_ePlayerStats[iAttacker][iVictim][PlayerHealth] : iAfter

	g_ePlayerStats[iAttacker][iVictim][DamageGiven] += iCalculation;
	g_ePlayerStats[iAttacker][iVictim][HitsGiven] += 1
}

public RG_Player_Killed_Post(iVictim, iKiller, iInflictor)
{
	if(IsPlayer(iVictim) && g_eBooleans[bIsWarm])
	{
		remove_task(iVictim + TASK_REVIVE)
		set_task(0.1, "task_revive", iVictim + TASK_REVIVE)
	}

	if(g_eBooleans[bIsMixOn] && !g_eBooleans[bIsWarm])
	{
		if(!IsPlayer(iKiller) || !IsPlayer(iVictim))
		{
			return HC_CONTINUE
		}

		if(iKiller == iVictim)
		{
						goto _return
		}

		new bool:bHeadshot = get_member(iVictim, m_bHeadshotKilled)

				g_iPlayerKills[iKiller] += 1

		ExecuteForward(g_eForwards[Kill], g_iRet, iVictim, iKiller, bHeadshot ? 1 : 0, g_szName[iKiller], g_szAuthID[iKiller])
	}
	_return:
	return HC_CONTINUE
}

public task_revive(iPlayer)
{
	iPlayer -= TASK_REVIVE

	if(IsPlayer(iPlayer))
	{
		new CsTeams:iTeam = cs_get_user_team(iPlayer)
		if(iTeam == CS_TEAM_SPECTATOR || iTeam == CS_TEAM_UNASSIGNED)
		{
			return HC_CONTINUE
		}

		set_entvar(iPlayer, var_health, 100)

		rg_round_respawn(iPlayer)
		rg_set_user_armor(iPlayer, 100, ARMOR_VESTHELM)

		switch(g_eWarmSettings[bWarmType])
		{
			case false:
			{
				set_task(1.0, "task_set_money", iPlayer + TASK_SET_MONEY)
			}
			case true:
			{
				set_task(1.0, "task_give_weapon", iPlayer + TASK_GIVE_WEAPON)
			}
		}
	}

	return PLUGIN_HANDLED
}


// Fix #3: Helper to print all elements of a command array
stock PrintCmdArray(id, Array:array, ML[])
{
	new iSize = ArraySize(array)
	if(iSize <= 0)
		return

	static szCmd[64]
	for(new i = 0; i < iSize; i++)
	{
		ArrayGetString(array, i, szCmd, charsmax(szCmd))
		console_print(id, "  [%L] %s", LANG_SERVER, ML, szCmd)
	}
}

public clcmd_showcmds(id)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	// Fix #3: was using sizeof(g_aStartCmds) which always returns 1 (handle size)
	// Rewritten to iterate each array fully, one by one
	console_print(id, "=-=-==-=-=---=-=-==-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-")

	PrintCmdArray(id, g_aStartCmds,    "MIX_START_COMMANDS_ARE")
	PrintCmdArray(id, g_aStopCmds,     "MIX_STOP_COMMANDS_ARE")
	PrintCmdArray(id, g_aWarmCmds,     "MIX_WARM_COMMANDS_ARE")
	PrintCmdArray(id, g_aKnifeCmds,    "MIX_KNIFE_COMMANDS_ARE")
	PrintCmdArray(id, g_aChatOnCmds,   "MIX_CHAT_ON_COMMANDS_ARE")
	PrintCmdArray(id, g_aChatOffCmds,  "MIX_CHAT_OFF_COMMANDS_ARE")
	PrintCmdArray(id, g_aOvertimeCmds, "MIX_OVERTIME_COMMANDS_ARE")
	PrintCmdArray(id, g_aPassOnCmds,   "MIX_PASSON_COMMANDS_ARE")
	PrintCmdArray(id, g_aPassOffCmds,  "MIX_PASSOFF_COMMANDS_ARE")
	PrintCmdArray(id, g_aSpecAllCmds,  "MIX_SPEC_ALL_COMMANDS_ARE")
	PrintCmdArray(id, g_aCTCmds,       "MIX_CT_MOVE_COMMANDS_ARE")
	PrintCmdArray(id, g_aTCmds,        "MIX_T_MOVE_COMMANDS_ARE")
	PrintCmdArray(id, g_aSpecCmds,     "MIX_SPEC_MOVE_COMMANDS_ARE")
	PrintCmdArray(id, g_aStartDemoCmds,"MIX_START_DEMO_COMMANDS_ARE")
	PrintCmdArray(id, g_aStopDemoCmds, "MIX_STOP_DEMO_COMMANDS_ARE")
	
	console_print(id, "=-=-==-=-=---=-=-==-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-")

	client_print_color(id, id, "^4%s ^1%L", g_ePluginSettings[szPrefix], LANG_SERVER, "OPEN_CONSOLE_FOR_CMDS")
	client_cmd(id, "toggleconsole")

	return PLUGIN_HANDLED
}

stock GetArrayCmd(id, Array:array, item, ML[])
{
	static temp[32]
	static szTemp[64]
	temp[0] = 0
	szTemp[0] = 0
	
	ArrayGetString(array, item, temp, charsmax(temp))
	formatex(szTemp, charsmax(szTemp), "%L: %s", LANG_SERVER, ML, temp)
	console_print(id, szTemp)
}

stock HLTV_StartRecording(const szDemoPrefix[])
{
	new szMapName[32], iDate[3], iTime[3]
	enum { iYear = 0, iMonth, iDay }
	enum { iHour = 0, iMin, iSec }
	get_mapname(szMapName, charsmax(szMapName))
	date(iDate[iYear], iDate[iMonth], iDate[iDay])
	time(iTime[iHour], iTime[iMin], iTime[iSec])

	formatex(g_szHltvDemoName, charsmax(g_szHltvDemoName), "%s_%04d-%02d-%02d_%02d-%02d", szDemoPrefix, iDate[iYear], iDate[iMonth], iDate[iDay], iTime[iHour], iTime[iMin])

	new fp = fopen("hltv_cmd.txt", "wt")
	if(fp)
	{
		fprintf(fp, "record %s^n", g_szHltvDemoName)
		fclose(fp)
	}

	new fp_rec = fopen("hltv_recording.txt", "wt")
	if(fp_rec)
	{
		fprintf(fp_rec, "%s^n", g_szHltvDemoName)
		fclose(fp_rec)
	}

	client_print_color(0, print_team_default, "^4[GAMELAND HLTV] ^1Demo recording ^3STARTED^1: ^4%s", g_szHltvDemoName)
	server_print("[GAMELAND HLTV] Demo recording STARTED: %s", g_szHltvDemoName)
}

stock HLTV_StopRecording()
{
	new fp = fopen("hltv_cmd.txt", "wt")
	if(fp)
	{
		fprintf(fp, "stoprecording^n")
		fclose(fp)
	}

	if(file_exists("hltv_recording.txt"))
	{
		delete_file("hltv_recording.txt")
	}

	new fp_q = fopen("ready_to_compress.txt", "at")
	if(fp_q)
	{
		if(g_szHltvDemoName[0])
		{
			fprintf(fp_q, "%s^n", g_szHltvDemoName)
		}
		else
		{
			fprintf(fp_q, "ALL^n")
		}
		fclose(fp_q)
	}

	if(g_szHltvDemoName[0])
	{
		client_print_color(0, print_team_default, "^4[GAMELAND HLTV] ^1Demo recording ^3STOPPED^1: ^4%s ^1-> Queued for Web Panel!", g_szHltvDemoName)
		server_print("[GAMELAND HLTV] Demo recording STOPPED: %s -> Queued for Web Panel!", g_szHltvDemoName)
		g_szHltvDemoName[0] = 0
	}
	else
	{
		client_print_color(0, print_team_default, "^4[GAMELAND HLTV] ^1Demo recording ^3STOPPED^1 -> Queued for Web Panel!")
		server_print("[GAMELAND HLTV] Demo recording STOPPED -> Queued for Web Panel!")
	}
}

stock gregorian_to_jalali(g_y, g_m, g_d, &j_y, &j_m, &j_d)
{
	new g_days_in_month[] = {31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31}
	new j_days_in_month[] = {31, 31, 31, 31, 31, 31, 30, 30, 30, 30, 30, 29}
	
	new gy = g_y - 1600
	new gm = g_m - 1
	new gd = g_d - 1
	
	new g_day_no = 365*gy + floatround(float((gy+3)/4)) - floatround(float((gy+99)/100)) + floatround(float((gy+399)/400))
	
	for(new i=0; i<gm; ++i)
		g_day_no += g_days_in_month[i]
		
	if (gm > 1 && ((gy%4==0 && gy%100!=0) || (gy%400==0)))
		g_day_no++
		
	g_day_no += gd
	new j_day_no = g_day_no - 79
	
	new j_np = j_day_no / 12053
	j_day_no = j_day_no % 12053
	
	j_y = 979 + 33*j_np + 4 * (j_day_no/1461)
	j_day_no %= 1461
	
	if (j_day_no >= 366) {
		j_y += (j_day_no-1)/365
		j_day_no = (j_day_no-1)%365
	}
	
	for (new i = 0; i < 11 && j_day_no >= j_days_in_month[i]; ++i) {
		j_day_no -= j_days_in_month[i]
		j_m = i + 1
	}
	j_m++
	j_d = j_day_no + 1
}

stock MakeDemoSafeName(szName[], const iLen)
{
	replace_all(szName, iLen, " ", "_")
	replace_all(szName, iLen, "^"", "_")
	replace_all(szName, iLen, "\", "_")
	replace_all(szName, iLen, "/", "_")
	replace_all(szName, iLen, ":", "_")
	replace_all(szName, iLen, "*", "_")
	replace_all(szName, iLen, "?", "_")
	replace_all(szName, iLen, "<", "_")
	replace_all(szName, iLen, ">", "_")
	replace_all(szName, iLen, "|", "_")
	replace_all(szName, iLen, ".", "_")
}

stock Client_StartRecordingAll(const szDemoPrefix[])
{
	#pragma unused szDemoPrefix
	client_print_color(0, print_team_default, "^4[GAMELAND] ^1Client POV demo is local-only now. Players can press ^3F5^1 to start or stop their own demo.")
}

stock Client_StopRecordingAll()
{
	client_print_color(0, print_team_default, "^4[GAMELAND] ^1Client POV demo is controlled locally with ^3F5^1.")
}


public clcmd_startmix(id, bool:bKnife)
{
	client_print_color(id, print_team_default, "^4[Debug] ^1clcmd_startmix called with id: %d", id)
	
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	if(g_eBooleans[bIsMixOn] || g_eBooleans[bIsKnife])
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_ALREADY_STARTED")
		return PLUGIN_HANDLED
	}

	if(g_ePluginSettings[bRequireTen])
	{
		new iTemp[7]
		rg_initialize_player_counts(iTemp[0], iTemp[1], iTemp[2], iTemp[3])
		iTemp[4] = iTemp[0] + iTemp[2]
		iTemp[5] = iTemp[1] + iTemp[3]
		iTemp[6] = iTemp[5] + iTemp[4]

		if(iTemp[6] < 10)
		{
			client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_NEEDS_TEN_PLAYERS")
			return PLUGIN_HANDLED
		}
	}

	g_eInformations[MIX_STARTER] = id

	#if defined FASTCUP_MODE
	if(!g_eBooleans[bWasKnife])
	{
		g_eBooleans[bShouldRecordMix] = false
		clcmd_startmix_internal(id, bKnife)
		return PLUGIN_HANDLED
	}
	#endif

	ShowRecordMatchMenu(id, bKnife)
	return PLUGIN_HANDLED
}

public ApplyShootingLoadout()
{
	if(!g_eBooleans[bIsMixOn] || !IsShootingMap())
	{
		return
	}

	new players[MAX_PLAYERS], count
	get_players(players, count, "ch")

	new mapName[32]
	get_mapname(mapName, charsmax(mapName))
	new bool:bAwp = containi(mapName, "awp_") == 0 || containi(mapName, "aim_sk_awp") == 0

	for(new i; i < count; i++)
	{
		new id = players[i]
		new CsTeams:team = cs_get_user_team(id)
		if(!IsPlayer(id) || (team != CS_TEAM_T && team != CS_TEAM_CT))
		{
			continue
		}

		if(bAwp)
		{
			rg_give_item(id, "weapon_awp", GT_REPLACE)
			rg_set_user_bpammo(id, WEAPON_AWP, 90)
		}
		else if(team == CS_TEAM_CT)
		{
			rg_give_item(id, "weapon_m4a1", GT_REPLACE)
			rg_set_user_bpammo(id, WEAPON_M4A1, 90)
		}
		else
		{
			rg_give_item(id, "weapon_ak47", GT_REPLACE)
			rg_set_user_bpammo(id, WEAPON_AK47, 90)
		}

		rg_give_item(id, "weapon_deagle", GT_REPLACE)
		rg_set_user_bpammo(id, WEAPON_DEAGLE, 35)
		rg_set_user_armor(id, 100, ARMOR_VESTHELM)
	}
}

stock ShowRecordMatchMenu(id, bool:bKnife)
{
	if(!is_user_connected(id))
	{
		g_eBooleans[bShouldRecordMix] = false
		clcmd_startmix_internal(id, bKnife)
		return
	}

	client_print_color(id, print_team_default, "^4[Debug] ^1Displaying HLTV record menu to id: %d", id)

	new szTitle[128]
	formatex(szTitle, charsmax(szTitle), "\y[GAMELAND]\w Start server-side HLTV recording?")
	new menu = menu_create(szTitle, "menu_record_match")
	
	new szInfo[2]
	szInfo[0] = bKnife ? '1' : '0'
	szInfo[1] = 0
	
	menu_additem(menu, "Yes, Record", szInfo)
	menu_additem(menu, "No, Do not record", szInfo)
	menu_additem(menu, "Cancel", "2")
	
	menu_display(id, menu)
}

public menu_record_match(id, menu, item)
{
	if(item == MENU_EXIT)
	{
		menu_destroy(menu)
		return PLUGIN_HANDLED
	}
	
	new szData[6], szName[64], access, callback
	menu_item_getinfo(menu, item, access, szData, charsmax(szData), szName, charsmax(szName), callback)
	menu_destroy(menu)
	
	if(szData[0] == '2') 
	{
		return PLUGIN_HANDLED // Cancel
	}
	
	new bool:bKnife = (szData[0] == '1')
	g_eBooleans[bShouldRecordMix] = (item == 0) // item 0 is Yes, item 1 is No
	
	clcmd_startmix_internal(id, bKnife)
	return PLUGIN_HANDLED
}

public clcmd_startmix_internal(id, bool:bKnife)
{
	new bool:bShootingMap = IsShootingMap()

	#if defined FASTCUP_MODE
	if(g_eBooleans[bWasKnife])
	#endif
	{
		ExecuteForward(g_eForwards[GameBeginPre], g_iRet)
	}

	new szMapName[32], iDate[3], iTime[3]
	enum { iYear = 0, iMonth, iDay }
	enum { iHour = 0, iMin, iSec }
	get_mapname(szMapName, charsmax(szMapName))
	date(iDate[iYear], iDate[iMonth], iDate[iDay])
	time(iTime[iHour], iTime[iMin], iTime[iSec])
	
	if(g_eBooleans[bShouldRecordMix])
	{
		HLTV_StartRecording("GL_Mix")
		Client_StartRecordingAll("GL_Mix")
	}

	static iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	new CsTeams:iTeam

	for(new i; i < iNum ; i++)
	{
		iPlayer = iPlayers[i]

		g_eBooleans[bCanChat][iPlayer] = true

		#if defined FASTCUP_MODE
		if(g_eBooleans[bWasKnife] && bKnife)
		{
		#endif
			if(g_eInformations[MIX_STARTER] == iPlayer)
			{
				client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_PLAYER, "MIX_STARTED_BY_YOU")
			}
			else
			{
				client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_STARTED_BY_X", g_szName[g_eInformations[MIX_STARTER]])
			}

			// Client POV demo recording disabled - HLTV records the match centrally on the server
			
			iTeam = cs_get_user_team(iPlayer)

			if(iTeam == CS_TEAM_CT || iTeam == CS_TEAM_T)
			{

							}
		#if defined FASTCUP_MODE
		}
		#endif
	}

	g_eBooleans[bCanChat][id] = false

	g_iStart = 0

	ResetScore()
	g_eBooleans[bIsShooting] = bShootingMap

	#if defined FASTCUP_MODE
	if(!bShootingMap && !g_eBooleans[bWasKnife])
	{
		g_eBooleans[bWasKnife] = true
		clcmd_knife(id)
		return PLUGIN_HANDLED
	}

	if(!bShootingMap && !bKnife)
	{
		return PLUGIN_HANDLED
	}
	#endif

	g_eBooleans[bIsMixOn] = true
	g_eBooleans[bOvertime] = false
	g_eBooleans[bIsStoppingMix] = false
	g_eInformations[ACE] = -1
	g_eInformations[SEMI_ACE] = -1
	g_eTeamPause[CT_PAUSE] = 0
	g_eTeamPause[TERO_PAUSE] = 0

	StartConfig()

	if(bShootingMap)
	{
		g_bShootingOpening = true
		RandomizeShootingTeams()
		server_cmd("mp_timelimit 0")
		// The plugin owns the ten-round shooting match. Keep the engine
		// max-round limit disabled so it cannot trigger a map change.
		server_cmd("mp_maxrounds 0")
		server_cmd("mp_winlimit 0")
		server_cmd("mp_freezetime 7")
		server_cmd("mp_buytime 0.25")
		set_task(0.4, "ApplyShootingLoadout")
		server_cmd("sv_restart 1")
		set_task(1.0, "StartCount", TASK_COUNT_DURATION, .flags = "b")
		return PLUGIN_CONTINUE
	}

	server_cmd("sv_restart 1")
	set_task(3.0, "task_mix_restart1")
	set_task(8.0, "task_mix_restart2")
	set_task(13.0, "task_mix_live")

	set_task(1.0, "StartCount", TASK_COUNT_DURATION, .flags = "b")

	return PLUGIN_CONTINUE
}

public clcmd_stopmix(id)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	#if defined DEBUG
	client_print_color(0, 0, "clcmd_stopmix() called")
	#endif

	if(!g_eBooleans[bIsKnife] && !g_eBooleans[bIsMixOn])
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_NOT_STARTED_YET")
		return PLUGIN_HANDLED
	}

	g_eBooleans[bIsStoppingMix] = true

	static iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	new CsTeams:iTeam

	g_eInformations[MIX_STOPER] = id

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		if(g_eInformations[MIX_STOPER] == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_PLAYER, "MIX_STOPPED_BY_YOU")
		}
		else
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_STOPPED_BY_X", g_szName[g_eInformations[MIX_STOPER]])
		}

		iTeam = cs_get_user_team(iPlayer)

		if(iTeam == CS_TEAM_CT || iTeam == CS_TEAM_T)
		{
					}

			}

	#if defined FASTCUP_MODE
	g_eBooleans[bWasKnife] = false
	#endif

	ResetScore()
	StopConfig()

	HLTV_StopRecording()
	Client_StopRecordingAll()

	server_cmd("sv_restart 1")

	return PLUGIN_CONTINUE
}

public clcmd_warm(id)
{
	if(is_user_connected(id))
	{
		if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
		{
			client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
			return PLUGIN_HANDLED
		}
	}

	if(g_eBooleans[bIsMixOn] || g_eBooleans[bIsKnife] || task_exists(TASK_CHECKVOTES))
	{
		clcmd_stopmix(id)
	}
	

	static iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	g_eInformations[WARM_CALLER] = id

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		if(g_eInformations[WARM_CALLER] == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_PLAYER, "WARM_STARTED_BY_YOU")
		}
		else
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "WARM_STARTED_BY_X", strlen(g_szName[g_eInformations[WARM_CALLER]]) ? 
			                   g_szName[g_eInformations[WARM_CALLER]] : "Server")
		}

		set_task(2.0, "Task_Warmup", iPlayer + TASK_WARM)
	}

	g_eBooleans[bIsWarm] = true
	g_eBooleans[bOvertime] = false
	// ReGameDLL must ignore team win conditions during warmup.  The hook
	// prevents our mix logic from advancing, while this cvar also blocks the
	// engine's native round-end path after a player dies.
	server_cmd("mp_ignore_round_win_conditions 1")
	#if defined FASTCUP_MODE
	g_eBooleans[bWasKnife] = false
	#endif

	StopConfig()

	server_cmd("mp_freezetime 0")

	server_cmd("mp_buytime 99999")

	server_cmd("sv_restart 1")

	SetGameDesc(MATCHSTATE_WARM)

	return PLUGIN_CONTINUE
}

public Task_Warmup(iPlayer)
{
	iPlayer -= TASK_WARM

	if(g_eBooleans[bIsWarm] && is_user_connected(iPlayer))
	{
		rg_set_user_armor(iPlayer, 100, ARMOR_VESTHELM)

		switch(g_eWarmSettings[bWarmType])
		{
			case false:
			{
				set_task(1.0, "task_set_money", iPlayer + TASK_SET_MONEY)
			}
			case true:
			{
				set_task(1.0, "task_give_weapon", iPlayer + TASK_GIVE_WEAPON)
			}
		}
	}
	return PLUGIN_CONTINUE
}

public task_set_money(id)
{
	id -= TASK_SET_MONEY

	if(!IsPlayer(id) || !g_eBooleans[bIsWarm])
	{
		return PLUGIN_HANDLED
	}

	rg_add_account(id, g_eWarmSettings[iWarmMoney], AS_ADD, true)

	#if defined DEBUG
	client_print_color(id, id, "task_set_money() called")
	#endif

	return PLUGIN_CONTINUE
}

public task_give_weapon(id)
{
	id -= TASK_GIVE_WEAPON

	if(!IsPlayer(id) || !g_eBooleans[bIsWarm] || !is_user_connected(id))
	{
		return PLUGIN_HANDLED
	}

	new TeamName:iTeam = get_member(id, m_iTeam)

	// Shooting maps use the same weapon set during warmup and live play.
	if(IsShootingMap())
	{
		new mapName[32]
		get_mapname(mapName, charsmax(mapName))
		new bool:bAwp = containi(mapName, "awp_") == 0 || containi(mapName, "aim_sk_awp") == 0
		rg_remove_all_items(id, true)
		if(bAwp)
		{
			rg_give_item(id, "weapon_awp", GT_REPLACE)
			rg_set_user_bpammo(id, WEAPON_AWP, 90)
		}
		else if(iTeam == TEAM_CT)
		{
			rg_give_item(id, "weapon_m4a1", GT_REPLACE)
			rg_set_user_bpammo(id, WEAPON_M4A1, 90)
		}
		else
		{
			rg_give_item(id, "weapon_ak47", GT_REPLACE)
			rg_set_user_bpammo(id, WEAPON_AK47, 90)
		}
		rg_give_item(id, "weapon_deagle", GT_REPLACE)
		rg_set_user_bpammo(id, WEAPON_DEAGLE, 35)
		rg_set_user_armor(id, 100, ARMOR_VESTHELM)
		return PLUGIN_HANDLED
	}

	new iWeaponID[3]

	iWeaponID[0] = rg_get_weapon_info(g_eWarmSettings[szWeaponT], WI_ID)
	iWeaponID[1] = rg_get_weapon_info(g_eWarmSettings[szWeaponCT], WI_ID)
	iWeaponID[2] = rg_get_weapon_info(g_eWarmSettings[szPistol], WI_ID)

	switch(iTeam)
	{
		case TEAM_TERRORIST:
		{
			rg_give_item(id, g_eWarmSettings[szWeaponT], GT_REPLACE)
			rg_give_item(id, g_eWarmSettings[szPistol], GT_REPLACE)
			rg_set_user_bpammo(id, WeaponIdType:iWeaponID[0], g_eWarmSettings[iBpAmmo])
			rg_set_user_bpammo(id, WeaponIdType:iWeaponID[2], g_eWarmSettings[iBpAmmo])
		}
		case TEAM_CT:
		{
			rg_give_item(id, g_eWarmSettings[szWeaponCT], GT_REPLACE)
			rg_give_item(id, g_eWarmSettings[szPistol], GT_REPLACE)
			rg_set_user_bpammo(id, WeaponIdType:iWeaponID[1], g_eWarmSettings[iBpAmmo])
			rg_set_user_bpammo(id, WeaponIdType:iWeaponID[2], g_eWarmSettings[iBpAmmo])
		}
	}
	
	#if defined DEBUG
	client_print_color(id, id, "task_give_weapon() called")
	#endif

	return PLUGIN_HANDLED
}

public clcmd_knife(id)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	if(g_eBooleans[bIsMixOn])
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_NEED_STOPPED")
		return PLUGIN_HANDLED
	}

	static iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	g_eInformations[KNIFE_STRATER] = id

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		#if !defined FASTCUP_MODE
		if(g_eInformations[KNIFE_STRATER] == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "KNIFE_STARTED_BY_YOU")
		}
		else
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "KNIFE_STARTED_BY_X", g_szName[g_eInformations[KNIFE_STRATER]])
		}
		#else
		client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "KNIFE_STARTED")
		#endif
	}

	g_iKnifes = 0

	ResetScore()

	g_eBooleans[bIsKnife] = true

	g_iKnifes += 1

	StopConfig()
	
	server_cmd("mp_freezetime 3")
	server_cmd("mp_startmoney 800")

	server_cmd("sv_restart 1")

	SetGameDesc(MATCHSTATE_KNIFE_ROUND)

	return PLUGIN_CONTINUE
}

public RG_EndRound(WinStatus:status, ScenarioEventEndRound:event, Float:tmDelay)
{
	if(get_playersnum() < 1)
	{
		return
	}

	if(event == ROUND_GAME_RESTART || event == ROUND_GAME_COMMENCE)
	{
		if(g_eBooleans[bIsWarm])
		{
			set_task(0.5, "task_reapply_warm")
		}
		return
	}

	if(g_eBooleans[bIsWarm])
	{
		return
	}

	set_task(1.0, "task_end_round", any:status)
}

public RG_EndRound_Pre(WinStatus:status, ScenarioEventEndRound:event, Float:tmDelay)
{
	if(!g_eBooleans[bIsWarm] || event == ROUND_GAME_RESTART || event == ROUND_GAME_COMMENCE)
	{
		return HC_CONTINUE
	}

	// Warmup is continuous: keep a 1v1 running after a death.
	for(new id = 1; id <= MAX_PLAYERS; id++)
	{
		if(IsPlayer(id) && !is_user_alive(id))
		{
			remove_task(id + TASK_REVIVE)
			set_task(0.1, "task_revive", id + TASK_REVIVE)
		}
	}

	return HC_SUPERCEDE
}

public RG_CheckWinConditions_Pre()
{
	if(g_eBooleans[bIsWarm])
	{
		return HC_SUPERCEDE
	}

	return HC_CONTINUE
}

public task_end_round(index)
{
	new WinStatus:status = WinStatus:index

	new szTeamWon[12]
	#if defined FASTCUP_MODE
	new TeamName:iWTeam
	#endif

	switch(status)
	{
		case WINSTATUS_CTS:
		{
			formatex(szTeamWon, charsmax(szTeamWon), "%L", LANG_SERVER, "CT_TEAM")
			#if defined FASTCUP_MODE
			iWTeam = TEAM_CT
			#endif

			if(g_eBooleans[bIsMixOn])
			{
				if(!g_eBooleans[bOvertime])
				{
					g_iScore[CT_SCORE] += 1
					g_iRoundNum += 1
				}
				else
				{
					g_iOvertimeScore[CT_OVER_SCORE] += 1
				}
			}
		}
		case WINSTATUS_TERRORISTS:
		{
			formatex(szTeamWon, charsmax(szTeamWon), "%L", LANG_SERVER, "TERO_TEAM")
			#if defined FASTCUP_MODE
			iWTeam = TEAM_TERRORIST
			#endif

			if(g_eBooleans[bIsMixOn])
			{
				if(!g_eBooleans[bOvertime])
				{
					g_iScore[TERO_SCORE] += 1
					g_iRoundNum += 1
				}
				else
				{
					g_iOvertimeScore[TERO_OVER_SCORE] += 1
				}
			}
		}
	}

	if(g_eBooleans[bIsMixOn])
		SetGameDesc(g_eBooleans[bOvertime] ? MATCHSTATE_OVERTIME : MATCHSTATE_IN_MATCH)
	else if(g_ePluginSettings[bForceWarmup] && !g_eBooleans[bIsWarm] && !g_eBooleans[bIsKnife])
	{
		clcmd_warm(0)
	}

	if(g_iKnifes >= 1 && (status == WINSTATUS_CTS || status == WINSTATUS_TERRORISTS))
	{
		if(g_eBooleans[bIsKnife] && !g_eBooleans[bIsStoppingMix])
		{
			set_pcvar_num(g_cFreezeTime, g_ePluginSettings[iKnifeStartDelay])
			static iPlayer, iPlayers[MAX_PLAYERS], iNum
			get_players(iPlayers, iNum, "ch")

			for(new i; i < iNum; i++)
			{
				iPlayer = iPlayers[i]

				client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "KNIFE_ROUND_WON_BY_X_TEAM", szTeamWon)
				client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "KNIFE_ROUND_MATCH_START_IN", g_ePluginSettings[iKnifeStartDelay])
				
				#if defined FASTCUP_MODE
				if(get_member(iPlayer, m_iTeam) == iWTeam)
				{
					g_iPlayers += 1
					set_task(0.2, "task_ask_player", iPlayer + TASK_ASK)
				}
				#endif
			}

#if defined FASTCUP_MODE
			if(!task_exists(TASK_CHECKVOTES))
			{
				set_task(float(g_ePluginSettings[iKnifeStartDelay]), "task_do_change", TASK_CHECKVOTES)
			}
#endif
			g_eBooleans[bIsKnife] = false
			g_iKnifes = 3

			ResetScore()
		}
	}

	if(CanOvertime() && g_ePluginSettings[iAutoOvertime] && !g_eBooleans[bOvertime])
	{
		g_eBooleans[bOvertime] = true
		g_eOvertime[FirstOvertime] = true

		new iPlayer, iPlayers[MAX_PLAYERS], iNum
		get_players(iPlayers, iNum, "ch")

		for(new i; i < iNum; i++)
		{
			iPlayer = iPlayers[i]

			if(!IsPlayer(iPlayer))
			{
				continue
			}

			#if defined OVERTIME_ONE_ROUND
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "OVERTIME_AUTOMATIC_WILL_START_ONER")
			#else
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "OVERTIME_AUTOMATIC_WILL_START")
			#endif
		}

		g_eBooleans[bTeamSwap] = false

		OvertimeConfig()

		set_pcvar_num(g_cFreezeTime, 15)
		set_task(0.2, "task_delayed_swap")
		set_task(2.5, "task_show_overtime_start")
		set_task(12.0, "task_halftime_restart1")
		set_task(17.0, "task_halftime_restart2")
		set_task(22.0, "task_overtime_live")
	}

	if(g_eBooleans[bOvertime])
	{
		CheckOvertimePhase()
	}

 	if(g_eBooleans[bIsKnife])
 	{
		g_iKnifes += 1
 	}

 	if(g_eBooleans[bIsMixOn])
 	{
 		g_bPaused = false
 		g_iTimer = g_ePluginSettings[iPauseTime] - 1

	 	static iPlayer, iPlayers[MAX_PLAYERS], iNum
		get_players(iPlayers, iNum, "ch")

		new iDamageGiven, iDamageTaken, iHitsGiven, iHitsTaken, iVictim, CsTeams:iTeam

		for(new i; i < iNum; i++)
		{
			iPlayer = iPlayers[i]

			if(false /* g_eBooleans[bCanShowStats] disabled by user */)
			{
				for(new j; j < iNum; j++)
				{
					iVictim = iPlayers[j]

					iTeam = cs_get_user_team(iVictim)

					if(iTeam == CS_TEAM_CT || iTeam == CS_TEAM_T)
					{
						iDamageGiven = g_ePlayerStats[iPlayer][iVictim][DamageGiven]
						iDamageTaken = g_ePlayerStats[iVictim][iPlayer][DamageGiven]

						if(iDamageGiven > 100)
						{
							iDamageGiven = 100
						}

						if(iDamageTaken > 100)
						{
							iDamageTaken = 100
						}

						if(i != j && iTeam != cs_get_user_team(iPlayer))
						{
							if(!(iDamageGiven || iDamageTaken))
								continue

							iHitsGiven = g_ePlayerStats[iPlayer][iVictim][HitsGiven]
							iHitsTaken = g_ePlayerStats[iVictim][iPlayer][HitsGiven]

							client_print_color(iPlayer, iPlayer, "^4%s ^1%s (^4%d ^1%L^4 %d^1) %L, (^4%d^1 %L^4 %d^1) %L.", 
							                   g_ePluginSettings[szPrefix], g_szName[iVictim], iDamageGiven, LANG_PLAYER, "IN",
							                    iHitsGiven, LANG_PLAYER, "DAMAGE", iDamageTaken, LANG_PLAYER, "IN", iHitsTaken, LANG_PLAYER, "RECEIVED")
						}
					}
				}
			}

			if(g_iPlayerKills[iPlayer] == 5)
			{
				g_eInformations[ACE] = iPlayer
			}

			if(g_iPlayerKills[iPlayer] == 4)
			{
				g_eInformations[SEMI_ACE] = iPlayer
			}
		}

		for(new i; i < iNum; i++)
		{
			iPlayer = iPlayers[i]

			if(g_eInformations[ACE] != -1)
			{
				if(g_eInformations[ACE] == iPlayer)
				{
									}
				else
				{
					client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "X_SCORED_ACE", g_szName[g_eInformations[ACE]])
				}
			}

			if(g_eInformations[SEMI_ACE] != -1)
			{
				if(g_eInformations[SEMI_ACE] == iPlayer)
				{
									}
				else
				{
					client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "X_SCORED_SEMIACE", g_szName[g_eInformations[SEMI_ACE]])
				}
			}

					}

		for(new i = 1; i <= MAX_PLAYERS; i++)
		{
			for(new j = 1; j <= MAX_PLAYERS; j++)
			{
				g_ePlayerStats[i][j][DamageGiven] = 0
				g_ePlayerStats[i][j][HitsGiven] = 0
				g_ePlayerStats[i][j][PlayerHealth] = 0
			}
		}

		if(g_eTeamPause[TERO_PAUSE] == 1)
		{
			set_pcvar_num(g_cFreezeTime, g_ePluginSettings[iPauseTime])
			server_cmd("mp_buytime 0.80")
			g_eTeamPause[TERO_PAUSE] += 1
			g_bPaused = true
		}
		else if(g_eTeamPause[CT_PAUSE] == 1)
		{
			set_pcvar_num(g_cFreezeTime, g_ePluginSettings[iPauseTime])
			server_cmd("mp_buytime 0.80")
			g_eTeamPause[CT_PAUSE] += 1
			g_bPaused = true
		}

		if(!g_bPaused && !task_exists(TASK_CHECKVOTES))
		{
			set_pcvar_num(g_cFreezeTime, g_eBooleans[bIsShooting] ? 0 : g_iFreezeTime)
		}

		if(IsHalf() && !g_eBooleans[bOvertime] && !g_eBooleans[bTeamSwap])
		{
			set_pcvar_num(g_cFreezeTime, g_ePluginSettings[iFreezetimeSwap])
			set_task(0.1, "task_swap_score")
			set_task(0.2, "task_delayed_swap")
			set_task(2.5, "task_show_halftime")
			set_task(12.0, "task_halftime_restart1")
			set_task(17.0, "task_halftime_restart2")
			set_task(22.0, "task_halftime_live")
		}
	}

	return HC_CONTINUE
}

#if defined FASTCUP_MODE
public task_ask_player(id)
{
	id -= TASK_ASK

	new szTemp[64]

	formatex(szTemp, charsmax(szTemp), "\r%s \w%L", g_ePluginSettings[szPrefix], LANG_SERVER, "MENU_ASK_PLAYER")
	new menu = menu_create(szTemp, "handle_ask_menu")

	formatex(szTemp, charsmax(szTemp), "\y%L", LANG_SERVER, "ASK_MENU_SWITCH")
	menu_additem(menu, szTemp)

	formatex(szTemp, charsmax(szTemp), "\y%L", LANG_SERVER, "ASK_MENU_STAY")
	menu_additem(menu, szTemp)

	_MenuDisplay(id, menu)
}

public handle_ask_menu(id, menu, item)
{
	if(item == MENU_EXIT || !IsPlayer(id) || g_bVoted || g_eBooleans[bIsMixOn])
	{
		return _MenuExit(menu)
	}

	switch(item)
	{
		case 0:
		{
			g_iAnswer[SWITCH] += 1
		}
		case 1:
		{
			g_iAnswer[STAY] += 1
		}
	}

	CheckVotes(g_iAnswer)

	return _MenuExit(menu)
}

public CheckVotes(any:iAnswer[])
{
	if(iAnswer[SWITCH] > iAnswer[STAY])
	{
		g_iVote = 1
	}
	else if(iAnswer[SWITCH] < iAnswer[STAY])
	{
		g_iVote = 0
	}
	else if(iAnswer[SWITCH] == iAnswer[STAY])
	{
		g_iVote = 0
	}
	else 
	{
		g_iVote = 0
	}
}

public task_do_change(iTaskID)
{
	g_bVoted = true

	new szTemp[128]

	switch(g_iVote)
	{
		case 0:
		{
			formatex(szTemp, charsmax(szTemp), "%L", LANG_SERVER, "STAY")
		}
		case 1:
		{
			formatex(szTemp, charsmax(szTemp), "%L", LANG_SERVER, "SWITCH")
		}
	}

	client_print_color(0, 0, "^4%s %L %s", g_ePluginSettings[szPrefix], LANG_SERVER, "TEAM_VOTED", szTemp)

	if(g_iVote) 
	{
		rg_swap_all_players()
	}

	g_eBooleans[bCanShowStats] = false

	ShowRecordMatchMenu(g_eInformations[MIX_STARTER], true)

	return PLUGIN_HANDLED
}
#endif

public ev_NewRound()
{
	#if defined FASTCUP_MODE
	if(g_eBooleans[bIsMixOn] && g_iKnifes == 3)
	#else
	if(g_eBooleans[bIsMixOn])
	#endif
	{
		set_task(1.0, "task_show_score")

		g_eBooleans[bCanShowStats] = true

		if(g_bPaused)
		{
			set_task(0.01, "task_show_dhud")
		}
	}
}

public ev_GameRestart()
{
	set_task(1.0, "task_change_bool", TASK_CHANGE_BOOL)
}

public task_change_bool(taskid)
{
	g_eBooleans[bIsStoppingMix] = false

	remove_task(TASK_CHANGE_BOOL)
}

public CS_OnBuyAttempt(id, item)
{
	if(g_eBooleans[bIsWarm] && g_eWarmSettings[bWarmType])
	{
		return PLUGIN_HANDLED
	}

	if(g_eBooleans[bIsKnife])
	{
		if(item != CSI_VEST && item != CSI_VESTHELM)
		{
			return PLUGIN_HANDLED
		}
	}
	
	if(item == CSI_SHIELDGUN || item == CSI_NVGS || item == CSI_SG550 || item == CSI_G3SG1 || item == CSI_SHIELD)
	{
		return PLUGIN_HANDLED
	}

	return PLUGIN_CONTINUE
}

public clcmd_chat_on(id)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	#if defined DEBUG
	client_print_color(0, 0, "clcmd_chat() called")
	#endif

	if(!g_eBooleans[bIsMixOn])
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_NOT_STARTED_YET")
		return PLUGIN_HANDLED
	}

	static iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	g_eInformations[CHAT] = id

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		if(g_eInformations[CHAT] == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "CHAT_OPENED_BY_YOU")
		}
		else
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "CHAT_OPENED_BY_X", g_szName[g_eInformations[CHAT]])
		}

		g_eBooleans[bCanChat][iPlayer] = true
	}

	return PLUGIN_HANDLED
}

public clcmd_chat_off(id)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	#if defined DEBUG
	client_print_color(0, 0, "clcmd_chat() called")
	#endif

	if(!g_eBooleans[bIsMixOn])
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_NOT_STARTED_YET")
		return PLUGIN_HANDLED
	}

	static iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	g_eInformations[CHAT] = id

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		if(g_eInformations[CHAT] == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "CHAT_CLOSED_BY_YOU")
		}
		else
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "CHAT_CLOSED_BY_X", g_szName[g_eInformations[CHAT]])
		}
		
		if(!(get_user_flags(iPlayer) & read_flags(g_ePluginSettings[szAdminFlags])))
		{
			g_eBooleans[bCanChat][iPlayer] = false
		}
	}

	return PLUGIN_HANDLED
}

public plugin_cfg()
{
	set_task(3.0, "task_start_warm")
}

public hook_say(id)
{
	if(!is_user_connected(id))
		return PLUGIN_CONTINUE

	if(!g_eBooleans[bCanChat][id] && g_eBooleans[bIsMixOn])
	{
		if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminFlags])))
		{
			return PLUGIN_HANDLED
		}
	}

	new sArg[MAX_NAME_LENGTH], szMessage[180]
	read_argv(1, sArg, charsmax(sArg))
	read_args(szMessage, charsmax(szMessage))
	remove_quotes(szMessage)

	if(equal(szMessage, "hs1") || equal(szMessage, "/hs1") || equal(szMessage, ".hs1"))
	{
		clcmd_hs1(id)
		return PLUGIN_HANDLED
	}
	if(equal(szMessage, "hs0") || equal(szMessage, "/hs0") || equal(szMessage, ".hs0"))
	{
		clcmd_hs0(id)
		return PLUGIN_HANDLED
	}

	if(strlen(szMessage) != 0)
	{
		if(szMessage[0] == '/')
		{
			switch(szMessage[1])
			{
				case 's':
				{
					if(szMessage[2] == 'p' && szMessage[5] != 'a')
					{
						clcmd_move_spec(id, szMessage, charsmax(szMessage), 1)
						return PLUGIN_HANDLED
					}
				}
				case 't':
				{
					if(szMessage[2] == ' ')
					{
						clcmd_move_t(id, szMessage, charsmax(szMessage), 1)
						return PLUGIN_HANDLED
					}
				}
				case 'c':
				{
					if(szMessage[2] == 't')
					{
						clcmd_move_ct(id, szMessage, charsmax(szMessage), 1)
						return PLUGIN_HANDLED
					}
				}
				case 'p':
				{
					if(szMessage[2] == 'a' && szMessage[5] == ' ')
					{
						clcmd_passon(id, szMessage, 1)
						return PLUGIN_HANDLED
					}
				}
			}
		}

		new iPlayer, iPlayers[MAX_PLAYERS], iNum
		get_players(iPlayers, iNum, "c")

		if(is_user_alive(id))
		{
			format(szMessage, charsmax(szMessage), "^3%n^1: %s", id, szMessage)
		}
		else
		{
			format(szMessage, charsmax(szMessage), "^1*[DEAD] ^3%n^1: %s", id, szMessage)
		}

		for(new i; i < iNum; i++)
		{
			iPlayer = iPlayers[i]

			client_print_color(iPlayer, id, szMessage)
		}
	}

	return PLUGIN_CONTINUE
}

public HookSay(iMsgID, Msg, iDest)
{
	new szBuffer[64]
	get_msg_arg_string(2, szBuffer, charsmax(szBuffer))

	if(g_eBooleans[bIsMixOn] || g_eBooleans[bIsStoppingMix])
	{
		if(equal(szBuffer, "#Cstrike_Name_Change"))
		{
	        return PLUGIN_HANDLED
		}
	}

	if(equal(szBuffer, "#Cstrike_Chat_CT") || equal(szBuffer, "#Cstrike_Chat_T") || equal(szBuffer, "#Cstrike_Chat_CT_Dead") || equal(szBuffer, "#Cstrike_Chat_T_Dead"))
	{
		return PLUGIN_CONTINUE
	}

	return PLUGIN_HANDLED
}

public clcmd_overtime(id)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	#if defined DEBUG
	client_print_color(0, 0, "clcmd_overtime() called")
	#endif

	if(!g_eBooleans[bIsMixOn])
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_NOT_STARTED_YET")
		return PLUGIN_HANDLED
	}

	if(!CanOvertime())
	{
		client_print_color(id, id, "^4%s ^1%L", g_ePluginSettings[szPrefix], LANG_SERVER, "CANT_START_OVERTIME_YET")
		return PLUGIN_HANDLED
	}

	if(g_eBooleans[bOvertime])
	{
		client_print_color(id, id, "^4%s ^1%L", g_ePluginSettings[szPrefix], LANG_SERVER, "OVERTIME_ALREADY_STARTED")
		return PLUGIN_HANDLED
	}

	static iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	g_eInformations[OVERTIME_STARTER] = id

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		if(g_eInformations[OVERTIME_STARTER] == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "OVERTIME_STARTED_BY_YOU")
		}
		else
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "OVERTIME_STARTED_BY_X", g_szName[g_eInformations[OVERTIME_STARTER]])
		}
	}

	OvertimeConfig()

	set_pcvar_num(g_cFreezeTime, 15)
	set_task(0.2, "task_delayed_swap")
	set_task(2.5, "task_show_overtime_start")
	set_task(12.0, "task_halftime_restart1")
	set_task(17.0, "task_halftime_restart2")
	set_task(22.0, "task_overtime_live")

	g_eBooleans[bOvertime] = true

	g_eBooleans[bTeamSwap] = false

	g_eOvertime[FirstOvertime] = true

	return PLUGIN_HANDLED
}

public clcmd_passon(id, szMessage[180], IsSay)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	#if defined DEBUG
	client_print_color(0, 0, "clcmd_passon() called")
	#endif

	if(!g_eBooleans[bIsMixOn])
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_NOT_STARTED_YET")
		return PLUGIN_HANDLED
	}

	if(IsSay)
	{
		read_argv(1, szMessage, charsmax(szMessage))
		replace_all(szMessage, charsmax(szMessage), "/pass", "")
	}

	server_cmd("sv_password %s", szMessage)

	static iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	g_eInformations[PASSON_CALLER] = id

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		if(g_eInformations[PASSON_CALLER] == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PASSWORD_SETTED_BY_YOU", szMessage)
		}
		else if((get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PASSWORD_SETTED_BY_X_ADMIN", g_szName[g_eInformations[PASSON_CALLER]], szMessage)
		}
		else
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PASSWORD_SETTED_BY_X", g_szName[g_eInformations[PASSON_CALLER]])
		}
	}

	return PLUGIN_HANDLED
}

public clcmd_passoff(id)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	#if defined DEBUG
	client_print_color(0, 0, "clcmd_passoff() called")
	#endif

	if(!g_eBooleans[bIsMixOn])
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_NOT_STARTED_YET")
		return PLUGIN_HANDLED
	}

	server_cmd("sv_password ^"^"")

	static iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	g_eInformations[PASSOFF_CALLER] = id

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		if(g_eInformations[PASSOFF_CALLER] == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PASSWORD_REMOVED_BY_YOU")
		}
		else
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PASSWORD_REMOVED_BY_X", g_szName[g_eInformations[PASSOFF_CALLER]])
		}
	}

	return PLUGIN_HANDLED
}

public task_show_score()
{
	new iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		if(!IsHalf() && !IsLastRound() && !g_eBooleans[bOvertime] && !IsPreLastRound())
		{
			if(!g_iStart)
			{
				client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_SCORE_IS", LANG_SERVER, "CT_TEAM", g_iScore[CT_SCORE], LANG_SERVER, "TERO_TEAM", g_iScore[TERO_SCORE])
			}
			else
			{
				client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_SCORE_IS_WITH_END", LANG_SERVER, "CT_TEAM", g_iScore[CT_SCORE], LANG_SERVER, "TERO_TEAM", g_iScore[TERO_SCORE])
			}
		}
		
		if(IsHalf() && !g_eBooleans[bOvertime] && !g_eBooleans[bTeamSwap])
		{
			set_pcvar_num(g_cFreezeTime, g_ePluginSettings[iFreezetimeSwap])
			if(!IsPreLastRound())
			{
				client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_HALF_SCORE", LANG_SERVER, "CT_TEAM", g_iScore[CT_SCORE], LANG_SERVER, "TERO_TEAM", g_iScore[TERO_SCORE])
			}

			#if defined DEBUG
			client_print_color(0, 0, "IsHalf() called")
			#endif
		}

		if(IsPreLastRound() && !g_eBooleans[bOvertime])
		{
			new szTemp[16]
			LastRoundUntilWin(szTemp, charsmax(szTemp))

			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_LAST_ROUND_FOR_X_TEAM", szTemp)
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_SCORE_IS_WITH_END", LANG_SERVER, "CT_TEAM", g_iScore[CT_SCORE], LANG_SERVER, "TERO_TEAM", g_iScore[TERO_SCORE])
		}

		if(IsLastRound())
		{
			new szTemp[16]
			WinnerTeam(szTemp, charsmax(szTemp))

			
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_WON_BY_X_TEAM", szTemp)
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_PLAYER, "MIX_END_SCORE", LANG_SERVER, "CT_TEAM", g_iScore[CT_SCORE], LANG_SERVER, "TERO_TEAM", g_iScore[TERO_SCORE])
		
			// Client POV demo recording is controlled locally by the player.
		}

		if(g_eOvertime[FirstOvertime] && !IsHalf() && !OvertimeFinished())
		{
			#if !defined OVERTIME_ONE_ROUND
			if(!g_eOvertime[SecondOvertime] && !g_eBooleans[bTeamSwap])
			{
				client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "FIRST_OVERTIME_SCORE_IS", LANG_SERVER, "CT_TEAM", g_iOvertimeScore[CT_OVER_SCORE], LANG_SERVER, "TERO_TEAM", g_iOvertimeScore[TERO_OVER_SCORE])
			}
			
			if(g_eOvertime[SecondOvertime] && g_eBooleans[bTeamSwap])
			{
				client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "SECOND_OVERTIME_SCORE_IS", LANG_SERVER, "CT_TEAM", g_iOvertimeScore[CT_OVER_SCORE], LANG_SERVER, "TERO_TEAM", g_iOvertimeScore[TERO_OVER_SCORE])
			}
			#else
			if(!g_eOvertime[SecondOvertime] && !g_eBooleans[bTeamSwap])
			{
				client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "ONE_ROUND_FOR_WIN", LANG_SERVER)
			}
			#endif
		}

		if(OvertimeFinished())
		{
			new szTemp[16]
			WinnerTeam(szTemp, charsmax(szTemp))

			
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_WON_BY_X_TEAM_IN_OVERTIME", szTemp)
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_PLAYER, "MIX_OVERTIME_END_SCORE", LANG_SERVER, "CT_TEAM", g_iOvertimeScore[CT_OVER_SCORE], LANG_SERVER, "TERO_TEAM", g_iOvertimeScore[TERO_OVER_SCORE])
		
			// Client POV demo recording is controlled locally by the player.
		}

		g_iPlayerKills[iPlayer] = 0
	}

	ExecuteForward(g_eForwards[NewRound], g_iRet, g_iScore[CT_SCORE], g_iScore[TERO_SCORE], g_iDuration)

	if(IsLastRound() || OvertimeFinished())
	{
		set_task(5.0, "task_start_warm")
		
		HLTV_StopRecording()
		Client_StopRecordingAll()
	}

	g_eBooleans[bIsStoppingMix] = false
	g_eInformations[ACE] = -1
	g_eInformations[SEMI_ACE] = -1

	g_iStart = 1
}

public task_show_dhud()
{
	if(g_iTimer > 0)
	{
		static szMsg[64]
		formatex(szMsg, charsmax(szMsg), "%s %L [%d]", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_TIMEOUTED", g_iTimer)
		set_dhudmessage(255, 255, 255, -1.0, 0.2, 0, 0.0, 1.00)
		show_dhudmessage(0, szMsg)

		g_iTimer--

		if(g_bPaused)
		{
			set_task(1.0, "task_show_dhud")
		}
	}
}

public task_delayed_swap()
{
	new iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]
		g_ePlayerScore[iPlayer][iKILLS] = get_user_frags(iPlayer)
		g_ePlayerScore[iPlayer][iDEATHS] = get_user_deaths(iPlayer)
	}

	rg_swap_all_players()

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		new TeamName:iTeam = get_member(iPlayer, m_iTeam)

		if(iTeam == TEAM_UNASSIGNED || iTeam == TEAM_SPECTATOR)
			continue 
		SetMembers()
		set_member_game(m_bCTCantBuy, true)
		set_member_game(m_bTCantBuy, true)
		rg_add_account(iPlayer, get_cvar_num("mp_startmoney"), AS_SET)
		rg_remove_all_items(iPlayer, true)

		set_task(1.4, "task_give_equipment", iPlayer + TASK_GIVE_EQUIPMENT)
	}

	rg_round_end(1.0, WINSTATUS_NONE, ROUND_GAME_OVER)

	set_task(1.2, "task_delayed_members")
}

public SetMembers()
{
	// https://github.com/rehlds/ReGameDLL_CS/blob/master/regamedll/dlls/multiplay_gamerules.cpp#L1967-L1978
	set_member_game(m_iAccountTerrorist, 0)
	set_member_game(m_iAccountCT, 0)
	set_member_game(m_iNumTerroristWins, 0)
	set_member_game(m_iNumCTWins, 0)
	set_member_game(m_iNumConsecutiveTerroristLoses, 0)
	set_member_game(m_iNumConsecutiveCTLoses, 0)
	set_member_game(m_iLoserBonus, rg_get_account_rules(RR_LOSER_BONUS_DEFAULT))
}

public task_delayed_members()
{
	set_member_game(m_bCTCantBuy, false)
	set_member_game(m_bTCantBuy, false)
	g_iGaveC4 = false
	
	new iCT, iT
	if(g_eBooleans[bOvertime])
	{
		iCT = g_iOvertimeScore[CT_OVER_SCORE]
		iT = g_iOvertimeScore[TERO_OVER_SCORE]
	}
	else
	{
		iCT = g_iScore[CT_SCORE]
		iT = g_iScore[TERO_SCORE]
	}

	// Set engine internal counters so sv_restart reads correct values
	set_member_game(m_iNumCTWins, iCT)
	set_member_game(m_iNumTerroristWins, iT)
	rg_update_teamscores(iCT, iT, false)

	new iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]
		set_user_frags(iPlayer, g_ePlayerScore[iPlayer][iKILLS])
		cs_set_user_deaths(iPlayer, g_ePlayerScore[iPlayer][iDEATHS])

		message_begin(MSG_ALL, get_user_msgid("ScoreInfo"))
		write_byte(iPlayer)
		write_short(g_ePlayerScore[iPlayer][iKILLS])
		write_short(g_ePlayerScore[iPlayer][iDEATHS])
		write_short(0)
		write_short(get_member(iPlayer, m_iTeam))
		message_end()
	}
}

public task_halftime_restart1()
{
	server_cmd("sv_restart 1")
	set_task(1.5, "task_delayed_members")
	client_print_color(0, print_team_default, "^4%s ^1Restart ^4[1/3]", g_ePluginSettings[szPrefix])
}

public task_halftime_restart2()
{
	server_cmd("sv_restart 1")
	set_task(1.5, "task_delayed_members")
	client_print_color(0, print_team_default, "^4%s ^1Restart ^4[2/3]", g_ePluginSettings[szPrefix])
}

public task_halftime_live()
{
	server_cmd("sv_restart 1")
	set_task(1.5, "task_delayed_members")
	set_task(1.5, "task_show_live")
}

public task_mix_restart1()
{
	server_cmd("sv_restart 1")
	client_print_color(0, print_team_default, "^4%s ^1Restart ^4[1/3]", g_ePluginSettings[szPrefix])
}

public task_mix_restart2()
{
	server_cmd("sv_restart 1")
	client_print_color(0, print_team_default, "^4%s ^1Restart ^4[2/3]", g_ePluginSettings[szPrefix])
}

public task_mix_live()
{
	server_cmd("sv_restart 1")
	set_task(2.5, "task_show_live")
}

public task_give_equipment(iPlayer)
{
	iPlayer -= TASK_GIVE_EQUIPMENT

	if(!is_user_alive(iPlayer))
		return

	new szDefaultWeap[48]

	new TeamName:iTeam = get_member(iPlayer, m_iTeam)

	if(iTeam == TEAM_UNASSIGNED || iTeam == TEAM_SPECTATOR)
		return 

	rg_remove_all_items(iPlayer, g_eBooleans[bIsShooting] && IsShootingMap())
	rg_set_user_armor(iPlayer, 100, ARMOR_KEVLAR)

	// Shooting maps own their weapon rules.  The regular mix equipment path
	// used to run after ApplyShootingLoadout and replace the guns with a knife
	// and the default pistol on every restart/round setup.
	if(g_eBooleans[bIsShooting] && IsShootingMap())
	{
		new mapName[32]
		get_mapname(mapName, charsmax(mapName))
		new bool:bAwp = containi(mapName, "awp_") == 0 || containi(mapName, "aim_sk_awp") == 0

		if(bAwp)
		{
			rg_give_item(iPlayer, "weapon_awp", GT_REPLACE)
			rg_set_user_bpammo(iPlayer, WEAPON_AWP, 90)
		}
		else if(iTeam == TEAM_CT)
		{
			rg_give_item(iPlayer, "weapon_m4a1", GT_REPLACE)
			rg_set_user_bpammo(iPlayer, WEAPON_M4A1, 90)
		}
		else
		{
			rg_give_item(iPlayer, "weapon_ak47", GT_REPLACE)
			rg_set_user_bpammo(iPlayer, WEAPON_AK47, 90)
		}

		rg_give_item(iPlayer, "weapon_deagle", GT_REPLACE)
		rg_set_user_bpammo(iPlayer, WEAPON_DEAGLE, 35)
		rg_set_user_armor(iPlayer, 100, ARMOR_VESTHELM)
		return
	}

	rg_give_item(iPlayer, "weapon_knife")

	switch(iTeam)
	{
		case TEAM_TERRORIST:
		{
			get_cvar_string("mp_t_default_weapons_secondary", szDefaultWeap, charsmax(szDefaultWeap))
			// if we stripped the C4 from player, give one to a random player
			if(get_member_game(m_bMapHasBombZone) && !g_iGaveC4)
			{
				rg_give_item(iPlayer, "weapon_c4", GT_REPLACE)
				g_iGaveC4 = true
			}
		}
		case TEAM_CT:
		{
			get_cvar_string("mp_ct_default_weapons_secondary", szDefaultWeap, charsmax(szDefaultWeap))
		}
	}

	format(szDefaultWeap, charsmax(szDefaultWeap), "weapon_%s", szDefaultWeap)
	rg_give_item(iPlayer, szDefaultWeap)
	new WeaponIdType:wid = rg_get_weapon_info(szDefaultWeap, WI_ID)

	if(!wid)
		return

	rg_set_user_bpammo(iPlayer, wid, rg_get_global_iteminfo(wid, ItemInfo_iMaxClip) * 2)
}

public task_swap_score()
{
	g_eBooleans[bTeamSwap] = true

	#if defined DEBUG
	client_print_color(0, 0, "task_swap_score() called")
	#endif
	
	new temp[6]
	if(g_eBooleans[bOvertime])
	{
			temp[2] = g_iOvertimeScore[CT_OVER_SCORE]
			temp[3] = g_iOvertimeScore[TERO_OVER_SCORE]
			g_iOvertimeScore[TERO_OVER_SCORE] = temp[2]
			g_iOvertimeScore[CT_OVER_SCORE] = temp[3]

			#if defined DEBUG
			client_print_color(0, 0, "if() called")
			#endif
	}
	else
	{
		temp[0] = g_iScore[CT_SCORE]
		temp[1] = g_iScore[TERO_SCORE]
		g_iScore[TERO_SCORE] = temp[0]
		g_iScore[CT_SCORE] = temp[1]

		#if defined DEBUG
		client_print_color(0, 0, "else() called")
		client_print_color(0, 0, "temp[0] = %i", temp[0])
		client_print_color(0, 0, "temp[1] = %i", temp[1])
		#endif
	}
	
	temp[4] = g_eTeamPause[CT_PAUSE]
	temp[5] = g_eTeamPause[TERO_PAUSE]
	g_eTeamPause[TERO_PAUSE] = temp[4]
	g_eTeamPause[CT_PAUSE] = temp[5]

	set_pcvar_num(g_cFreezeTime, g_iFreezeTime)

	for(new i; i < ArraySize(g_aPlayerData); i++)
	{
		ArrayDeleteItem(g_aPlayerData, i)
	}
}

public clcmd_specall(id)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	if(g_eBooleans[bIsMixOn])
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_NEED_STOPPED")
		return PLUGIN_HANDLED
	}

	static iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	g_eInformations[SPECALL_CALLER] = id

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		if(g_eInformations[SPECALL_CALLER] == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYERS_MOVED_SPEC_BY_YOU")
		}
		else
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYERS_MOVED_SPEC_BY_X", g_szName[g_eInformations[SPECALL_CALLER]])
		}

		rg_join_team(iPlayer, TEAM_SPECTATOR)
		rg_round_end(1.0, WINSTATUS_DRAW, ROUND_END_DRAW, "ROUND DRAW", "ROUND DRAW", true)
	}

	return PLUGIN_HANDLED
}

public task_specall(id)
{
	id -= TASK_SPECALL

	if(!is_user_connected(id))
	{
		return
	}

	rg_join_team(id, TEAM_SPECTATOR)
}

public clcmd_restart(id)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	if(g_eBooleans[bIsKnife])
	{
		g_iKnifes = 0
		
		#if defined FASTCUP_MODE
		g_bVoted = false
		remove_task(TASK_CHECKVOTES)
		arrayset(g_iAnswer, 0, sizeof(g_iAnswer))
		#endif
	}

	new iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")
	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]
		g_ePlayerScore[iPlayer][iKILLS] = get_user_frags(iPlayer)
		g_ePlayerScore[iPlayer][iDEATHS] = get_user_deaths(iPlayer)
	}

	server_cmd("sv_restart 1")
	set_task(1.5, "task_delayed_members")
	client_print_color(0, print_team_default, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_HAS_BEEN_RESTARTED")

	return PLUGIN_HANDLED
}

public task_set_score()
{
	rg_update_teamscores(g_iScore[CT_SCORE], g_iScore[TERO_SCORE], false)
}

public clcmd_score(id)
{
	if(!g_eBooleans[bIsMixOn])
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_NOT_STARTED_YET")
		return PLUGIN_HANDLED
	}

	if(!IsHalf() && !IsLastRound() && !g_eBooleans[bOvertime] && !IsPreLastRound())
	{
		if(!g_iStart)
		{
			client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_SCORE_IS", LANG_SERVER, "CT_TEAM", g_iScore[CT_SCORE], LANG_SERVER, "TERO_TEAM", g_iScore[TERO_SCORE])
		}
		else
		{
			client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_SCORE_IS_WITH_END", LANG_SERVER, "CT_TEAM", g_iScore[CT_SCORE], LANG_SERVER, "TERO_TEAM", g_iScore[TERO_SCORE])
		}
	}

	if(g_eOvertime[FirstOvertime] && !IsHalf() && !OvertimeFinished())
	{
		if(!g_eOvertime[SecondOvertime] && !g_eBooleans[bTeamSwap])
		{
			client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "FIRST_OVERTIME_SCORE_IS", LANG_SERVER, "CT_TEAM", g_iOvertimeScore[CT_OVER_SCORE], LANG_SERVER, "TERO_TEAM", g_iOvertimeScore[TERO_OVER_SCORE])
		}
	}

	if(IsPreLastRound() && !g_eBooleans[bOvertime])
	{
		new szTemp[16]
		LastRoundUntilWin(szTemp, charsmax(szTemp))

		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_LAST_ROUND_FOR_X_TEAM", szTemp)
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_SCORE_IS_WITH_END", LANG_SERVER, "CT_TEAM", g_iScore[CT_SCORE], LANG_SERVER, "TERO_TEAM", g_iScore[TERO_SCORE])
	}

	return PLUGIN_CONTINUE
}

public clcmd_ct(id)
{
	new arg1[MAX_NAME_LENGTH]
	read_argv(1, arg1, charsmax(arg1))

	clcmd_move_ct(id, arg1, charsmax(arg1))

	return PLUGIN_HANDLED
}

stock clcmd_move_ct(id, szMessage[], iLen, IsSay = -1)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	new target

	if(IsSay)
	{
		replace_all(szMessage, iLen, "/ct ", "")
		replace_all(szMessage, iLen, "^"", "")
	}

	target = cmd_target(id, szMessage, CMDTARGET_ALLOW_SELF)

	if(!target)
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYER_NOT_FOUND")
		return PLUGIN_HANDLED
	}

	static iPlayer, iPlayers[MAX_PLAYERS], iNum, szTeam[22]
	get_players(iPlayers, iNum, "ch")

	GetTeam(CT, szTeam, charsmax(szTeam))

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		if(id == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYER_X_MOVED_X_BY_YOU", g_szName[target], szTeam)
		}
		else if(target == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_WERE_MOVED_X_BY_X", szTeam, g_szName[id])
		}
		else
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYER_X_MOVED_X_BY_X", g_szName[target], szTeam, g_szName[id])
		}
	}

	rg_join_team(target, TEAM_CT)

	return PLUGIN_HANDLED
}

public clcmd_t(id)
{
	new arg1[MAX_NAME_LENGTH]
	read_argv(1, arg1, charsmax(arg1))

	clcmd_move_t(id, arg1, charsmax(arg1))

	return PLUGIN_HANDLED
}

stock clcmd_move_t(id, szMessage[], iLen, IsSay = -1)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	new target
	
	if(IsSay)
	{
		replace_all(szMessage, iLen, "/t ", "")
		replace_all(szMessage, iLen, "^"", "")
	}

	target = cmd_target(id, szMessage, CMDTARGET_ALLOW_SELF)

	if(!target)
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYER_NOT_FOUND")
		return PLUGIN_HANDLED
	}

	static iPlayer, iPlayers[MAX_PLAYERS], iNum, szTeam[22]
	get_players(iPlayers, iNum, "ch")

	GetTeam(TERO, szTeam, charsmax(szTeam))

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		if(id == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYER_X_MOVED_X_BY_YOU", g_szName[target], szTeam)
		}
		else if(target == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_WERE_MOVED_X_BY_X", szTeam, g_szName[id])
		}
		else
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYER_X_MOVED_X_BY_X", g_szName[target], szTeam, g_szName[id])
		}
	}

	rg_join_team(target, TEAM_TERRORIST)

	return PLUGIN_HANDLED
}

public clcmd_spec(id)
{
	new arg1[MAX_NAME_LENGTH]
	read_argv(1, arg1, charsmax(arg1))

	clcmd_move_spec(id, arg1, charsmax(arg1))

	return PLUGIN_HANDLED
}

stock clcmd_move_spec(id, szMessage[], iLen, IsSay = -1)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	new target

	if(IsSay)
	{
		replace_all(szMessage, iLen, "/spec ", "")
		replace_all(szMessage, iLen, "^"", "")
	}

	target = cmd_target(id, szMessage, CMDTARGET_ALLOW_SELF)

	if(!target)
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYER_NOT_FOUND")
		return PLUGIN_HANDLED
	}

	static iPlayer, iPlayers[MAX_PLAYERS], iNum, szTeam[22]
	get_players(iPlayers, iNum, "ch")

	GetTeam(SPEC, szTeam, charsmax(szTeam))

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		if(id == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYER_X_MOVED_X_BY_YOU", g_szName[target], szTeam)
		}
		else if(target == iPlayer)
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_WERE_MOVED_X_BY_X", szTeam, g_szName[id])
		}
		else
		{
			client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYER_X_MOVED_X_BY_X", g_szName[target], szTeam, g_szName[id])
		}
	}

	rg_join_team(target, TEAM_SPECTATOR)
	

	return PLUGIN_HANDLED
}

public clcmd_start_demo(id)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	#if defined DEBUG
	client_print_color(0, 0, "clcmd_start_Demo() called")
	#endif

	if(!g_eBooleans[bIsMixOn])
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_NOT_STARTED_YET")
		return PLUGIN_HANDLED
	}

	new arg1[MAX_NAME_LENGTH], arg2[32], target
	read_argv(1, arg1, charsmax(arg1))

	if(g_eDemoSettings[iDemoType] == DEMO_CIN_NAME)
	{
		read_argv(2, arg2, charsmax(arg2))
	}

	#if defined DEBUG
	target = cmd_target(id, arg1, CMDTARGET_ALLOW_SELF)
	#else
	target = cmd_target(id, arg1)
	#endif

	if(!target)
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYER_NOT_FOUND")
		return PLUGIN_HANDLED
	}

	new len = strlen(arg2)
	if(g_eDemoSettings[iDemoType] == DEMO_CIN_NAME)
	{
		if(len < 2)
		{
			client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "DEMO_NAME_REQUIRED")
			return PLUGIN_HANDLED
		}
	}

	static iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		if(get_user_flags(iPlayer) & read_flags(g_ePluginSettings[szAdminFlags]))
		{
			if(iPlayer == id)
			{
				client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "DEMO_STARTED_BY_YOU_FOR_X", g_szName[target])
			}
			else
			{
				client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "DEMO_STARTED_BY_X_FOR_X", g_szName[id], g_szName[target])
			}
		}
	}

	client_print_color(target, target, "^4[GAMELAND] ^1Admin requested a POV demo. Press ^3F5^1 and choose ^3Start demo^1.")
	client_print_color(id, id, "^4%s ^1Client POV demo is local-only now. Player must press ^3F5^1.", g_ePluginSettings[szPrefix])

	return PLUGIN_HANDLED
}

public clcmd_stop_demo(id)
{
	if(!(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	#if defined DEBUG
	client_print_color(0, 0, "clcmd_stop_Demo() called")
	#endif

	if(!g_eBooleans[bIsMixOn])
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_NOT_STARTED_YET")
		return PLUGIN_HANDLED
	}

	new arg1[MAX_NAME_LENGTH], target
	read_argv(1, arg1, charsmax(arg1))

	#if defined DEBUG
	target = cmd_target(id, arg1, CMDTARGET_ALLOW_SELF)
	#else
	target = cmd_target(id, arg1)
	#endif

	if(!target)
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYER_NOT_FOUND")
		return PLUGIN_HANDLED
	}

	static iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")

	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]

		if(get_user_flags(iPlayer) & read_flags(g_ePluginSettings[szAdminFlags]))
		{
			if(iPlayer == id)
			{
				client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "DEMO_STOPPED_BY_YOU_FOR_X", g_szName[target])
			}
			else
			{
				client_print_color(iPlayer, iPlayer, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "DEMO_STOPPED_BY_X_FOR_X", g_szName[id], g_szName[target])
			}
		}
	}

	client_print_color(target, target, "^4[GAMELAND] ^1Admin requested demo stop. Press ^3F5^1 and choose ^3Stop demo^1.")
	client_print_color(id, id, "^4%s ^1Client POV demo is local-only now. Player must press ^3F5^1.", g_ePluginSettings[szPrefix])

	return PLUGIN_HANDLED
}


public clcmd_say_pause(id)
{
	if(!g_eBooleans[bIsMixOn])
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_NOT_STARTED_YET")
		return PLUGIN_HANDLED
	}

	new CsTeams:iTeam = cs_get_user_team(id)

	switch(iTeam)
	{
		case CS_TEAM_T:
		{
			if(!g_eTeamPause[TERO_PAUSE])
			{
				g_eTeamPause[TERO_PAUSE] = 1
				client_print_color(0, 0, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYER_X_REQUESTED_TIMEOUT", g_szName[id])
			}
			else
			{
				client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOUR_TEAM_ALREADY_TIMEOUT")
			}
		}
		case CS_TEAM_CT:
		{
			if(!g_eTeamPause[CT_PAUSE])
			{
				g_eTeamPause[CT_PAUSE] = 1
				client_print_color(0, 0, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "PLAYER_X_REQUESTED_TIMEOUT", g_szName[id])
			}
			else
			{
				client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOUR_TEAM_ALREADY_TIMEOUT")
			}
		}
	}

	return PLUGIN_CONTINUE
}


ResetScore()
{
	g_bShootingOpening = false
	if(g_eBooleans[bIsShooting])
	{
		for(new id = 1; id <= MAX_PLAYERS; id++)
			if(is_user_connected(id))
				cs_reset_user_model(id)
	}
	g_iScore[TERO_SCORE] = 0
	g_iScore[CT_SCORE] = 0
	g_iOvertimeScore[CT_OVER_SCORE] = 0
	g_iOvertimeScore[TERO_OVER_SCORE] = 0
	g_eTeamPause[CT_PAUSE] = 0
	g_eTeamPause[TERO_PAUSE] = 0
	g_iRoundNum = 0
	for(new i; i < MAX_PLAYERS; i++ )
	{
		g_eBooleans[bCanChat][i] = true
	}
	g_eBooleans[bIsMixOn] = false

	HLTV_StopRecording()
	Client_StopRecordingAll()
	g_eBooleans[bOvertime] = false  // Fix #5: removed duplicate reset that was on next line
	g_eBooleans[bIsShooting] = false
	g_eBooleans[bTeamSwap] = false
	g_eBooleans[bIsWarm] = false
	server_cmd("mp_ignore_round_win_conditions 0")
	g_eOvertime[FirstOvertime] = false
	g_eOvertime[SecondOvertime] = false
	g_eBooleans[bIsKnife] = false

	#if defined FASTCUP_MODE
	g_bVoted = false
	arrayset(g_iAnswer, 0, sizeof(g_iAnswer))
	#endif
	server_cmd("sv_restart 1")
}

stock StartConfig()
{
	GetConfigsDir()
	
	server_cmd("exec %s/%s", g_szConfigsDir, g_ePluginSettings[szStartCfg])
}

stock StopConfig()
{
	GetConfigsDir()

	server_cmd("exec %s/%s", g_szConfigsDir, g_ePluginSettings[szStopCfg])
}

stock OvertimeConfig()
{
	GetConfigsDir()

	server_cmd("exec %s/%s", g_szConfigsDir, g_ePluginSettings[szOvertimeCfg])
}

stock GetConfigsDir()
{
	if(g_szConfigsDir[0] == EOS)
	{
		get_configsdir(g_szConfigsDir, charsmax(g_szConfigsDir))
	}
}

stock bool:is_bot(id)
{
	if(is_user_bot(id) || is_user_hltv(id))
	{
		return true
	}
	return false
}

public task_stop_mix()
{
	g_iDuration = 0

	remove_task(TASK_COUNT_DURATION)

	ResetScore()
}

stock bool:IsHalf()
{
	if(g_eBooleans[bIsShooting])
	{
		return false
	}

	if(!g_eBooleans[bTeamSwap] && g_iRoundNum == 15 && !g_eBooleans[bOvertime])
	{
		return true
	}
	return false
}

stock bool:IsLastRound()
{
	if(g_eBooleans[bIsShooting])
	{
		return g_iScore[CT_SCORE] >= SHOOTING_END_SCORE || g_iScore[TERO_SCORE] >= SHOOTING_END_SCORE
	}

	if(g_eBooleans[bTeamSwap] && g_iScore[CT_SCORE] == g_ePluginSettings[iMixEndRound] && !g_eBooleans[bOvertime] || g_eBooleans[bTeamSwap] && g_iScore[TERO_SCORE] == g_ePluginSettings[iMixEndRound] && !g_eBooleans[bOvertime])
	{
		return true
	}
	return false
}

stock bool:IsShootingMap()
{
	new mapName[32]
	get_mapname(mapName, charsmax(mapName))

	// Standard fast-shooting map families. Keep de_/cs_ maps on the normal
	// competitive mix path; everything here uses randomized teams and a
	// dedicated weapon loadout.
	return containi(mapName, "aim_") == 0
		|| containi(mapName, "awp_") == 0
		|| containi(mapName, "sk_") == 0
		|| containi(mapName, "fy_") == 0
		|| containi(mapName, "dm_") == 0
		|| containi(mapName, "ka_") == 0
		|| containi(mapName, "hs_") == 0
}

stock RandomizeShootingTeams()
{
	new connected[MAX_PLAYERS], players[MAX_PLAYERS], count, playerCount
	get_players(connected, count, "ch")

	for(new i; i < count; i++)
	{
		new id = connected[i]
		new CsTeams:team = cs_get_user_team(id)
		if(team == CS_TEAM_T || team == CS_TEAM_CT)
		{
			players[playerCount++] = id
		}
	}

	for(new i = playerCount - 1; i > 0; i--)
	{
		new j = random_num(0, i)
		new temp = players[i]
		players[i] = players[j]
		players[j] = temp
	}

	new half = playerCount / 2 + (playerCount % 2 ? random_num(0, 1) : 0)
	for(new i; i < playerCount; i++)
	{
		new id = players[i]
		if(!IsPlayer(id))
		{
			continue
		}

		cs_set_user_team(id, i < half ? CS_TEAM_CT : CS_TEAM_T, i < half ? CS_CT_URBAN : CS_T_TERROR)
		cs_set_user_model(id, i < half ? "urban" : "terror")
	}
}

stock bool:IsPreLastRound()
{
	if(g_eBooleans[bTeamSwap] && g_iScore[CT_SCORE] == g_ePluginSettings[iOvertimeScore] && !g_eBooleans[bOvertime] || g_eBooleans[bTeamSwap] && g_iScore[TERO_SCORE] == g_ePluginSettings[iOvertimeScore] && !g_eBooleans[bOvertime])
	{
		return true
	}
	return false
}

stock bool:CanOvertime()
{
	if(IsPreLastRound() && g_iScore[CT_SCORE] == g_iScore[TERO_SCORE])
	{
		return true
	}
	return false
}

stock bool:OvertimeFinished()
{
	#if !defined OVERTIME_ONE_ROUND
	if(g_eBooleans[bOvertime] && g_eOvertime[SecondOvertime])
	{
		if(CheckOverScore() == g_ePluginSettings[iRoundOvertime] * 2)
		{
			return true
		}
		return false
	}
	#else
	if(g_eBooleans[bOvertime])
	{
		if(CheckOverScore())
		{
			return true
		}
		return false
	}
	#endif
	return false
}

stock CheckOvertimePhase()
{
	if((CheckOverScore() == g_ePluginSettings[iRoundOvertime]) && g_eOvertime[FirstOvertime])
	{
		if(g_eBooleans[bOvertime] && !OvertimeFinished() && !g_eBooleans[bTeamSwap] && !g_eOvertime[SecondOvertime])
		{
			g_eOvertime[FirstOvertime] = true
			g_eOvertime[SecondOvertime] = true

			set_pcvar_num(g_cFreezeTime, 15)
			set_task(0.1, "task_swap_score")
			set_task(0.2, "task_delayed_swap")
			set_task(2.5, "task_show_halftime")
			set_task(12.0, "task_halftime_restart1")
			set_task(17.0, "task_halftime_restart2")
			set_task(22.0, "task_overtime_halftime_live")
		}
	}

	#if defined DEBUG
	client_print_color(0, 0, "CheckOvertimePhase() called")
	#endif
}

stock CheckOverScore()
{
	new iResult
	iResult = g_iOvertimeScore[CT_OVER_SCORE] + g_iOvertimeScore[TERO_OVER_SCORE]

	return iResult
}

stock LastRoundUntilWin(output[], len)
{
	if(IsPreLastRound())
	{
		switch(CheckScore())
		{
			case CT_LAST:
			{
				formatex(output, len, "CTs")
			}
			case T_LAST:
			{
				formatex(output, len, "TERORISTs")
			}
		}
	}
}

stock CheckWinner()
{
	new iResult

	if(!g_eBooleans[bOvertime])
	{
		if(g_iScore[CT_SCORE] == g_ePluginSettings[iMixEndRound])
		{
			iResult = CT_SCORE

			#if defined DEBUG
			server_print("iResult case CT_SCORE")
			#endif
		}
		else if(g_iScore[TERO_SCORE] == g_ePluginSettings[iMixEndRound])
		{
			iResult = TERO_SCORE

			#if defined DEBUG
			server_print("iResult case TERO_SCORE")
			#endif
		}
	}
	else 
	{
		if(CheckOverScore() == (g_ePluginSettings[iRoundOvertime] * 2))
		{
			if(g_iOvertimeScore[CT_OVER_SCORE] > g_iOvertimeScore[TERO_OVER_SCORE])
			{
				iResult = CT_OVER_SCORE

				#if defined DEBUG
				server_print("iResult case CT_OVER_SCORE")
				#endif
			}
			else if(g_iOvertimeScore[TERO_OVER_SCORE] > g_iOvertimeScore[CT_OVER_SCORE])
			{
				iResult = TERO_OVER_SCORE

				#if defined DEBUG
				server_print("iResult case TERO_OVER_sCORE")
				#endif
			}
			else if(g_iOvertimeScore[TERO_OVER_SCORE] == g_iOvertimeScore[CT_OVER_SCORE])
			{
				iResult = DRAW

				#if defined DEBUG
				server_print("iResult case DRAW")
				#endif
			}
		}
	}

	#if defined DEBUG
	server_print("iResult: %i", iResult)
	#endif

	return iResult
}

stock WinnerTeam(output[], len)
{
	if(IsLastRound() || OvertimeFinished())
	{
		switch(CheckWinner())
		{
			case CT_SCORE, CT_OVER_SCORE:
			{
				formatex(output, len, "%L", LANG_SERVER, "CT_TEAM")
			}
			case TERO_SCORE, TERO_OVER_SCORE:
			{
				formatex(output, len, "%L", LANG_SERVER, "TERO_TEAM")
			}
			case DRAW:
			{
				formatex(output, len, "%L", LANG_SERVER, "DRAW")
			}
		}
	}
}

stock GiveTeamReward(iPlayer, iPoints)
{
	if(IsLastRound() || OvertimeFinished())
	{
		client_print_color(iPlayer, iPlayer, "^4%s ^1%L", g_ePluginSettings[szPrefix], LANG_SERVER, "MIX_YOUR_TEAM_WON", g_ePointSystem[PointsTeamWin])
	
		g_iPoints[iPlayer] += iPoints
	}
}

stock CheckScore()
{
	new iResult
	if(!g_eBooleans[bOvertime])
	{
		if(g_iScore[CT_SCORE] == (g_ePluginSettings[iMixEndRound] - 1 ))
		{
			iResult = CT_LAST
		}
		
		if(g_iScore[TERO_SCORE] == (g_ePluginSettings[iMixEndRound] - 1))
		{
			iResult = T_LAST
		}
	}

	return iResult
}

stock GetTeam(iNum, output[], len)
{
	switch(iNum)
	{
		case SPEC:
		{
			formatex(output, len, "%L", LANG_SERVER, "SPEC_TEAM")
		}
		case TERO:
		{
			formatex(output, len, "%L", LANG_SERVER, "TERO_TEAM")
		}
		case CT:
		{
			formatex(output, len, "%L", LANG_SERVER, "CT_TEAM")
		}
	}
}

stock _MenuExit(menu)
{
	menu_destroy(menu)
	return PLUGIN_HANDLED
}

stock _MenuDisplay(id, menu)
{
	menu_display(id, menu)
	set_member(id, m_iMenu, Menu_OFF)
	return PLUGIN_HANDLED
}

stock mysql_escape_string(const source[], dest[], length)
{
	SQL_QuoteString(Empty_Handle, dest, length, source)
}

stock SetGameDesc(MatchState:matchState)
{
	new szTemp[30]
	switch(matchState)
	{
		case MATCHSTATE_WARM:
		{
			formatex(szTemp, charsmax(szTemp), "%L", LANG_SERVER, "MATCHSTATE_WARM")
		}
		case MATCHSTATE_IN_MATCH:
		{
			formatex(szTemp, charsmax(szTemp), "%L", LANG_SERVER, "MATCHSTATE_IN_MATCH", g_iScore[CT_SCORE], g_iScore[TERO_SCORE])
		}
		case MATCHSTATE_KNIFE_ROUND:
		{
			formatex(szTemp, charsmax(szTemp), "%L", LANG_SERVER, "MATCHSTATE_KNIFE_ROUND")
		}
		case MATCHSTATE_OVERTIME:
		{
			formatex(szTemp, charsmax(szTemp), "%L", LANG_SERVER, "MATCHSTATE_OVERTIME", g_iOvertimeScore[CT_OVER_SCORE], g_iOvertimeScore[TERO_OVER_SCORE])
		}
	}

	set_member_game(m_GameDesc, szTemp)
}

public native_is_half(iPluginID, iParamNum)
{
	return IsHalf()
}

public native_is_last_round(iPluginID, iParamNum)
{
	return IsLastRound()
}

public native_is_prelast_round(iPluginID, iParamNum)
{
	return IsPreLastRound()
}

public native_can_overtime(iPluginID, iParamNum)
{
	return CanOvertime()
}

public native_is_started(iPluginID, iParamNum)
{
	return g_eBooleans[bIsMixOn]
}

public native_is_warm(iPluginID, iParamNum)
{
	return g_eBooleans[bIsWarm]
}	

public native_get_prefix(iPluginID, iParamNum)
{
	set_string(1, g_ePluginSettings[szPrefix], get_param(2))
}

public native_get_username(iPluginID, iParamNum)
{
	if (iParamNum != 3)
	{
		log_error(AMX_ERR_NATIVE, "%s Invalid param num ! Valid: (PlayerID, Name[], Len)", g_ePluginSettings[szPrefix])
		return NATIVE_ERROR
	}
	new id = get_param(1)

	if(!is_user_connected(id))
	{
		log_error(AMX_ERR_NATIVE, "%s Player is not connected (%d)", g_ePluginSettings[szPrefix], id)
		return NATIVE_ERROR
	}

	set_string(2, g_szName[id], get_param(3))

	return 1
}


public native_has_points_sys(iPluginID, iParamNum)
{
	return false
}

public task_start_warm()
{
	clcmd_warm(0)
}

public task_show_live()
{
	fnScreenFade(0, 5, 5, {0, 255, 0}, 75, 0x0000)
	set_dhudmessage(0, 255, 0, -1.0, 0.3, 2, 0.1, 5.0, 0.1, 5.0)
	show_dhudmessage(0, "=== LIVE LIVE LIVE ===")
}

public task_show_halftime()
{
	fnScreenFade(0, 5, 5, {0, 150, 255}, 75, 0x0000)
	set_dhudmessage(0, 150, 255, -1.0, 0.3, 2, 0.1, 5.0, 0.1, 5.0)
	show_dhudmessage(0, "=== HALF TIME ===")
}

public task_reapply_warm()
{
	server_cmd("mp_freezetime 0")
	server_cmd("mp_buytime 99999")
	server_cmd("mp_startmoney 16000")
	new iPlayer, iPlayers[MAX_PLAYERS], iNum
	get_players(iPlayers, iNum, "ch")
	for(new i; i < iNum; i++)
	{
		iPlayer = iPlayers[i]
		if(is_user_connected(iPlayer))
			rg_add_account(iPlayer, 16000, AS_SET)
	}
}

stock fnScreenFade(id, Timer, FadeTime, Colors[3], Alpha, Type)
{
	if(id == 0)
	{
		message_begin(MSG_BROADCAST, g_iMsgScreenFade)
	}
	else
	{
		if(!is_user_connected(id)) return
		message_begin(MSG_ONE_UNRELIABLE, g_iMsgScreenFade, _, id)
	}
	write_short((1<<12) * Timer)
	write_short((1<<12) * FadeTime)
	write_short(Type)
	write_byte(Colors[0])
	write_byte(Colors[1])
	write_byte(Colors[2])
	write_byte(Alpha)
	message_end()
}

public task_overtime_live()
{
	server_cmd("sv_restart 1")
	set_pcvar_num(g_cFreezeTime, 12)
	set_task(2.5, "task_show_overtime_start")
}

public task_show_overtime_start()
{
	fnScreenFade(0, 5, 5, {255, 100, 0}, 75, 0x0000)
	set_dhudmessage(255, 100, 0, -1.0, 0.3, 2, 0.1, 5.0, 0.1, 5.0)
	
	new szMsg[128]
	formatex(szMsg, charsmax(szMsg), "=== OVERTIME STARTED ===^nWINNER GETS %d ROUNDS TOTAL", g_ePluginSettings[iRoundOvertime] + 1)
	show_dhudmessage(0, szMsg)
}

public task_overtime_halftime_live()
{
	server_cmd("sv_restart 1")
	set_pcvar_num(g_cFreezeTime, 12)
	set_task(2.5, "task_show_halftime")
}

public clcmd_hs1(id)
{
	if(id && !(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	HLTV_StartRecording("GL_Mix")
	client_print_color(id ? id : 0, print_team_default, "^4[GAMELAND] ^1HLTV recording started. Client POV recording is local-only; players use ^3F5^1.")
	return PLUGIN_HANDLED
}

public clcmd_hs0(id)
{
	if(id && !(get_user_flags(id) & read_flags(g_ePluginSettings[szAdminAccess])))
	{
		client_print_color(id, id, "^4%s %L", g_ePluginSettings[szPrefix], LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
		return PLUGIN_HANDLED
	}

	HLTV_StopRecording()
	Client_StopRecordingAll()
	return PLUGIN_HANDLED
}
