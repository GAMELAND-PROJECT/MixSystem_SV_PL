/*
 * GAMELAND Clan War Mode (10 Slots Dedicated Plugin)
 * Independent Clan War System - ReAPI Modernized Edition
 * Author: GAMELAND Team
 * Contact: l1gameland@gmail.com
 *
 * Features:
 * - 10-Slot Dedicated Clan War Architecture
 * - Pure ReAPI, zero MySQL / points / rank overhead
 * - Independent configuration: ClanWarSettings.ini
 * - Independent language dictionary: clanwar_system.txt
 * - Clan War Hostname Tags: [CW WarmUp], [CW Knife], [CW Live]
 * - Instant single-vote knife winner side selection
 * - Crash-proof menus & live updates
 */

#include <amxmodx>
#include <amxmisc>
#include <reapi>
#include <mix_system>

#define PLUGIN_NAME        "GAMELAND Clan War Mode"
#define PLUGIN_VERSION     "2.5.0-GL"
#define PLUGIN_AUTHOR      "GAMELAND"

// -----------------------------------------------------------------------------
// Constants & Enums
// -----------------------------------------------------------------------------
enum MatchState
{
    STATE_WARMUP = 0,
    STATE_CAPTAIN_COUNTDOWN,
    STATE_CAPTAIN_VOTE,
    STATE_PICKING,
    STATE_KNIFE,
    STATE_FIRST_HALF,
    STATE_SECOND_HALF,
    STATE_OVERTIME_FIRST_HALF,
    STATE_OVERTIME_SECOND_HALF
}

enum TeamScore
{
    CT_SCORE = 0,
    TERO_SCORE
}

#define TASK_HALFTIME_LIVE       3101
#define TASK_KNIFE_COUNTDOWN     3102
#define TASK_LIVE_COUNTDOWN      3103
#define TASK_HUD_STATUS          3104
#define TASK_TIMEOUT_EXPIRE      3105
#define TASK_END_ROUND           3106
#define TASK_MATCH_END           3107
#define TASK_KNIFE_VOTE          3108
#define TASK_MIX_VOTE            3109
#define TASK_LIVE_PULSE          3112
#define TASK_VICTORY_PULSE       3110
#define TASK_SHOW_LEADERBOARD    3111
#define TASK_CW_COUNTDOWN        3120
#define TASK_CW_CAPTAIN_VOTE     3121
#define TASK_CW_PICK_TIMER       3122

#define MIX_VOTE_MENU_ID         "GAMELAND_CW_Vote"
#define KNIFE_SIDE_MENU_ID       "GAMELAND_CW_Knife_Side"
#define CW_ADMIN_MENU_ID         "GAMELAND_CW_Admin_Menu" 

#define VOTE_STAY   1
#define VOTE_SWITCH 2

// -----------------------------------------------------------------------------
// Admin Manager Data Structure
// -----------------------------------------------------------------------------
enum AdminAddSession
{
    SessionTargetId,
    SessionAuth[64],
    SessionName[32],
    SessionFlags[36],
    SessionAccountFlags[8],
    SessionPassword[32]
}

new g_eAdminSession[MAX_PLAYERS + 1][AdminAddSession]

// -----------------------------------------------------------------------------
// Global Variables
// -----------------------------------------------------------------------------
new MatchState:g_iMatchState = STATE_WARMUP

new g_iScore[TeamScore]
new g_iFirstHalfScore[TeamScore]
new g_iOvertimeScore[TeamScore]
new g_iSavedFrags[MAX_PLAYERS + 1]
new g_iSavedDeaths[MAX_PLAYERS + 1]
new bool:g_bHalftimePendingSync = false

// Competitive Match Statistics
new g_iMatchKills[MAX_PLAYERS + 1]
new g_iMatchDeaths[MAX_PLAYERS + 1]
new g_iMatchHS[MAX_PLAYERS + 1]
new g_iMatchKnifeKills[MAX_PLAYERS + 1]
new g_iMatchPlants[MAX_PLAYERS + 1]
new g_iMatchDefuses[MAX_PLAYERS + 1]

// Victory Celebration State
new TeamName:g_iVictoryWinnerTeam = TEAM_UNASSIGNED
new g_iVictoryPulseCount = 0
new g_iMsgScreenFade = 0

new bool:g_bRoundScored = false
new bool:g_bChatMuted = false
new bool:g_bPaused = false
new g_iPauseTimer = 0
new bool:g_bTeamTimeoutUsed[TeamScore]

// Settings from MixSettings.ini
new g_szChatPrefix[32] = "[GAMELAND CW]"
new g_iOvertimeRounds = 3
new g_iOvertimeTriggerScore = 15
new g_iMixEndRound = 16
new g_szAdminFlags[16] = "c"
new g_szAdminAccess[16] = "c"
new g_iFreezeTimeSwap = 7
new bool:g_bAutoOvertime = true
new g_szStartConfig[64] = "start.cfg"
new g_szStopConfig[64] = "stop.cfg"
new g_iKnifeDelay = 10
new g_iWarmMoney = 16000
new bool:g_bForceWarmup = true
new g_iPauseDuration = 60

// Player data

// -----------------------------------------------------------------------------
// Clan War Auto-Start, Captain Election & Turn Draft Variables
// -----------------------------------------------------------------------------
new g_iCwReadyTimer = 30
new g_iPlayerCaptVotes[MAX_PLAYERS + 1]
new g_iVotedForCapt[MAX_PLAYERS + 1]
new g_iCaptVoteTimer = 20
new g_iEligibleVoters[MAX_PLAYERS + 1]
new g_iEligibleVoterCount = 0

#define TASK_BIND_F3              3140

new g_iCaptainCT = 0
new g_iCaptainTR = 0
new g_iCurrentDraftTurn = 1 // 1: CT, 2: TR
new g_iPickTimer = 15
new g_iDraftRound = 1
new bool:g_bAdminForceStarted = false
new bool:g_bFastTestMode = false

#define TASK_POST_MATCH_MAP_VOTE  3130

new g_iPlayerKickVotes[MAX_PLAYERS + 1]
new g_iVotedKickTarget[MAX_PLAYERS + 1]
new g_iMapVoteChoice[MAX_PLAYERS + 1]
new g_iMapVoteCount[8]
new bool:g_bVotedRePick[MAX_PLAYERS + 1]
new bool:g_bVotedRestart[MAX_PLAYERS + 1]

new const g_szStandardMaps[][] = {
    "de_dust2",
    "de_inferno",
    "de_nuke",
    "de_train",
    "de_aztec",
    "de_mirage"
}

// Post-Match Map Vote State
new g_szPostMatchMaps[8][32]
new g_iPostMatchMapCount = 0
new g_iPostMatchVoteCount[8]
new g_iPlayerPostMatchVote[MAX_PLAYERS + 1]
new g_iPostMatchVoteTimer = 15

stock ResetPlayerF3Votes(id)
{
    if(1 <= id <= MAX_PLAYERS)
    {
        new kickTarget = g_iVotedKickTarget[id]
        if(1 <= kickTarget <= MAX_PLAYERS && g_iPlayerKickVotes[kickTarget] > 0)
        {
            g_iPlayerKickVotes[kickTarget]--
        }
        g_iVotedKickTarget[id] = 0

        new mapIdx = g_iMapVoteChoice[id]
        if(0 <= mapIdx < sizeof(g_szStandardMaps) && g_iMapVoteCount[mapIdx] > 0)
        {
            g_iMapVoteCount[mapIdx]--
        }
        g_iMapVoteChoice[id] = -1

        g_bVotedRePick[id] = false
        g_bVotedRestart[id] = false
        g_iPlayerPostMatchVote[id] = -1
    }
}

stock ResetAllF3Votes()
{
    for(new i = 1; i <= MAX_PLAYERS; i++)
    {
        g_iPlayerKickVotes[i] = 0
        g_iVotedKickTarget[i] = 0
        g_iMapVoteChoice[i] = -1
        g_bVotedRePick[i] = false
        g_bVotedRestart[i] = false
        g_iPlayerPostMatchVote[i] = -1
    }
    for(new m = 0; m < 8; m++)
    {
        g_iMapVoteCount[m] = 0
        g_iPostMatchVoteCount[m] = 0
    }
}

stock bool:IsBetterCaptainCandidate(candA, votesA, candB, votesB)
{
    if(votesA != votesB)
    {
        return votesA > votesB;
    }

    // Tie-breaker 1: Frags / Kills in server
    new fragsA = get_user_frags(candA);
    new fragsB = get_user_frags(candB);
    if(fragsA != fragsB)
    {
        return fragsA > fragsB;
    }

    // Tie-breaker 2: Deaths (fewer is better)
    new deathsA = get_member(candA, m_iDeaths);
    new deathsB = get_member(candB, m_iDeaths);
    if(deathsA != deathsB)
    {
        return deathsA < deathsB;
    }

    // Tie-breaker 3: Deterministic connection index
    return candA < candB;
}
new g_szUserName[MAX_PLAYERS + 1][MAX_NAME_LENGTH]

// /mix Global Vote (Knife vs Direct Live)
new g_iMixVoteKnife = 0
new g_iMixVoteLive = 0
new g_iPlayerMixVote[MAX_PLAYERS + 1]
new bool:g_bPlayerMixLocked[MAX_PLAYERS + 1]
new g_iPlayerMixSwitches[MAX_PLAYERS + 1]
new Float:g_flLastMixVoteTime[MAX_PLAYERS + 1]
new g_iMixVoteTimer = 0

// Knife round side selection vote (TR [Red] vs CT [Blue] - Single-Vote Instant Choice)
new TeamName:g_iKnifeWinnerTeam = TEAM_UNASSIGNED
new g_iVoteTR = 0
new g_iVoteCT = 0
new g_iPlayerKnifeVote[MAX_PLAYERS + 1]
new bool:g_bPlayerKnifeVoted[MAX_PLAYERS + 1]
new g_iKnifeVoteTimer = 0

// CS2-style round kill streak / cards
new g_iRoundKills[MAX_PLAYERS + 1]

// Warmup & Revive Team-Specific Spawns (CT & TR completely separated)
new Float:g_vecSpawnsCT[64][3]
new Float:g_vecAnglesCT[64][3]
new g_iTotalSpawnsCT = 0

new Float:g_vecSpawnsTR[64][3]
new Float:g_vecAnglesTR[64][3]
new g_iTotalSpawnsTR = 0

// Infinite Revive Mode (/rev1 & /rev0)
new bool:g_bReviveMode = false

// Dynamic Hostname & Captain Pick Mode Management
new g_szBaseHostname[64] = "GAMELAND"
new bool:g_bPickMode = false
new g_iLivePulseCount = 0

// Countdown
new g_iMatchStartTime = 0

// HUD Sync
new g_iHudSync

// Forwards
new g_hFwdPlayerKilled
new g_hFwdGameBeginPre
new g_hFwdGameBeginPost
new g_hFwdNewRound
new g_hFwdGameStopped
new g_hFwdGameOver
new g_hFwdMatchWinner
new g_hFwdUserSave
new g_hFwdDbConnected
new g_hFwdSysLeaver
new g_iRet

// Command dynamic arrays
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
new Array:g_aRestartCmds
new Array:g_aScoreCmds
new Array:g_aMoveCTCmds
new Array:g_aMoveTCmds
new Array:g_aMoveSpecCmds
new Array:g_aPauseCmds

// -----------------------------------------------------------------------------
// Plugin Init & Configuration
// -----------------------------------------------------------------------------
public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR)
    register_cvar("gameland_clanwar_version", PLUGIN_VERSION, FCVAR_SERVER | FCVAR_SPONLY)
    register_cvar("gameland_cw_version", PLUGIN_VERSION, FCVAR_SERVER | FCVAR_SPONLY)
    register_cvar("cw_version", PLUGIN_VERSION, FCVAR_SERVER | FCVAR_SPONLY)
    register_concmd("gameland_cw_version", "Cmd_Version")
    register_concmd("cw_version", "Cmd_Version")
    register_clcmd("say /ver", "Cmd_SayVersion")
    register_clcmd("say_team /ver", "Cmd_SayVersion")
    register_clcmd("say /version", "Cmd_SayVersion")
    register_clcmd("say_team /version", "Cmd_SayVersion")

    // Built-in Teammate Semiclip to permanently prevent spawn overlapping / stuck
    if(get_cvar_pointer("mp_semiclip"))
        set_cvar_num("mp_semiclip", 1)
    if(get_cvar_pointer("mp_semiclip_actions"))
        set_cvar_num("mp_semiclip_actions", 3)

    register_dictionary("clanwar_system.txt")

    // ReAPI HookChains
    RegisterHookChain(RG_CBasePlayer_Spawn, "RG_CBasePlayer_Spawn_Post", .post = true)
    RegisterHookChain(RG_CBasePlayer_Killed, "RG_CBasePlayer_Killed_Post", .post = true)
    RegisterHookChain(RG_RoundEnd, "RG_RoundEnd_Pre", .post = false)
    RegisterHookChain(RG_RoundEnd, "RG_RoundEnd_Post", .post = true)
    RegisterHookChain(RG_CSGameRules_CheckWinConditions, "RG_CSGameRules_CheckWinConditions_Pre", .post = false)
    RegisterHookChain(RG_CSGameRules_RestartRound, "RG_CSGameRules_RestartRound_Post", .post = true)
    RegisterHookChain(RG_PlantBomb, "RG_PlantBomb_Post", .post = true)
    RegisterHookChain(RG_CGrenade_DefuseBombEnd, "RG_CGrenade_DefuseBombEnd_Post", .post = true)
    RegisterHookChain(RG_CBasePlayer_MakeBomber, "RG_CBasePlayer_MakeBomber_Pre", .post = false)
    RegisterHookChain(RG_CBasePlayer_Observer_IsValidTarget, "RG_Observer_IsValidTarget_Pre", .post = false)
    RegisterHookChain(RG_HandleMenu_ChooseTeam, "RG_HandleMenu_ChooseTeam_Pre", .post = false)

    register_clcmd("jointeam", "Cmd_BlockTeamChange")
    register_clcmd("chooseteam", "Cmd_BlockTeamChange")
    register_clcmd("joinclass", "Cmd_BlockTeamChange")

    ApplySpectatorCameraSettings()

    g_iMsgScreenFade = get_user_msgid("ScreenFade")

    // Dynamic arrays for commands
    InitCommandArrays()

    // Load configuration
    LoadConfiguration()

    // Create Forwards
    g_hFwdPlayerKilled = CreateMultiForward("mix_player_killed", ET_IGNORE, FP_CELL, FP_CELL, FP_CELL, FP_STRING, FP_STRING)
    g_hFwdGameBeginPre = CreateMultiForward("mix_game_begin_pre", ET_IGNORE)
    g_hFwdGameBeginPost = CreateMultiForward("mix_game_begin_post", ET_IGNORE, FP_CELL, FP_CELL, FP_STRING, FP_STRING, FP_CELL)
    g_hFwdNewRound = CreateMultiForward("mix_game_new_round", ET_IGNORE, FP_CELL, FP_CELL, FP_CELL)
    g_hFwdGameStopped = CreateMultiForward("mix_game_stopped", ET_IGNORE, FP_CELL, FP_CELL, FP_CELL)
    g_hFwdGameOver = CreateMultiForward("mix_game_over", ET_IGNORE, FP_CELL, FP_CELL, FP_CELL, FP_CELL)
    g_hFwdMatchWinner = CreateMultiForward("mix_match_winner", ET_IGNORE, FP_CELL)
    g_hFwdUserSave = CreateMultiForward("mix_user_save", ET_IGNORE, FP_CELL)
    g_hFwdDbConnected = CreateMultiForward("mix_database_connected", ET_IGNORE, FP_CELL, FP_CELL)
    g_hFwdSysLeaver = CreateMultiForward("mix_sys_leaver", ET_IGNORE, FP_STRING)

    // Execute initial dummy DB connected forward for third-party listeners
    ExecuteForward(g_hFwdDbConnected, g_iRet, 0, 0)

    g_iHudSync = CreateHudSyncObj()

    // Initialize Server Hostname State
    InitBaseHostname()
    UpdateServerHostname()
    set_task(0.5, "Task_InitHostname")

    // Register HUD task
    set_task(1.0, "Task_HudDisplay", TASK_HUD_STATUS, .flags = "b")

    // Mass Instant Revive All Dead Players Command (/rev)
    register_clcmd("say /rev", "Cmd_ReviveAll")
    register_clcmd("say_team /rev", "Cmd_ReviveAll")
    register_clcmd("rev", "Cmd_ReviveAll")
    register_concmd("amx_rev", "Cmd_ReviveAll", ADMIN_CFG, "- Revive all dead players immediately")

    // Spectator & Captain Pick Mode (/spec)
    register_clcmd("say /spec", "Cmd_SpecAll")
    register_clcmd("say_team /spec", "Cmd_SpecAll")
    register_clcmd("say /specall", "Cmd_SpecAll")
    register_clcmd("say_team /specall", "Cmd_SpecAll")
    register_clcmd("spec", "Cmd_SpecAll")
    register_clcmd("specall", "Cmd_SpecAll")
    register_concmd("amx_specall", "Cmd_SpecAll", ADMIN_CFG, "- Move all players to spectator (Captain Pick)")

    // Infinite Revive Mode Commands (/rev1, /rev0, /dm1)
    register_clcmd("say /rev1", "Cmd_ReviveOn")
    register_clcmd("say_team /rev1", "Cmd_ReviveOn")
    register_clcmd("say /rev0", "Cmd_ReviveOff")
    register_clcmd("say_team /rev0", "Cmd_ReviveOff")
    register_clcmd("say /dm1", "Cmd_LegacyDm")
    register_clcmd("say_team /dm1", "Cmd_LegacyDm")
    register_concmd("amx_rev1", "Cmd_ReviveOn", ADMIN_CFG, "- Enable Infinite Revive mode")
    register_concmd("amx_rev0", "Cmd_ReviveOff", ADMIN_CFG, "- Disable Infinite Revive mode")

    // Set visible maxplayers strictly to 10
    set_cvar_num("sv_visiblemaxplayers", 10)

    // Player Action Menu [Key N & F3] (/n, /f3, /menu, nightvision)
    register_clcmd("nightvision", "Cmd_F3Menu")
    register_clcmd("client_buy_nightvision", "Cmd_F3Menu")
    register_clcmd("cw_menu", "Cmd_F3Menu")
    register_clcmd("say /n", "Cmd_F3Menu")
    register_clcmd("say_team /n", "Cmd_F3Menu")
    register_clcmd("say /f3", "Cmd_F3Menu")
    register_clcmd("say_team /f3", "Cmd_F3Menu")
    register_clcmd("say /menu", "Cmd_F3Menu")
    register_clcmd("say_team /menu", "Cmd_F3Menu")
    register_clcmd("say /cwmenu", "Cmd_F3Menu")
    register_clcmd("say_team /cwmenu", "Cmd_F3Menu")
    register_clcmd("n", "Cmd_F3Menu")
    register_clcmd("f3", "Cmd_F3Menu")
    register_clcmd("menu", "Cmd_F3Menu")

    // Clan War Admin Control Commands (/cw, /clanwar)
    register_clcmd("say /cw", "Cmd_ClanWarAdmin")
    register_clcmd("say_team /cw", "Cmd_ClanWarAdmin")
    register_clcmd("say /clanwar", "Cmd_ClanWarAdmin")
    register_clcmd("say_team /clanwar", "Cmd_ClanWarAdmin")
    register_clcmd("cw", "Cmd_ClanWarAdmin")
    register_clcmd("clanwar", "Cmd_ClanWarAdmin")
    register_concmd("amx_cw", "Cmd_ClanWarAdmin", ADMIN_CFG, "- Open Clan War Admin Control Menu")
    register_clcmd("say /cwcomenzi", "Cmd_ShowCommands")
    register_clcmd("say_team /cwcomenzi", "Cmd_ShowCommands")
    register_clcmd("say /comenzi", "Cmd_ShowCommands")
    register_clcmd("say_team /comenzi", "Cmd_ShowCommands")
    register_clcmd("say /live", "Cmd_DirectLive")
    register_clcmd("say_team /live", "Cmd_DirectLive")
    register_clcmd("say /lv", "Cmd_DirectLive")
    register_clcmd("say_team /lv", "Cmd_DirectLive")
    register_clcmd("live", "Cmd_DirectLive")
    register_clcmd("lv", "Cmd_DirectLive")

    // Voice & Spectator Commands (/t1, /t2, /t3, /s1, /s0)
    register_clcmd("say /t1", "Cmd_Alltalk1")
    register_clcmd("say_team /t1", "Cmd_Alltalk1")
    register_clcmd("t1", "Cmd_Alltalk1")
    register_clcmd("say /t2", "Cmd_Alltalk2")
    register_clcmd("say_team /t2", "Cmd_Alltalk2")
    register_clcmd("t2", "Cmd_Alltalk2")
    register_clcmd("say /t3", "Cmd_Alltalk3")
    register_clcmd("say_team /t3", "Cmd_Alltalk3")
    register_clcmd("t3", "Cmd_Alltalk3")
    register_clcmd("say /s1", "Cmd_Spec1")
    register_clcmd("say_team /s1", "Cmd_Spec1")
    register_clcmd("s1", "Cmd_Spec1")
    register_clcmd("say /s0", "Cmd_Spec0")
    register_clcmd("say_team /s0", "Cmd_Spec0")
    register_clcmd("s0", "Cmd_Spec0")
    register_clcmd("say /halftime", "Cmd_Halftime")
    register_clcmd("say_team /halftime", "Cmd_Halftime")

    // Master /a Admin Menu commands
    register_clcmd("say /a", "Cmd_AdminDashboard")
    register_clcmd("say_team /a", "Cmd_AdminDashboard")
    register_clcmd("a", "Cmd_AdminDashboard")
    register_clcmd("amx_a", "Cmd_AdminDashboard")
    register_clcmd("say /adminmenu", "Cmd_AdminDashboard")
    register_clcmd("say_team /adminmenu", "Cmd_AdminDashboard")

    register_clcmd("say", "Hook_Say")
    register_clcmd("say_team", "Hook_SayTeam")

    // Interactive crash-proof native text voting menus
    register_menucmd(register_menuid(MIX_VOTE_MENU_ID, 1), MENU_KEY_1 | MENU_KEY_2, "HandleMixVoteMenu")
    register_menucmd(register_menuid(KNIFE_SIDE_MENU_ID, 1), MENU_KEY_1 | MENU_KEY_2, "HandleKnifeSideMenu")
    register_menucmd(register_menuid(CW_ADMIN_MENU_ID, 1), 1023, "HandleClanWarNativeMenu")

    // Start with Warmup if configured
    if(g_bForceWarmup)
    {
        StartWarmup()
    }
}

public plugin_natives()
{
    register_library("clanwar_system")
    register_library("mix_system")

    register_native("CW_IsHalf", "native_is_half")
    register_native("CW_IsLastRound", "native_is_last_round")
    register_native("CW_IsPreLastRound", "native_is_prelast_round")
    register_native("CW_CanOvertime", "native_can_overtime")
    register_native("CW_IsStarted", "native_is_started")
    register_native("CW_IsWarm", "native_is_warm")
    register_native("CW_GetPrefix", "native_get_prefix")
    register_native("CW_GetUserName", "native_get_username")

    register_native("Mix_IsHalf", "native_is_half")
    register_native("Mix_IsLastRound", "native_is_last_round")
    register_native("Mix_IsPreLastRound", "native_is_prelast_round")
    register_native("Mix_CanOvertime", "native_can_overtime")
    register_native("Mix_IsStarted", "native_is_started")
    register_native("Mix_IsWarm", "native_is_warm")
    register_native("Mix_GetPrefix", "native_get_prefix")
    register_native("Mix_GetUserName", "native_get_username")

    // Dummy backwards-compatible natives (Points & SQL removed)
    register_native("Mix_UserPoints", "native_user_points")
    register_native("Mix_HasPointsSys", "native_has_points_sys")
    register_native("Mix_SearchForUser", "native_search_for_user")
    register_native("Mix_MultiplyFactor", "native_multiply_factor")
    register_native("Mix_GetPointsTable", "native_get_points_table")
}

public plugin_end()
{
    DestroyCommandArrays()
}

// -----------------------------------------------------------------------------
// Command Arrays Management
// -----------------------------------------------------------------------------
InitCommandArrays()
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
    g_aRestartCmds = ArrayCreate(32)
    g_aScoreCmds = ArrayCreate(32)
    g_aMoveCTCmds = ArrayCreate(32)
    g_aMoveTCmds = ArrayCreate(32)
    g_aMoveSpecCmds = ArrayCreate(32)
    g_aPauseCmds = ArrayCreate(32)
}

DestroyCommandArrays()
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
    ArrayDestroy(g_aRestartCmds)
    ArrayDestroy(g_aScoreCmds)
    ArrayDestroy(g_aMoveCTCmds)
    ArrayDestroy(g_aMoveTCmds)
    ArrayDestroy(g_aMoveSpecCmds)
    ArrayDestroy(g_aPauseCmds)
}

// -----------------------------------------------------------------------------
// Server Hostname State Management
// -----------------------------------------------------------------------------
InitBaseHostname()
{
    new szCurrentHost[64]
    get_cvar_string("hostname", szCurrentHost, charsmax(szCurrentHost))
    trim(szCurrentHost)

    if(!szCurrentHost[0])
    {
        copy(g_szBaseHostname, charsmax(g_szBaseHostname), "GAMELAND")
        return
    }

    // Strip dynamic tags: " [WarmUp]", " [Pick]", " [Knife]", " CT ["
    new iPos = containi(szCurrentHost, " [WarmUp]")
    if(iPos != -1) szCurrentHost[iPos] = EOS

    iPos = containi(szCurrentHost, " [Pick]")
    if(iPos != -1) szCurrentHost[iPos] = EOS

    iPos = containi(szCurrentHost, " [Knife]")
    if(iPos != -1) szCurrentHost[iPos] = EOS

    new iPos2 = containi(szCurrentHost, " | CT [")
    if(iPos2 != -1) szCurrentHost[iPos2] = EOS

    iPos = containi(szCurrentHost, " CT [")
    if(iPos != -1) szCurrentHost[iPos] = EOS

    trim(szCurrentHost)
    if(szCurrentHost[0])
    {
        copy(g_szBaseHostname, charsmax(g_szBaseHostname), szCurrentHost)
    }
    else
    {
        copy(g_szBaseHostname, charsmax(g_szBaseHostname), "GAMELAND")
    }
}

UpdateServerHostname()
{
    if(!g_szBaseHostname[0])
    {
        InitBaseHostname()
    }

    new szNewHostname[128]

    if(g_iMatchState == STATE_CAPTAIN_COUNTDOWN)
    {
        formatex(szNewHostname, charsmax(szNewHostname), "%s [CW Ready 30s]", g_szBaseHostname)
    }
    else if(g_iMatchState == STATE_CAPTAIN_VOTE)
    {
        formatex(szNewHostname, charsmax(szNewHostname), "%s [CW Vote Captain]", g_szBaseHostname)
    }
    else if(g_iMatchState == STATE_PICKING || g_bPickMode)
    {
        formatex(szNewHostname, charsmax(szNewHostname), "%s [CW Pick Teams]", g_szBaseHostname)
    }
    else if(g_iMatchState == STATE_WARMUP)
    {
        formatex(szNewHostname, charsmax(szNewHostname), "%s [CW WarmUp]", g_szBaseHostname)
    }
    else if(g_iMatchState == STATE_KNIFE)
    {
        // Knife Round active
        formatex(szNewHostname, charsmax(szNewHostname), "%s [CW Knife]", g_szBaseHostname)
    }
    else // Match live (STATE_FIRST_HALF, STATE_SECOND_HALF, OVERTIME_FIRST_HALF, OVERTIME_SECOND_HALF)
    {
        // Exact live score format: GAMELAND CT [5] TR [7]
        formatex(szNewHostname, charsmax(szNewHostname), "%s [CW] | CT [%d] TR [%d]", 
            g_szBaseHostname, g_iScore[CT_SCORE], g_iScore[TERO_SCORE])
    }

    set_cvar_string("hostname", szNewHostname)
}

public Task_InitHostname()
{
    InitBaseHostname()
    UpdateServerHostname()
}

// -----------------------------------------------------------------------------
// Configuration Parser
// -----------------------------------------------------------------------------
LoadConfiguration()
{
    new szConfigPath[128]
    get_configsdir(szConfigPath, charsmax(szConfigPath))
    add(szConfigPath, charsmax(szConfigPath), "/ClanWarSettings.ini")

    if(!file_exists(szConfigPath))
    {
        server_print("[%s] Config file '%s' not found! Using defaults.", PLUGIN_NAME, szConfigPath)
        RegisterDefaultCommands()
        return
    }

    new iFile = fopen(szConfigPath, "rt")
    if(!iFile)
    {
        RegisterDefaultCommands()
        return
    }

    new szLine[256], szKey[64], szValue[192]
    new iSection = 0 // 1: General, 2: Commands, 3: Warm

    while(!feof(iFile))
    {
        fgets(iFile, szLine, charsmax(szLine))
        trim(szLine)

        if(!szLine[0] || szLine[0] == ';' || szLine[0] == '#')
            continue

        if(szLine[0] == '[')
        {
            if(containi(szLine, "General") != -1)
                iSection = 1
            else if(containi(szLine, "Commands") != -1)
                iSection = 2
            else if(containi(szLine, "Warm") != -1)
                iSection = 3
            else
                iSection = 0
            continue
        }

        strtok(szLine, szKey, charsmax(szKey), szValue, charsmax(szValue), '=')
        trim(szKey)
        trim(szValue)

        switch(iSection)
        {
            case 1: // General Settings
            {
                if(equal(szKey, "CHAT_PREFIX"))
                    copy(g_szChatPrefix, charsmax(g_szChatPrefix), szValue)
                else if(equal(szKey, "OVERTIME_ROUNDS"))
                    g_iOvertimeRounds = str_to_num(szValue)
                else if(equal(szKey, "OVERTIME_SCORE"))
                    g_iOvertimeTriggerScore = str_to_num(szValue)
                else if(equal(szKey, "MIX_END_ROUND"))
                    g_iMixEndRound = str_to_num(szValue)
                else if(equal(szKey, "ADMIN_CHAT_FLAGS"))
                    copy(g_szAdminFlags, charsmax(g_szAdminFlags), szValue)
                else if(equal(szKey, "ADMIN_LEVEL_ACCESS"))
                    copy(g_szAdminAccess, charsmax(g_szAdminAccess), szValue)
                else if(equal(szKey, "FREEZE_TIME_SWAP"))
                    g_iFreezeTimeSwap = str_to_num(szValue)
                else if(equal(szKey, "AUTOMATIC_OVERTIME"))
                    g_bAutoOvertime = bool:str_to_num(szValue)
                else if(equal(szKey, "START_CONFIG"))
                    copy(g_szStartConfig, charsmax(g_szStartConfig), szValue)
                else if(equal(szKey, "STOP_CONFIG"))
                    copy(g_szStopConfig, charsmax(g_szStopConfig), szValue)
                else if(equal(szKey, "KNIFE_ROUND_START_DELAY"))
                    g_iKnifeDelay = str_to_num(szValue)
                else if(equal(szKey, "FORCE_WARMUP"))
                    g_bForceWarmup = bool:str_to_num(szValue)
                else if(equal(szKey, "PAUSE_DURATION"))
                    g_iPauseDuration = str_to_num(szValue)
            }
            case 2: // Commands
            {
                if(equal(szKey, "START_MIX_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_StartMix", g_aStartCmds)
                else if(equal(szKey, "CLANWAR_ADMIN_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_ClanWarAdmin", g_aStartCmds)
                else if(equal(szKey, "STOP_MIX_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_StopMix", g_aStopCmds)
                else if(equal(szKey, "WARM_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_Warmup", g_aWarmCmds)
                else if(equal(szKey, "KNIFE_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_KnifeRound", g_aKnifeCmds)
                else if(equal(szKey, "CHAT_ON_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_ChatOn", g_aChatOnCmds)
                else if(equal(szKey, "CHAT_OFF_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_ChatOff", g_aChatOffCmds)
                else if(equal(szKey, "OVERTIME_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_Overtime", g_aOvertimeCmds)
                else if(equal(szKey, "PASSWORD_ON_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_PassOn", g_aPassOnCmds)
                else if(equal(szKey, "PASSWORD_OFF_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_PassOff", g_aPassOffCmds)
                else if(equal(szKey, "SPECALL_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_SpecAll", g_aSpecAllCmds)
                else if(equal(szKey, "RESTART_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_Restart", g_aRestartCmds)
                else if(equal(szKey, "SCORE_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_Score", g_aScoreCmds)
                else if(equal(szKey, "MOVE_CT_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_MoveCT", g_aMoveCTCmds)
                else if(equal(szKey, "MOVE_TERO_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_MoveT", g_aMoveTCmds)
                else if(equal(szKey, "MOVE_SPEC_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_MoveSpec", g_aMoveSpecCmds)
                else if(equal(szKey, "PAUSE_COMMANDS"))
                    RegisterCommandsFromCSV(szValue, "Cmd_Pause", g_aPauseCmds)
            }
            case 3: // Warm Settings
            {
                if(equal(szKey, "WARMUP_SPAWN_MONEY"))
                    g_iWarmMoney = str_to_num(szValue)
            }
        }
    }
    fclose(iFile)

    // Make sure /warm is always explicitly registered for Warmup
    RegisterSingleCmd("say /warm", "Cmd_Warmup", g_aWarmCmds)
    RegisterSingleCmd("say_team /warm", "Cmd_Warmup", g_aWarmCmds)
    RegisterSingleCmd("say /cw", "Cmd_ClanWarAdmin", g_aStartCmds)
    RegisterSingleCmd("say_team /cw", "Cmd_ClanWarAdmin", g_aStartCmds)
    RegisterSingleCmd("say /clanwar", "Cmd_ClanWarAdmin", g_aStartCmds)
    RegisterSingleCmd("say_team /clanwar", "Cmd_ClanWarAdmin", g_aStartCmds)
    RegisterSingleCmd("say /cwmenu", "Cmd_ClanWarAdmin", g_aStartCmds)
    RegisterSingleCmd("say_team /cwmenu", "Cmd_ClanWarAdmin", g_aStartCmds)
}

RegisterCommandsFromCSV(const szCSV[], const szFunction[], Array:aHolder)
{
    new szBuffer[192], szToken[64]
    copy(szBuffer, charsmax(szBuffer), szCSV)

    while(szBuffer[0] != EOS && strtok2(szBuffer, szToken, charsmax(szToken), szBuffer, charsmax(szBuffer), ',', TRIM_INNER))
    {
        trim(szToken)
        if(!szToken[0])
            continue

        register_clcmd(szToken, szFunction)
        ArrayPushString(aHolder, szToken)
    }
}

RegisterSingleCmd(const szCmd[], const szFunction[], Array:aHolder)
{
    register_clcmd(szCmd, szFunction)
    ArrayPushString(aHolder, szCmd)
}

RegisterDefaultCommands()
{
    RegisterSingleCmd("say /warm", "Cmd_Warmup", g_aWarmCmds)
    RegisterSingleCmd("say_team /warm", "Cmd_Warmup", g_aWarmCmds)
    RegisterSingleCmd("say /cw", "Cmd_ClanWarAdmin", g_aStartCmds)
    RegisterSingleCmd("say_team /cw", "Cmd_ClanWarAdmin", g_aStartCmds)
    RegisterSingleCmd("say /clanwar", "Cmd_ClanWarAdmin", g_aStartCmds)
    RegisterSingleCmd("say_team /clanwar", "Cmd_ClanWarAdmin", g_aStartCmds)
    RegisterSingleCmd("say /cwmenu", "Cmd_ClanWarAdmin", g_aStartCmds)
    RegisterSingleCmd("say_team /cwmenu", "Cmd_ClanWarAdmin", g_aStartCmds)
    RegisterSingleCmd("say /mix", "Cmd_StartMix", g_aStartCmds)
    RegisterSingleCmd("say_team /mix", "Cmd_StartMix", g_aStartCmds)
    RegisterSingleCmd("say /start", "Cmd_StartMix", g_aStartCmds)
    RegisterSingleCmd("say_team /start", "Cmd_StartMix", g_aStartCmds)
    RegisterSingleCmd("say /stop", "Cmd_StopMix", g_aStopCmds)
    RegisterSingleCmd("say_team /stop", "Cmd_StopMix", g_aStopCmds)
    RegisterSingleCmd("say /knife", "Cmd_KnifeRound", g_aKnifeCmds)
    RegisterSingleCmd("say_team /knife", "Cmd_KnifeRound", g_aKnifeCmds)
    RegisterSingleCmd("say /score", "Cmd_Score", g_aScoreCmds)
    RegisterSingleCmd("say_team /score", "Cmd_Score", g_aScoreCmds)
    RegisterSingleCmd("say /rr", "Cmd_Restart", g_aRestartCmds)
    RegisterSingleCmd("say /restart", "Cmd_Restart", g_aRestartCmds)
}

// -----------------------------------------------------------------------------
// Client Connection & Info
// -----------------------------------------------------------------------------
public client_putinserver(id)
{
    get_user_name(id, g_szUserName[id], charsmax(g_szUserName[]))

    // Enforce 10 human slots strictly
    if(!is_user_bot(id) && !is_user_hltv(id))
    {
        new iConnectedHumans = 0
        for(new p = 1; p <= MaxClients; p++)
        {
            if(is_user_connected(p) && !is_user_bot(p) && !is_user_hltv(p))
                iConnectedHumans++
        }
        if(iConnectedHumans > 10 && !HasAdminAccess(id))
        {
            rh_drop_client(id, "Server is full (10/10 Clan War slots)")
            return
        }
    }
    g_iPlayerMixVote[id] = 0
    g_bPlayerMixLocked[id] = false
    g_iPlayerMixSwitches[id] = 0
    g_flLastMixVoteTime[id] = 0.0
    g_iSavedFrags[id] = 0
    g_iSavedDeaths[id] = 0
    g_iPlayerKnifeVote[id] = 0
    g_bPlayerKnifeVoted[id] = false
    g_iRoundKills[id] = 0
    g_iMatchKills[id] = 0
    g_iMatchDeaths[id] = 0
    g_iMatchHS[id] = 0
    g_iMatchKnifeKills[id] = 0
    g_iMatchPlants[id] = 0
    g_iMatchDefuses[id] = 0
    ResetPlayerF3Votes(id)
    remove_task(TASK_BIND_F3 + id)
    set_task(1.0, "Task_BindClientF3", TASK_BIND_F3 + id)
    set_task(3.0, "Task_BindClientF3", TASK_BIND_F3 + id)

    if(g_iMatchState == STATE_FIRST_HALF || g_iMatchState == STATE_SECOND_HALF ||
       g_iMatchState == STATE_OVERTIME_FIRST_HALF || g_iMatchState == STATE_OVERTIME_SECOND_HALF)
    {
        set_task(1.0, "Task_LateJoinScoreSync", id)
    }
}

public Task_LateJoinScoreSync(id)
{
    if(is_user_connected(id))
    {
        SyncPlayerScore(id)
    }
}

public client_disconnected(id)
{
    new szAuthID[36]
    get_user_authid(id, szAuthID, charsmax(szAuthID))

    if(g_iMatchState == STATE_FIRST_HALF || g_iMatchState == STATE_SECOND_HALF)
    {
        ExecuteForward(g_hFwdSysLeaver, g_iRet, szAuthID)
    }

    ExecuteForward(g_hFwdUserSave, g_iRet, id)
    ResetPlayerF3Votes(id)
    remove_task(TASK_BIND_F3 + id)

    g_szUserName[id][0] = EOS
    if(task_exists(TASK_MIX_VOTE))
    {
        if(g_iPlayerMixVote[id] == 1) g_iMixVoteKnife--
        else if(g_iPlayerMixVote[id] == 2) g_iMixVoteLive--
        if(g_iMixVoteKnife < 0) g_iMixVoteKnife = 0
        if(g_iMixVoteLive < 0) g_iMixVoteLive = 0
    }
    if(task_exists(TASK_KNIFE_VOTE))
    {
        if(g_iPlayerKnifeVote[id] == 1) g_iVoteTR--
        else if(g_iPlayerKnifeVote[id] == 2) g_iVoteCT--
        if(g_iVoteTR < 0) g_iVoteTR = 0
        if(g_iVoteCT < 0) g_iVoteCT = 0
    }
    if(g_iMatchState == STATE_CAPTAIN_COUNTDOWN)
    {
        if(!g_bAdminForceStarted && !g_bFastTestMode && GetActiveInGamePlayerCount() < 10)
        {
            remove_task(TASK_CW_COUNTDOWN)
            g_iMatchState = STATE_WARMUP
            UpdateServerHostname()
            client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3Player disconnected! ^1Captain vote countdown cancelled. Waiting for 10 players (%d/10)...", GetActiveInGamePlayerCount())
        }
    }
    else if(g_iMatchState == STATE_CAPTAIN_VOTE || g_iMatchState == STATE_PICKING)
    {
        if(!is_user_bot(id))
        {
            new iTotalActive = 0
            for(new p = 1; p <= MaxClients; p++)
            {
                if(is_user_connected(p) && !is_user_hltv(p) && p != id)
                    iTotalActive++
            }
            if(!g_bAdminForceStarted && !g_bFastTestMode && iTotalActive < 10)
            {
                client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3Player disconnected during election/draft! ^1Resetting to WarmUp...")
                StartWarmup()
            }
        }
    }
    g_iPlayerMixVote[id] = 0
    g_bPlayerMixLocked[id] = false
    g_iPlayerMixSwitches[id] = 0
    g_flLastMixVoteTime[id] = 0.0
    g_iPlayerKnifeVote[id] = 0
    g_bPlayerKnifeVoted[id] = false
    g_iRoundKills[id] = 0
    g_iSavedFrags[id] = 0
    g_iSavedDeaths[id] = 0
    g_iMatchKills[id] = 0
    g_iMatchDeaths[id] = 0
    g_iMatchHS[id] = 0
    g_iMatchKnifeKills[id] = 0
    g_iMatchPlants[id] = 0
    g_iMatchDefuses[id] = 0
}

// -----------------------------------------------------------------------------
// ReAPI Hooks: Player Spawn, Killed, Round End, Restart
// -----------------------------------------------------------------------------
public RG_CBasePlayer_Spawn_Post(id)
{
    if(!is_user_alive(id))
        return

    if(!is_user_bot(id))
    {
        client_cmd(id, "bind n nightvision")
        client_cmd(id, "bind N nightvision")
        client_cmd(id, "bind F3 cw_menu")
        client_cmd(id, "bind f3 cw_menu")
    }

    if(g_bReviveMode)
    {
        rg_add_account(id, 16000, AS_SET)
        set_member(id, m_iAccount, 16000)
        rg_set_user_armor(id, 100, ARMOR_VESTHELM)
        rg_remove_item(id, "weapon_c4")
        TeleportToRandomSpawn(id)
        set_entvar(id, var_takedamage, DAMAGE_NO)
        set_task(2.0, "Task_RemoveSpawnProtection", id)
        return
    }

    switch(g_iMatchState)
    {
        case STATE_WARMUP, STATE_CAPTAIN_COUNTDOWN:
        {
            // Standard Clan War Warmup: base spawn, $16,000, armor, no C4
            rg_add_account(id, g_iWarmMoney, AS_SET)
            set_member(id, m_iAccount, g_iWarmMoney)
            rg_set_user_armor(id, 100, ARMOR_VESTHELM)
            rg_remove_item(id, "weapon_c4")
        }
        case STATE_KNIFE:
        {
            // Strip all weapons and give only knife + Kevlar (shield 1, NO helmet) & NO C4
            rg_remove_all_items(id)
            rg_give_item(id, "weapon_knife")
            rg_set_user_armor(id, 100, ARMOR_KEVLAR)
            rg_add_account(id, 0, AS_SET)
            rg_remove_item(id, "weapon_c4")
        }
        case STATE_FIRST_HALF, STATE_SECOND_HALF, STATE_OVERTIME_FIRST_HALF, STATE_OVERTIME_SECOND_HALF:
        {
            SyncPlayerScore(id)
            if(g_bHalftimePendingSync && (g_iMatchState == STATE_SECOND_HALF || g_iMatchState == STATE_OVERTIME_SECOND_HALF))
            {
                rg_add_account(id, 800, AS_SET, true)
            }
        }
    }
}

// -----------------------------------------------------------------------------
// Win Condition & Round End Interceptors (Infinite Revive Protection)
// -----------------------------------------------------------------------------
public RG_CSGameRules_CheckWinConditions_Pre()
{
    // Supercede win condition checks completely during warmup, countdown, captain election or drafting
    if(g_bReviveMode || g_iMatchState == STATE_WARMUP || g_iMatchState == STATE_CAPTAIN_COUNTDOWN || g_iMatchState == STATE_CAPTAIN_VOTE || g_iMatchState == STATE_PICKING || g_bPickMode)
    {
        return HC_SUPERCEDE
    }
    return HC_CONTINUE
}

public RG_RoundEnd_Pre(WinStatus:status, ScenarioEventEndRound:event, Float:tmDelay)
{
    // Block any round ending during warmup, countdown, captain election or drafting
    if(g_bReviveMode || g_iMatchState == STATE_WARMUP || g_iMatchState == STATE_CAPTAIN_COUNTDOWN || g_iMatchState == STATE_CAPTAIN_VOTE || g_iMatchState == STATE_PICKING || g_bPickMode)
    {
        if(event == ROUND_GAME_RESTART || event == ROUND_GAME_COMMENCE)
            return HC_CONTINUE

        return HC_SUPERCEDE
    }
    return HC_CONTINUE
}

public RG_CBasePlayer_Killed_Post(iVictim, iKiller, iGib)
{
    if(!is_user_connected(iVictim))
        return

    new szKillerName[MAX_NAME_LENGTH], szKillerAuth[36]
    if(is_user_connected(iKiller))
    {
        get_user_name(iKiller, szKillerName, charsmax(szKillerName))
        get_user_authid(iKiller, szKillerAuth, charsmax(szKillerAuth))
    }

    new bool:bHeadshot = bool:get_member(iVictim, m_bHeadshotKilled)

    // 1. Infinite Revive Mode (/rev1): Instant respawn, round NEVER ends (even 1v1 duels)
    if(g_bReviveMode)
    {
        set_task(1.0, "Task_RevivePlayer", iVictim)
        return
    }

    // 2. Standard Warmup Mode (/warm): Clan War rules - NO auto-respawn!
    // When killed, player stays dead and waits for round to end normally.
    if(g_iMatchState == STATE_WARMUP || g_iMatchState == STATE_CAPTAIN_COUNTDOWN)
    {
        return
    }

    // In competitive modes (Knife & Match Live), enforce that the dead player's camera switches to a teammate (never enemy)
    set_task(0.1, "Task_EnforceTeammateObserver", iVictim)

    // 3. Knife Round Elimination Detection: Instant winner detection & menu trigger
    if(g_iMatchState == STATE_KNIFE)
    {
        new iAliveCT = 0, iAliveTR = 0
        new iPlayers[MAX_PLAYERS], iNum
        get_players(iPlayers, iNum, "a")

        for(new i = 0; i < iNum; i++)
        {
            new id = iPlayers[i]
            if(id == iVictim)
                continue

            new TeamName:team = get_member(id, m_iTeam)
            if(team == TEAM_CT)
                iAliveCT++
            else if(team == TEAM_TERRORIST)
                iAliveTR++
        }

        if(iAliveCT == 0 || iAliveTR == 0)
        {
            if(!g_bRoundScored)
            {
                g_bRoundScored = true
                if(iAliveCT > 0)
                    g_iKnifeWinnerTeam = TEAM_CT
                else if(iAliveTR > 0)
                    g_iKnifeWinnerTeam = TEAM_TERRORIST
                else
                    g_iKnifeWinnerTeam = TEAM_CT

                client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "KNIFE_ROUND_WON_BY_X_TEAM", g_iKnifeWinnerTeam == TEAM_CT ? "CT" : "TERRORIST")

                if(g_iKnifeWinnerTeam == TEAM_CT)
                    rg_send_audio(0, "radio/ctwin.wav")
                else
                    rg_send_audio(0, "radio/terwin.wav")

                rg_round_end(4.0, g_iKnifeWinnerTeam == TEAM_CT ? WINSTATUS_CTS : WINSTATUS_TERRORISTS, ROUND_TERRORISTS_ESCAPED, "Knife Round Finished", "")
                set_task(0.8, "Task_StartKnifeVoteDelayed")
            }
        }
        return
    }

    if(g_iMatchState == STATE_FIRST_HALF || g_iMatchState == STATE_SECOND_HALF ||
       g_iMatchState == STATE_OVERTIME_FIRST_HALF || g_iMatchState == STATE_OVERTIME_SECOND_HALF)
    {
        g_iMatchDeaths[iVictim]++

        if(is_user_connected(iKiller) && iKiller != iVictim)
        {
            g_iMatchKills[iKiller]++
            g_iRoundKills[iKiller]++

            // CS2-style announcements for high kill streaks
            if(g_iRoundKills[iKiller] == 3)
            {
                client_print_color(0, print_team_default, "^4%s ^4%s ^3scored a ^4TRIPLE KILL^3! [ 3 ]", g_szChatPrefix, szKillerName)
            }
            else if(g_iRoundKills[iKiller] == 4)
            {
                client_print_color(0, print_team_default, "^4%s ^4%s ^3scored a ^4QUAD KILL^3! [ 4 ]", g_szChatPrefix, szKillerName)
            }
            else if(g_iRoundKills[iKiller] >= 5)
            {
                client_print_color(0, print_team_default, "^4%s ^3* * * ^4%s ^3SCORED AN ACE! * * * [ * ACE * ]", g_szChatPrefix, szKillerName)
            }

            if(bHeadshot)
            {
                g_iMatchHS[iKiller]++
            }

            new iClip, iAmmo
            if(get_user_weapon(iKiller, iClip, iAmmo) == 29 /* CSW_KNIFE */)
            {
                g_iMatchKnifeKills[iKiller]++
            }
        }

        ExecuteForward(g_hFwdPlayerKilled, g_iRet, iKiller, iVictim, bHeadshot, szKillerName, szKillerAuth)
    }
}

ApplySpectatorCameraSettings()
{
    if(g_iMatchState == STATE_WARMUP)
    {
        // Warmup: Allow players to spectate freely, any team, any mode
        set_cvar_num("mp_forcecamera", 0)
        set_cvar_num("mp_forcechasecam", 0)
        set_cvar_num("mp_fadetoblack", 0)
    }
    else
    {
        // Competitive Match / Knife Round: Teammates only, locked in eye view, NO enemy spectating
        set_cvar_num("mp_forcecamera", 2)
        set_cvar_num("mp_forcechasecam", 2)
        set_cvar_num("mp_fadetoblack", 0)
    }
}

public RG_Observer_IsValidTarget_Pre(const id, iTargetIndex, bool:bSameTeam)
{
    // In WarmUp, dead players can spectate anyone (no restriction)
    if(g_iMatchState == STATE_WARMUP)
    {
        return HC_CONTINUE
    }

    // In Mix Mode (Knife, Live match, Halftime, Overtime):
    // If the spectator player is on CT or Terrorist, they can ONLY spectate their own team!
    if(is_user_connected(id) && is_user_connected(iTargetIndex))
    {
        new TeamName:iMyTeam = get_member(id, m_iTeam)
        if(iMyTeam == TEAM_TERRORIST || iMyTeam == TEAM_CT)
        {
            new TeamName:iTargetTeam = get_member(iTargetIndex, m_iTeam)
            if(iMyTeam != iTargetTeam)
            {
                SetHookChainReturn(ATYPE_INTEGER, 0)
                return HC_SUPERCEDE
            }
        }
    }

    return HC_CONTINUE
}

public Task_EnforceTeammateObserver(id)
{
    if(!is_user_connected(id) || is_user_alive(id))
        return

    if(g_iMatchState == STATE_WARMUP)
        return

    new TeamName:iMyTeam = get_member(id, m_iTeam)
    if(iMyTeam != TEAM_TERRORIST && iMyTeam != TEAM_CT)
        return

    new iTarget = get_member(id, m_hObserverTarget)
    new bool:bNeedsFix = false

    if(!iTarget || !is_user_connected(iTarget) || !is_user_alive(iTarget))
    {
        bNeedsFix = true
    }
    else if(get_member(iTarget, m_iTeam) != iMyTeam)
    {
        bNeedsFix = true
    }

    if(bNeedsFix)
    {
        new iPlayers[MAX_PLAYERS], iNum
        get_players(iPlayers, iNum, "ae", iMyTeam == TEAM_CT ? "CT" : "TERRORIST")
        for(new i = 0; i < iNum; i++)
        {
            new p = iPlayers[i]
            if(p != id && is_user_alive(p))
            {
                set_member(id, m_hObserverTarget, p)
                set_member(id, m_iObserverLastMode, 4) // OBS_IN_EYE
                break
            }
        }
    }
}

public RG_PlantBomb_Post(const index, Float:vecStart[3], Float:vecVelocity[3])
{
    if(g_iMatchState == STATE_FIRST_HALF || g_iMatchState == STATE_SECOND_HALF ||
       g_iMatchState == STATE_OVERTIME_FIRST_HALF || g_iMatchState == STATE_OVERTIME_SECOND_HALF)
    {
        if(is_user_connected(index))
        {
            g_iMatchPlants[index]++
        }
    }
}

public RG_CGrenade_DefuseBombEnd_Post(const this, const player, bool:bDefused)
{
    if(!bDefused)
        return

    if(g_iMatchState == STATE_FIRST_HALF || g_iMatchState == STATE_SECOND_HALF ||
       g_iMatchState == STATE_OVERTIME_FIRST_HALF || g_iMatchState == STATE_OVERTIME_SECOND_HALF)
    {
        if(is_user_connected(player))
        {
            g_iMatchDefuses[player]++
        }
    }
}

public RG_CBasePlayer_MakeBomber_Pre(const this)
{
    // Never give C4 during Knife Round, Warmup, or Infinite Revive!
    if(g_iMatchState == STATE_KNIFE || g_iMatchState == STATE_WARMUP || g_bReviveMode)
    {
        SetHookChainReturn(ATYPE_BOOL, false)
        return HC_SUPERCEDE
    }
    return HC_CONTINUE
}

public Task_RevivePlayer(id)
{
    if(!g_bReviveMode)
        return

    if(!is_user_connected(id) || is_user_alive(id))
        return

    new TeamName:iTeam = get_member(id, m_iTeam)
    if(iTeam != TEAM_TERRORIST && iTeam != TEAM_CT)
        return

    rg_round_respawn(id)
    set_member(id, m_iAccount, 16000)
    rg_give_item(id, "item_kevlar")
    rg_give_item(id, "item_assaultsuit")
    TeleportToRandomSpawn(id)
}

public Task_StartKnifeVoteDelayed()
{
    if(g_iMatchState == STATE_KNIFE)
    {
        StartKnifeVote()
    }
}

public Task_WarmupRespawn(id)
{
    if(!is_user_connected(id) || is_user_alive(id) || g_iMatchState != STATE_WARMUP)
        return

    new TeamName:iTeam = get_member(id, m_iTeam)
    if(iTeam != TEAM_TERRORIST && iTeam != TEAM_CT)
        return

    rg_round_respawn(id)
}

public Task_RemoveSpawnProtection(id)
{
    if(is_user_connected(id) && is_user_alive(id) && g_iMatchState == STATE_WARMUP)
    {
        set_entvar(id, var_takedamage, DAMAGE_AIM)
    }
}

stock LoadMapSpawns()
{
    g_iTotalSpawnsCT = 0
    g_iTotalSpawnsTR = 0

    // Load CT Spawns: info_player_start
    new iEnt = -1
    while((iEnt = rg_find_ent_by_class(iEnt, "info_player_start")) > 0)
    {
        if(g_iTotalSpawnsCT >= sizeof(g_vecSpawnsCT))
            break
        get_entvar(iEnt, var_origin, g_vecSpawnsCT[g_iTotalSpawnsCT])
        get_entvar(iEnt, var_angles, g_vecAnglesCT[g_iTotalSpawnsCT])
        g_iTotalSpawnsCT++
    }

    // Load Terrorist Spawns: info_player_deathmatch
    iEnt = -1
    while((iEnt = rg_find_ent_by_class(iEnt, "info_player_deathmatch")) > 0)
    {
        if(g_iTotalSpawnsTR >= sizeof(g_vecSpawnsTR))
            break
        get_entvar(iEnt, var_origin, g_vecSpawnsTR[g_iTotalSpawnsTR])
        get_entvar(iEnt, var_angles, g_vecAnglesTR[g_iTotalSpawnsTR])
        g_iTotalSpawnsTR++
    }
}

stock bool:IsSpawnOccupied(Float:vecOrigin[3])
{
    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "a")
    for(new i = 0; i < iNum; i++)
    {
        new Float:pOrigin[3]
        get_entvar(iPlayers[i], var_origin, pOrigin)
        if(get_distance_f(vecOrigin, pOrigin) < 65.0)
        {
            return true
        }
    }
    return false
}

stock TeleportToRandomSpawn(id)
{
    new TeamName:team = get_member(id, m_iTeam)
    if(team == TEAM_CT && g_iTotalSpawnsCT > 0)
    {
        new iChosen = -1
        new iStartIdx = random_num(0, g_iTotalSpawnsCT - 1)
        for(new i = 0; i < g_iTotalSpawnsCT; i++)
        {
            new idx = (iStartIdx + i) % g_iTotalSpawnsCT
            new Float:testOrigin[3]
            testOrigin[0] = g_vecSpawnsCT[idx][0]
            testOrigin[1] = g_vecSpawnsCT[idx][1]
            testOrigin[2] = g_vecSpawnsCT[idx][2] + 10.0
            if(!IsSpawnOccupied(testOrigin))
            {
                iChosen = idx
                break
            }
        }
        if(iChosen == -1) iChosen = iStartIdx

        new Float:vecOrigin[3]
        vecOrigin[0] = g_vecSpawnsCT[iChosen][0]
        vecOrigin[1] = g_vecSpawnsCT[iChosen][1]
        vecOrigin[2] = g_vecSpawnsCT[iChosen][2] + 10.0

        set_entvar(id, var_origin, vecOrigin)
        set_entvar(id, var_angles, g_vecAnglesCT[iChosen])
        set_entvar(id, var_v_angle, g_vecAnglesCT[iChosen])
        set_entvar(id, var_fixangle, 1)
        set_entvar(id, var_velocity, Float:{0.0, 0.0, 0.0})
        rg_reset_maxspeed(id)
    }
    else if(team == TEAM_TERRORIST && g_iTotalSpawnsTR > 0)
    {
        new iChosen = -1
        new iStartIdx = random_num(0, g_iTotalSpawnsTR - 1)
        for(new i = 0; i < g_iTotalSpawnsTR; i++)
        {
            new idx = (iStartIdx + i) % g_iTotalSpawnsTR
            new Float:testOrigin[3]
            testOrigin[0] = g_vecSpawnsTR[idx][0]
            testOrigin[1] = g_vecSpawnsTR[idx][1]
            testOrigin[2] = g_vecSpawnsTR[idx][2] + 10.0
            if(!IsSpawnOccupied(testOrigin))
            {
                iChosen = idx
                break
            }
        }
        if(iChosen == -1) iChosen = iStartIdx

        new Float:vecOrigin[3]
        vecOrigin[0] = g_vecSpawnsTR[iChosen][0]
        vecOrigin[1] = g_vecSpawnsTR[iChosen][1]
        vecOrigin[2] = g_vecSpawnsTR[iChosen][2] + 10.0

        set_entvar(id, var_origin, vecOrigin)
        set_entvar(id, var_angles, g_vecAnglesTR[iChosen])
        set_entvar(id, var_v_angle, g_vecAnglesTR[iChosen])
        set_entvar(id, var_fixangle, 1)
        set_entvar(id, var_velocity, Float:{0.0, 0.0, 0.0})
        rg_reset_maxspeed(id)
    }
}

public RG_CSGameRules_RestartRound_Post()
{
    // Reset round score lock and round kills when new round starts!
    g_bRoundScored = false
    remove_task(TASK_END_ROUND)

    for(new i = 1; i <= MAX_PLAYERS; i++)
    {
        g_iRoundKills[i] = 0
    }

    ApplySpectatorCameraSettings()

    if(g_iMatchState == STATE_FIRST_HALF || g_iMatchState == STATE_SECOND_HALF ||
       g_iMatchState == STATE_OVERTIME_FIRST_HALF || g_iMatchState == STATE_OVERTIME_SECOND_HALF)
    {
        SyncTeamScores()
        if(g_bHalftimePendingSync)
        {
            g_bHalftimePendingSync = false
            RestoreHalftimePlayerStats()
        }
    }
}

public RG_RoundEnd_Post(WinStatus:status, ScenarioEventEndRound:event, Float:tmDelay)
{
    if(event == ROUND_GAME_RESTART || event == ROUND_GAME_COMMENCE)
        return

    // 1. Warmup Mode: Natural round elimination reset (normal gameplay)
    if(g_iMatchState == STATE_WARMUP)
    {
        return
    }

    // 2. Knife Round Handling
    if(g_iMatchState == STATE_KNIFE)
    {
        if(g_bRoundScored)
            return
        g_bRoundScored = true

        if(status == WINSTATUS_CTS)
            g_iKnifeWinnerTeam = TEAM_CT
        else if(status == WINSTATUS_TERRORISTS)
            g_iKnifeWinnerTeam = TEAM_TERRORIST
        else
            return

        client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "KNIFE_ROUND_WON_BY_X_TEAM", g_iKnifeWinnerTeam == TEAM_CT ? "CT" : "TERRORIST")

        // Start knife side vote directly
        StartKnifeVote()
        return
    }

    // 3. Competitive Match Round Scoring
    if(g_iMatchState != STATE_FIRST_HALF && g_iMatchState != STATE_SECOND_HALF &&
       g_iMatchState != STATE_OVERTIME_FIRST_HALF && g_iMatchState != STATE_OVERTIME_SECOND_HALF)
    {
        return
    }

    // BUGFIX: Prevent double counting bug!
    if(g_bRoundScored)
    {
        return
    }
    g_bRoundScored = true

    new TeamScore:iWinner = TeamScore:-1
    if(status == WINSTATUS_CTS)
    {
        g_iScore[CT_SCORE]++
        iWinner = CT_SCORE
    }
    else if(status == WINSTATUS_TERRORISTS)
    {
        g_iScore[TERO_SCORE]++
        iWinner = TERO_SCORE
    }

    if(iWinner == TeamScore:-1)
        return

    // Track overtime rounds
    if(g_iMatchState == STATE_OVERTIME_FIRST_HALF || g_iMatchState == STATE_OVERTIME_SECOND_HALF)
    {
        g_iOvertimeScore[iWinner]++
    }

    // Keep scoreboard and engine synchronized
    SyncTeamScores()

    // Announcement of current score
    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_SCORE_IS_WITH_END",
        LANG_SERVER, "CT_TEAM", g_iScore[CT_SCORE],
        LANG_SERVER, "TERO_TEAM", g_iScore[TERO_SCORE])

    if(g_iMatchState == STATE_SECOND_HALF && (g_iFirstHalfScore[CT_SCORE] > 0 || g_iFirstHalfScore[TERO_SCORE] > 0))
    {
        client_print_color(0, print_team_default, "^4%s ^11st Half: ^4CT %d ^3- ^4TR %d", g_szChatPrefix, g_iFirstHalfScore[CT_SCORE], g_iFirstHalfScore[TERO_SCORE])
    }

    // Execute Forward
    new iDuration = get_systime() - g_iMatchStartTime
    ExecuteForward(g_hFwdNewRound, g_iRet, g_iScore[CT_SCORE], g_iScore[TERO_SCORE], iDuration)

    // Schedule round state check
    set_task(1.0, "Task_CheckMatchProgress", TASK_END_ROUND)
}

// -----------------------------------------------------------------------------
// Match Progression & Halftime Logic
// -----------------------------------------------------------------------------
public Task_CheckMatchProgress()
{
    new iTotalRounds = g_iScore[CT_SCORE] + g_iScore[TERO_SCORE]

    // 1. Check First Half Halftime
    if(g_iMatchState == STATE_FIRST_HALF)
    {
        if(iTotalRounds >= 15)
        {
            TriggerHalftime()
            return
        }

        if(iTotalRounds == 14)
        {
            client_print_color(0, print_team_default, "^4%s ^1Last round of the ^4First Half^1!", g_szChatPrefix)
        }
    }
    // 2. Check Second Half Win or Tie
    else if(g_iMatchState == STATE_SECOND_HALF)
    {
        // Check if CT or TR reached win target (16 rounds)
        if(g_iScore[CT_SCORE] >= g_iMixEndRound)
        {
            EndMatch(TEAM_CT)
            return
        }
        else if(g_iScore[TERO_SCORE] >= g_iMixEndRound)
        {
            EndMatch(TEAM_TERRORIST)
            return
        }

        // Check for 15-15 Tie
        if(g_iScore[CT_SCORE] == g_iOvertimeTriggerScore && g_iScore[TERO_SCORE] == g_iOvertimeTriggerScore)
        {
            if(g_bAutoOvertime)
            {
                client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "OVERTIME_AUTOMATIC_WILL_START")
                set_task(5.0, "StartOvertime")
            }
            else
            {
                EndMatch(TEAM_UNASSIGNED) // Draw
            }
            return
        }

        // Pre-last or last round notices
        if(g_iScore[CT_SCORE] == g_iMixEndRound - 1)
        {
            client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_LAST_ROUND_FOR_X_TEAM", "CT")
        }
        else if(g_iScore[TERO_SCORE] == g_iMixEndRound - 1)
        {
            client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_LAST_ROUND_FOR_X_TEAM", "TERRORIST")
        }
    }
    // 3. Overtime Check
    else if(g_iMatchState == STATE_OVERTIME_FIRST_HALF)
    {
        new iOTRounds = g_iOvertimeScore[CT_SCORE] + g_iOvertimeScore[TERO_SCORE]
        if(iOTRounds >= g_iOvertimeRounds)
        {
            TriggerOvertimeHalftime()
        }
    }
    else if(g_iMatchState == STATE_OVERTIME_SECOND_HALF)
    {
        new iTarget = g_iOvertimeTriggerScore + g_iOvertimeRounds + 1
        if(g_iScore[CT_SCORE] >= iTarget)
            EndMatch(TEAM_CT)
        else if(g_iScore[TERO_SCORE] >= iTarget)
            EndMatch(TEAM_TERRORIST)
        else if(g_iScore[CT_SCORE] == iTarget - 1 && g_iScore[TERO_SCORE] == iTarget - 1)
            EndMatch(TEAM_UNASSIGNED) // Tie in OT
    }
}

// -----------------------------------------------------------------------------
// Halftime Execution (Clean atomic swap, stat & score preservation)
// -----------------------------------------------------------------------------
TriggerHalftime()
{
    g_iMatchState = STATE_SECOND_HALF

    // Record exact 1st half score
    g_iFirstHalfScore[CT_SCORE] = g_iScore[CT_SCORE]
    g_iFirstHalfScore[TERO_SCORE] = g_iScore[TERO_SCORE]

    // Carry rounds forward to swapped sides
    new iTemp = g_iScore[CT_SCORE]
    g_iScore[CT_SCORE] = g_iScore[TERO_SCORE]
    g_iScore[TERO_SCORE] = iTemp

    // Atomically swap all players using ReAPI native
    rg_swap_all_players()

    // Save player frags and deaths across the halftime restart
    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i]
        g_iSavedFrags[id] = floatround(Float:get_entvar(id, var_frags))
        g_iSavedDeaths[id] = get_member(id, m_iDeaths)
    }
    g_bHalftimePendingSync = true

    // Synchronize scores directly with ReGameDLL engine and scoreboard
    SyncTeamScores()

    // Announce Halftime and upcoming 3 restarts (7s -> 5s -> 3s)
    client_print_color(0, print_team_default, "^4%s ^1=== ^4HALF TIME ^1=== Teams Swapped!", g_szChatPrefix)
    client_print_color(0, print_team_default, "^4%s ^11st Half Finished: ^4CT %d ^1- ^4%d TR", g_szChatPrefix, g_iFirstHalfScore[CT_SCORE], g_iFirstHalfScore[TERO_SCORE])
    client_print_color(0, print_team_default, "^4%s ^1Transferred Starting Score: ^4CT %d ^1- ^4%d TR", g_szChatPrefix, g_iScore[CT_SCORE], g_iScore[TERO_SCORE])
    client_print_color(0, print_team_default, "^4%s ^3Halftime Restarts: ^11st in ^47s^1, 2nd in ^45s^1, 3rd in ^43s ^3(LIVE)", g_szChatPrefix)

    set_dhudmessage(0, 150, 255, -1.0, 0.35, 2, 0.1, 5.0, 0.1, 1.0)
    show_dhudmessage(0, "=== HALF TIME ===\nTeams Swapped!\nScore: CT %d - %d TR\nRestarts: 7s -> 5s -> 3s (LIVE)", g_iScore[CT_SCORE], g_iScore[TERO_SCORE])

    // Initial clean round restart to move players to new spawn bases
    new iFirstWait = (g_iFreezeTimeSwap > 0) ? g_iFreezeTimeSwap : 7
    set_cvar_num("mp_freezetime", iFirstWait)
    set_cvar_num("sv_alltalk", 1) // Allow all players to chat during halftime swap
    rg_restart_round()
    RestoreHalftimePlayerStats()

    // Triple restart sequence: 7 seconds -> 5 seconds -> 3 seconds -> LIVE!
    remove_task(TASK_HALFTIME_LIVE)
    set_task(float(iFirstWait), "Task_HalftimeRestart1", TASK_HALFTIME_LIVE)
}

public Task_HalftimeRestart1()
{
    rg_restart_round()
    SyncTeamScores()
    RestoreHalftimePlayerStats()

    client_print_color(0, print_team_default, "^4%s ^3[1/3] Restart 1/3 Completed! ^1Next restart in ^45s^1...", g_szChatPrefix)
    set_dhudmessage(255, 200, 0, -1.0, 0.35, 0, 0.0, 3.0, 0.1, 0.5)
    show_dhudmessage(0, "--- RESTART 1/3 ---\nNext restart in 5 seconds...")

    set_cvar_num("mp_freezetime", 5)
    set_task(5.0, "Task_HalftimeRestart2", TASK_HALFTIME_LIVE)
}

public Task_HalftimeRestart2()
{
    rg_restart_round()
    SyncTeamScores()
    RestoreHalftimePlayerStats()

    client_print_color(0, print_team_default, "^4%s ^3[2/3] Restart 2/3 Completed! ^1Final restart in ^43s ^3(LIVE)^1...", g_szChatPrefix)
    set_dhudmessage(255, 140, 0, -1.0, 0.35, 0, 0.0, 2.5, 0.1, 0.5)
    show_dhudmessage(0, "--- RESTART 2/3 ---\nFinal restart in 3 seconds!")

    set_cvar_num("mp_freezetime", 3)
    set_task(3.0, "Task_HalftimeRestart3", TASK_HALFTIME_LIVE)
}

public Task_HalftimeRestart3()
{
    set_cvar_num("mp_freezetime", 15)
    rg_restart_round()
    SyncTeamScores()
    RestoreHalftimePlayerStats()

    set_cvar_num("sv_alltalk", 3)
    if(get_cvar_pointer("allow_spectators"))
        set_cvar_num("allow_spectators", 1)

    // Competitive camera: dead players can ONLY spectate alive teammates (NO enemies)
    set_cvar_num("mp_forcecamera", 2)
    set_cvar_num("mp_forcechasecam", 2)
    set_cvar_num("mp_fadetoblack", 0)

    // Green ScreenFade Heartbeat & Prominent LIVE notice
    StartLiveGreenPulse()

    client_print_color(0, print_team_default, "^4%s ^4* * * LIVE! LIVE! LIVE! * * * ^1Good Luck & Have Fun!", g_szChatPrefix)
    client_print_color(0, print_team_default, "^4%s ^1Voice mode set to ^3Team Talk (Dead+Alive) + Spec All ^4[/t3 /s1]^1.", g_szChatPrefix)
    client_print_color(0, print_team_default, "^4%s ^1Current Score: ^4CT %d ^1- ^4%d TR ^1(Target: %d)", g_szChatPrefix, g_iScore[CT_SCORE], g_iScore[TERO_SCORE], g_iMixEndRound)
}

public Task_PostHalftimeSync()
{
    SyncTeamScores()
    RestoreHalftimePlayerStats()
}

// -----------------------------------------------------------------------------
// Score Synchronization & Stat Restoration
// -----------------------------------------------------------------------------
stock SyncTeamScores()
{
    if(g_iMatchState != STATE_FIRST_HALF && g_iMatchState != STATE_SECOND_HALF &&
       g_iMatchState != STATE_OVERTIME_FIRST_HALF && g_iMatchState != STATE_OVERTIME_SECOND_HALF)
    {
        return
    }

    // Synchronize ReGameDLL game rules internal round counters
    set_member_game(m_iNumCTWins, g_iScore[CT_SCORE])
    set_member_game(m_iNumTerroristWins, g_iScore[TERO_SCORE])

    // Update ReGameDLL engine scores (bAdd = false -> direct assignment)
    rg_update_teamscores(g_iScore[CT_SCORE], g_iScore[TERO_SCORE], false)

    // Broadcast TeamScore network message to synchronize in-game TAB scoreboard
    static iMsgTeamScore
    if(!iMsgTeamScore)
        iMsgTeamScore = get_user_msgid("TeamScore")

    if(iMsgTeamScore > 0)
    {
        message_begin(MSG_ALL, iMsgTeamScore)
        write_string("CT")
        write_short(g_iScore[CT_SCORE])
        message_end()

        message_begin(MSG_ALL, iMsgTeamScore)
        write_string("TERRORIST")
        write_short(g_iScore[TERO_SCORE])
        message_end()
    }

    UpdateServerHostname()
}

stock SyncPlayerScore(id)
{
    if(!is_user_connected(id))
        return

    static iMsgTeamScore
    if(!iMsgTeamScore)
        iMsgTeamScore = get_user_msgid("TeamScore")

    if(iMsgTeamScore > 0)
    {
        message_begin(MSG_ONE, iMsgTeamScore, _, id)
        write_string("CT")
        write_short(g_iScore[CT_SCORE])
        message_end()

        message_begin(MSG_ONE, iMsgTeamScore, _, id)
        write_string("TERRORIST")
        write_short(g_iScore[TERO_SCORE])
        message_end()
    }
}

stock RestoreHalftimePlayerStats()
{
    SyncTeamScores()

    static iMsgScoreInfo
    if(!iMsgScoreInfo)
        iMsgScoreInfo = get_user_msgid("ScoreInfo")

    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i]
        if(!is_user_connected(id))
            continue

        // Restore saved player frags and deaths from before restart if saved
        if(g_iSavedFrags[id] > 0 || g_iSavedDeaths[id] > 0)
        {
            set_entvar(id, var_frags, float(g_iSavedFrags[id]))
            set_member(id, m_iDeaths, g_iSavedDeaths[id])
        }

        // Ensure pistol round starting money ($800)
        rg_add_account(id, 800, AS_SET, true)

        // Broadcast updated ScoreInfo so TAB scoreboard updates immediately
        if(iMsgScoreInfo > 0)
        {
            message_begin(MSG_ALL, iMsgScoreInfo)
            write_byte(id)
            write_short(g_iSavedFrags[id])
            write_short(g_iSavedDeaths[id])
            write_short(0)
            write_short(_:get_member(id, m_iTeam))
            message_end()
        }
    }
}

// -----------------------------------------------------------------------------
// Overtime Execution
// -----------------------------------------------------------------------------
public StartOvertime()
{
    g_iMatchState = STATE_OVERTIME_FIRST_HALF
    g_iOvertimeScore[CT_SCORE] = 0
    g_iOvertimeScore[TERO_SCORE] = 0

    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i]
        g_iSavedFrags[id] = floatround(Float:get_entvar(id, var_frags))
        g_iSavedDeaths[id] = get_member(id, m_iDeaths)
    }
    g_bHalftimePendingSync = true

    rg_restart_round()
    SyncTeamScores()
    set_task(1.0, "Task_PostHalftimeSync")
    client_print_color(0, print_team_default, "^4%s ^1Overtime First Half is ^4LIVE! ^1MR%d (Score: CT %d - %d TR)", g_szChatPrefix, g_iOvertimeRounds, g_iScore[CT_SCORE], g_iScore[TERO_SCORE])
}

TriggerOvertimeHalftime()
{
    g_iMatchState = STATE_OVERTIME_SECOND_HALF

    new iTemp = g_iScore[CT_SCORE]
    g_iScore[CT_SCORE] = g_iScore[TERO_SCORE]
    g_iScore[TERO_SCORE] = iTemp

    new iTempOT = g_iOvertimeScore[CT_SCORE]
    g_iOvertimeScore[CT_SCORE] = g_iOvertimeScore[TERO_SCORE]
    g_iOvertimeScore[TERO_SCORE] = iTempOT

    rg_swap_all_players()

    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i]
        g_iSavedFrags[id] = floatround(Float:get_entvar(id, var_frags))
        g_iSavedDeaths[id] = get_member(id, m_iDeaths)
    }
    g_bHalftimePendingSync = true

    new iFirstWait = (g_iFreezeTimeSwap > 0) ? g_iFreezeTimeSwap : 7
    SyncTeamScores()
    set_cvar_num("mp_freezetime", iFirstWait)
    rg_restart_round()
    RestoreHalftimePlayerStats()

    client_print_color(0, print_team_default, "^4%s ^1=== ^4OVERTIME HALF TIME ^1=== Teams Swapped!", g_szChatPrefix)
    set_dhudmessage(255, 150, 0, -1.0, 0.35, 2, 0.1, 4.0, 0.1, 1.0)
    show_dhudmessage(0, "=== OVERTIME HALF TIME ===\nTeams Swapped!\nScore: CT %d - %d TR\nRestarts: 7s -> 5s -> 3s (LIVE)", g_iScore[CT_SCORE], g_iScore[TERO_SCORE])

    remove_task(TASK_HALFTIME_LIVE)
    set_task(float(iFirstWait), "Task_HalftimeRestart1", TASK_HALFTIME_LIVE)
}

// -----------------------------------------------------------------------------
// Match End
// -----------------------------------------------------------------------------
EndMatch(TeamName:iWinnerTeam)
{
    new iDuration = get_systime() - g_iMatchStartTime

    if(iWinnerTeam == TEAM_CT)
    {
        client_print_color(0, print_team_default, "^4%s ^3* * * ^4CONGRATULATIONS TO COUNTER-TERRORISTS! ^3* * *", g_szChatPrefix)
        client_print_color(0, print_team_default, "^4%s ^1Counter-Terrorists won the match with score ^4%d ^1- ^3%d^1! GG WP!", g_szChatPrefix, g_iScore[CT_SCORE], g_iScore[TERO_SCORE])
    }
    else if(iWinnerTeam == TEAM_TERRORIST)
    {
        client_print_color(0, print_team_default, "^4%s ^3* * * ^4CONGRATULATIONS TO TERRORISTS! ^3* * *", g_szChatPrefix)
        client_print_color(0, print_team_default, "^4%s ^1Terrorists won the match with score ^4%d ^1- ^3%d^1! GG WP!", g_szChatPrefix, g_iScore[TERO_SCORE], g_iScore[CT_SCORE])
    }
    else
    {
        client_print_color(0, print_team_default, "^4%s ^1Match ended in a ^3DRAW ^1(%d - %d)!", g_szChatPrefix, g_iScore[CT_SCORE], g_iScore[TERO_SCORE])
    }

    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_END_SCORE",
        LANG_SERVER, "CT_TEAM", g_iScore[CT_SCORE],
        LANG_SERVER, "TERO_TEAM", g_iScore[TERO_SCORE])

    // Forward winners to other plugins
    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i]
        if(get_member(id, m_iTeam) == iWinnerTeam)
        {
            ExecuteForward(g_hFwdMatchWinner, g_iRet, id)
        }
    }

    ExecuteForward(g_hFwdGameOver, g_iRet, 0, iDuration, iWinnerTeam == TEAM_CT ? 'C' : 'T', 0)

    // Start Victory Heartbeat / Pulsing ScreenFade Celebration ("Heartbeat Pulse")
    g_iVictoryWinnerTeam = iWinnerTeam
    g_iVictoryPulseCount = 0

    remove_task(TASK_VICTORY_PULSE)
    remove_task(TASK_SHOW_LEADERBOARD)
    remove_task(TASK_MATCH_END)

    Task_VictoryPulse()

    // Trigger professional Post-Match Map Vote after 10 seconds of celebration!
    set_task(10.0, "StartPostMatchMapVote", TASK_MATCH_END)
}

public Task_VictoryPulse()
{
    g_iVictoryPulseCount++

    new r, g, b
    if(g_iVictoryWinnerTeam == TEAM_TERRORIST)
    {
        // Pulsing Crimson Red for Terrorists
        r = 230
        g = 25
        b = 25
    }
    else if(g_iVictoryWinnerTeam == TEAM_CT)
    {
        // Pulsing Vibrant Blue for Counter-Terrorists
        r = 25
        g = 120
        b = 245
    }
    else
    {
        // Draw: Golden Yellow
        r = 240
        g = 190
        b = 20
    }

    // ScreenFade message (0.5s fade-in, 0.25s hold, FFADE_IN fade out to clear screen)
    if(g_iMsgScreenFade > 0)
    {
        message_begin(MSG_ALL, g_iMsgScreenFade)
        write_short((1<<12) / 2) // Duration: 0.5s
        write_short((1<<12) / 4) // Hold: 0.25s
        write_short(0x0000)      // FFADE_IN (fade back to normal screen)
        write_byte(r)
        write_byte(g)
        write_byte(b)
        write_byte(130)          // Alpha intensity
        message_end()
    }

    // Play official victory sound on first pulse, and audio bells on remaining pulses
    if(g_iVictoryPulseCount == 1)
    {
        if(g_iVictoryWinnerTeam == TEAM_TERRORIST)
        {
            rg_send_audio(0, "radio/terwin.wav")
        }
        else if(g_iVictoryWinnerTeam == TEAM_CT)
        {
            rg_send_audio(0, "radio/ctwin.wav")
        }
    }
    else
    {
        client_cmd(0, "spk buttons/bell1")
    }

    // Dynamic congratulatory DHUD banner
    if(g_iVictoryWinnerTeam == TEAM_TERRORIST)
    {
        set_dhudmessage(255, 40, 40, -1.0, 0.28, 2, 0.05, 0.7, 0.05, 0.1)
        show_dhudmessage(0, "* * * TERRORISTS VICTORY! * * *\nScore: %d - %d\nCongratulations to Terrorists!", g_iScore[TERO_SCORE], g_iScore[CT_SCORE])
    }
    else if(g_iVictoryWinnerTeam == TEAM_CT)
    {
        set_dhudmessage(40, 140, 255, -1.0, 0.28, 2, 0.05, 0.7, 0.05, 0.1)
        show_dhudmessage(0, "* * * COUNTER-TERRORISTS VICTORY! * * *\nScore: %d - %d\nCongratulations to Counter-Terrorists!", g_iScore[CT_SCORE], g_iScore[TERO_SCORE])
    }
    else
    {
        set_dhudmessage(255, 215, 0, -1.0, 0.28, 2, 0.05, 0.7, 0.05, 0.1)
        show_dhudmessage(0, "* * * MATCH DRAW! * * *\nScore: %d - %d\nWell Played Everyone!", g_iScore[CT_SCORE], g_iScore[TERO_SCORE])
    }

    // Pulse 5 times (every 0.75 seconds = ~3.75s)
    if(g_iVictoryPulseCount < 5)
    {
        set_task(0.75, "Task_VictoryPulse", TASK_VICTORY_PULSE)
    }
    else
    {
        // After pulsing completes, show leaderboard MOTD and print chat stats
        set_task(0.5, "Task_ShowMatchLeaderboard", TASK_SHOW_LEADERBOARD)
    }
}

public Task_ShowMatchLeaderboard()
{
    // Collect all participating human players
    new iPlayerList[MAX_PLAYERS]
    new iPlayerScores[MAX_PLAYERS]
    new iTotalCount = 0

    for(new id = 1; id <= MAX_PLAYERS; id++)
    {
        if(!is_user_connected(id) || is_user_bot(id))
            continue

        new TeamName:iTeam = get_member(id, m_iTeam)
        if(iTeam != TEAM_TERRORIST && iTeam != TEAM_CT)
            continue

        iPlayerList[iTotalCount] = id
        // Weighted Score: Kills*3 + HS*2 + Knife*5 + Plants*3 + Defuses*3 - Deaths
        iPlayerScores[iTotalCount] = (g_iMatchKills[id] * 3) + (g_iMatchHS[id] * 2) + (g_iMatchKnifeKills[id] * 5) + (g_iMatchPlants[id] * 3) + (g_iMatchDefuses[id] * 3) - g_iMatchDeaths[id]
        iTotalCount++
    }

    if(iTotalCount == 0)
        return

    // Sort descending by score
    for(new i = 0; i < iTotalCount - 1; i++)
    {
        for(new j = i + 1; j < iTotalCount; j++)
        {
            if(iPlayerScores[j] > iPlayerScores[i] || (iPlayerScores[j] == iPlayerScores[i] && g_iMatchKills[iPlayerList[j]] > g_iMatchKills[iPlayerList[i]]))
            {
                new iTempScore = iPlayerScores[i]
                iPlayerScores[i] = iPlayerScores[j]
                iPlayerScores[j] = iTempScore

                new iTempId = iPlayerList[i]
                iPlayerList[i] = iPlayerList[j]
                iPlayerList[j] = iTempId
            }
        }
    }

    // Winner details
    new szWinnerTitle[32], szWinnerColor[16]
    if(g_iVictoryWinnerTeam == TEAM_CT)
    {
        copy(szWinnerTitle, charsmax(szWinnerTitle), "Counter-Terrorists")
        copy(szWinnerColor, charsmax(szWinnerColor), "#58a6ff")
    }
    else if(g_iVictoryWinnerTeam == TEAM_TERRORIST)
    {
        copy(szWinnerTitle, charsmax(szWinnerTitle), "Terrorists")
        copy(szWinnerColor, charsmax(szWinnerColor), "#ff7b72")
    }
    else
    {
        copy(szWinnerTitle, charsmax(szWinnerTitle), "DRAW")
        copy(szWinnerColor, charsmax(szWinnerColor), "#ffd700")
    }

    // Build ultra-compact, professional HTML table (under 1100 bytes for GoldSrc safety)
    static szHtml[1500]
    new iLen = 0

    iLen += formatex(szHtml[iLen], charsmax(szHtml) - iLen,
        "<body bgcolor='#0e1117' text='#c9d1d9' style='font-family:Tahoma,sans-serif;font-size:11px;margin:8px;text-align:center'>")
    iLen += formatex(szHtml[iLen], charsmax(szHtml) - iLen,
        "<h3 style='color:#f5a623;margin:2px'>* GAMELAND 5v5 MATCH MVP & STATS *</h3>")
    iLen += formatex(szHtml[iLen], charsmax(szHtml) - iLen,
        "<font color='#8b949e'>Winner: <b style='color:%s'>%s</b> | Score: <b>CT %d : %d TR</b></font><br><br>",
        szWinnerColor, szWinnerTitle, g_iScore[CT_SCORE], g_iScore[TERO_SCORE])

    iLen += formatex(szHtml[iLen], charsmax(szHtml) - iLen,
        "<table width='100%%' border='1' bordercolor='#30363d' cellpadding='3' cellspacing='0' style='font-size:10px;text-align:center'>")
    iLen += formatex(szHtml[iLen], charsmax(szHtml) - iLen,
        "<tr bgcolor='#161b22' style='color:#58a6ff'><th>#</th><th align='left'>Player</th><th>K</th><th>D</th><th>K/D</th><th>HS</th><th>Knf</th><th>Plt</th><th>Def</th><th>Pts</th></tr>")

    new iMaxRows = min(10, iTotalCount)
    for(new i = 0; i < iMaxRows; i++)
    {
        new id = iPlayerList[i]
        new Float:flKD = (g_iMatchDeaths[id] > 0) ? (float(g_iMatchKills[id]) / float(g_iMatchDeaths[id])) : float(g_iMatchKills[id])

        new szCleanName[20]
        copy(szCleanName, charsmax(szCleanName), g_szUserName[id])
        replace_all(szCleanName, charsmax(szCleanName), "<", "")
        replace_all(szCleanName, charsmax(szCleanName), ">", "")
        replace_all(szCleanName, charsmax(szCleanName), "'", "")

        if(i == 0)
        {
            // MVP row highlighted in Gold!
            iLen += formatex(szHtml[iLen], charsmax(szHtml) - iLen,
                "<tr bgcolor='#2e2305' style='color:#ffd700;font-weight:bold'><td>[MVP]</td><td align='left'>%s</td><td>%d</td><td>%d</td><td>%.2f</td><td>%d</td><td>%d</td><td>%d</td><td>%d</td><td>%d</td></tr>",
                szCleanName, g_iMatchKills[id], g_iMatchDeaths[id], flKD, g_iMatchHS[id], g_iMatchKnifeKills[id], g_iMatchPlants[id], g_iMatchDefuses[id], iPlayerScores[i])
        }
        else
        {
            iLen += formatex(szHtml[iLen], charsmax(szHtml) - iLen,
                "<tr><td>%d</td><td align='left'>%s</td><td>%d</td><td>%d</td><td>%.2f</td><td>%d</td><td>%d</td><td>%d</td><td>%d</td><td><b>%d</b></td></tr>",
                i + 1, szCleanName, g_iMatchKills[id], g_iMatchDeaths[id], flKD, g_iMatchHS[id], g_iMatchKnifeKills[id], g_iMatchPlants[id], g_iMatchDefuses[id], iPlayerScores[i])
        }
    }

    iLen += formatex(szHtml[iLen], charsmax(szHtml) - iLen, "</table></body>")

    // Show MOTD to each connected player
    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        show_motd(iPlayers[i], szHtml, "GAMELAND Match Summary")
    }

    // Broadcast colored chat summary with top players and MVP
    new iMvpId = iPlayerList[0]
    new Float:flMvpKD = (g_iMatchDeaths[iMvpId] > 0) ? (float(g_iMatchKills[iMvpId]) / float(g_iMatchDeaths[iMvpId])) : float(g_iMatchKills[iMvpId])

    client_print_color(0, print_team_default, "^4%s ^3========================================", g_szChatPrefix)
    client_print_color(0, print_team_default, "^4%s ^3* MATCH MVP: ^4%s ^3(Score: %d | K/D: %d/%d [%.2f])",
        g_szChatPrefix, g_szUserName[iMvpId], iPlayerScores[0], g_iMatchKills[iMvpId], g_iMatchDeaths[iMvpId], flMvpKD)

    new iChatLimit = min(3, iTotalCount)
    for(new i = 0; i < iChatLimit; i++)
    {
        new id = iPlayerList[i]
        client_print_color(0, print_team_default, "^4%s ^3#%d ^4%s ^1- ^4%d K ^1/ ^3%d D ^1(HS: ^4%d^1, Knife: ^4%d^1, Plant: ^4%d^1, Defuse: ^4%d^1)",
            g_szChatPrefix, i + 1, g_szUserName[id], g_iMatchKills[id], g_iMatchDeaths[id], g_iMatchHS[id], g_iMatchKnifeKills[id], g_iMatchPlants[id], g_iMatchDefuses[id])
    }
    client_print_color(0, print_team_default, "^4%s ^3========================================", g_szChatPrefix)
}

// -----------------------------------------------------------------------------
// Warmup / DM1 Mode Implementation
// -----------------------------------------------------------------------------
public StartWarmup()
{
    remove_task(TASK_HALFTIME_LIVE)
    remove_task(TASK_KNIFE_COUNTDOWN)
    remove_task(TASK_LIVE_COUNTDOWN)
    remove_task(TASK_END_ROUND)
    remove_task(TASK_KNIFE_VOTE)
    remove_task(TASK_TIMEOUT_EXPIRE)
    remove_task(TASK_MIX_VOTE)
    remove_task(TASK_CW_COUNTDOWN)
    remove_task(TASK_CW_CAPTAIN_VOTE)
    remove_task(TASK_CW_PICK_TIMER)

    g_iCwReadyTimer = g_bFastTestMode ? 5 : 30
    g_iCaptainCT = 0
    g_iCaptainTR = 0
    g_iCurrentDraftTurn = 1
    g_iDraftRound = 1
    g_bAdminForceStarted = false

    for(new i = 1; i <= MAX_PLAYERS; i++)
    {
        if(is_user_connected(i))
        {
            show_menu(i, 0, "^n", 1)
        }
    }
    remove_task(TASK_VICTORY_PULSE)
    remove_task(TASK_SHOW_LEADERBOARD)
    remove_task(TASK_MATCH_END)

    g_iMatchState = STATE_WARMUP
    g_bPickMode = false
    UpdateServerHostname()
    g_bRoundScored = false
    g_bHalftimePendingSync = false
    g_iScore[CT_SCORE] = 0
    g_iScore[TERO_SCORE] = 0
    g_iFirstHalfScore[CT_SCORE] = 0
    g_iFirstHalfScore[TERO_SCORE] = 0
    g_bTeamTimeoutUsed[CT_SCORE] = false
    g_bTeamTimeoutUsed[TERO_SCORE] = false

    for(new i = 1; i <= MAX_PLAYERS; i++)
    {
        g_iSavedFrags[i] = 0
        g_iSavedDeaths[i] = 0
        g_iMatchKills[i] = 0
        g_iMatchDeaths[i] = 0
        g_iMatchHS[i] = 0
        g_iMatchKnifeKills[i] = 0
        g_iMatchPlants[i] = 0
        g_iMatchDefuses[i] = 0
    }

    set_member_game(m_iNumCTWins, 0)
    set_member_game(m_iNumTerroristWins, 0)
    rg_update_teamscores(0, 0, false)

    // Execute stop config if present
    if(g_szStopConfig[0])
    {
        server_cmd("exec %s", g_szStopConfig)
    }

    // Cache map spawns for Deathmatch random respawning
    if(g_iTotalSpawnsCT == 0 && g_iTotalSpawnsTR == 0)
    {
        LoadMapSpawns()
    }

    // Warmup gameplay rules: 1.0 minute round, Clan War style (no auto-respawn), $16,000, buy anywhere, no friendly fire
    set_cvar_num("mp_freezetime", 0)
    set_cvar_num("mp_buytime", 999)
    set_cvar_num("mp_startmoney", g_iWarmMoney)
    set_cvar_float("mp_roundtime", 1.0)
    set_cvar_num("mp_friendlyfire", 0)
    if(get_cvar_pointer("mp_semiclip")) set_cvar_num("mp_semiclip", 1)
    if(get_cvar_pointer("mp_semiclip_actions")) set_cvar_num("mp_semiclip_actions", 3)

    // Warmup camera: Free spectating permitted
    set_cvar_num("mp_forcecamera", 0)
    set_cvar_num("mp_forcechasecam", 0)
    set_cvar_num("mp_fadetoblack", 0)

    // Voice mode: Warmup is always /t1 (Alltalk 1 - everyone hears everyone)
    set_cvar_num("sv_alltalk", 1)

    if(get_cvar_pointer("mp_buy_anywhere"))
        set_cvar_num("mp_buy_anywhere", 1)

    if(get_cvar_pointer("mp_round_infinite"))
        set_cvar_string("mp_round_infinite", "0")

    if(get_cvar_pointer("mp_auto_reload_weapons"))
        set_cvar_num("mp_auto_reload_weapons", 1)

    server_cmd("sv_restart 1")

    client_print_color(0, print_team_default, "^4%s ^1WarmUp mode is now ^4ACTIVE^1! Voice set to ^4AllTalk ON ^3[/t1]^1.", g_szChatPrefix)
    client_print_color(0, print_team_default, "^4%s ^1Practice with ^4$16,000^1! For infinite instant respawns type ^3/rev1^1.", g_szChatPrefix)
}

// -----------------------------------------------------------------------------
// /mix Global Vote: Knife Round vs Direct Live
// -----------------------------------------------------------------------------
StartMixVote()
{
    remove_task(TASK_MIX_VOTE)

    g_iMixVoteKnife = 0
    g_iMixVoteLive = 0
    g_iMixVoteTimer = 10

    for(new id = 1; id <= MAX_PLAYERS; id++)
    {
        g_iPlayerMixVote[id] = 0
        g_bPlayerMixLocked[id] = false
        g_iPlayerMixSwitches[id] = 0
        g_flLastMixVoteTime[id] = 0.0
    }

    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")

    for(new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i]
        ShowMixVoteMenu(id)
    }

    set_task(1.0, "Task_MixVoteCountdown", TASK_MIX_VOTE, .flags = "b")
}

ShowMixVoteMenu(id)
{
    if(!is_user_connected(id) || is_user_bot(id) || g_bPlayerMixLocked[id])
        return

    new szMenu[512]
    new iLen = 0

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y[GAMELAND] Match Start Vote \r[%d sec]\w^n", g_iMixVoteTimer)
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d(Press selected option again to Confirm & Close)^n\d(Max 3 switches allowed)^n\r[1] Knife: %d \d| \y[2] Direct Live: %d^n^n", g_iMixVoteKnife, g_iMixVoteLive)

    if(g_iPlayerMixVote[id] == 1)
    {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y1. \y[*] \wKnife Round \y[Selected - Press 1 to Confirm] \d(%d vote%s)^n", g_iMixVoteKnife, g_iMixVoteKnife == 1 ? "" : "s")
    }
    else
    {
        new iNext = (g_iPlayerMixVote[id] == 0) ? 0 : g_iPlayerMixSwitches[id] + 1
        if(g_iPlayerMixVote[id] != 0)
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y1. \wKnife Round \d(Switch [%d/3]) \d(%d vote%s)^n", iNext, g_iMixVoteKnife, g_iMixVoteKnife == 1 ? "" : "s")
        else
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y1. \wKnife Round \y(Winner picks side) \d(%d vote%s)^n", g_iMixVoteKnife, g_iMixVoteKnife == 1 ? "" : "s")
    }

    if(g_iPlayerMixVote[id] == 2)
    {
        iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y2. \y[*] \wDirect Live \y[Selected - Press 2 to Confirm] \d(%d vote%s)^n", g_iMixVoteLive, g_iMixVoteLive == 1 ? "" : "s")
    }
    else
    {
        new iNext = (g_iPlayerMixVote[id] == 0) ? 0 : g_iPlayerMixSwitches[id] + 1
        if(g_iPlayerMixVote[id] != 0)
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y2. \wDirect Live \d(Switch [%d/3]) \d(%d vote%s)^n", iNext, g_iMixVoteLive, g_iMixVoteLive == 1 ? "" : "s")
        else
            iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y2. \wDirect Live \y(Start match now) \d(%d vote%s)^n", g_iMixVoteLive, g_iMixVoteLive == 1 ? "" : "s")
    }

    show_menu(id, MENU_KEY_1 | MENU_KEY_2, szMenu, -1, MIX_VOTE_MENU_ID)
}

public HandleMixVoteMenu(id, key)
{
    if(!task_exists(TASK_MIX_VOTE) || !is_user_connected(id) || g_bPlayerMixLocked[id])
        return PLUGIN_HANDLED

    new Float:flGameTime = get_gametime()
    if(flGameTime - g_flLastMixVoteTime[id] < 0.35)
        return PLUGIN_HANDLED
    g_flLastMixVoteTime[id] = flGameTime

    new iChoice = key + 1 // 0 -> 1 (Knife), 1 -> 2 (Live)

    // 1. Re-press the same option -> Confirm & Lock & Close
    if(g_iPlayerMixVote[id] == iChoice)
    {
        g_bPlayerMixLocked[id] = true
        show_menu(id, 0, "^n", 1)
        client_cmd(id, "spk buttons/blip1")

        client_print_color(id, print_team_default, "^4%s ^1Your vote for ^3%s ^1is ^4CONFIRMED & LOCKED^1! (Menu closed)",
            g_szChatPrefix, (iChoice == 1) ? "Knife Round" : "Direct Live")
        return PLUGIN_HANDLED
    }

    // 2. Switch or Initial Vote
    new bool:bSwitched = (g_iPlayerMixVote[id] != 0)
    if(bSwitched)
    {
        g_iPlayerMixSwitches[id]++
    }

    if(g_iPlayerMixVote[id] == 1)
        g_iMixVoteKnife--
    else if(g_iPlayerMixVote[id] == 2)
        g_iMixVoteLive--

    if(iChoice == 1)
    {
        g_iMixVoteKnife++
        g_iPlayerMixVote[id] = 1
    }
    else
    {
        g_iMixVoteLive++
        g_iPlayerMixVote[id] = 2
    }

    new const szChoiceNames[][] = { "", "Knife Round", "Direct Live" }

    // Check max 3 switches reached
    if(g_iPlayerMixSwitches[id] >= 3)
    {
        g_bPlayerMixLocked[id] = true
        show_menu(id, 0, "^n", 1)
        client_cmd(id, "spk buttons/blip1")

        client_print_color(id, print_team_default, "^4%s ^1Max switches reached ^4(3/3)^1. Your vote for ^3%s ^1is now ^4LOCKED^1!",
            g_szChatPrefix, szChoiceNames[iChoice])
        return PLUGIN_HANDLED
    }

    if(bSwitched)
    {
        client_print_color(id, print_team_default, "^4%s ^1Switched to ^3%s ^1(Switch ^4%d/3^1). ^2Press %d again to Confirm & Lock^1.",
            g_szChatPrefix, szChoiceNames[iChoice], g_iPlayerMixSwitches[id], iChoice)
    }
    else
    {
        client_print_color(id, print_team_default, "^4%s ^1Voted for ^3%s^1. ^2Press %d again to Confirm & Lock^1.",
            g_szChatPrefix, szChoiceNames[iChoice], iChoice)
    }

    // Update only this player's menu immediately
    ShowMixVoteMenu(id)

    return PLUGIN_HANDLED
}

public Task_MixVoteCountdown()
{
    g_iMixVoteTimer--

    if(g_iMixVoteTimer <= 0)
    {
        remove_task(TASK_MIX_VOTE)
        FinishMixVote()
        return
    }

    set_hudmessage(0, 200, 255, -1.0, 0.22, 0, 0.0, 0.9, 0.0, 0.1)
    show_hudmessage(0, "Match Start Vote: %d seconds left^n[1] Knife Round: %d | [2] Direct Live: %d",
        g_iMixVoteTimer, g_iMixVoteKnife, g_iMixVoteLive)

    // Keep active unlocked players synced with countdown and tallies
    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        new p = iPlayers[i]
        if(!g_bPlayerMixLocked[p])
        {
            ShowMixVoteMenu(p)
        }
    }
}

FinishMixVote()
{
    // Close menus on all players
    for(new i = 1; i <= MAX_PLAYERS; i++)
    {
        if(is_user_connected(i))
        {
            show_menu(i, 0, "^n", 1)
        }
    }

    client_print_color(0, print_team_default, "^4%s ^1Vote Finished: ^3Knife Round: %d ^1| ^4Direct Live: %d",
        g_szChatPrefix, g_iMixVoteKnife, g_iMixVoteLive)

    if(g_iMixVoteLive > g_iMixVoteKnife)
    {
        client_print_color(0, print_team_default, "^4%s ^1Winner: ^4Direct Live^1! Match countdown starting...", g_szChatPrefix)
        StartLiveCountdown()
    }
    else
    {
        client_print_color(0, print_team_default, "^4%s ^1Winner: ^3Knife Round^1! Knife round starting...", g_szChatPrefix)
        StartKnifeRound()
    }
}

// -----------------------------------------------------------------------------
// Knife Round & Side Vote Implementation (Zero HLTV / No Demo Menus)
// -----------------------------------------------------------------------------
public StartKnifeRound()
{
    g_iMatchState = STATE_KNIFE
    g_bPickMode = false
    UpdateServerHostname()
    g_bRoundScored = false
    g_iKnifeWinnerTeam = TEAM_UNASSIGNED
    g_iVoteTR = 0
    g_iVoteCT = 0
    g_bReviveMode = false

    if(g_szStopConfig[0])
    {
        server_cmd("exec %s", g_szStopConfig)
    }

    set_cvar_num("mp_freezetime", 3)
    set_cvar_num("mp_buytime", 0)
    set_cvar_float("mp_roundtime", 3.0)
    if(get_cvar_pointer("mp_semiclip")) set_cvar_num("mp_semiclip", 1)
    if(get_cvar_pointer("mp_semiclip_actions")) set_cvar_num("mp_semiclip_actions", 3)

    // Competitive camera: dead players can ONLY spectate alive teammates (NO enemies)
    set_cvar_num("mp_forcecamera", 2)
    set_cvar_num("mp_forcechasecam", 2)
    set_cvar_num("mp_fadetoblack", 0)

    if(get_cvar_pointer("mp_round_infinite"))
        set_cvar_string("mp_round_infinite", "0")

    if(get_cvar_pointer("mp_buy_anywhere"))
        set_cvar_num("mp_buy_anywhere", 0)

    if(get_cvar_pointer("mp_auto_reload_weapons"))
        set_cvar_num("mp_auto_reload_weapons", 0)

    remove_task(TASK_KNIFE_VOTE)
    remove_task(TASK_LIVE_PULSE)

    server_cmd("sv_restart 1")

    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "KNIFE_STARTED")
}

StartKnifeVote()
{
    remove_task(TASK_KNIFE_VOTE)

    g_iVoteTR = 0
    g_iVoteCT = 0
    g_iKnifeVoteTimer = g_iKnifeDelay > 0 ? g_iKnifeDelay : 10

    for(new id = 1; id <= MAX_PLAYERS; id++)
    {
        g_iPlayerKnifeVote[id] = 0
        g_bPlayerKnifeVoted[id] = false
    }

    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")

    for(new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i]
        new TeamName:team = get_member(id, m_iTeam)
        if(team == g_iKnifeWinnerTeam)
        {
            ShowKnifeSideMenu(id)
        }
    }

    set_task(1.0, "Task_KnifeVoteCountdown", TASK_KNIFE_VOTE, .flags = "b")
}

ShowKnifeSideMenu(id)
{
    if(!is_user_connected(id) || is_user_bot(id) || g_bPlayerKnifeVoted[id])
        return

    new szMenu[512]
    new iLen = 0

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y[GAMELAND] Knife Winner - Pick Starting Side \r[%d sec]\w^n", g_iKnifeVoteTimer)
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\d(Single vote - Your click is final!)^n^n")
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y1. \r[ Terrorist ] \d(Red Side) \d(%d vote%s)^n", g_iVoteTR, g_iVoteTR == 1 ? "" : "s")
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y2. \w[ Counter-Terrorist ] \y(Blue Side) \d(%d vote%s)^n", g_iVoteCT, g_iVoteCT == 1 ? "" : "s")

    show_menu(id, MENU_KEY_1 | MENU_KEY_2, szMenu, -1, KNIFE_SIDE_MENU_ID)
}

public HandleKnifeSideMenu(id, key)
{
    if(g_iMatchState != STATE_KNIFE || !task_exists(TASK_KNIFE_VOTE) || !is_user_connected(id) || g_bPlayerKnifeVoted[id])
        return PLUGIN_HANDLED

    // Single-Vote: mark voted immediately so player cannot click again
    g_bPlayerKnifeVoted[id] = true

    new iChoice = key + 1 // 0 -> 1 (TR), 1 -> 2 (CT)
    g_iPlayerKnifeVote[id] = iChoice

    if(iChoice == 1)
        g_iVoteTR++
    else if(iChoice == 2)
        g_iVoteCT++

    // Close player's menu immediately
    show_menu(id, 0, "^n", 1)
    client_cmd(id, "spk buttons/blip1")

    client_print_color(0, print_team_default, "^4%s ^3%s ^1voted for ^4%s^1! (TR: ^3%d ^1| CT: ^4%d^1)",
        g_szChatPrefix, g_szUserName[id], (iChoice == 1) ? "Terrorist" : "Counter-Terrorist", g_iVoteTR, g_iVoteCT)

    // Check if all winning players have finished voting
    new iPlayers[MAX_PLAYERS], iNum, iWinningTotal = 0, iVotedTotal = 0
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        new p = iPlayers[i]
        if(get_member(p, m_iTeam) == g_iKnifeWinnerTeam)
        {
            iWinningTotal++
            if(g_bPlayerKnifeVoted[p])
            {
                iVotedTotal++
            }
        }
    }

    if(iWinningTotal > 0 && iVotedTotal >= iWinningTotal)
    {
        remove_task(TASK_KNIFE_VOTE)
        FinishKnifeVote()
        return PLUGIN_HANDLED
    }

    return PLUGIN_HANDLED
}

public Task_KnifeVoteCountdown()
{
    g_iKnifeVoteTimer--

    if(g_iKnifeVoteTimer <= 0)
    {
        remove_task(TASK_KNIFE_VOTE)
        FinishKnifeVote()
        return
    }

    set_hudmessage(0, 200, 255, -1.0, 0.25, 0, 0.0, 0.9, 0.0, 0.1)
    show_hudmessage(0, "Side Choice Vote: %d seconds left^nTerrorist (Red): %d | Counter-Terrorist (Blue): %d", g_iKnifeVoteTimer, g_iVoteTR, g_iVoteCT)

    // Only update menu for winning team players who have NOT voted yet
    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        new p = iPlayers[i]
        if(get_member(p, m_iTeam) == g_iKnifeWinnerTeam && !g_bPlayerKnifeVoted[p])
        {
            ShowKnifeSideMenu(p)
        }
    }
}

FinishKnifeVote()
{
    remove_task(TASK_KNIFE_VOTE)

    // Close menus on all players
    for(new i = 1; i <= MAX_PLAYERS; i++)
    {
        if(is_user_connected(i))
        {
            show_menu(i, 0, "^n", 1)
        }
    }

    new TeamName:iChosenSide
    if(g_iVoteTR > g_iVoteCT)
        iChosenSide = TEAM_TERRORIST
    else if(g_iVoteCT > g_iVoteTR)
        iChosenSide = TEAM_CT
    else
        iChosenSide = (g_iKnifeWinnerTeam != TEAM_UNASSIGNED) ? g_iKnifeWinnerTeam : TEAM_CT

    client_print_color(0, print_team_default, "^4%s ^1Winning team chose: ^4%s^1! (TR: ^3%d ^1votes | CT: ^4%d ^1votes)",
        g_szChatPrefix, (iChosenSide == TEAM_TERRORIST) ? "Terrorist" : "Counter-Terrorist", g_iVoteTR, g_iVoteCT)

    // If the winning team selected a different side than their current one, swap!
    if(g_iKnifeWinnerTeam != iChosenSide && g_iKnifeWinnerTeam != TEAM_UNASSIGNED)
    {
        client_print_color(0, print_team_default, "^4%s ^1Swapping teams to match chosen side!", g_szChatPrefix)
        rg_swap_all_players()
    }
    else
    {
        client_print_color(0, print_team_default, "^4%s ^1Teams stay on their current sides!", g_szChatPrefix)
    }

    // Direct transition into LIVE match countdown
    StartLiveCountdown()
}

// -----------------------------------------------------------------------------
// Live Match Countdown & Start
// -----------------------------------------------------------------------------
StartLiveCountdown()
{
    g_bPickMode = false
    UpdateServerHostname()
    remove_task(TASK_LIVE_COUNTDOWN)

    set_cvar_num("mp_freezetime", 2)

    // Competitive camera: dead players can ONLY spectate alive teammates (NO enemies)
    set_cvar_num("mp_forcecamera", 2)
    set_cvar_num("mp_forcechasecam", 2)
    set_cvar_num("mp_fadetoblack", 0)

    // Restart 1
    server_cmd("sv_restart 1")
    set_dhudmessage(255, 140, 0, -1.0, 0.35, 1, 0.1, 2.0, 0.05, 0.1)
    show_dhudmessage(0, "--- RESTART 1/3 ---^nMatch starting soon...")
    client_cmd(0, "spk buttons/bell1")

    set_task(2.5, "Task_LiveRestart2", TASK_LIVE_COUNTDOWN)
}

public Task_LiveRestart2()
{
    // Restart 2
    server_cmd("sv_restart 1")
    set_dhudmessage(255, 200, 0, -1.0, 0.35, 1, 0.1, 2.0, 0.05, 0.1)
    show_dhudmessage(0, "--- RESTART 2/3 ---^nFinal restart in 2.5 seconds...")
    client_cmd(0, "spk buttons/bell1")

    set_task(2.5, "Task_LiveRestart3", TASK_LIVE_COUNTDOWN)
}

public Task_LiveRestart3()
{
    // Final Restart 3 -> Directly enters LIVE with Green ScreenFade Pulse!
    StartMatchLive()
}

// -----------------------------------------------------------------------------
// Live Pulsing Green ScreenFade & Announcement ("Green Heartbeat Pulse")
// -----------------------------------------------------------------------------
stock StartLiveGreenPulse()
{
    g_iLivePulseCount = 0
    remove_task(TASK_LIVE_PULSE)
    Task_LiveGreenPulse()
}

public Task_LiveGreenPulse()
{
    g_iLivePulseCount++

    // Neon Green pulsing ScreenFade
    if(g_iMsgScreenFade > 0)
    {
        message_begin(MSG_ALL, g_iMsgScreenFade)
        write_short((1<<12) / 2) // Duration: 0.5s fade
        write_short((1<<12) / 4) // Hold: 0.25s
        write_short(0x0000)      // FFADE_IN (fade back to normal)
        write_byte(20)           // R
        write_byte(235)          // G
        write_byte(40)           // B
        write_byte(125)          // Alpha intensity
        message_end()
    }

    client_cmd(0, "spk buttons/bell1")

    set_dhudmessage(0, 255, 50, -1.0, 0.35, 2, 0.1, 0.7, 0.05, 0.1)
    show_dhudmessage(0, "* * * LIVE! LIVE! LIVE! * * *^nGood Luck & Have Fun!")

    if(g_iLivePulseCount < 4)
    {
        set_task(0.75, "Task_LiveGreenPulse", TASK_LIVE_PULSE)
    }
}

StartMatchLive()
{
    g_iMatchState = STATE_FIRST_HALF
    g_bPickMode = false
    UpdateServerHostname()
    g_iScore[CT_SCORE] = 0
    g_iScore[TERO_SCORE] = 0
    g_iFirstHalfScore[CT_SCORE] = 0
    g_iFirstHalfScore[TERO_SCORE] = 0
    g_bHalftimePendingSync = false
    g_bRoundScored = false
    g_bTeamTimeoutUsed[CT_SCORE] = false
    g_bTeamTimeoutUsed[TERO_SCORE] = false
    g_iMatchStartTime = get_systime()

    for(new i = 1; i <= MAX_PLAYERS; i++)
    {
        g_iSavedFrags[i] = 0
        g_iSavedDeaths[i] = 0
    }

    SyncTeamScores()

    if(g_szStartConfig[0])
    {
        server_cmd("exec %s", g_szStartConfig)
    }

    set_cvar_num("mp_freezetime", 15)
    set_cvar_num("mp_buytime", 15)
    set_cvar_num("mp_startmoney", 800)
    set_cvar_float("mp_roundtime", 1.75)
    set_cvar_num("mp_friendlyfire", 0)

    // Competitive camera: dead players can ONLY spectate alive teammates (NO enemies)
    set_cvar_num("mp_forcecamera", 2)
    set_cvar_num("mp_forcechasecam", 2)
    set_cvar_num("mp_fadetoblack", 0)

    if(get_cvar_pointer("mp_buy_anywhere"))
        set_cvar_num("mp_buy_anywhere", 0)

    if(get_cvar_pointer("mp_round_infinite"))
        set_cvar_string("mp_round_infinite", "0")

    if(get_cvar_pointer("mp_auto_reload_weapons"))
        set_cvar_num("mp_auto_reload_weapons", 0)

    // Voice mode: Competitive match is always /t3 (sv_alltalk 3: teammates hear each other, spec hears all)
    set_cvar_num("sv_alltalk", 3)
    if(get_cvar_pointer("allow_spectators"))
        set_cvar_num("allow_spectators", 1)

    g_bReviveMode = false
    server_cmd("sv_restart 1")

    // Green ScreenFade Heartbeat & Prominent LIVE notice
    StartLiveGreenPulse()

    client_print_color(0, print_team_default, "^4%s ^4* * * LIVE! LIVE! LIVE! * * * ^1Good Luck & Have Fun!", g_szChatPrefix)

    ExecuteForward(g_hFwdGameBeginPre, g_iRet)

    // Notify post forward for all connected players
    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        new id = iPlayers[i]
        new szAuth[36]
        get_user_authid(id, szAuth, charsmax(szAuth))
        ExecuteForward(g_hFwdGameBeginPost, g_iRet, id, (i == iNum - 1) ? 1 : 0, szAuth, g_szUserName[id], 0)
    }
}

// -----------------------------------------------------------------------------
// HUD Display & Status Banner
// -----------------------------------------------------------------------------
public Task_HudDisplay()
{
    static szMsg[256]

    if(g_iMatchState == STATE_CAPTAIN_COUNTDOWN)
    {
        formatex(szMsg, charsmax(szMsg), "== [ 10 PLAYERS READY ] ==^nCaptain Election in: %d seconds...", g_iCwReadyTimer)
        set_hudmessage(255, 200, 0, -1.0, 0.015, 0, 0.0, 1.1, 0.0, 0.0)
        ShowSyncHudMsg(0, g_iHudSync, szMsg)
        return
    }
    else if(g_iMatchState == STATE_CAPTAIN_VOTE)
    {
        formatex(szMsg, charsmax(szMsg), "== [ CAPTAIN ELECTION ] ==^nVoting ends in: %d seconds", g_iCaptVoteTimer)
        set_hudmessage(0, 220, 255, -1.0, 0.015, 0, 0.0, 1.1, 0.0, 0.0)
        ShowSyncHudMsg(0, g_iHudSync, szMsg)
        return
    }
    else if(g_iMatchState == STATE_PICKING)
    {
        new activeCapt = (g_iCurrentDraftTurn == 1) ? g_iCaptainCT : g_iCaptainTR
        new szTeamName[32]
        copy(szTeamName, charsmax(szTeamName), (g_iCurrentDraftTurn == 1) ? "CT" : "TR")
        formatex(szMsg, charsmax(szMsg), "== [ TEAM DRAFT: ROUND %d / 7 ] ==^nTurn: Captain %s (%s) [%d s]",
            g_iDraftRound, g_szUserName[activeCapt], szTeamName, g_iPickTimer)
        set_hudmessage(255, 170, 0, -1.0, 0.015, 0, 0.0, 1.1, 0.0, 0.0)
        ShowSyncHudMsg(0, g_iHudSync, szMsg)
        return
    }
    else if(g_bPickMode)
    {
        formatex(szMsg, charsmax(szMsg), "== [ CAPTAIN PICK ] ==^nPick Teams (/a, /st, /spec)")
        set_hudmessage(255, 200, 0, -1.0, 0.015, 0, 0.0, 1.1, 0.0, 0.0)
        ShowSyncHudMsg(0, g_iHudSync, szMsg)
        return
    }

    switch(g_iMatchState)
    {
        case STATE_WARMUP:
        {
            new iInGame = GetActiveInGamePlayerCount()
            if(iInGame >= 10)
            {
                StartCaptainCountdown()
                return
            }

            if(g_bReviveMode)
            {
                formatex(szMsg, charsmax(szMsg), "== [ CW WARMUP (10 SLOTS) - REVIVE ON ] ==^nWaiting for 10 Players: [ %d / 10 ]^n(Admins can type /cw to force start)", iInGame)
                set_hudmessage(0, 255, 120, -1.0, 0.015, 0, 0.0, 1.1, 0.0, 0.0)
            }
            else
            {
                formatex(szMsg, charsmax(szMsg), "== [ CLAN WAR WARMUP (10 SLOTS) ] ==^nWaiting for 10 Players: [ %d / 10 ]^n(Admins can type /cw to force start)", iInGame)
                set_hudmessage(0, 220, 255, -1.0, 0.015, 0, 0.0, 1.1, 0.0, 0.0)
            }
            ShowSyncHudMsg(0, g_iHudSync, szMsg)
        }
        case STATE_KNIFE:
        {
            formatex(szMsg, charsmax(szMsg), "== [ KNIFE ROUND ] ==")
            set_hudmessage(255, 170, 0, -1.0, 0.015, 0, 0.0, 1.1, 0.0, 0.0)
            ShowSyncHudMsg(0, g_iHudSync, szMsg)
        }
        case STATE_FIRST_HALF, STATE_SECOND_HALF, STATE_OVERTIME_FIRST_HALF, STATE_OVERTIME_SECOND_HALF:
        {
            new iPlayers[MAX_PLAYERS], iNum
            get_players(iPlayers, iNum, "ch")

            for(new p = 0; p < iNum; p++)
            {
                new id = iPlayers[p]
                new iTarget = id

                if(!is_user_alive(id))
                {
                    new iSpec = get_entvar(id, var_iuser2)
                    if(1 <= iSpec <= MAX_PLAYERS && is_user_alive(iSpec))
                    {
                        iTarget = iSpec
                    }
                }

                new szCards[64] = ""
                new iKills = (1 <= iTarget <= MAX_PLAYERS && is_user_alive(iTarget)) ? g_iRoundKills[iTarget] : 0

                // Single dynamic kill badge replacing itself in place: 1 -> 2 -> 3 -> 4 -> ACE
                if(iKills == 1)
                    copy(szCards, charsmax(szCards), "^n[ 1 ]")
                else if(iKills == 2)
                    copy(szCards, charsmax(szCards), "^n[ 2 ]")
                else if(iKills == 3)
                    copy(szCards, charsmax(szCards), "^n[ 3 ]")
                else if(iKills == 4)
                    copy(szCards, charsmax(szCards), "^n[ 4 ]")
                else if(iKills >= 5)
                    copy(szCards, charsmax(szCards), "^n[ * ACE * ]")

                if(g_iMatchState == STATE_FIRST_HALF)
                {
                    formatex(szMsg, charsmax(szMsg), "== [ 1st HALF ] ==^nCT [ %d ]  :  [ %d ] TR%s",
                        g_iScore[CT_SCORE], g_iScore[TERO_SCORE], szCards)
                    set_hudmessage(0, 255, 150, -1.0, 0.015, 0, 0.0, 1.1, 0.0, 0.0)
                }
                else if(g_iMatchState == STATE_SECOND_HALF)
                {
                    formatex(szMsg, charsmax(szMsg), "== [ 2nd HALF ] ==^nCT [ %d ]  :  [ %d ] TR%s",
                        g_iScore[CT_SCORE], g_iScore[TERO_SCORE], szCards)
                    set_hudmessage(0, 255, 150, -1.0, 0.015, 0, 0.0, 1.1, 0.0, 0.0)
                }
                else if(g_iMatchState == STATE_OVERTIME_FIRST_HALF)
                {
                    formatex(szMsg, charsmax(szMsg), "== [ OVERTIME - 1st HALF ] ==^nCT [ %d ]  :  [ %d ] TR%s",
                        g_iScore[CT_SCORE], g_iScore[TERO_SCORE], szCards)
                    set_hudmessage(255, 200, 0, -1.0, 0.015, 0, 0.0, 1.1, 0.0, 0.0)
                }
                else if(g_iMatchState == STATE_OVERTIME_SECOND_HALF)
                {
                    formatex(szMsg, charsmax(szMsg), "== [ OVERTIME - 2nd HALF ] ==^nCT [ %d ]  :  [ %d ] TR%s",
                        g_iScore[CT_SCORE], g_iScore[TERO_SCORE], szCards)
                    set_hudmessage(255, 200, 0, -1.0, 0.015, 0, 0.0, 1.1, 0.0, 0.0)
                }

                ShowSyncHudMsg(id, g_iHudSync, szMsg)
            }
        }
    }
}

// -----------------------------------------------------------------------------
// Admin & Client Commands Handlers
// -----------------------------------------------------------------------------
bool:HasAdminAccess(id)
{
    if(!id)
        return true
    new iFlags = get_user_flags(id)
    if(iFlags & (ADMIN_KICK | ADMIN_BAN | ADMIN_RCON | ADMIN_CFG | ADMIN_IMMUNITY | ADMIN_LEVEL_A | ADMIN_LEVEL_B | ADMIN_LEVEL_C | ADMIN_CHAT | ADMIN_VOTE | ADMIN_PASSWORD))
        return true
    return bool:(iFlags & read_flags(g_szAdminAccess))
}

bool:HasRconOrBanAccess(id)
{
    if(!id)
        return true
    new iFlags = get_user_flags(id)
    return bool:(iFlags & ADMIN_RCON || iFlags & ADMIN_BAN || iFlags & ADMIN_IMMUNITY)
}

public Cmd_ReviveAll(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    if(g_iTotalSpawnsCT == 0 && g_iTotalSpawnsTR == 0)
    {
        LoadMapSpawns()
    }

    new iPlayers[MAX_PLAYERS], iNum, iRevived = 0
    get_players(iPlayers, iNum, "ch")

    for(new i = 0; i < iNum; i++)
    {
        new p = iPlayers[i]
        if(!is_user_alive(p))
        {
            new TeamName:team = get_member(p, m_iTeam)
            if(team == TEAM_TERRORIST || team == TEAM_CT)
            {
                rg_round_respawn(p)
                if(g_iMatchState == STATE_WARMUP)
                {
                    set_member(p, m_iAccount, 16000)
                    rg_give_item(p, "item_kevlar")
                    rg_give_item(p, "item_assaultsuit")
                }
                else if(g_iMatchState == STATE_KNIFE)
                {
                    rg_remove_all_items(p)
                    rg_give_item(p, "weapon_knife")
                    rg_give_item(p, "item_kevlar")
                }
                TeleportToRandomSpawn(p)
                iRevived++
            }
        }
    }

    new szAdmin[MAX_NAME_LENGTH]
    if(id) get_user_name(id, szAdmin, charsmax(szAdmin))
    else copy(szAdmin, charsmax(szAdmin), "Server")

    if(iRevived > 0)
    {
        client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1revived all dead players (^4%d revived^1) [/rev].", g_szChatPrefix, szAdmin, iRevived)
    }
    else
    {
        client_print_color(id, print_team_default, "^4%s ^1No dead players found to revive.", g_szChatPrefix)
    }

    return PLUGIN_HANDLED
}

public Cmd_ReviveOn(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    g_bReviveMode = true

    if(g_iTotalSpawnsCT == 0 && g_iTotalSpawnsTR == 0)
    {
        LoadMapSpawns()
    }

    if(get_cvar_pointer("mp_round_infinite"))
        set_cvar_string("mp_round_infinite", "abcdef")

    if(get_cvar_pointer("mp_buy_anywhere"))
        set_cvar_num("mp_buy_anywhere", 1)

    if(get_cvar_pointer("mp_auto_reload_weapons"))
        set_cvar_num("mp_auto_reload_weapons", 1)

    set_cvar_num("mp_freezetime", 0)
    set_cvar_num("mp_buytime", 999)
    set_cvar_num("mp_startmoney", 16000)
    set_cvar_float("mp_roundtime", 99.0)

    // Respawn all dead players immediately
    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")
    for(new i = 0; i < iNum; i++)
    {
        new p = iPlayers[i]
        if(!is_user_alive(p))
        {
            new TeamName:team = get_member(p, m_iTeam)
            if(team == TEAM_TERRORIST || team == TEAM_CT)
            {
                rg_round_respawn(p)
                set_member(p, m_iAccount, 16000)
                rg_give_item(p, "item_kevlar")
                rg_give_item(p, "item_assaultsuit")
                TeleportToRandomSpawn(p)
            }
        }
    }

    new szAdmin[MAX_NAME_LENGTH]
    if(id) get_user_name(id, szAdmin, charsmax(szAdmin))
    else copy(szAdmin, charsmax(szAdmin), "Server")

    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1enabled ^4Infinite Revive Mode ^3[/rev1]^1!", g_szChatPrefix, szAdmin)
    client_print_color(0, print_team_default, "^4%s ^1Instant Respawn ON | 1v1 Round End Blocked | $16,000 & Buy Anywhere!", g_szChatPrefix)

    return PLUGIN_HANDLED
}

public Cmd_ReviveOff(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    if(!g_bReviveMode)
    {
        if(id)
            client_print_color(id, print_team_default, "^4%s ^1Infinite Revive mode is already ^3inactive^1.", g_szChatPrefix)
        return PLUGIN_HANDLED
    }

    g_bReviveMode = false

    if(get_cvar_pointer("mp_round_infinite"))
        set_cvar_string("mp_round_infinite", "0")

    if(get_cvar_pointer("mp_buy_anywhere"))
        set_cvar_num("mp_buy_anywhere", 0)

    if(get_cvar_pointer("mp_auto_reload_weapons"))
        set_cvar_num("mp_auto_reload_weapons", 0)

    new szAdmin[MAX_NAME_LENGTH]
    if(id) get_user_name(id, szAdmin, charsmax(szAdmin))
    else copy(szAdmin, charsmax(szAdmin), "Server")

    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1disabled ^3Infinite Revive Mode ^1[/rev0]. Normal rules restored.", g_szChatPrefix, szAdmin)
    return PLUGIN_HANDLED
}

public Cmd_LegacyDm(id)
{
    client_print_color(id, print_team_default, "^4%s ^1Note: ^3/dm1 ^1was replaced! Use ^4/rev1 ^1(Infinite Revive) or ^4/rev0 ^1(Turn Off).", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^1For standard competitive warmup, use ^3/warm^1.", g_szChatPrefix)
    return PLUGIN_HANDLED
}

public Cmd_StartMix(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    g_bPickMode = false
    UpdateServerHostname()

    // Automatically deactivate Revive mode if active
    if(g_bReviveMode)
    {
        Cmd_ReviveOff(0)
    }

    if(g_iMatchState == STATE_FIRST_HALF || g_iMatchState == STATE_SECOND_HALF)
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_ALREADY_STARTED")
        return PLUGIN_HANDLED
    }

    if(task_exists(TASK_MIX_VOTE))
    {
        client_print_color(id, print_team_default, "^4%s ^1A match vote is already in progress!", g_szChatPrefix)
        return PLUGIN_HANDLED
    }

    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1started match vote: ^3[1] Knife Round ^1vs ^4[2] Direct Live^1!", g_szChatPrefix, g_szUserName[id])
    StartMixVote()
    return PLUGIN_HANDLED
}

public Cmd_DirectLive(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    g_bPickMode = false
    UpdateServerHostname()

    if(g_bReviveMode)
    {
        Cmd_ReviveOff(0)
    }

    remove_task(TASK_MIX_VOTE)
    remove_task(TASK_LIVE_COUNTDOWN)

    for(new i = 1; i <= MAX_PLAYERS; i++)
    {
        if(is_user_connected(i))
        {
            show_menu(i, 0, "^n", 1)
        }
    }

    new szAdmin[MAX_NAME_LENGTH]
    if(id) get_user_name(id, szAdmin, charsmax(szAdmin))
    else copy(szAdmin, charsmax(szAdmin), "Server")

    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1triggered ^4LIVE^1! Starting 3 Restarts...", g_szChatPrefix, szAdmin)
    StartLiveCountdown()
    return PLUGIN_HANDLED
}

public Cmd_Alltalk1(id)
{
    if(!HasAdminAccess(id)) return PLUGIN_HANDLED
    set_cvar_num("sv_alltalk", 1)
    new szAdmin[MAX_NAME_LENGTH]
    if(id) get_user_name(id, szAdmin, charsmax(szAdmin))
    else copy(szAdmin, charsmax(szAdmin), "Server")
    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1set Voice Chat to ^4AllTalk ON ^3[/t1]^1.", g_szChatPrefix, szAdmin)
    return PLUGIN_HANDLED
}

public Cmd_Alltalk2(id)
{
    if(!HasAdminAccess(id)) return PLUGIN_HANDLED
    set_cvar_num("sv_alltalk", 2)
    new szAdmin[MAX_NAME_LENGTH]
    if(id) get_user_name(id, szAdmin, charsmax(szAdmin))
    else copy(szAdmin, charsmax(szAdmin), "Server")
    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1set Voice Chat to ^4Team Only ^3[/t2]^1.", g_szChatPrefix, szAdmin)
    return PLUGIN_HANDLED
}

public Cmd_Alltalk3(id)
{
    if(!HasAdminAccess(id)) return PLUGIN_HANDLED
    set_cvar_num("sv_alltalk", 3)
    new szAdmin[MAX_NAME_LENGTH]
    if(id) get_user_name(id, szAdmin, charsmax(szAdmin))
    else copy(szAdmin, charsmax(szAdmin), "Server")
    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1set Voice Chat to ^4Team Talk (Dead+Alive) + Spec All ^3[/t3]^1.", g_szChatPrefix, szAdmin)
    return PLUGIN_HANDLED
}

public Cmd_Spec1(id)
{
    if(!HasAdminAccess(id)) return PLUGIN_HANDLED
    if(get_cvar_pointer("allow_spectators")) set_cvar_num("allow_spectators", 1)
    set_cvar_num("sv_alltalk", 3)
    new szAdmin[MAX_NAME_LENGTH]
    if(id) get_user_name(id, szAdmin, charsmax(szAdmin))
    else copy(szAdmin, charsmax(szAdmin), "Server")
    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1enabled Spectators & Spec Voice ^4[/s1 /t3]^1.", g_szChatPrefix, szAdmin)
    return PLUGIN_HANDLED
}

public Cmd_Spec0(id)
{
    if(!HasAdminAccess(id)) return PLUGIN_HANDLED
    if(get_cvar_pointer("allow_spectators")) set_cvar_num("allow_spectators", 0)
    new szAdmin[MAX_NAME_LENGTH]
    if(id) get_user_name(id, szAdmin, charsmax(szAdmin))
    else copy(szAdmin, charsmax(szAdmin), "Server")
    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1disabled Spectators ^3[/s0]^1.", g_szChatPrefix, szAdmin)
    return PLUGIN_HANDLED
}

public Cmd_StopMix(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_STOPPED_BY_X", g_szUserName[id])
    
    new iDuration = get_systime() - g_iMatchStartTime
    ExecuteForward(g_hFwdGameStopped, g_iRet, id, iDuration, 0)

    StartWarmup()
    return PLUGIN_HANDLED
}

public Cmd_Warmup(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    StartWarmup()
    return PLUGIN_HANDLED
}

public Cmd_KnifeRound(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    if(g_bReviveMode)
    {
        Cmd_ReviveOff(0)
    }

    remove_task(TASK_MIX_VOTE)
    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1forced ^3Knife Round^1!", g_szChatPrefix, g_szUserName[id])
    StartKnifeRound()
    return PLUGIN_HANDLED
}

public Cmd_Halftime(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1triggered ^3Halftime Team Swap^1!", g_szChatPrefix, g_szUserName[id])
    TriggerHalftime()
    return PLUGIN_HANDLED
}

public Cmd_Score(id)
{
    if(g_iMatchState == STATE_WARMUP)
    {
        client_print_color(id, print_team_default, "^4%s ^1Server is currently in ^4Warmup / DM1^1 mode.", g_szChatPrefix)
        return PLUGIN_HANDLED
    }

    client_print_color(id, print_team_default, "^4%s ^1Current Match Score: ^4CT %d ^1- ^4TR %d", g_szChatPrefix, g_iScore[CT_SCORE], g_iScore[TERO_SCORE])
    if(g_iMatchState == STATE_SECOND_HALF)
    {
        client_print_color(id, print_team_default, "^4%s ^1First Half Result: ^4CT %d ^3- ^4TR %d ^1| Target: ^4%d rounds",
            g_szChatPrefix, g_iFirstHalfScore[CT_SCORE], g_iFirstHalfScore[TERO_SCORE], g_iMixEndRound)
    }
    else if(g_iMatchState == STATE_FIRST_HALF)
    {
        new iRemaining = 15 - (g_iScore[CT_SCORE] + g_iScore[TERO_SCORE])
        client_print_color(id, print_team_default, "^4%s ^1First Half: ^4%d ^1rounds until Halftime swap.", g_szChatPrefix, iRemaining)
    }
    else if(g_iMatchState == STATE_OVERTIME_FIRST_HALF || g_iMatchState == STATE_OVERTIME_SECOND_HALF)
    {
        client_print_color(id, print_team_default, "^4%s ^1Overtime Round Score: ^4CT %d ^1- ^4TR %d",
            g_szChatPrefix, g_iOvertimeScore[CT_SCORE], g_iOvertimeScore[TERO_SCORE])
    }
    return PLUGIN_HANDLED
}

public Cmd_Restart(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    server_cmd("sv_restart 1")
    client_print_color(0, print_team_default, "^4%s ^1Round restarted by ^4%s^1.", g_szChatPrefix, g_szUserName[id])
    return PLUGIN_HANDLED
}

public Cmd_ChatOn(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    g_bChatMuted = false
    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "CHAT_OPENED_BY_X", g_szUserName[id])
    return PLUGIN_HANDLED
}

public Cmd_ChatOff(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    g_bChatMuted = true
    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "CHAT_CLOSED_BY_X", g_szUserName[id])
    return PLUGIN_HANDLED
}

public Cmd_PassOn(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    new szPass[32]
    read_argv(1, szPass, charsmax(szPass))
    if(!szPass[0])
        copy(szPass, charsmax(szPass), "mix")

    server_cmd("sv_password ^"%s^"", szPass)
    client_print_color(id, print_team_default, "^4%s ^1Server password set to: ^4%s", g_szChatPrefix, szPass)
    return PLUGIN_HANDLED
}

public Cmd_PassOff(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    server_cmd("sv_password ^"^"")
    client_print_color(id, print_team_default, "^4%s ^1Server password has been ^4removed^1.", g_szChatPrefix)
    return PLUGIN_HANDLED
}

public Cmd_SpecAll(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")

    for(new i = 0; i < iNum; i++)
    {
        new p = iPlayers[i]
        if(is_user_alive(p))
        {
            user_silentkill(p)
        }
        rg_set_user_team(p, TEAM_SPECTATOR)
    }

    g_bPickMode = true
    UpdateServerHostname()

    new szAdmin[MAX_NAME_LENGTH]
    if(id) get_user_name(id, szAdmin, charsmax(szAdmin))
    else copy(szAdmin, charsmax(szAdmin), "Server")

    client_print_color(0, print_team_default, "^4%s ^1Admin ^4%s ^1moved all players to Spectator.", g_szChatPrefix, szAdmin)
    client_print_color(0, print_team_default, "^4%s ^1Server is now in ^3Captain Pick Mode ^1[[Pick]]. Pick your teams and start ^4/mix^1!", g_szChatPrefix)
    return PLUGIN_HANDLED
}

public Cmd_MoveCT(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    new szTarget[32]
    read_argv(1, szTarget, charsmax(szTarget))
    new iTarget = cmd_target(id, szTarget, CMDTARGET_NO_BOTS)
    if(!iTarget)
        return PLUGIN_HANDLED

    rg_set_user_team(iTarget, TEAM_CT)
    client_print_color(0, print_team_default, "^4%s ^1Player ^4%s ^1moved to ^4CT^1 by ^4%s^1.", g_szChatPrefix, g_szUserName[iTarget], g_szUserName[id])
    return PLUGIN_HANDLED
}

public Cmd_MoveT(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    new szTarget[32]
    read_argv(1, szTarget, charsmax(szTarget))
    new iTarget = cmd_target(id, szTarget, CMDTARGET_NO_BOTS)
    if(!iTarget)
        return PLUGIN_HANDLED

    rg_set_user_team(iTarget, TEAM_TERRORIST)
    client_print_color(0, print_team_default, "^4%s ^1Player ^4%s ^1moved to ^4TERRORIST^1 by ^4%s^1.", g_szChatPrefix, g_szUserName[iTarget], g_szUserName[id])
    return PLUGIN_HANDLED
}

public Cmd_MoveSpec(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    new szTarget[32]
    read_argv(1, szTarget, charsmax(szTarget))
    new iTarget = cmd_target(id, szTarget, CMDTARGET_NO_BOTS)
    if(!iTarget)
        return PLUGIN_HANDLED

    rg_set_user_team(iTarget, TEAM_SPECTATOR)
    client_print_color(0, print_team_default, "^4%s ^1Player ^4%s ^1moved to ^4SPECTATOR^1 by ^4%s^1.", g_szChatPrefix, g_szUserName[iTarget], g_szUserName[id])
    return PLUGIN_HANDLED
}

public Cmd_Pause(id)
{
    // If admin calls pause, direct toggle
    if(HasAdminAccess(id))
    {
        if(!g_bPaused)
        {
            g_bPaused = true
            server_cmd("pausable 1; pause")
            client_print_color(0, print_team_default, "^4%s ^1Match has been ^4PAUSED^1 by Admin ^4%s^1.", g_szChatPrefix, g_szUserName[id])
        }
        else
        {
            g_bPaused = false
            server_cmd("pause; pausable 0")
            client_print_color(0, print_team_default, "^4%s ^1Match has been ^4UNPAUSED^1 by Admin ^4%s^1.", g_szChatPrefix, g_szUserName[id])
        }
        return PLUGIN_HANDLED
    }

    // Player tactical timeout request
    if(g_iMatchState != STATE_FIRST_HALF && g_iMatchState != STATE_SECOND_HALF)
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "MIX_NOT_STARTED_YET")
        return PLUGIN_HANDLED
    }

    new TeamName:team = get_member(id, m_iTeam)
    new TeamScore:tScore = (team == TEAM_CT) ? CT_SCORE : TERO_SCORE

    if(g_bTeamTimeoutUsed[tScore])
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOUR_TEAM_ALREADY_TIMEOUT")
        return PLUGIN_HANDLED
    }

    g_bTeamTimeoutUsed[tScore] = true
    g_iPauseTimer = g_iPauseDuration > 0 ? g_iPauseDuration : 60
    g_bPaused = true

    server_cmd("pausable 1; pause")
    client_print_color(0, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "PLAYER_X_REQUESTED_TIMEOUT", g_szUserName[id])

    set_task(1.0, "Task_TimeoutCountdown", TASK_TIMEOUT_EXPIRE, .flags = "b")
    return PLUGIN_HANDLED
}

public Task_TimeoutCountdown()
{
    g_iPauseTimer--

    if(g_iPauseTimer <= 0)
    {
        remove_task(TASK_TIMEOUT_EXPIRE)
        g_bPaused = false
        server_cmd("pause; pausable 0")
        client_print_color(0, print_team_default, "^4%s ^1Timeout expired! Match resumed.", g_szChatPrefix)
        return
    }

    set_hudmessage(255, 200, 0, -1.0, 0.40, 0, 0.0, 0.9, 0.0, 0.1)
    show_hudmessage(0, "Tactical Timeout: %d seconds remaining", g_iPauseTimer)
}

public Cmd_Overtime(id)
{
    if(!HasAdminAccess(id))
        return PLUGIN_HANDLED

    StartOvertime()
    return PLUGIN_HANDLED
}

public Cmd_ShowCommands(id)
{
    client_print_color(id, print_team_default, "^4%s ^1=== Available Mix Commands ===", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/a ^1: Master Admin Control Panel", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/warm ^1: Warmup Mode ($16,000 practice)", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/rev1 ^1/ ^3/rev0 ^1: Infinite Revive (instant respawn, round never ends)", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/mix ^1or ^3/start ^1: Vote Knife Round vs Direct Live", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/knife ^1: Direct Knife Round for side choice", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/live ^1: Direct Live match start", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/stop ^1: Stop match and return to warmup", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/score ^1: Show current round scores", g_szChatPrefix)
    client_print_color(id, print_team_default, "^4%s ^3/pause ^1: Request tactical timeout or pause", g_szChatPrefix)
    return PLUGIN_HANDLED
}

// -----------------------------------------------------------------------------
// MASTER /a ADMIN CONTROL PANEL & ADMIN MANAGER
// -----------------------------------------------------------------------------
public Cmd_AdminDashboard(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s %L", g_szChatPrefix, LANG_SERVER, "YOU_DONT_HAVE_ACCESS")
        return PLUGIN_HANDLED
    }

    new iMenu = menu_create("\y[GAMELAND] Master Admin Panel (/a)\w", "Menu_DashboardHandler")

    menu_additem(iMenu, "\rAdmin Manager \y(Add Admins to users.ini)\w", "1")
    menu_additem(iMenu, "\yMatch & Mix Controls \d(/mix, /live, /rev1)\w", "2")
    menu_additem(iMenu, "\wTeam Management \y(/st, /spec, /kspec)\w", "3")
    menu_additem(iMenu, "\wVoice & Server Rules \y(/t1-/t3, /ff, /j0-/j2)\w", "4")
    menu_additem(iMenu, "\wMap Browser & Vote \y(/map, /vm)\w", "5")
    menu_additem(iMenu, "\wPlayer Moderation \y(/k, /b, /ub)\w", "6")
    menu_additem(iMenu, "\wFast Server Tools \y(/r, /passon, /off)\w", "7")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
    return PLUGIN_HANDLED
}

public Menu_DashboardHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: ShowAdminManagerMenu(id)
        case 2: ShowMatchControlMenu(id)
        case 3: ShowTeamControlMenu(id)
        case 4: ShowVoiceAndRulesMenu(id)
        case 5: ShowMapControlMenu(id)
        case 6: ShowModerationMenu(id)
        case 7: ShowServerControlMenu(id)
    }
    return PLUGIN_HANDLED
}

// --- 1. ADMIN MANAGER WIZARD ---
ShowAdminManagerMenu(id)
{
    if(!HasRconOrBanAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s ^1You need ^4RCON / High Admin^1 privilege to access Admin Manager!", g_szChatPrefix)
        Cmd_AdminDashboard(id)
        return
    }

    new iMenu = menu_create("\y[GAMELAND] Admin Manager:\w", "Menu_AdminManagerHandler")

    menu_additem(iMenu, "\wAdd Admin from \yConnected Players\w", "1")
    menu_additem(iMenu, "\rRemove Admin \y(Revoke rights & remove from users.ini)\w", "2")
    menu_additem(iMenu, "\wReload Admins from \yusers.ini\w", "3")
    menu_additem(iMenu, "\d<- Back to Main Menu\w", "9")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_AdminManagerHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: ShowSelectPlayerForAdmin(id)
        case 2: ShowRemoveAdminMenu(id)
        case 3:
        {
            server_cmd("amx_reloadadmins")
            client_print_color(id, print_team_default, "^4%s ^1Admins reloaded successfully from ^4users.ini^1!", g_szChatPrefix)
            ShowAdminManagerMenu(id)
        }
        case 9: Cmd_AdminDashboard(id)
    }
    return PLUGIN_HANDLED
}

ShowRemoveAdminMenu(id)
{
    new szConfigDir[128], szUsersFile[128]
    get_configsdir(szConfigDir, charsmax(szConfigDir))
    formatex(szUsersFile, charsmax(szUsersFile), "%s/users.ini", szConfigDir)

    new iFile = fopen(szUsersFile, "rt")
    if(!iFile)
    {
        client_print_color(id, print_team_default, "^4%s ^1Could not open ^4users.ini^1!", g_szChatPrefix)
        ShowAdminManagerMenu(id)
        return
    }

    new iMenu = menu_create("\r[GAMELAND] Select Admin to Remove:\w", "Menu_RemoveAdminHandler")
    new szLine[256], szAuth[64], szPass[32], szFlags[36], szAccFlags[16]
    new iCount = 0

    while(!feof(iFile))
    {
        fgets(iFile, szLine, charsmax(szLine))
        trim(szLine)

        if(!szLine[0] || szLine[0] == ';' || szLine[0] == '#')
            continue

        szAuth[0] = EOS
        szPass[0] = EOS
        szFlags[0] = EOS
        szAccFlags[0] = EOS

        parse(szLine, szAuth, charsmax(szAuth), szPass, charsmax(szPass), szFlags, charsmax(szFlags), szAccFlags, charsmax(szAccFlags))

        if(!szAuth[0])
            continue

        if(equal(szAuth, "loopback"))
            continue

        new szItemText[96]
        formatex(szItemText, charsmax(szItemText), "\w%s \d[flags: %s]", szAuth, szFlags)
        menu_additem(iMenu, szItemText, szAuth)
        iCount++
    }
    fclose(iFile)

    if(iCount == 0)
    {
        menu_destroy(iMenu)
        client_print_color(id, print_team_default, "^4%s ^1No removable admins found in ^4users.ini^1!", g_szChatPrefix)
        ShowAdminManagerMenu(id)
        return
    }

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_RemoveAdminHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        ShowAdminManagerMenu(id)
        return PLUGIN_HANDLED
    }

    new szAuthToRemove[64], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szAuthToRemove, charsmax(szAuthToRemove), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    RemoveAdminFromFile(id, szAuthToRemove)
    return PLUGIN_HANDLED
}

stock CopyFile(const szSource[], const szDest[])
{
    new iIn = fopen(szSource, "rt")
    if(!iIn) return 0

    new iOut = fopen(szDest, "wt")
    if(!iOut)
    {
        fclose(iIn)
        return 0
    }

    new szLine[256]
    while(!feof(iIn))
    {
        szLine[0] = EOS
        fgets(iIn, szLine, charsmax(szLine))
        if(szLine[0])
        {
            fputs(iOut, szLine)
        }
    }

    fclose(iIn)
    fclose(iOut)
    return 1
}

stock RemoveAdminFromFile(id, const szTargetAuth[])
{
    new szConfigDir[128], szUsersFile[128], szTempFile[128]
    get_configsdir(szConfigDir, charsmax(szConfigDir))
    formatex(szUsersFile, charsmax(szUsersFile), "%s/users.ini", szConfigDir)
    formatex(szTempFile, charsmax(szTempFile), "%s/users_temp.ini", szConfigDir)

    new iIn = fopen(szUsersFile, "rt")
    if(!iIn)
        return

    new iOut = fopen(szTempFile, "wt")
    if(!iOut)
    {
        fclose(iIn)
        return
    }

    new szLine[256], szAuth[64], szPass[32], szFlags[36], szAccFlags[16]
    new bool:bFound = false

    while(!feof(iIn))
    {
        fgets(iIn, szLine, charsmax(szLine))
        new szTrimmed[256]
        copy(szTrimmed, charsmax(szTrimmed), szLine)
        trim(szTrimmed)

        if(szTrimmed[0] && szTrimmed[0] != ';' && szTrimmed[0] != '#')
        {
            parse(szTrimmed, szAuth, charsmax(szAuth), szPass, charsmax(szPass), szFlags, charsmax(szFlags), szAccFlags, charsmax(szAccFlags))
            if(equal(szAuth, szTargetAuth))
            {
                bFound = true
                fprintf(iOut, "; [REMOVED by %s] %s^n", g_szUserName[id], szTrimmed)
                continue
            }
        }
        fputs(iOut, szLine)
    }

    fclose(iIn)
    fclose(iOut)

    if(bFound)
    {
        delete_file(szUsersFile)
        while(!rename_file(szTempFile, szUsersFile, 1) && file_exists(szTempFile))
        {
            break
        }

        // Reload admins
        server_cmd("amx_reloadadmins")

        // Persist admin backup to /opt/gameland/persistent/users.ini
        if(dir_exists("/opt/gameland/persistent"))
        {
            new szPersistPath[128] = "/opt/gameland/persistent/users.ini"
            CopyFile(szUsersFile, szPersistPath)
        }

        // If target is connected, strip their in-memory admin flags
        new iPlayers[MAX_PLAYERS], iNum
        get_players(iPlayers, iNum, "ch")
        for(new i = 0; i < iNum; i++)
        {
            new p = iPlayers[i]
            new szPAuth[36], szPName[MAX_NAME_LENGTH]
            get_user_authid(p, szPAuth, charsmax(szPAuth))
            get_user_name(p, szPName, charsmax(szPName))

            if(equal(szPAuth, szTargetAuth) || equal(szPName, szTargetAuth))
            {
                remove_user_flags(p, read_flags("abcdefghijklmnopqrstuv"))
                client_print_color(p, print_team_default, "^4[GAMELAND] ^1Your Admin rights were ^3revoked^1 by ^4%s^1.", g_szUserName[id])
            }
        }

        client_print_color(id, print_team_default, "^4%s ^1Successfully removed admin ^4%s^1 from ^3users.ini^1!", g_szChatPrefix, szTargetAuth)
    }
    else
    {
        delete_file(szTempFile)
        client_print_color(id, print_team_default, "^4%s ^1Admin ^3%s ^1was not found in users.ini.", g_szChatPrefix, szTargetAuth)
    }

    ShowAdminManagerMenu(id)
}

ShowSelectPlayerForAdmin(id)
{
    new iMenu = menu_create("\ySelect Player to Make Admin:\w", "Menu_SelectPlayerAdminHandler")

    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")

    for(new i = 0; i < iNum; i++)
    {
        new player = iPlayers[i]
        new szInfo[6], szDisplay[96], szAuth[36]
        num_to_str(player, szInfo, charsmax(szInfo))
        get_user_authid(player, szAuth, charsmax(szAuth))

        formatex(szDisplay, charsmax(szDisplay), "\w%s \d[%s]", g_szUserName[player], szAuth)
        menu_additem(iMenu, szDisplay, szInfo)
    }

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_SelectPlayerAdminHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        ShowAdminManagerMenu(id)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    new iTarget = str_to_num(szData)
    if(!is_user_connected(iTarget))
    {
        client_print_color(id, print_team_default, "^4%s ^1Selected player is no longer connected.", g_szChatPrefix)
        ShowAdminManagerMenu(id)
        return PLUGIN_HANDLED
    }

    g_eAdminSession[id][SessionTargetId] = iTarget
    copy(g_eAdminSession[id][SessionName], charsmax(g_eAdminSession[][SessionName]), g_szUserName[iTarget])
    get_user_authid(iTarget, g_eAdminSession[id][SessionAuth], charsmax(g_eAdminSession[][SessionAuth]))

    ShowAdminPresetMenu(id)
    return PLUGIN_HANDLED
}

ShowAdminPresetMenu(id)
{
    new szTitle[96]
    formatex(szTitle, charsmax(szTitle), "\yAssign Permissions for: \w%s", g_eAdminSession[id][SessionName])
    new iMenu = menu_create(szTitle, "Menu_AdminPresetHandler")

    menu_additem(iMenu, "\rFull Owner \d[abcdefghijklmnopqrstu]", "1")
    menu_additem(iMenu, "\yHead Admin \d[abcdefghijklmnopqrst]", "2")
    menu_additem(iMenu, "\wMatch Admin \d[bcdefij]", "3")
    menu_additem(iMenu, "\wBasic Admin \d[cdeij]", "4")
    menu_additem(iMenu, "\wVIP Member \d[bit]", "5")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_AdminPresetHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        ShowAdminManagerMenu(id)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: copy(g_eAdminSession[id][SessionFlags], charsmax(g_eAdminSession[][SessionFlags]), "abcdefghijklmnopqrstu")
        case 2: copy(g_eAdminSession[id][SessionFlags], charsmax(g_eAdminSession[][SessionFlags]), "abcdefghijklmnopqrst")
        case 3: copy(g_eAdminSession[id][SessionFlags], charsmax(g_eAdminSession[][SessionFlags]), "bcdefij")
        case 4: copy(g_eAdminSession[id][SessionFlags], charsmax(g_eAdminSession[][SessionFlags]), "cdeij")
        case 5: copy(g_eAdminSession[id][SessionFlags], charsmax(g_eAdminSession[][SessionFlags]), "bit")
    }

    ShowAdminAuthTypeMenu(id)
    return PLUGIN_HANDLED
}

ShowAdminAuthTypeMenu(id)
{
    new iMenu = menu_create("\ySelect Authentication Method:\w", "Menu_AdminAuthTypeHandler")

    new szItem1[96]
    formatex(szItem1, charsmax(szItem1), "\wSteamID Auth \y[%s] \d(flag 'ce')", g_eAdminSession[id][SessionAuth])
    menu_additem(iMenu, szItem1, "1")

    new szItem2[96]
    formatex(szItem2, charsmax(szItem2), "\wNickname Auth \y[%s] \d(pass: 123456, flag 'a')", g_eAdminSession[id][SessionName])
    menu_additem(iMenu, szItem2, "2")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_AdminAuthTypeHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        ShowAdminManagerMenu(id)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    if(str_to_num(szData) == 1)
    {
        // SteamID Auth
        copy(g_eAdminSession[id][SessionAccountFlags], charsmax(g_eAdminSession[][SessionAccountFlags]), "ce")
        copy(g_eAdminSession[id][SessionPassword], charsmax(g_eAdminSession[][SessionPassword]), "")
        CommitAdminToFile(id, false)
    }
    else
    {
        // Nickname Auth
        copy(g_eAdminSession[id][SessionAccountFlags], charsmax(g_eAdminSession[][SessionAccountFlags]), "a")
        copy(g_eAdminSession[id][SessionPassword], charsmax(g_eAdminSession[][SessionPassword]), "123456")
        CommitAdminToFile(id, true)
    }
    return PLUGIN_HANDLED
}

CommitAdminToFile(id, bool:bUseNick)
{
    new szConfigDir[128], szUsersFile[128]
    get_configsdir(szConfigDir, charsmax(szConfigDir))
    formatex(szUsersFile, charsmax(szUsersFile), "%s/users.ini", szConfigDir)

    new iFile = fopen(szUsersFile, "at")
    if(!iFile)
    {
        client_print_color(id, print_team_default, "^4%s ^1Failed to open ^4users.ini^1 for writing!", g_szChatPrefix)
        return
    }

    new szAuthIdentifier[64]
    if(bUseNick)
    {
        copy(szAuthIdentifier, charsmax(szAuthIdentifier), g_eAdminSession[id][SessionName])
    }
    else
    {
        copy(szAuthIdentifier, charsmax(szAuthIdentifier), g_eAdminSession[id][SessionAuth])
    }

    fprintf(iFile, "^n^"%s^" ^"%s^" ^"%s^" ^"%s^" ; Added by %s via /a menu^n",
        szAuthIdentifier,
        g_eAdminSession[id][SessionPassword],
        g_eAdminSession[id][SessionFlags],
        g_eAdminSession[id][SessionAccountFlags],
        g_szUserName[id])

    fclose(iFile)

    // Reload admins into memory
    server_cmd("amx_reloadadmins")

    // Persist admin backup to /opt/gameland/persistent/users.ini
    if(dir_exists("/opt/gameland/persistent"))
    {
        new szPersistPath[128] = "/opt/gameland/persistent/users.ini"
        CopyFile(szUsersFile, szPersistPath)
    }

    client_print_color(id, print_team_default, "^4%s ^1Successfully added ^4%s ^1as Admin!", g_szChatPrefix, g_eAdminSession[id][SessionName])
    client_print_color(id, print_team_default, "^4%s ^1Flags: ^3%s ^1| Auth: ^3%s ^1| Type: ^3%s",
        g_szChatPrefix,
        g_eAdminSession[id][SessionFlags],
        szAuthIdentifier,
        bUseNick ? "Name (pass: 123456)" : "SteamID (ce)")

    // Notify player if connected
    new iTarget = g_eAdminSession[id][SessionTargetId]
    if(is_user_connected(iTarget))
    {
        client_print_color(iTarget, print_team_default, "^4[GAMELAND] ^1You have been granted Admin rights by ^3%s^1! Reconnect to apply.", g_szUserName[id])
    }
}

// --- 2. MATCH & MIX CONTROLS ---
ShowMatchControlMenu(id)
{
    new iMenu = menu_create("\y[GAMELAND] Match & Mix Control:\w", "Menu_MatchControlHandler")

    menu_additem(iMenu, "\wStart Match \y(Trigger Global Vote)\w", "1")
    menu_additem(iMenu, "\rForce Direct Live \y(Skip Knife/Vote)\w", "2")
    menu_additem(iMenu, "\yForce Knife Round \y(Side selection)\w", "3")
    menu_additem(iMenu, "\wWarmup Mode \y($16,000 practice)\w", "4")
    menu_additem(iMenu, "\wStop Match \y(Return to Warmup)\w", "5")
    menu_additem(iMenu, "\wPause / Unpause Match\w", "6")
    menu_additem(iMenu, "\yTrigger Halftime Swap \d(Score & Side Swap)\w", "7")
    menu_additem(iMenu, g_bReviveMode ? "\rInfinite Revive: \y[ ACTIVE - Turn OFF ]\w" : "\yInfinite Revive: \d[ INACTIVE - Turn ON ]\w", "8")
    menu_additem(iMenu, "\wRevive All Dead Players \y(/rev)\w", "9")
    menu_additem(iMenu, "\d<- Back to Main Menu\w", "0")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_MatchControlHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: Cmd_StartMix(id)
        case 2: Cmd_DirectLive(id)
        case 3: Cmd_KnifeRound(id)
        case 4: Cmd_Warmup(id)
        case 5: Cmd_StopMix(id)
        case 6: Cmd_Pause(id)
        case 7: Cmd_Halftime(id)
        case 8:
        {
            if(g_bReviveMode) Cmd_ReviveOff(id)
            else Cmd_ReviveOn(id)
            ShowMatchControlMenu(id)
        }
        case 9:
        {
            Cmd_ReviveAll(id)
            ShowMatchControlMenu(id)
        }
        case 0: Cmd_AdminDashboard(id)
    }
    return PLUGIN_HANDLED
}

// --- 3. TEAM CONTROLS ---
ShowTeamControlMenu(id)
{
    new iMenu = menu_create("\y[GAMELAND] Team Management:\w", "Menu_TeamControlHandler")

    menu_additem(iMenu, "\ySwap All Teams \d(/st)\w", "1")
    menu_additem(iMenu, "\wMove All Players to \ySpectator \d(/spec)\w", "2")
    menu_additem(iMenu, "\wRevive All Dead Players \y(/rev)\w", "3")
    menu_additem(iMenu, "\wKick Spectators \d(/kspec)\w", "4")
    menu_additem(iMenu, "\wMove Single Player to \yCT\w", "5")
    menu_additem(iMenu, "\wMove Single Player to \yTERRORIST\w", "6")
    menu_additem(iMenu, "\wMove Single Player to \ySPECTATOR\w", "7")
    menu_additem(iMenu, "\d<- Back to Main Menu\w", "9")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_TeamControlHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1:
        {
            amxclient_cmd(id, "say", "/st")
            ShowTeamControlMenu(id)
        }
        case 2:
        {
            Cmd_SpecAll(id)
            ShowTeamControlMenu(id)
        }
        case 3:
        {
            Cmd_ReviveAll(id)
            ShowTeamControlMenu(id)
        }
        case 4:
        {
            amxclient_cmd(id, "say", "/kspec")
            ShowTeamControlMenu(id)
        }
        case 5: ShowMovePlayerMenu(id, TEAM_CT)
        case 6: ShowMovePlayerMenu(id, TEAM_TERRORIST)
        case 7: ShowMovePlayerMenu(id, TEAM_SPECTATOR)
        case 9: Cmd_AdminDashboard(id)
    }
    return PLUGIN_HANDLED
}

ShowMovePlayerMenu(id, TeamName:targetTeam)
{
    new szTitle[64]
    formatex(szTitle, charsmax(szTitle), "\yMove Player to %s:\w", targetTeam == TEAM_CT ? "CT" : (targetTeam == TEAM_TERRORIST ? "TERRORIST" : "SPECTATOR"))
    new iMenu = menu_create(szTitle, "Menu_MovePlayerTargetHandler")

    new iPlayers[MAX_PLAYERS], iNum
    get_players(iPlayers, iNum, "ch")

    for(new i = 0; i < iNum; i++)
    {
        new player = iPlayers[i]
        new szInfo[12], szDisplay[64]
        formatex(szInfo, charsmax(szInfo), "%d %d", player, _:targetTeam)
        formatex(szDisplay, charsmax(szDisplay), "\w%s", g_szUserName[player])
        menu_additem(iMenu, szDisplay, szInfo)
    }

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_MovePlayerTargetHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        ShowTeamControlMenu(id)
        return PLUGIN_HANDLED
    }

    new szData[12], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    new szPlayer[6], szTeam[6]
    strtok(szData, szPlayer, charsmax(szPlayer), szTeam, charsmax(szTeam), ' ')

    new iTarget = str_to_num(szPlayer)
    new TeamName:team = TeamName:str_to_num(szTeam)

    if(is_user_connected(iTarget))
    {
        rg_set_user_team(iTarget, team)
        client_print_color(0, print_team_default, "^4%s ^1Player ^4%s ^1moved to ^3%s ^1by ^4%s^1.",
            g_szChatPrefix, g_szUserName[iTarget],
            team == TEAM_CT ? "CT" : (team == TEAM_TERRORIST ? "TERRORIST" : "SPECTATOR"),
            g_szUserName[id])
    }
    ShowTeamControlMenu(id)
    return PLUGIN_HANDLED
}

// --- 4. VOICE & SERVER RULES CONTROLS ---
ShowVoiceAndRulesMenu(id)
{
    new iMenu = menu_create("\y[GAMELAND] Voice & Server Rules:\w", "Menu_VoiceRulesHandler")

    menu_additem(iMenu, "\wAlltalk \yON \d(sv_alltalk 1 / /t1)\w", "1")
    menu_additem(iMenu, "\wAlltalk \yTeam-Only \d(sv_alltalk 2 / /t2)\w", "2")
    menu_additem(iMenu, "\wAlltalk \yReHLDS Advanced \d(sv_alltalk 3 / /t3)\w", "3")
    menu_additem(iMenu, "\wFriendly Fire \yON \d(/ff1)\w", "4")
    menu_additem(iMenu, "\wFriendly Fire \yOFF \d(/ff0)\w", "5")
    menu_additem(iMenu, "\wJoin Mode: \yOpen \d(/j1)\w", "6")
    menu_additem(iMenu, "\wJoin Mode: \yLocked \d(/j0)\w", "7")
    menu_additem(iMenu, "\wJoin Mode: \yBlack Screen \d(/j2)\w", "8")
    menu_additem(iMenu, "\d<- Back to Main Menu\w", "9")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_VoiceRulesHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: { amxclient_cmd(id, "say", "/t1"); ShowVoiceAndRulesMenu(id); }
        case 2: { amxclient_cmd(id, "say", "/t2"); ShowVoiceAndRulesMenu(id); }
        case 3: { amxclient_cmd(id, "say", "/t3"); ShowVoiceAndRulesMenu(id); }
        case 4: { amxclient_cmd(id, "say", "/ff1"); ShowVoiceAndRulesMenu(id); }
        case 5: { amxclient_cmd(id, "say", "/ff0"); ShowVoiceAndRulesMenu(id); }
        case 6: { amxclient_cmd(id, "say", "/j1"); ShowVoiceAndRulesMenu(id); }
        case 7: { amxclient_cmd(id, "say", "/j0"); ShowVoiceAndRulesMenu(id); }
        case 8: { amxclient_cmd(id, "say", "/j2"); ShowVoiceAndRulesMenu(id); }
        case 9: Cmd_AdminDashboard(id)
    }
    return PLUGIN_HANDLED
}

// --- 5. MAP CONTROLS ---
ShowMapControlMenu(id)
{
    new iMenu = menu_create("\y[GAMELAND] Map Management:\w", "Menu_MapControlHandler")

    menu_additem(iMenu, "\wGameLand Map Browser \y(/map)\w", "1")
    menu_additem(iMenu, "\wVote Map Menu \y(/vm)\w", "2")
    menu_additem(iMenu, "\dStandard AMX Map Menu \d(amx_mapmenu)\w", "3")
    menu_additem(iMenu, "\d<- Back to Main Menu\w", "9")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_MapControlHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: amxclient_cmd(id, "say", "/map")
        case 2: amxclient_cmd(id, "say", "/vm")
        case 3: client_cmd(id, "amx_mapmenu")
        case 9: Cmd_AdminDashboard(id)
    }
    return PLUGIN_HANDLED
}

// --- 6. MODERATION CONTROLS ---
ShowModerationMenu(id)
{
    new iMenu = menu_create("\y[GAMELAND] Player Moderation:\w", "Menu_ModerationHandler")

    menu_additem(iMenu, "\wKick Player Menu \y(/k)\w", "1")
    menu_additem(iMenu, "\wBan Player Menu \y(/b)\w", "2")
    menu_additem(iMenu, "\wUnban Player Menu \y(/ub)\w", "3")
    menu_additem(iMenu, "\dStandard Slap Menu \d(amx_slapmenu)\w", "4")
    menu_additem(iMenu, "\d<- Back to Main Menu\w", "9")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_ModerationHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: amxclient_cmd(id, "say", "/k")
        case 2: amxclient_cmd(id, "say", "/b")
        case 3: amxclient_cmd(id, "say", "/ub")
        case 4: client_cmd(id, "amx_slapmenu")
        case 9: Cmd_AdminDashboard(id)
    }
    return PLUGIN_HANDLED
}

// --- 7. FAST SERVER TOOLS ---
ShowServerControlMenu(id)
{
    new iMenu = menu_create("\y[GAMELAND] Fast Server Controls:\w", "Menu_ServerControlHandler")

    menu_additem(iMenu, "\wRestart Round 1s \y(/r)\w", "1")
    menu_additem(iMenu, "\wSet Server Password \y(/passon)\w", "2")
    menu_additem(iMenu, "\wRemove Server Password \y(/passoff)\w", "3")
    menu_additem(iMenu, "\wMute All Chat \y(/off)\w", "4")
    menu_additem(iMenu, "\wUnmute All Chat \y(/on)\w", "5")
    menu_additem(iMenu, "\d<- Back to Main Menu\w", "9")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public Menu_ServerControlHandler(id, iMenu, iItem)
{
    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[6], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    switch(str_to_num(szData))
    {
        case 1: amxclient_cmd(id, "say", "/r")
        case 2: { Cmd_PassOn(id); ShowServerControlMenu(id); }
        case 3: { Cmd_PassOff(id); ShowServerControlMenu(id); }
        case 4: { Cmd_ChatOff(id); ShowServerControlMenu(id); }
        case 5: { Cmd_ChatOn(id); ShowServerControlMenu(id); }
        case 9: Cmd_AdminDashboard(id)
    }
    return PLUGIN_HANDLED
}

// -----------------------------------------------------------------------------
// Chat management
// -----------------------------------------------------------------------------
public Hook_Say(id)
{
    if(g_bChatMuted && !HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4%s ^1Chat is currently muted by an Administrator.", g_szChatPrefix)
        return PLUGIN_HANDLED
    }
    return PLUGIN_CONTINUE
}

public Hook_SayTeam(id)
{
    return PLUGIN_CONTINUE
}

// -----------------------------------------------------------------------------
// Natives Implementation
// -----------------------------------------------------------------------------
public native_is_half(iPlugin, iParams)
{
    return (g_iMatchState == STATE_FIRST_HALF && (g_iScore[CT_SCORE] + g_iScore[TERO_SCORE]) >= 15)
}

public native_is_last_round(iPlugin, iParams)
{
    if(g_iMatchState == STATE_SECOND_HALF)
    {
        return (g_iScore[CT_SCORE] == g_iMixEndRound - 1 || g_iScore[TERO_SCORE] == g_iMixEndRound - 1)
    }
    return false
}

public native_is_prelast_round(iPlugin, iParams)
{
    if(g_iMatchState == STATE_SECOND_HALF)
    {
        return (g_iScore[CT_SCORE] == g_iMixEndRound - 2 || g_iScore[TERO_SCORE] == g_iMixEndRound - 2)
    }
    return false
}

public native_can_overtime(iPlugin, iParams)
{
    return (g_iScore[CT_SCORE] == g_iOvertimeTriggerScore && g_iScore[TERO_SCORE] == g_iOvertimeTriggerScore)
}

public native_is_started(iPlugin, iParams)
{
    return (g_iMatchState == STATE_FIRST_HALF || g_iMatchState == STATE_SECOND_HALF ||
            g_iMatchState == STATE_OVERTIME_FIRST_HALF || g_iMatchState == STATE_OVERTIME_SECOND_HALF)
}

public native_is_warm(iPlugin, iParams)
{
    return (g_iMatchState == STATE_WARMUP)
}

public native_get_prefix(iPlugin, iParams)
{
    set_string(1, g_szChatPrefix, get_param(2))
}

public native_get_username(iPlugin, iParams)
{
    new id = get_param(1)
    if(id < 1 || id > MaxClients)
        return -1

    set_string(2, g_szUserName[id], get_param(3))
    return 1
}

// Backwards compatibility dummies (Points & SQL removed)
public native_user_points(iPlugin, iParams)
{
    return 0
}

public bool:native_has_points_sys(iPlugin, iParams)
{
    return false
}

public native_search_for_user(iPlugin, iParams)
{
    return -1
}

public native_multiply_factor(iPlugin, iParams)
{
    return 1
}

public native_get_points_table(iPlugin, iParams)
{
    set_string(1, "", get_param(2))
    return 0
}


// -----------------------------------------------------------------------------
// CLAN WAR MODE: AUTO-START, CAPTAIN ELECTION & TURN-BASED DRAFT SYSTEM
// -----------------------------------------------------------------------------

stock GetActiveInGamePlayerCount()
{
    new iCount = 0
    for(new id = 1; id <= MaxClients; id++)
    {
        if(is_user_connected(id) && !is_user_hltv(id))
        {
            new TeamName:team = get_member(id, m_iTeam)
            if(team == TEAM_CT || team == TEAM_TERRORIST)
            {
                iCount++
            }
        }
    }
    return iCount
}

stock GetTeamPlayerCount(TeamName:team)
{
    new iCount = 0
    for(new id = 1; id <= MaxClients; id++)
    {
        if(is_user_connected(id) && !is_user_hltv(id))
        {
            if(get_member(id, m_iTeam) == team)
            {
                iCount++
            }
        }
    }
    return iCount
}

public RG_HandleMenu_ChooseTeam_Pre(const id, const MenuChooseTeam:slot)
{
    if(g_iMatchState == STATE_CAPTAIN_VOTE || g_iMatchState == STATE_PICKING || g_bPickMode)
    {
        client_print_color(id, print_team_default, "^4[GAMELAND CW] ^1Team selection is locked during Captain Election and Drafting!")
        return HC_SUPERCEDE
    }
    return HC_CONTINUE
}

public Cmd_BlockTeamChange(id)
{
    if(g_iMatchState == STATE_CAPTAIN_VOTE || g_iMatchState == STATE_PICKING || g_bPickMode)
    {
        client_print_color(id, print_team_default, "^4[GAMELAND CW] ^1Team selection is locked during Captain Election and Drafting!")
        return PLUGIN_HANDLED
    }
    return PLUGIN_CONTINUE
}

public StartCaptainCountdown()
{
    if(g_iMatchState != STATE_WARMUP)
        return

    g_iMatchState = STATE_CAPTAIN_COUNTDOWN
    g_iCwReadyTimer = g_bFastTestMode ? 5 : 30
    UpdateServerHostname()

    remove_task(TASK_CW_COUNTDOWN)
    set_task(1.0, "Task_CaptainCountdown", TASK_CW_COUNTDOWN, .flags = "b")

    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
    if(g_bAdminForceStarted)
    {
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3CAPTAIN COUNTDOWN FORCE-STARTED BY ADMIN! ^1(^430 seconds^1)")
    }
    else
    {
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^310 PLAYERS REACHED! ^1Captain Election will begin in ^430 seconds^1.")
    }
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1All players will be moved to Spectator for Captain Voting & Team Pick.")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
    client_cmd(0, "spk buttons/bell1")
}

public Task_CaptainCountdown()
{
    if(g_iMatchState != STATE_CAPTAIN_COUNTDOWN)
    {
        remove_task(TASK_CW_COUNTDOWN)
        return
    }

    new iInGame = GetActiveInGamePlayerCount()
    if(!g_bAdminForceStarted && !g_bFastTestMode && iInGame < 10)
    {
        remove_task(TASK_CW_COUNTDOWN)
        g_iMatchState = STATE_WARMUP
        UpdateServerHostname()
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3Player left team! ^1Countdown cancelled. Waiting for 10 players (%d/10)...", iInGame)
        return
    }

    g_iCwReadyTimer--

    if(g_iCwReadyTimer == 20 || g_iCwReadyTimer == 10 || (g_iCwReadyTimer <= 5 && g_iCwReadyTimer > 0))
    {
        client_cmd(0, "spk buttons/blip1")
    }

    set_dhudmessage(0, 220, 255, -1.0, 0.22, 0, 0.0, 1.0, 0.0, 0.1)
    show_dhudmessage(0, "=== [ 10 PLAYERS READY ] ===^nCaptain Election starts in: %d SECONDS^nGet ready to elect your Team Captains!", g_iCwReadyTimer)

    if(g_iCwReadyTimer <= 0)
    {
        remove_task(TASK_CW_COUNTDOWN)
        StartCaptainElection()
    }
}

public StartCaptainElection()
{
    remove_task(TASK_CW_COUNTDOWN)
    remove_task(TASK_CW_CAPTAIN_VOTE)
    remove_task(TASK_CW_PICK_TIMER)

    g_iMatchState = STATE_CAPTAIN_VOTE
    g_bPickMode = true
    UpdateServerHostname()

    // 1. Gather up to 10 human players from teams or spectator
    g_iEligibleVoterCount = 0

    for(new id = 1; id <= MaxClients; id++)
    {
        if(is_user_connected(id) && !is_user_bot(id) && !is_user_hltv(id))
        {
            new TeamName:team = get_member(id, m_iTeam)
            if(team == TEAM_CT || team == TEAM_TERRORIST || team == TEAM_SPECTATOR)
            {
                if(g_iEligibleVoterCount < 10)
                {
                    g_iEligibleVoters[g_iEligibleVoterCount++] = id
                }
            }
        }
    }

    // 2. Move all gathered players to Spectator safely without double-kill / ReGameDLL crash
    for(new i = 0; i < g_iEligibleVoterCount; i++)
    {
        new id = g_iEligibleVoters[i]
        if(!is_user_connected(id))
            continue

        g_iPlayerCaptVotes[id] = 0
        g_iVotedForCapt[id] = 0

        // In ReGameDLL, rg_set_user_team safely moves players to spectator without double-silentkill
        rg_set_user_team(id, TEAM_SPECTATOR, MODEL_UNASSIGNED, true, false)
    }

    // Real human election without bots

    g_iCaptVoteTimer = g_bFastTestMode ? 10 : 20
    set_task(1.0, "Task_CaptVoteTimer", TASK_CW_CAPTAIN_VOTE, .flags = "b")

    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3CAPTAIN ELECTION HAS STARTED! ^1(%d Seconds)", g_iCaptVoteTimer)
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Vote for the player you want as your Team Captain!")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^4Top 2 players ^1with most votes become Captain CT & Captain TR.")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
    client_cmd(0, "spk buttons/bell1")

    // Open Vote Menu for all human eligible voters
    for(new i = 0; i < g_iEligibleVoterCount; i++)
    {
        new id = g_iEligibleVoters[i]
        if(!is_user_bot(id))
        {
            ShowCaptainVoteMenu(id)
        }
    }
}



public ShowCaptainVoteMenu(id)
{
    if(!is_user_connected(id) || is_user_bot(id) || g_iMatchState != STATE_CAPTAIN_VOTE)
        return

    if(g_iVotedForCapt[id] > 0)
    {
        // Player has already voted - strictly 1 vote allowed!
        return
    }

    new szTitle[128]
    formatex(szTitle, charsmax(szTitle), "\y[GAMELAND CW] Vote Team Captain \r[%d sec]\w^n\dVote for another player to be Captain (Top 2 win):", g_iCaptVoteTimer)
    new iMenu = menu_create(szTitle, "HandleCaptainVoteMenu")

    for(new i = 0; i < g_iEligibleVoterCount; i++)
    {
        new candidateId = g_iEligibleVoters[i]
        // Disallow self-voting: candidateId != id
        if(!is_user_connected(candidateId) || candidateId == id)
            continue

        new szData[8], szItem[96]
        num_to_str(candidateId, szData, charsmax(szData))

        new iVotes = g_iPlayerCaptVotes[candidateId]
        formatex(szItem, charsmax(szItem), "\w%s \d(%d vote%s)", g_szUserName[candidateId], iVotes, iVotes == 1 ? "" : "s")
        menu_additem(iMenu, szItem, szData)
    }

    // Show all candidates on page 1 without pagination
    menu_setprop(iMenu, MPROP_PERPAGE, 0)
    menu_setprop(iMenu, MPROP_EXIT, MEXIT_NEVER)
    menu_display(id, iMenu, 0)
}

public HandleCaptainVoteMenu(id, iMenu, iItem)
{
    if(g_iMatchState != STATE_CAPTAIN_VOTE || !is_user_connected(id))
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    if(iItem < 0)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[8], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    new candidateId = str_to_num(szData)

    if(!is_user_connected(candidateId))
    {
        ShowCaptainVoteMenu(id)
        return PLUGIN_HANDLED
    }

    // Strict rule: each player can vote ONLY ONCE!
    if(g_iVotedForCapt[id] > 0)
    {
        client_print_color(id, print_team_default, "^4[GAMELAND CW] ^3You have already cast your vote! You cannot vote multiple times.")
        return PLUGIN_HANDLED
    }

    // Strict rule: no self-voting!
    if(candidateId == id)
    {
        client_print_color(id, print_team_default, "^4[GAMELAND CW] ^3You cannot vote for yourself! Please vote for another player.")
        ShowCaptainVoteMenu(id)
        return PLUGIN_HANDLED
    }

    g_iVotedForCapt[id] = candidateId
    g_iPlayerCaptVotes[candidateId]++

    client_print_color(id, print_team_default, "^4[GAMELAND CW] ^1Your vote for ^4%s ^1as Captain is recorded! (Total votes: ^3%d^1)", g_szUserName[candidateId], g_iPlayerCaptVotes[candidateId])
    client_cmd(id, "spk buttons/blip1")

    // Check if all connected human voters have cast their votes
    new iTotalHumanVoted = 0, iTotalHumans = 0
    for(new i = 0; i < g_iEligibleVoterCount; i++)
    {
        new p = g_iEligibleVoters[i]
        if(is_user_connected(p) && !is_user_bot(p))
        {
            iTotalHumans++
            if(g_iVotedForCapt[p] > 0)
            {
                iTotalHumanVoted++
            }
        }
    }

    if(iTotalHumanVoted >= iTotalHumans && iTotalHumans > 0)
    {
        remove_task(TASK_CW_CAPTAIN_VOTE)
        FinishCaptainElection()
        return PLUGIN_HANDLED
    }

    // Do NOT reopen menu - vote is locked!
    return PLUGIN_HANDLED
}

public Task_CaptVoteTimer()
{
    if(g_iMatchState != STATE_CAPTAIN_VOTE)
    {
        remove_task(TASK_CW_CAPTAIN_VOTE)
        return
    }

    g_iCaptVoteTimer--

    if(g_iCaptVoteTimer <= 0)
    {
        remove_task(TASK_CW_CAPTAIN_VOTE)
        FinishCaptainElection()
        return
    }

    // Find current top 2 leaders
    new iTop1 = 0, iTop2 = 0
    new iMax1 = -1, iMax2 = -1

    for(new i = 0; i < g_iEligibleVoterCount; i++)
    {
        new p = g_iEligibleVoters[i]
        if(!is_user_connected(p)) continue
        new v = g_iPlayerCaptVotes[p]
        if(v > iMax1)
        {
            iMax2 = iMax1
            iTop2 = iTop1
            iMax1 = v
            iTop1 = p
        }
        else if(v > iMax2)
        {
            iMax2 = v
            iTop2 = p
        }
    }

    set_hudmessage(0, 200, 255, -1.0, 0.25, 0, 0.0, 0.9, 0.0, 0.1)
    if(iTop1 > 0 && iTop2 > 0)
    {
        show_hudmessage(0, "Captain Election: %d seconds left^n#1: %s (%d votes) | #2: %s (%d votes)", 
            g_iCaptVoteTimer, g_szUserName[iTop1], max(0, iMax1), g_szUserName[iTop2], max(0, iMax2))
    }
    else
    {
        show_hudmessage(0, "Captain Election: %d seconds left^nCast your votes in the menu!", g_iCaptVoteTimer)
    }
}

public FinishCaptainElection()
{
    remove_task(TASK_CW_CAPTAIN_VOTE)

    // Close open menus cleanly using newmenu API
    for(new i = 1; i <= MaxClients; i++)
    {
        if(is_user_connected(i))
        {
            menu_cancel(i)
        }
    }

    // Sort candidates descending by votes
    new iCandidates[MAX_PLAYERS], iVotes[MAX_PLAYERS]
    new iCount = 0

    for(new i = 0; i < g_iEligibleVoterCount; i++)
    {
        new p = g_iEligibleVoters[i]
        if(is_user_connected(p))
        {
            iCandidates[iCount] = p
            iVotes[iCount] = g_iPlayerCaptVotes[p]
            iCount++
        }
    }

    if(iCount < 2)
    {
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3Not enough players to elect captains! Returning to WarmUp.")
        StartWarmup()
        return
    }

    // Sort candidates with smart tie-breaking:
    // 1) Votes count
    // 2) Kills/Frags
    // 3) Deaths (fewer is better)
    // 4) Deterministic fair selection
    for(new i = 0; i < iCount - 1; i++)
    {
        for(new j = i + 1; j < iCount; j++)
        {
            if(IsBetterCaptainCandidate(iCandidates[j], iVotes[j], iCandidates[i], iVotes[i]))
            {
                new tempV = iVotes[i]; iVotes[i] = iVotes[j]; iVotes[j] = tempV
                new tempC = iCandidates[i]; iCandidates[i] = iCandidates[j]; iCandidates[j] = tempC
            }
        }
    }

    if(iCount >= 2 && iVotes[0] == iVotes[1])
    {
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3Captain vote tie detected! Winner chosen fairly based on match performance (frags/deaths).")
    }

    g_iCaptainCT = iCandidates[0]
    g_iCaptainTR = iCandidates[1]

    // Assign captains to their teams
    rg_set_user_team(g_iCaptainCT, TEAM_CT)
    rg_set_user_team(g_iCaptainTR, TEAM_TERRORIST)

    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3CAPTAIN ELECTION COMPLETED!")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^4Captain CT (Winner #1): ^3%s ^1(^4%d votes^1)", g_szUserName[g_iCaptainCT], iVotes[0])
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3Captain TR (Winner #2): ^3%s ^1(^4%d votes^1)", g_szUserName[g_iCaptainTR], iVotes[1])
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Drafting phase will start in 3 seconds...")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")

    client_cmd(0, "spk buttons/bell1")

    set_task(3.0, "StartDraftPhase")
}

public StartDraftPhase()
{
    g_iMatchState = STATE_PICKING
    g_bPickMode = true
    UpdateServerHostname()

    g_iCurrentDraftTurn = 1 // 1: CT, 2: TR
    g_iDraftRound = 1

    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3TEAM DRAFT PHASE IS NOW LIVE!")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Captains will pick players turn-by-turn from Spectator pool.")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")

    TriggerNextPickTurn()
}

public TriggerNextPickTurn()
{
    remove_task(TASK_CW_PICK_TIMER)

    if(g_iMatchState != STATE_PICKING)
        return

    // Gather spectators
    new iPool[MAX_PLAYERS], iPoolCount = 0
    for(new id = 1; id <= MaxClients; id++)
    {
        if(is_user_connected(id) && !is_user_hltv(id))
        {
            if(get_member(id, m_iTeam) == TEAM_SPECTATOR)
            {
                iPool[iPoolCount++] = id
            }
        }
    }

    if(iPoolCount == 0)
    {
        new iCtCount = GetTeamPlayerCount(TEAM_CT)
        new iTrCount = GetTeamPlayerCount(TEAM_TERRORIST)

        if(iCtCount >= 5 && iTrCount >= 5)
        {
            FinishDraftPhase()
        }
        else
        {
            client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3Both Captains assigned! (CT: ^4%s ^3| TR: ^4%s^3)",
                g_szUserName[g_iCaptainCT], g_szUserName[g_iCaptainTR])
            client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Drafting complete for current players. Start match with ^4/mix ^1or ^4/cw^1.")
            g_bPickMode = false
            UpdateServerHostname()
        }
        return
    }

    if(iPoolCount == 1)
    {
        new lastPlayer = iPool[0]
        new iCtCount = GetTeamPlayerCount(TEAM_CT)

        new TeamName:destTeam = (iCtCount < 5) ? TEAM_CT : TEAM_TERRORIST
        rg_set_user_team(lastPlayer, destTeam)

        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Final player ^4%s ^1automatically assigned to ^3%s^1!", 
            g_szUserName[lastPlayer], (destTeam == TEAM_CT) ? "Counter-Terrorist" : "Terrorist")
        client_cmd(0, "spk buttons/bell1")

        set_task(2.0, "FinishDraftPhase")
        return
    }

    new activeCaptain = (g_iCurrentDraftTurn == 1) ? g_iCaptainCT : g_iCaptainTR
    new szTeamName[32]
    copy(szTeamName, charsmax(szTeamName), (g_iCurrentDraftTurn == 1) ? "Counter-Terrorist" : "Terrorist")

    if(!is_user_connected(activeCaptain))
    {
        activeCaptain = FindFallbackCaptain((g_iCurrentDraftTurn == 1) ? TEAM_CT : TEAM_TERRORIST)
        if(g_iCurrentDraftTurn == 1) g_iCaptainCT = activeCaptain
        else g_iCaptainTR = activeCaptain
    }

    if(!is_user_connected(activeCaptain))
    {
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3Captain left! Resetting to WarmUp.")
        StartWarmup()
        return
    }

    g_iPickTimer = g_bFastTestMode ? 10 : 15
    set_task(1.0, "Task_PickTimerCountdown", TASK_CW_PICK_TIMER, .flags = "b")

    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^4Round %d ^1| Turn: Captain ^3%s ^1(%s) is picking! (%ds)",
        g_iDraftRound, g_szUserName[activeCaptain], szTeamName, g_iPickTimer)

    ShowPickMenu(activeCaptain)
}

stock FindFallbackCaptain(TeamName:targetTeam)
{
    for(new id = 1; id <= MaxClients; id++)
    {
        if(is_user_connected(id) && !is_user_hltv(id))
        {
            if(get_member(id, m_iTeam) == targetTeam)
                return id
        }
    }
    return 0
}

public ShowPickMenu(id)
{
    if(!is_user_connected(id) || g_iMatchState != STATE_PICKING)
        return

    new szTitle[128]
    formatex(szTitle, charsmax(szTitle), "\y[GAMELAND CW] Your Turn to Pick! \r[%d sec]\w^n\dSelect a teammate to draft to your team:", g_iPickTimer)
    new iMenu = menu_create(szTitle, "HandlePickMenu")

    for(new p = 1; p <= MaxClients; p++)
    {
        if(is_user_connected(p) && !is_user_hltv(p))
        {
            if(get_member(p, m_iTeam) == TEAM_SPECTATOR)
            {
                new szData[8], szItem[64]
                num_to_str(p, szData, charsmax(szData))
                formatex(szItem, charsmax(szItem), "\w%s", g_szUserName[p])
                menu_additem(iMenu, szItem, szData)
            }
        }
    }

    menu_setprop(iMenu, MPROP_PERPAGE, 0)
    menu_setprop(iMenu, MPROP_EXIT, MEXIT_NEVER)
    menu_display(id, iMenu, 0)
}

public HandlePickMenu(id, iMenu, iItem)
{
    if(g_iMatchState != STATE_PICKING || !is_user_connected(id))
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    if(iItem == MENU_EXIT)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[8], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    new pickedPlayer = str_to_num(szData)
    if(!is_user_connected(pickedPlayer) || get_member(pickedPlayer, m_iTeam) != TEAM_SPECTATOR)
    {
        ShowPickMenu(id)
        return PLUGIN_HANDLED
    }

    ApplyDraftPick(id, pickedPlayer)
    return PLUGIN_HANDLED
}

ApplyDraftPick(captainId, pickedId)
{
    remove_task(TASK_CW_PICK_TIMER)

    new TeamName:captainTeam = get_member(captainId, m_iTeam)
    rg_set_user_team(pickedId, captainTeam)

    new szTeam[32]
    copy(szTeam, charsmax(szTeam), (captainTeam == TEAM_CT) ? "Counter-Terrorist" : "Terrorist")

    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^4Captain %s ^1drafted ^3%s ^1to ^4%s^1! [CT: %d | TR: %d]",
        g_szUserName[captainId], g_szUserName[pickedId], szTeam, GetTeamPlayerCount(TEAM_CT), GetTeamPlayerCount(TEAM_TERRORIST))

    client_cmd(0, "spk buttons/bell1")

    // Flash green ScreenFade on drafted player if human
    if(g_iMsgScreenFade > 0 && !is_user_bot(pickedId))
    {
        message_begin(MSG_ONE_UNRELIABLE, g_iMsgScreenFade, _, pickedId)
        write_short((1<<12) / 2)
        write_short((1<<12) / 4)
        write_short(0x0000)
        write_byte(40)
        write_byte(220)
        write_byte(40)
        write_byte(120)
        message_end()
    }

    // Switch turn
    g_iCurrentDraftTurn = (g_iCurrentDraftTurn == 1) ? 2 : 1
    g_iDraftRound++

    set_task(1.0, "TriggerNextPickTurn")
}

public Task_PickTimerCountdown()
{
    if(g_iMatchState != STATE_PICKING)
    {
        remove_task(TASK_CW_PICK_TIMER)
        return
    }

    g_iPickTimer--

    new activeCaptain = (g_iCurrentDraftTurn == 1) ? g_iCaptainCT : g_iCaptainTR
    new szTeamName[32]
    copy(szTeamName, charsmax(szTeamName), (g_iCurrentDraftTurn == 1) ? "Counter-Terrorist" : "Terrorist")

    if(g_iPickTimer <= 0)
    {
        remove_task(TASK_CW_PICK_TIMER)

        // Find first available spectator to auto-pick
        new autoPick = 0
        for(new id = 1; id <= MaxClients; id++)
        {
            if(is_user_connected(id) && !is_user_hltv(id))
            {
                if(get_member(id, m_iTeam) == TEAM_SPECTATOR)
                {
                    autoPick = id
                    break
                }
            }
        }

        if(autoPick > 0 && is_user_connected(activeCaptain))
        {
            client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Time expired for Captain ^4%s^1! Auto-picked ^3%s^1.", 
                g_szUserName[activeCaptain], g_szUserName[autoPick])
            ApplyDraftPick(activeCaptain, autoPick)
        }
        else
        {
            TriggerNextPickTurn()
        }
        return
    }
}

public FinishDraftPhase()
{
    remove_task(TASK_CW_PICK_TIMER)
    g_bPickMode = false

    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3TEAMS FULLY DRAFTED! (5 CT vs 5 TR)")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Starting ^3KNIFE ROUND ^1directly in 2 seconds...")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")

    client_cmd(0, "spk buttons/bell1")

    // Directly transition to Knife Round!
    set_task(2.0, "StartKnifeRound")
}


// -----------------------------------------------------------------------------
// CLAN WAR ADMIN CONTROL COMMANDS & INTERACTIVE MENU (/cw)
// -----------------------------------------------------------------------------

public Cmd_ClanWarAdmin(id)
{
    if(!HasAdminAccess(id))
    {
        client_print_color(id, print_team_default, "^4[GAMELAND CW] ^1You need Admin access to manage Clan War! ^3(Flags: a, c, d, l, u)")
        return PLUGIN_HANDLED
    }

    new szFullArgs[64], szToken1[32], szToken2[32]
    read_args(szFullArgs, charsmax(szFullArgs))
    remove_quotes(szFullArgs)
    trim(szFullArgs)

    // Parse arguments: e.g. "/cw start" -> token1="/cw", token2="start"
    // or console "cw start" -> token1="start", token2=""
    parse(szFullArgs, szToken1, charsmax(szToken1), szToken2, charsmax(szToken2))

    new szSubCmd[32]
    if(szToken1[0] == '/' || equali(szToken1, "cw") || equali(szToken1, "clanwar") || equali(szToken1, "cwmenu"))
    {
        copy(szSubCmd, charsmax(szSubCmd), szToken2)
    }
    else
    {
        copy(szSubCmd, charsmax(szSubCmd), szToken1)
    }

    if(equali(szSubCmd, "start") || equali(szSubCmd, "force"))
    {
        g_bAdminForceStarted = true
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Admin ^4%s ^1force-started the countdown!", g_szUserName[id])
        StartCaptainCountdown()
        return PLUGIN_HANDLED
    }
    else if(equali(szSubCmd, "fast") || equali(szSubCmd, "speed"))
    {
        g_bFastTestMode = !g_bFastTestMode
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Fast Test Mode is now: ^4%s ^1(5s countdown, 10s election, 10s pick)", g_bFastTestMode ? "ENABLED" : "DISABLED")
        return PLUGIN_HANDLED
    }
    else if(equali(szSubCmd, "vote") || equali(szSubCmd, "elect"))
    {
        g_bAdminForceStarted = true
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Admin ^4%s ^1force-started Captain Election!", g_szUserName[id])
        StartCaptainElection()
        return PLUGIN_HANDLED
    }
    else if(equali(szSubCmd, "draft") || equali(szSubCmd, "pick"))
    {
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Admin ^4%s ^1force-started Team Drafting!", g_szUserName[id])
        StartDraftPhase()
        return PLUGIN_HANDLED
    }
    else if(equali(szSubCmd, "stop") || equali(szSubCmd, "warm"))
    {
        g_bAdminForceStarted = false
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Admin ^4%s ^1reset server to WarmUp!", g_szUserName[id])
        StartWarmup()
        return PLUGIN_HANDLED
    }

    if(id > 0)
    {
        ShowClanWarAdminMenu(id)
    }
    else
    {
        server_print("[GAMELAND CW] Usage: amx_cw <start|fast|vote|draft|stop>")
    }
    return PLUGIN_HANDLED
}

public ShowClanWarAdminMenu(id)
{
    if(!is_user_connected(id) || !HasAdminAccess(id))
        return

    new szState[64]
    GetMatchStateName(szState, charsmax(szState))

    new szMenu[512]
    new iLen = 0

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y[GAMELAND] Clan War Control Menu\w^n")
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\dStatus: \r%s \d| Fast: \y%s^n^n", 
        szState, g_bFastTestMode ? "ON (5s)" : "OFF (30s)")

    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y1. \wStart 30s Countdown \y[/cw start]^n")
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y2. \wStart Captain Election Now \y[/cw vote]^n")
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y3. \wStart Team Drafting Phase \y[/cw draft]^n")
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y4. \wStart Match Vote (Knife vs Live) \y[/mix]^n")
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y5. \wFast Test Mode: %s^n", g_bFastTestMode ? "\r[ON - 5s]" : "\d[OFF - 30s]")
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y6. \wMove All to Spectator \y[/spec]^n")
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y7. \rReset to WarmUp \d[/cw stop]^n^n")
    iLen += formatex(szMenu[iLen], charsmax(szMenu) - iLen, "\y0. \dExit Menu")

    new keys = MENU_KEY_1 | MENU_KEY_2 | MENU_KEY_3 | MENU_KEY_4 | MENU_KEY_5 | MENU_KEY_6 | MENU_KEY_7 | MENU_KEY_0
    show_menu(id, keys, szMenu, -1, CW_ADMIN_MENU_ID)
}

public HandleClanWarNativeMenu(id, key)
{
    if(!is_user_connected(id) || !HasAdminAccess(id))
        return PLUGIN_HANDLED

    switch(key)
    {
        case 0: // 1. Start Countdown
        {
            g_bAdminForceStarted = true
            client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Admin ^4%s ^1force-started the countdown!", g_szUserName[id])
            StartCaptainCountdown()
        }
        case 1: // 2. Start Captain Election
        {
            g_bAdminForceStarted = true
            client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Admin ^4%s ^1force-started Captain Election!", g_szUserName[id])
            StartCaptainElection()
        }
        case 2: // 3. Start Team Drafting
        {
            client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Admin ^4%s ^1force-started Team Drafting!", g_szUserName[id])
            StartDraftPhase()
        }
        case 3: // 4. Start Match Vote
        {
            StartMixVote()
        }
        case 4: // 5. Fast Test Mode
        {
            g_bFastTestMode = !g_bFastTestMode
            client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Fast Test Mode is now: ^4%s ^1(5s countdown, 10s election, 10s pick)", g_bFastTestMode ? "ENABLED" : "DISABLED")
            ShowClanWarAdminMenu(id)
        }
        case 5: // 6. Move All to Spectator
        {
            Cmd_SpecAll(id)
            ShowClanWarAdminMenu(id)
        }
        case 6: // 7. Reset to WarmUp
        {
            g_bAdminForceStarted = false
            client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Admin ^4%s ^1reset server to WarmUp!", g_szUserName[id])
            StartWarmup()
        }
        case 9: // 0. Exit
        {
            // Close menu
        }
    }
    return PLUGIN_HANDLED
}

stock GetMatchStateName(szOutput[], iMaxLen)
{
    switch(g_iMatchState)
    {
        case STATE_WARMUP: copy(szOutput, iMaxLen, "WarmUp (Waiting for 10 Players)")
        case STATE_CAPTAIN_COUNTDOWN: copy(szOutput, iMaxLen, "30s Captain Countdown")
        case STATE_CAPTAIN_VOTE: copy(szOutput, iMaxLen, "Captain Election Vote")
        case STATE_PICKING: copy(szOutput, iMaxLen, "Turn-by-Turn Drafting")
        case STATE_KNIFE: copy(szOutput, iMaxLen, "Knife Round")
        case STATE_FIRST_HALF: copy(szOutput, iMaxLen, "Live Match (First Half)")
        case STATE_SECOND_HALF: copy(szOutput, iMaxLen, "Live Match (Second Half)")
        case STATE_OVERTIME_FIRST_HALF, STATE_OVERTIME_SECOND_HALF: copy(szOutput, iMaxLen, "Overtime")
        default: copy(szOutput, iMaxLen, "Unknown")
    }
}


// =============================================================================
// F3 PLAYER ACTION MENU & POST-MATCH MAP VOTE SYSTEM
// =============================================================================

public Cmd_F3Menu(id)
{
    if(!is_user_connected(id))
        return PLUGIN_HANDLED

    new szTitle[128]
    formatex(szTitle, charsmax(szTitle), "\y[GAMELAND CW] Action Menu \r[N] \d(v%s)\w^n\dQuick Match & Team Management:", PLUGIN_VERSION)
    new iMenu = menu_create(szTitle, "Handle_F3Menu")

    new iCtRePick = 0, iTrRePick = 0
    new iCtRestart = 0, iTrRestart = 0
    for(new p = 1; p <= MaxClients; p++)
    {
        if(is_user_connected(p) && !is_user_bot(p))
        {
            new TeamName:t = get_member(p, m_iTeam)
            if(t == TEAM_CT)
            {
                if(g_bVotedRePick[p]) iCtRePick++
                if(g_bVotedRestart[p]) iCtRestart++
            }
            else if(t == TEAM_TERRORIST)
            {
                if(g_bVotedRePick[p]) iTrRePick++
                if(g_bVotedRestart[p]) iTrRestart++
            }
        }
    }

    new TeamName:myTeam = get_member(id, m_iTeam)
    new myTeamRePick = (myTeam == TEAM_CT) ? iCtRePick : ((myTeam == TEAM_TERRORIST) ? iTrRePick : 0)

    new szItem[128]
    menu_additem(iMenu, "\wVote Kick Teammate \y[3 votes needed]\w", "1")
    menu_additem(iMenu, "\wVote Change Map \d(dust2, nuke, inferno, train, aztec)\w", "2")

    formatex(szItem, charsmax(szItem), "%sVote Re-Pick & Captains \d(Need 5 team votes: \y%d/5\d)\w",
        g_bVotedRePick[id] ? "\y[*] \r" : "\w", myTeamRePick)
    menu_additem(iMenu, szItem, "3")

    formatex(szItem, charsmax(szItem), "%sVote Restart Match \d(Need 3 CT & 3 TR: \yCT %d/3 \d| \yTR %d/3\d)\w",
        g_bVotedRestart[id] ? "\y[*] \r" : "\w", iCtRestart, iTrRestart)
    menu_additem(iMenu, szItem, "4")

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
    return PLUGIN_HANDLED
}

public Handle_F3Menu(id, iMenu, iItem)
{
    if(!is_user_connected(id))
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    if(iItem < 0)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[8], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    new choice = str_to_num(szData)
    switch(choice)
    {
        case 1: ShowVoteKickMenu(id)
        case 2: ShowVoteMapMenu(id)
        case 3: ProcessVoteRePick(id)
        case 4: ProcessVoteRestart(id)
    }

    return PLUGIN_HANDLED
}

public ShowVoteKickMenu(id)
{
    if(!is_user_connected(id)) return

    new TeamName:myTeam = get_member(id, m_iTeam)
    if(myTeam != TEAM_CT && myTeam != TEAM_TERRORIST)
    {
        client_print_color(id, print_team_default, "^4[GAMELAND CW] ^3You must be in a team (CT or TR) to vote kick a teammate.")
        return
    }

    new iTeammates[MAX_PLAYERS], iCount = 0
    for(new p = 1; p <= MaxClients; p++)
    {
        if(is_user_connected(p) && !is_user_bot(p) && !is_user_hltv(p))
        {
            if(get_member(p, m_iTeam) == myTeam && p != id)
            {
                iTeammates[iCount++] = p
            }
        }
    }

    if(iCount == 0)
    {
        client_print_color(id, print_team_default, "^4[GAMELAND CW] ^3No teammates available to vote kick.")
        return
    }

    new szTitle[128]
    formatex(szTitle, charsmax(szTitle), "\y[GAMELAND CW] Vote Kick Teammate \r[3 Votes Needed]\w^n\dSelect teammate to kick:")
    new iMenu = menu_create(szTitle, "HandleVoteKickMenu")

    for(new i = 0; i < iCount; i++)
    {
        new targetId = iTeammates[i]
        new szData[8], szItem[96]
        num_to_str(targetId, szData, charsmax(szData))
        new v = g_iPlayerKickVotes[targetId]
        if(g_iVotedKickTarget[id] == targetId)
        {
            formatex(szItem, charsmax(szItem), "\y[*] \r%s \y[VOTED] \d(%d/3 votes)", g_szUserName[targetId], v)
        }
        else
        {
            formatex(szItem, charsmax(szItem), "\w%s \d(%d/3 votes)", g_szUserName[targetId], v)
        }
        menu_additem(iMenu, szItem, szData)
    }

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public HandleVoteKickMenu(id, iMenu, iItem)
{
    if(!is_user_connected(id))
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    if(iItem < 0)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[8], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    new targetId = str_to_num(szData)
    if(!is_user_connected(targetId) || targetId == id)
    {
        return PLUGIN_HANDLED
    }

    new TeamName:myTeam = get_member(id, m_iTeam)
    if(get_member(targetId, m_iTeam) != myTeam)
    {
        client_print_color(id, print_team_default, "^4[GAMELAND CW] ^3You can only vote kick your own teammates.")
        return PLUGIN_HANDLED
    }

    if(g_iVotedKickTarget[id] > 0 && g_iVotedKickTarget[id] != targetId)
    {
        new oldTarget = g_iVotedKickTarget[id]
        if(1 <= oldTarget <= MAX_PLAYERS && g_iPlayerKickVotes[oldTarget] > 0)
        {
            g_iPlayerKickVotes[oldTarget]--
        }
    }

    if(g_iVotedKickTarget[id] == targetId)
    {
        if(g_iPlayerKickVotes[targetId] > 0) g_iPlayerKickVotes[targetId]--
        g_iVotedKickTarget[id] = 0
        client_print_color(id, print_team_default, "^4[GAMELAND CW] ^1You retracted your vote kick for ^4%s^1.", g_szUserName[targetId])
        return PLUGIN_HANDLED
    }

    g_iVotedKickTarget[id] = targetId
    g_iPlayerKickVotes[targetId]++

    new needed = 3

    for(new p = 1; p <= MaxClients; p++)
    {
        if(is_user_connected(p) && get_member(p, m_iTeam) == myTeam)
        {
            client_print_color(p, print_team_default, "^4[GAMELAND CW] ^3%s ^1voted to kick ^4%s^1! (^3%d/%d votes^1)",
                g_szUserName[id], g_szUserName[targetId], g_iPlayerKickVotes[targetId], needed)
        }
    }
    client_cmd(id, "spk buttons/blip1")

    if(g_iPlayerKickVotes[targetId] >= needed)
    {
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3%s ^1was vote-kicked by their team! (^4%d votes^1)", g_szUserName[targetId], g_iPlayerKickVotes[targetId])
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")

        for(new p = 1; p <= MAX_PLAYERS; p++)
        {
            if(g_iVotedKickTarget[p] == targetId)
            {
                g_iVotedKickTarget[p] = 0
            }
        }
        g_iPlayerKickVotes[targetId] = 0

        new userid = get_user_userid(targetId)
        server_cmd("kick #%d ^"Voted off by team (%d votes)^"", userid, needed)
        server_exec()
    }

    return PLUGIN_HANDLED
}

public ShowVoteMapMenu(id)
{
    if(!is_user_connected(id)) return

    new iTotalHumans = 0
    for(new p = 1; p <= MaxClients; p++)
    {
        if(is_user_connected(p) && !is_user_bot(p) && !is_user_hltv(p))
            iTotalHumans++
    }

    new needed = max(2, iTotalHumans - 1)

    new szTitle[128]
    formatex(szTitle, charsmax(szTitle), "\y[GAMELAND CW] Vote Change Map \r[Need %d votes]\w^n\dVote for a competitive map:", needed)
    new iMenu = menu_create(szTitle, "HandleVoteMapMenu")

    for(new i = 0; i < sizeof(g_szStandardMaps); i++)
    {
        new szData[8], szItem[96]
        num_to_str(i, szData, charsmax(szData))
        new v = g_iMapVoteCount[i]
        if(g_iMapVoteChoice[id] == i)
        {
            formatex(szItem, charsmax(szItem), "\y[*] \r%s \y[VOTED] \d(%d/%d votes)", g_szStandardMaps[i], v, needed)
        }
        else
        {
            formatex(szItem, charsmax(szItem), "\w%s \d(%d/%d votes)", g_szStandardMaps[i], v, needed)
        }
        menu_additem(iMenu, szItem, szData)
    }

    menu_setprop(iMenu, MPROP_EXIT, MEXIT_ALL)
    menu_display(id, iMenu, 0)
}

public HandleVoteMapMenu(id, iMenu, iItem)
{
    if(!is_user_connected(id))
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    if(iItem < 0)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[8], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    new mapIdx = str_to_num(szData)
    if(mapIdx < 0 || mapIdx >= sizeof(g_szStandardMaps))
        return PLUGIN_HANDLED

    new iTotalHumans = 0
    for(new p = 1; p <= MaxClients; p++)
    {
        if(is_user_connected(p) && !is_user_bot(p) && !is_user_hltv(p))
            iTotalHumans++
    }
    new needed = max(2, iTotalHumans - 1)

    if(g_iMapVoteChoice[id] >= 0 && g_iMapVoteChoice[id] != mapIdx)
    {
        new old = g_iMapVoteChoice[id]
        if(old < sizeof(g_szStandardMaps) && g_iMapVoteCount[old] > 0)
        {
            g_iMapVoteCount[old]--
        }
    }

    if(g_iMapVoteChoice[id] == mapIdx)
    {
        if(g_iMapVoteCount[mapIdx] > 0) g_iMapVoteCount[mapIdx]--
        g_iMapVoteChoice[id] = -1
        client_print_color(id, print_team_default, "^4[GAMELAND CW] ^1You retracted your vote for ^3%s^1.", g_szStandardMaps[mapIdx])
        return PLUGIN_HANDLED
    }

    g_iMapVoteChoice[id] = mapIdx
    g_iMapVoteCount[mapIdx]++

    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3%s ^1voted for map ^4%s^1! (^3%d/%d votes^1)",
        g_szUserName[id], g_szStandardMaps[mapIdx], g_iMapVoteCount[mapIdx], needed)
    client_cmd(id, "spk buttons/blip1")

    if(g_iMapVoteCount[mapIdx] >= needed)
    {
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^4MAP VOTE PASSED! ^1Changing map to ^3%s ^1in 3 seconds...", g_szStandardMaps[mapIdx])
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
        client_cmd(0, "spk buttons/bell1")

        set_dhudmessage(0, 220, 255, -1.0, 0.35, 0, 0.0, 3.0, 0.1, 0.2)
        show_dhudmessage(0, "MAP VOTE PASSED!^nChanging level to: %s", g_szStandardMaps[mapIdx])

        new szChangeCmd[64]
        formatex(szChangeCmd, charsmax(szChangeCmd), "changelevel %s", g_szStandardMaps[mapIdx])
        set_task(3.0, "Task_ExecChangelevel", _, szChangeCmd, sizeof(szChangeCmd))
    }

    return PLUGIN_HANDLED
}

public Task_ExecChangelevel(const szCmd[])
{
    server_cmd("%s", szCmd)
}

public ProcessVoteRePick(id)
{
    if(!is_user_connected(id)) return

    new TeamName:myTeam = get_member(id, m_iTeam)
    if(myTeam != TEAM_CT && myTeam != TEAM_TERRORIST)
    {
        client_print_color(id, print_team_default, "^4[GAMELAND CW] ^3You must be on a team (CT or TR) to vote for Re-Pick.")
        return
    }

    g_bVotedRePick[id] = !g_bVotedRePick[id]

    new iCtCount = 0, iTrCount = 0
    for(new p = 1; p <= MaxClients; p++)
    {
        if(is_user_connected(p) && !is_user_bot(p))
        {
            if(get_member(p, m_iTeam) == TEAM_CT && g_bVotedRePick[p]) iCtCount++
            else if(get_member(p, m_iTeam) == TEAM_TERRORIST && g_bVotedRePick[p]) iTrCount++
        }
    }

    new myCount = (myTeam == TEAM_CT) ? iCtCount : iTrCount
    if(g_bVotedRePick[id])
    {
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3%s ^1voted for ^4RE-PICK^1! (Team %s: ^3%d/5 votes^1)",
            g_szUserName[id], (myTeam == TEAM_CT) ? "CT" : "TR", myCount)
        client_cmd(id, "spk buttons/blip1")
    }
    else
    {
        client_print_color(id, print_team_default, "^4[GAMELAND CW] ^1You retracted your vote for ^3RE-PICK^1.")
    }

    if(iCtCount >= 5 || iTrCount >= 5)
    {
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^4RE-PICK TRIGGERED! ^1Team ^3%s ^1voted 5/5 for Re-Pick!",
            (iCtCount >= 5) ? "Counter-Terrorist" : "Terrorist")
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Returning to Captain Election and Drafting in 3 seconds...")
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
        client_cmd(0, "spk buttons/bell1")

        ResetAllF3Votes()
        remove_task(TASK_CW_COUNTDOWN)
        remove_task(TASK_CW_CAPTAIN_VOTE)
        remove_task(TASK_CW_PICK_TIMER)
        remove_task(TASK_KNIFE_COUNTDOWN)
        remove_task(TASK_LIVE_COUNTDOWN)

        set_task(3.0, "StartCaptainElection")
    }
}

public ProcessVoteRestart(id)
{
    if(!is_user_connected(id)) return

    new TeamName:myTeam = get_member(id, m_iTeam)
    if(myTeam != TEAM_CT && myTeam != TEAM_TERRORIST)
    {
        client_print_color(id, print_team_default, "^4[GAMELAND CW] ^3You must be on a team (CT or TR) to vote for restart.")
        return
    }

    g_bVotedRestart[id] = !g_bVotedRestart[id]

    new iCtCount = 0, iTrCount = 0
    for(new p = 1; p <= MaxClients; p++)
    {
        if(is_user_connected(p) && !is_user_bot(p))
        {
            if(get_member(p, m_iTeam) == TEAM_CT && g_bVotedRestart[p]) iCtCount++
            else if(get_member(p, m_iTeam) == TEAM_TERRORIST && g_bVotedRestart[p]) iTrCount++
        }
    }

    if(g_bVotedRestart[id])
    {
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3%s ^1voted to ^4RESTART MATCH^1! (CT: ^3%d/3 ^1| TR: ^3%d/3^1)",
            g_szUserName[id], iCtCount, iTrCount)
        client_cmd(id, "spk buttons/blip1")
    }
    else
    {
        client_print_color(id, print_team_default, "^4[GAMELAND CW] ^1You retracted your vote to ^3Restart Match^1.")
    }

    if(iCtCount >= 3 && iTrCount >= 3)
    {
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^4MUTUAL RESTART AGREED! ^1(3 CT and 3 TR voted to restart)")
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Resetting match scores and restarting from Round 1 in 3 seconds...")
        client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
        client_cmd(0, "spk buttons/bell1")

        ResetAllF3Votes()
        g_iScore[CT_SCORE] = 0
        g_iScore[TERO_SCORE] = 0
        g_iFirstHalfScore[CT_SCORE] = 0
        g_iFirstHalfScore[TERO_SCORE] = 0
        g_iOvertimeScore[CT_SCORE] = 0
        g_iOvertimeScore[TERO_SCORE] = 0

        set_task(3.0, "StartKnifeRound")
    }
}

// -----------------------------------------------------------------------------
// POST-MATCH MAP VOTE (END OF MIX CELEBRATION VOTE)
// -----------------------------------------------------------------------------

public StartPostMatchMapVote()
{
    remove_task(TASK_MATCH_END)
    remove_task(TASK_POST_MATCH_MAP_VOTE)

    new szCurrentMap[32]
    get_mapname(szCurrentMap, charsmax(szCurrentMap))

    g_iPostMatchMapCount = 0

    // 1. Add current map played first
    copy(g_szPostMatchMaps[g_iPostMatchMapCount++], 31, szCurrentMap)

    // 2. Add other competitive standard maps without duplicates
    for(new i = 0; i < sizeof(g_szStandardMaps); i++)
    {
        if(!equali(g_szStandardMaps[i], szCurrentMap))
        {
            if(g_iPostMatchMapCount < 7)
            {
                copy(g_szPostMatchMaps[g_iPostMatchMapCount++], 31, g_szStandardMaps[i])
            }
        }
    }

    for(new i = 0; i < g_iPostMatchMapCount; i++)
    {
        g_iPostMatchVoteCount[i] = 0
    }

    for(new p = 1; p <= MAX_PLAYERS; p++)
    {
        g_iPlayerPostMatchVote[p] = -1
    }

    g_iPostMatchVoteTimer = 15

    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3MATCH ENDED! VOTE NEXT CLAN WAR MAP!")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Vote for the map you want to play next (%d seconds)...", g_iPostMatchVoteTimer)
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
    client_cmd(0, "spk buttons/bell1")

    set_task(1.0, "Task_PostMatchVoteTimer", TASK_POST_MATCH_MAP_VOTE, .flags = "b")

    for(new p = 1; p <= MaxClients; p++)
    {
        if(is_user_connected(p) && !is_user_bot(p) && !is_user_hltv(p))
        {
            ShowPostMatchVoteMenu(p)
        }
    }
}

public ShowPostMatchVoteMenu(id)
{
    if(!is_user_connected(id) || is_user_bot(id)) return

    new szCurrentMap[32]
    get_mapname(szCurrentMap, charsmax(szCurrentMap))

    new szTitle[128]
    formatex(szTitle, charsmax(szTitle), "\y[GAMELAND CW] Vote Next Match Map \r[%d sec]\w^n\dChoose the map for next Clan War / Mix:", g_iPostMatchVoteTimer)
    new iMenu = menu_create(szTitle, "HandlePostMatchVoteMenu")

    for(new i = 0; i < g_iPostMatchMapCount; i++)
    {
        new szData[8], szItem[96]
        num_to_str(i, szData, charsmax(szData))
        new v = g_iPostMatchVoteCount[i]

        new szTag[32] = ""
        if(equali(g_szPostMatchMaps[i], szCurrentMap))
        {
            copy(szTag, charsmax(szTag), " \y[Current Map]\w")
        }

        if(g_iPlayerPostMatchVote[id] == i)
        {
            formatex(szItem, charsmax(szItem), "\y[*] \r%s%s \y[VOTED] \d(%d vote%s)", g_szPostMatchMaps[i], szTag, v, (v == 1) ? "" : "s")
        }
        else
        {
            formatex(szItem, charsmax(szItem), "\w%s%s \d(%d vote%s)", g_szPostMatchMaps[i], szTag, v, (v == 1) ? "" : "s")
        }
        menu_additem(iMenu, szItem, szData)
    }

    menu_setprop(iMenu, MPROP_PERPAGE, 0)
    menu_setprop(iMenu, MPROP_EXIT, MEXIT_NEVER)
    menu_display(id, iMenu, 0)
}

public HandlePostMatchVoteMenu(id, iMenu, iItem)
{
    if(!is_user_connected(id))
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    if(iItem < 0)
    {
        menu_destroy(iMenu)
        return PLUGIN_HANDLED
    }

    new szData[8], szName[64], iAccess, iCallback
    menu_item_getinfo(iMenu, iItem, iAccess, szData, charsmax(szData), szName, charsmax(szName), iCallback)
    menu_destroy(iMenu)

    new mapIdx = str_to_num(szData)
    if(mapIdx < 0 || mapIdx >= g_iPostMatchMapCount)
        return PLUGIN_HANDLED

    // Only 1 vote per player
    if(g_iPlayerPostMatchVote[id] >= 0 && g_iPlayerPostMatchVote[id] != mapIdx)
    {
        new old = g_iPlayerPostMatchVote[id]
        if(0 <= old < g_iPostMatchMapCount && g_iPostMatchVoteCount[old] > 0)
        {
            g_iPostMatchVoteCount[old]--
        }
    }

    g_iPlayerPostMatchVote[id] = mapIdx
    g_iPostMatchVoteCount[mapIdx]++

    client_print_color(id, print_team_default, "^4[GAMELAND CW] ^1Your vote for ^4%s ^1was recorded! (^3%d votes^1)",
        g_szPostMatchMaps[mapIdx], g_iPostMatchVoteCount[mapIdx])
    client_cmd(id, "spk buttons/blip1")

    // Check if all connected human players voted
    new iVoted = 0, iTotal = 0
    for(new p = 1; p <= MaxClients; p++)
    {
        if(is_user_connected(p) && !is_user_bot(p) && !is_user_hltv(p))
        {
            iTotal++
            if(g_iPlayerPostMatchVote[p] >= 0) iVoted++
        }
    }

    if(iVoted >= iTotal && iTotal > 0)
    {
        remove_task(TASK_POST_MATCH_MAP_VOTE)
        FinishPostMatchMapVote()
        return PLUGIN_HANDLED
    }

    return PLUGIN_HANDLED
}

public Task_PostMatchVoteTimer()
{
    g_iPostMatchVoteTimer--

    if(g_iPostMatchVoteTimer <= 0)
    {
        remove_task(TASK_POST_MATCH_MAP_VOTE)
        FinishPostMatchMapVote()
        return
    }

    new bestIdx = 0, maxV = -1
    for(new i = 0; i < g_iPostMatchMapCount; i++)
    {
        if(g_iPostMatchVoteCount[i] > maxV)
        {
            maxV = g_iPostMatchVoteCount[i]
            bestIdx = i
        }
    }

    set_dhudmessage(0, 220, 255, -1.0, 0.22, 0, 0.0, 1.0, 0.0, 0.1)
    show_dhudmessage(0, "=== [ NEXT MAP VOTE ] ===^nVoting ends in: %d SECONDS^nLeader: %s (%d votes)",
        g_iPostMatchVoteTimer, g_szPostMatchMaps[bestIdx], max(0, maxV))
}

public FinishPostMatchMapVote()
{
    remove_task(TASK_POST_MATCH_MAP_VOTE)

    for(new i = 1; i <= MaxClients; i++)
    {
        if(is_user_connected(i)) show_menu(i, 0, "^n", 1)
    }

    new bestIdx = 0, maxV = -1
    for(new i = 0; i < g_iPostMatchMapCount; i++)
    {
        if(g_iPostMatchVoteCount[i] > maxV)
        {
            maxV = g_iPostMatchVoteCount[i]
            bestIdx = i
        }
    }

    new szWinningMap[32]
    copy(szWinningMap, charsmax(szWinningMap), g_szPostMatchMaps[bestIdx])

    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3MAP VOTE COMPLETED!")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^4Winning Next Map: ^3%s ^1with ^4%d votes^1!", szWinningMap, max(0, maxV))
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1Changing map in 5 seconds...")
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^3========================================")
    client_cmd(0, "spk buttons/bell1")

    set_dhudmessage(0, 255, 100, -1.0, 0.35, 0, 0.0, 5.0, 0.1, 0.2)
    show_dhudmessage(0, "NEXT MAP: %s (%d votes)^nChanging level in 5 seconds...", szWinningMap, max(0, maxV))

    new szChangeCmd[64]
    formatex(szChangeCmd, charsmax(szChangeCmd), "changelevel %s", szWinningMap)
    set_task(5.0, "Task_ExecChangelevel", _, szChangeCmd, sizeof(szChangeCmd))
}


public Cmd_SayVersion(id)
{
    client_print_color(0, print_team_default, "^4[GAMELAND CW] ^1System Version: ^3v%s ^1| ReAPI Dedicated Engine | Build: ^4%s", PLUGIN_VERSION, __DATE__)
    return PLUGIN_HANDLED
}

public Cmd_Version(id)
{
    console_print(id, "=================================================")
    console_print(id, " GAMELAND Clan War Dedicated System")
    console_print(id, " Version: v%s (ReAPI / Auto-Knife / 10-Slot / Key N)", PLUGIN_VERSION)
    console_print(id, " Build Date: %s %s", __DATE__, __TIME__)
    console_print(id, "=================================================")
    return PLUGIN_HANDLED
}

public Task_BindClientF3(taskid)
{
    new id = taskid - TASK_BIND_F3
    if(!is_user_connected(id) || is_user_bot(id) || is_user_hltv(id))
        return

    client_cmd(id, "bind n nightvision")
    client_cmd(id, "bind N nightvision")
    client_cmd(id, "bind F3 cw_menu")
    client_cmd(id, "bind f3 cw_menu")
    client_print_color(id, print_team_default, "^4[GAMELAND CW] ^1System: ^3v%s ^1| Press ^3[N]^1 (or ^3[F3]^1) or type ^4/n^1 for Player Menu!", PLUGIN_VERSION)
}
